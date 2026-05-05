-- Panel frame: dark-fill + lighter-border rectangle with an optional
-- title in the top-left corner. The single canonical visual style for
-- bordered widgets across the app.

local M = {}

function M.draw(x: number, y: number, w: number, h: number, label: string)
   love.graphics.setColor(0.18, 0.18, 0.20, 1.0)
   love.graphics.rectangle("fill", x, y, w, h)
   love.graphics.setColor(0.40, 0.40, 0.45, 1.0)
   love.graphics.rectangle("line", x, y, w, h)
   if label ~= "" then
      love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
      love.graphics.print(label, x + 8, y + 4)
   end
end

return M
