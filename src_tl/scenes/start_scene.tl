-- Start scene. Title screen with three options: begin a fresh run, jump
-- into the S05 debug table for development, or quit. Selection navigates
-- with up/down/k/j; confirms with return/enter/space.
--
-- "Start Run" currently routes to the debug table scene as a placeholder;
-- commit 2 inserts the boon select scene in front of it.

require("app.scene_stack")

local scene_stack = require("app.scene_stack")
local table_scene = require("scenes.table_scene")

local record StartState
   selected: integer
end

local state: StartState = nil

local MENU_LABELS: {string} = {
   "Start Run",
   "Debug Table (S05)",
   "Quit",
}

local M: Scene = {} as Scene

function M.load()
   love.graphics.setBackgroundColor(0.10, 0.10, 0.12, 1.0)
   state = { selected = 1 }
end

function M.update(_dt: number)
end

function M.draw()
   love.graphics.setColor(0.95, 0.95, 0.95, 1.0)
   love.graphics.print("facai", 40, 30)
   love.graphics.setColor(0.65, 0.65, 0.70, 1.0)
   love.graphics.print("a solo roguelike Hong Kong mahjong", 40, 50)

   for i, label in ipairs(MENU_LABELS) do
      local y = 110 + (i - 1) * 26
      if i == state.selected then
         love.graphics.setColor(1.00, 0.92, 0.40, 1.0)
         love.graphics.print("> " .. label, 60, y)
      else
         love.graphics.setColor(0.80, 0.80, 0.85, 1.0)
         love.graphics.print("  " .. label, 60, y)
      end
   end

   love.graphics.setColor(0.45, 0.45, 0.50, 1.0)
   love.graphics.print("up/down or j/k select   return/space confirm   esc quit", 40, 280)
end

local function activate()
   local choice = MENU_LABELS[state.selected]
   if choice == "Start Run" then
      scene_stack.replace(table_scene as Scene)
   elseif choice == "Debug Table (S05)" then
      scene_stack.replace(table_scene as Scene)
   elseif choice == "Quit" then
      love.event.quit(0)
   end
end

function M.keypressed(key: string)
   if key == "escape" then
      love.event.quit(0)
      return
   end
   if key == "up" or key == "k" then
      state.selected = state.selected - 1
      if state.selected < 1 then state.selected = #MENU_LABELS end
      return
   end
   if key == "down" or key == "j" then
      state.selected = state.selected + 1
      if state.selected > #MENU_LABELS then state.selected = 1 end
      return
   end
   if key == "return" or key == "kpenter" or key == "space" then
      activate()
      return
   end
end

return M
