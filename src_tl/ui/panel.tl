-- Panel frame: dark-fill + lighter-border rectangle with an optional
-- title in the top-left corner. Border and label stay at full opacity
-- so the frame stays readable when the fill is translucent over a busy
-- background. `draw_alpha` exposes the fill alpha; `draw` defaults to
-- opaque.

local M = {}

local function fill_and_frame(x: number, y: number, w: number, h: number, label: string, fill_a: number)
   love.graphics.setColor(0.18, 0.18, 0.20, fill_a)
   love.graphics.rectangle("fill", x, y, w, h)
   love.graphics.setColor(0.55, 0.55, 0.60, 1.0)
   love.graphics.rectangle("line", x, y, w, h)
   if label ~= "" then
      love.graphics.setColor(0.92, 0.92, 0.95, 1.0)
      love.graphics.print(label, x + 8, y + 4)
   end
end

function M.draw(x: number, y: number, w: number, h: number, label: string)
   fill_and_frame(x, y, w, h, label, 1.0)
end

function M.draw_alpha(x: number, y: number, w: number, h: number, label: string, fill_a: number)
   fill_and_frame(x, y, w, h, label, fill_a)
end

return M
