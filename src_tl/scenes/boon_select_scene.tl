-- Boon select scene. Presents 3 curated starter boon offers to the player;
-- the chosen boon is activated for player 1 (East / human seat) and the
-- resulting RunState is handed to the table scene, which is then pushed.
--
-- The 3 offers are intentionally hand-picked to span the M1 archetypes:
--   - Fresh Start  (Reader, opening interaction)
--   - Third Eye    (Reader, passive Known Wall)
--   - Dragon's Weight (Caller, scoring boost)
-- This list is the "curated" pool S08 ships; future slices may rotate or
-- randomize from the broader content.boons.starter() set.

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.effect_types")
require("app.scene_stack")

local scene_stack = require("app.scene_stack")
local table_scene = require("scenes.table_scene")
local content     = require("content.boons")
local run_state   = require("game.run_state")
local rng_mod     = require("core.rng")
local boons_init  = require("effects.boons.init")

local CURATED_BOON_IDS: {string} = { "fresh_start", "third_eye", "dragons_weight" }

local record BoonSelectState
   selected: integer
   offers:   {BoonContent}
end

local state: BoonSelectState = nil

local M: Scene = {} as Scene

function M.load()
   love.graphics.setBackgroundColor(0.10, 0.10, 0.12, 1.0)
   boons_init.reset_and_register_all()
   local offers: {BoonContent} = {}
   for _, id in ipairs(CURATED_BOON_IDS) do
      local b = content.find(id)
      if b ~= nil then offers[#offers + 1] = b end
   end
   state = { selected = 1, offers = offers }
end

function M.update(_dt: number)
end

function M.draw()
   love.graphics.setColor(0.95, 0.95, 0.95, 1.0)
   love.graphics.print("Choose a starter boon", 40, 30)

   for i, offer in ipairs(state.offers) do
      local y = 80 + (i - 1) * 70
      if i == state.selected then
         love.graphics.setColor(1.00, 0.92, 0.40, 1.0)
         love.graphics.print("> " .. offer.label .. "  (" .. offer.archetype .. ")", 60, y)
      else
         love.graphics.setColor(0.80, 0.80, 0.85, 1.0)
         love.graphics.print("  " .. offer.label .. "  (" .. offer.archetype .. ")", 60, y)
      end
      love.graphics.setColor(0.65, 0.65, 0.70, 1.0)
      love.graphics.printf(offer.description, 80, y + 18, 720, "left")
   end

   love.graphics.setColor(0.45, 0.45, 0.50, 1.0)
   love.graphics.print("up/down or j/k select   return/space confirm   esc back", 40, 320)
end

local function start_run_with(boon_id: string)
   local seed = os.time() as integer
   local rng = rng_mod.from_seed(seed)
   local rs = run_state.new_run(rng)
   rs.active_effects = { content.activate_for(boon_id, 1) }
   table_scene.start_run(rs, seed)
   scene_stack.replace(table_scene as Scene)
end

function M.keypressed(key: string)
   if key == "escape" then
      scene_stack.pop()
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
      if offer ~= nil then start_run_with(offer.boon_id) end
      return
   end
end

return M
