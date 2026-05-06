-- Panel frame: dark-fill + lighter-border rectangle with an optional
-- title in the top-left corner. The single canonical visual style for
-- bordered widgets across the app.
--
-- M.draw is the default opaque variant. M.draw_alpha takes an explicit
-- fill alpha so callers (notably table_scene's hand strips) can let the
-- background image show through. Border and label stay at full opacity
-- so panel boundaries remain readable on busy backgrounds.

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
