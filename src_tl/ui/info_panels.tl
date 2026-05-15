-- Player-facing info strips: active boons (with counters) and known-wall
-- reveals. Both cache derived per-frame data (sorted boon list, wall
-- id→Tile lookup) keyed on the DealState pointer. The engine returns
-- a new deal table on every action, so pointer identity changes exactly
-- when state changes; UI-only frames keep the same pointer and hit the
-- cache. Reset gives a fresh deal pointer, so the cache invalidates
-- across deals automatically.

require("game.deal_types")
require("effects.effect_types")

local content     = require("content.boons")
local tile_render = require("ui.tile_render")
local panel       = require("ui.panel")

local M = {}

local function sorted_keys(t: {string:integer}): {string}
   local keys: {string} = {}
   for k, _ in pairs(t) do keys[#keys + 1] = k end
   table.sort(keys)
   return keys
end

local boon_cache_deal: DealState
local boon_cache_owner: integer = 0
local boon_cache_list: {ActiveEffectState} = {}

local function owned_boons_sorted(d: DealState, owner_index: integer): {ActiveEffectState}
   if d == boon_cache_deal and owner_index == boon_cache_owner then
      return boon_cache_list
   end
   local owned: {ActiveEffectState} = {}
   for _, st in pairs(d.effect_states) do
      if st.owner_player_index == owner_index then owned[#owned + 1] = st end
   end
   table.sort(owned, function(a: ActiveEffectState, b: ActiveEffectState): boolean
      return a.effect_id < b.effect_id
   end)
   boon_cache_deal = d
   boon_cache_owner = owner_index
   boon_cache_list = owned
   return owned
end

function M.draw_boon_strip(d: DealState, owner_index: integer, x: number, y: number, w: number, h: number)
   panel.draw(x, y, w, h, "Boons")

   local owned = owned_boons_sorted(d, owner_index)
   if #owned == 0 then
      love.graphics.setColor(0.55, 0.55, 0.60, 1.0)
      love.graphics.print("(none)", x + 60, y + 4)
      return
   end

   local cx = x + 60
   local font = love.graphics.getFont()
   for _, st in ipairs(owned) do
      local b = content.find(st.effect_id)
      local label = (b ~= nil) and b.label or st.effect_id
      local extras: {string} = {}
      for _, k in ipairs(sorted_keys(st.counters)) do
         extras[#extras + 1] = k .. "=" .. tostring(st.counters[k])
      end
      if st.used_this_deal then extras[#extras + 1] = "used" end
      if #extras > 0 then label = label .. " (" .. table.concat(extras, ", ") .. ")" end
      love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
      love.graphics.print(label, cx, y + 4)
      cx = cx + font:getWidth(label) + 18
   end
end

local wall_cache_deal: DealState
local wall_cache: {string: Tile} = {}

local function wall_by_id(d: DealState): {string: Tile}
   if d == wall_cache_deal then return wall_cache end
   local by_id: {string: Tile} = {}
   for _, t in ipairs(d.wall.tiles) do by_id[t.tile_id as string] = t end
   wall_cache_deal = d
   wall_cache = by_id
   return by_id
end

-- Milestone progress (M2-S01 debug). One-line status showing player 1's
-- set-count high-water and ting-reached flag. Useful during playtest to
-- verify fork events fire at the right boundary.
function M.draw_milestone_status(d: DealState, x: number, y: number, w: number, h: number)
   panel.draw(x, y, w, h, "Milestones")

   local set_count = d.set_count_high_water
   if set_count > 3 then set_count = 3 end   -- display caps at 3; no set_4 fork

   love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
   local sets_label = "sets " .. tostring(set_count) .. " / 3"
   love.graphics.print(sets_label, x + 100, y + 4)

   local ting_label = d.reached_ting and "ting YES" or "ting —"
   if d.reached_ting then
      love.graphics.setColor(0.40, 0.85, 0.40, 1.0)
   else
      love.graphics.setColor(0.55, 0.55, 0.60, 1.0)
   end
   love.graphics.print(ting_label, x + 200, y + 4)
end

function M.draw_known_wall(d: DealState, owner_index: integer, x: number, y: number, w: number, h: number)
   panel.draw(x, y, w, h, "Known Wall")

   local ids = d.players[owner_index].known_wall_tile_ids
   if #ids == 0 then
      love.graphics.setColor(0.55, 0.55, 0.60, 1.0)
      love.graphics.print("(empty)", x + 96, y + 4)
      return
   end

   local by_id = wall_by_id(d)
   local tile_w = 22
   local tile_h = h - 8
   local gap = 3
   local cx = x + 96
   for _, id in ipairs(ids) do
      local t = by_id[id as string]
      if t ~= nil then
         tile_render.draw_tile(t, cx, y + 4, tile_w, tile_h, "south",
            tile_render.PARCHMENT_ACCENT, tile_render.CREAM_FACE)
      end
      cx = cx + tile_w + gap
   end
end

return M
