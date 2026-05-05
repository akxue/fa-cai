-- Player-facing info strips: active boons (with counters) and known-wall
-- reveals. Both strips render horizontally so they sit naturally above
-- the player hand row.

require("game.deal_types")
require("effects.effect_types")

local content     = require("content.boons")
local tile_render = require("ui.tile_render")

local M = {}

local function panel_bg(x: number, y: number, w: number, h: number, title: string)
   love.graphics.setColor(0.18, 0.18, 0.20, 1.0)
   love.graphics.rectangle("fill", x, y, w, h)
   love.graphics.setColor(0.40, 0.40, 0.45, 1.0)
   love.graphics.rectangle("line", x, y, w, h)
   love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
   love.graphics.print(title, x + 8, y + 4)
end

-- Sorted keys of a string-keyed table — Lua's pairs() does not guarantee
-- order, and the strip should look stable across frames.
local function sorted_keys(t: {string:integer}): {string}
   local keys: {string} = {}
   for k, _ in pairs(t) do keys[#keys + 1] = k end
   table.sort(keys)
   return keys
end

-- Active boons owned by `owner_index`, with any non-zero counters and
-- the used_this_deal flag rendered after the label. Sorted by effect_id
-- for stable order.
function M.draw_boon_strip(d: DealState, owner_index: integer, x: number, y: number, w: number, h: number)
   panel_bg(x, y, w, h, "Boons")

   local owned: {ActiveEffectState} = {}
   for _, st in pairs(d.effect_states) do
      if st.owner_player_index == owner_index then owned[#owned + 1] = st end
   end
   table.sort(owned, function(a: ActiveEffectState, b: ActiveEffectState): boolean
      return a.effect_id < b.effect_id
   end)

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

-- Known-wall reveals for `owner_index` rendered as small face-up tile
-- boxes. Tile lookup walks d.wall.tiles since revealed tiles have not
-- been drawn yet — once drawn, the engine clears them from the list.
function M.draw_known_wall(d: DealState, owner_index: integer, x: number, y: number, w: number, h: number)
   panel_bg(x, y, w, h, "Known Wall")

   local ids = d.players[owner_index].known_wall_tile_ids
   if #ids == 0 then
      love.graphics.setColor(0.55, 0.55, 0.60, 1.0)
      love.graphics.print("(empty)", x + 96, y + 4)
      return
   end

   local tile_w = 22
   local tile_h = h - 8
   local gap = 3
   local cx = x + 96
   for _, id in ipairs(ids) do
      for _, t in ipairs(d.wall.tiles) do
         if t.tile_id == id then
            tile_render.draw_tile_box(t, cx, y + 4, tile_w, tile_h, 0.92, 0.90, 0.82, 0.55, 0.50, 0.40)
            break
         end
      end
      cx = cx + tile_w + gap
   end
end

return M
