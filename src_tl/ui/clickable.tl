-- Click-handling helper. A Clickable bundles a hit rectangle with the
-- callback the scene wants invoked when the user left-clicks inside it.
-- Scenes typically rebuild their clickables list each frame during draw
-- and walk it in mousepressed.

local M = {}

global record Clickable
   x:        number
   y:        number
   w:        number
   h:        number
   callback: function()
end

function M.find(list: {Clickable}, x: number, y: number): Clickable
   for _, c in ipairs(list) do
      if x >= c.x and x <= c.x + c.w and y >= c.y and y <= c.y + c.h then
         return c
      end
   end
   return nil
end

return M
