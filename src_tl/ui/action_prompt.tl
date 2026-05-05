-- Action prompt panel. Renders a list of player-facing options as
-- (key, label) rows with the keybind highlighted on the left, the
-- description on the right. Caller supplies the option list — this
-- module does not enumerate legal actions; that logic lives in the
-- scene because it depends on engine state and private helpers.
--
-- M.draw returns one rectangle per option in the same order so the
-- caller can register Clickables that dispatch each option.

require("game.deal_types")

global record ActionPromptOption
   key:    string       -- the key the player presses (e.g. "p", "h", "x")
   label:  string       -- human-readable description
   action: DealAction   -- nil for placeholder options the scene
                        -- constructs at dispatch time
end

global record OptionRect
   x: number
   y: number
   w: number
   h: number
end

local M = {}

local ROW_H <const> = 24

function M.draw(opts: {ActionPromptOption}, title: string, x: number, y: number, w: number, h: number): {OptionRect}
   love.graphics.setColor(0.18, 0.18, 0.20, 1.0)
   love.graphics.rectangle("fill", x, y, w, h)
   love.graphics.setColor(0.40, 0.40, 0.45, 1.0)
   love.graphics.rectangle("line", x, y, w, h)

   love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
   love.graphics.print(title, x + 10, y + 6)

   local rects: {OptionRect} = {}
   if #opts == 0 then
      love.graphics.setColor(0.55, 0.55, 0.60, 1.0)
      love.graphics.print("(no actions)", x + 14, y + 32)
      return rects
   end

   local row_top = y + 30
   for i, opt in ipairs(opts) do
      local row_x = x + 10
      local row_y = row_top + (i - 1) * ROW_H
      local row_w = w - 20
      local row_h = ROW_H - 2

      love.graphics.setColor(0.22, 0.24, 0.30, 1.0)
      love.graphics.rectangle("fill", row_x, row_y, row_w, row_h)
      love.graphics.setColor(0.50, 0.55, 0.65, 1.0)
      love.graphics.rectangle("line", row_x, row_y, row_w, row_h)

      love.graphics.setColor(1.00, 0.92, 0.40, 1.0)
      love.graphics.print("[" .. opt.key:upper() .. "]", row_x + 8, row_y + 4)
      love.graphics.setColor(0.92, 0.92, 0.95, 1.0)
      love.graphics.print(opt.label, row_x + 44, row_y + 4)

      rects[i] = { x = row_x, y = row_y, w = row_w, h = row_h }
   end
   return rects
end

return M
