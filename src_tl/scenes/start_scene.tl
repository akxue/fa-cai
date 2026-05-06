-- Start scene. Title screen with three options: begin a fresh run,
-- jump into the debug table for development, or quit.

require("app.scene_stack")

local scene_stack       = require("app.scene_stack")
local table_scene       = require("scenes.table_scene")
local boon_select_scene = require("scenes.boon_select_scene")
local clickable_mod     = require("ui.clickable")

local record StartState
   selected:   integer
   clickables: {Clickable}
end

local state: StartState = nil

local MENU_LABELS: {string} = {
   "Start Run",
   "Debug Table",
   "Quit",
}

local function on_load()
   love.graphics.setBackgroundColor(0.10, 0.10, 0.12, 1.0)
   state = { selected = 1, clickables = {} }
end

local function on_update(_dt: number)
end

local function activate(idx: integer)
   state.selected = idx
   local choice = MENU_LABELS[idx]
   if choice == "Start Run" then
      scene_stack.push(boon_select_scene)
   elseif choice == "Debug Table" then
      scene_stack.replace(table_scene.scene)
   elseif choice == "Quit" then
      love.event.quit(0)
   end
end

local function on_draw()
   love.graphics.setColor(0.95, 0.95, 0.95, 1.0)
   love.graphics.print("facai", 40, 30)
   love.graphics.setColor(0.65, 0.65, 0.70, 1.0)
   love.graphics.print("a solo roguelike Hong Kong mahjong", 40, 50)

   state.clickables = {}
   for i, label in ipairs(MENU_LABELS) do
      local y = 110 + (i - 1) * 32
      local row_x, row_y = 50, y - 4
      local row_w, row_h = 320, 28

      -- Hover/selected styling
      if i == state.selected then
         love.graphics.setColor(0.20, 0.22, 0.30, 1.0)
         love.graphics.rectangle("fill", row_x, row_y, row_w, row_h)
         love.graphics.setColor(1.00, 0.92, 0.40, 1.0)
      else
         love.graphics.setColor(0.16, 0.17, 0.22, 1.0)
         love.graphics.rectangle("fill", row_x, row_y, row_w, row_h)
         love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
      end
      love.graphics.print(label, row_x + 12, y)

      local idx = i
      state.clickables[#state.clickables + 1] = {
         x = row_x, y = row_y, w = row_w, h = row_h,
         callback = function() activate(idx) end,
      }
   end

   love.graphics.setColor(0.45, 0.45, 0.50, 1.0)
   love.graphics.print("click to choose   /   up-down + enter also work   /   esc quits", 40, 280)
end

local function on_mousepressed(x: number, y: number, mouse_button: integer)
   if mouse_button ~= 1 then return end
   local hit = clickable_mod.find(state.clickables, x, y)
   if hit ~= nil then hit.callback() end
end

local function on_keypressed(key: string)
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
      activate(state.selected)
      return
   end
end

return scene_stack.make_scene(on_load, on_update, on_draw, on_keypressed, on_mousepressed)
