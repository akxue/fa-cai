-- Clickable labeled button. Renders a dark-fill rectangle with an
-- accent border and the label text, then appends a Clickable to
-- `clickables` so the scene's mousepressed dispatcher invokes
-- `callback` when the button is hit.

require("ui.clickable")

local M = {}

function M.draw(
   label:     string,
   x:         number,
   y:         number,
   w:         number,
   h:         number,
   accent_r:  number,
   accent_g:  number,
   accent_b:  number,
   clickables: {Clickable},
   callback:  function()
)
   love.graphics.setColor(0.20, 0.20, 0.24, 1.0)
   love.graphics.rectangle("fill", x, y, w, h)
   love.graphics.setColor(accent_r, accent_g, accent_b, 1.0)
   love.graphics.rectangle("line", x, y, w, h)
   love.graphics.setColor(0.95, 0.95, 0.95, 1.0)
   love.graphics.print(label, x + 12, y + 8)
   clickables[#clickables + 1] = {
      x = x, y = y, w = w, h = h, callback = callback,
   }
end

return M
