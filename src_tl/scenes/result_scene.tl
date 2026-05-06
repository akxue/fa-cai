-- Result scene. Shown after a deal ends without a player Hu — opponent
-- win or wall exhaustion. Lives are decremented in main.tl's deal_over
-- handler before this scene loads. Click Retry (or press enter/space) to
-- replay Round 1 while lives > 0; click Back to start (or press
-- enter/space/esc when lives == 0, or press esc anytime) to abandon
-- the run.

require("core.types")
require("game.run_state")
require("game.deal_types")
require("app.scene_stack")

local scene_stack   = require("app.scene_stack")
local clickable_mod = require("ui.clickable")
local button        = require("ui.button")
local assets        = require("app.assets")

local record ResultState
   run_state:     RunState
   outcome_label: string
   clickables:    {Clickable}
end

-- Caller sets state via start() before scene_stack pushes the scene;
-- on_load only handles LÖVE state setup and a defensive empty-state
-- fallback for the "scene shown without start" case.
local state: ResultState = nil

-- Caller should already have decremented run_state.lives. The scene only
-- displays the post-decrement state and routes the retry/end flow.
local function start(rs: RunState, outcome_label: string)
   state = { run_state = rs, outcome_label = outcome_label, clickables = {} }
end

local function on_load()
   love.graphics.setBackgroundColor(0.12, 0.10, 0.10, 1.0)
   if state == nil then
      state = { run_state = nil, outcome_label = "", clickables = {} }
   end
end

local function on_update(_dt: number)
end

local function draw_button(label: string, x: number, y: number, w: number, h: number, accent_r: number, accent_g: number, accent_b: number, callback: function())
   button.draw(label, x, y, w, h, accent_r, accent_g, accent_b, state.clickables, callback)
end

local function on_draw()
   assets.draw_bg_dimmed(0.55)
   state.clickables = {}
   if state.run_state == nil then
      love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
      love.graphics.print("(no run in progress)", 40, 30)
      return
   end

   local lives = state.run_state.lives
   if lives > 0 then
      love.graphics.setColor(1.00, 0.55, 0.30, 1.0)
      love.graphics.print("Round 1 lost.", 40, 30)
   else
      love.graphics.setColor(0.95, 0.30, 0.30, 1.0)
      love.graphics.print("Run over.", 40, 30)
   end

   love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
   love.graphics.print(state.outcome_label, 40, 60)
   love.graphics.print(string.format("Lives remaining: %d / 3", lives), 40, 90)

   if lives > 0 then
      local rs = state.run_state
      draw_button("Retry Round 1", 40, 140, 240, 36, 1.00, 0.85, 0.30,
         function() scene_stack.fire_retry(rs) end)
      draw_button("Quit run",        300, 140, 160, 36, 0.55, 0.55, 0.60,
         function() scene_stack.fire_back_to_start() end)
   else
      draw_button("Back to start", 40, 140, 240, 36, 0.55, 0.55, 0.60,
         function() scene_stack.fire_back_to_start() end)
   end
end

local function on_mousepressed(x: number, y: number, mouse_button: integer)
   if mouse_button ~= 1 then return end
   local hit = clickable_mod.find(state.clickables, x, y)
   if hit ~= nil then hit.callback() end
end

local function on_keypressed(key: string)
   if key == "escape" then
      scene_stack.fire_back_to_start()
      return
   end
   if key == "return" or key == "kpenter" or key == "space" then
      local rs = state.run_state
      if rs == nil or rs.lives <= 0 then
         scene_stack.fire_back_to_start()
      else
         scene_stack.fire_retry(rs)
      end
      return
   end
end

return {
   scene = scene_stack.make_scene(on_load, on_update, on_draw, on_keypressed, on_mousepressed),
   start = start,
}
