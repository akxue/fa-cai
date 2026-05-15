-- M2-S03 pre-deal starter pick scene. Presents one starter-eligible boon
-- per cluster (Honor / Suit / Concealed) using the shared boon_card
-- component. Picking adds the boon to RunState.active_boons and replaces
-- the scene with the table scene to begin Round 1.
--
-- Parallel to scenes/boon_select_scene.tl (M1) until S05 retires M1.

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.boon_types")
require("app.scene_stack")

local scene_stack   = require("app.scene_stack")
local table_scene   = require("scenes.table_scene")
local m2_boons      = require("content.m2_boons")
local boon_offer    = require("effects.boon_offer")
local boon_context  = require("effects.boon_context")
local run_state     = require("game.run_state")
local rng_mod       = require("core.rng")
local boons_init    = require("effects.boons.init")
local clickable_mod = require("ui.clickable")
local card          = require("ui.boon_card")
local assets        = require("app.assets")

local record M2BoonSelectState
   selected:   integer
   offers:     {Boon}
   clickables: {Clickable}
   seed:       integer
end

local state: M2BoonSelectState = nil

local function on_load()
   love.graphics.setBackgroundColor(0.10, 0.10, 0.12, 1.0)
   -- M1 effect registry needed for the parallel-run M1 boon system to
   -- behave correctly on first deal (no M1 boons active, but the
   -- registry must be populated for runner null-checks).
   boons_init.reset_and_register_all()
   -- M2 catalog: register stub boons so the starter pool is populated.
   m2_boons.reset()
   m2_boons.register_all()

   local seed = os.time() as integer
   local offer, _ = boon_offer.compose_starter_offer(rng_mod.from_seed(seed))
   state = { selected = 1, offers = offer, clickables = {}, seed = seed }
end

local function on_update(_dt: number)
end

local function start_run_with(boon_id: string)
   local rng = rng_mod.from_seed(state.seed)
   local rs = run_state.new_run(rng)
   rs.active_boons[#rs.active_boons + 1] =
      boon_context.new_active(boon_id, "starter" as AcquisitionPoint)
   table_scene.start_run(rs, state.seed)
   scene_stack.replace(table_scene.scene)
end

-- Card geometry. Three cards centered horizontally on the screen.
local CARD_W <const> = 280
local CARD_H <const> = 220
local CARD_GAP <const> = 32

local function card_views(): {BoonCardView}
   local sw = love.graphics.getWidth()
   local sh = love.graphics.getHeight()
   local total_w = #state.offers * CARD_W + (#state.offers - 1) * CARD_GAP
   local x0 = (sw - total_w) / 2
   local y0 = (sh - CARD_H) / 2

   local views: {BoonCardView} = {}
   for i, boon in ipairs(state.offers) do
      views[i] = {
         x = x0 + (i - 1) * (CARD_W + CARD_GAP),
         y = y0,
         w = CARD_W,
         h = CARD_H,
         boon     = boon,
         selected = (i == state.selected),
         hotkey   = tostring(i),
      }
   end
   return views
end

local function on_draw()
   assets.draw_menu_bg()
   love.graphics.setColor(0.95, 0.95, 0.95, 1.0)
   love.graphics.printf("Choose your starting boon", 0, 40, love.graphics.getWidth(), "center")
   love.graphics.setColor(0.65, 0.65, 0.70, 1.0)
   love.graphics.printf("one per cluster — click or press 1 / 2 / 3", 0, 64, love.graphics.getWidth(), "center")

   state.clickables = {}
   for i, view in ipairs(card_views()) do
      card.draw(view)
      local boon_id = view.boon.id
      local idx = i
      state.clickables[#state.clickables + 1] = {
         x = view.x, y = view.y, w = view.w, h = view.h,
         callback = function()
            state.selected = idx
            start_run_with(boon_id)
         end,
      }
   end

   love.graphics.setColor(0.45, 0.45, 0.50, 1.0)
   love.graphics.printf(
      "↑ ↓ + enter also works   •   esc back",
      0, love.graphics.getHeight() - 36, love.graphics.getWidth(), "center"
   )
end

local function on_mousepressed(x: number, y: number, mouse_button: integer)
   if mouse_button ~= 1 then return end
   local hit = clickable_mod.find(state.clickables, x, y)
   if hit ~= nil then hit.callback() end
end

local function on_keypressed(key: string)
   if key == "escape" then
      scene_stack.pop()
      return
   end
   if key == "1" or key == "2" or key == "3" then
      local idx = tonumber(key) as integer
      if state.offers[idx] ~= nil then
         state.selected = idx
         start_run_with(state.offers[idx].id)
      end
      return
   end
   if key == "left" or key == "h" then
      state.selected = state.selected - 1
      if state.selected < 1 then state.selected = #state.offers end
      return
   end
   if key == "right" or key == "l" then
      state.selected = state.selected + 1
      if state.selected > #state.offers then state.selected = 1 end
      return
   end
   if key == "up" or key == "k" then
      state.selected = state.selected - 1
      if state.selected < 1 then state.selected = #state.offers end
      return
   end
   if key == "down" or key == "j" then
      state.selected = state.selected + 1
      if state.selected > #state.offers then state.selected = 1 end
      return
   end
   if key == "return" or key == "kpenter" or key == "space" then
      local offer = state.offers[state.selected]
      if offer ~= nil then start_run_with(offer.id) end
      return
   end
end

return scene_stack.make_scene(on_load, on_update, on_draw, on_keypressed, on_mousepressed)
