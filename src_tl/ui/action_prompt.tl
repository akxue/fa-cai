-- Action prompt panel. Renders a list of player-facing options as
-- (key, label) rows with the keybind highlighted on the left, the
-- description on the right. Caller supplies the option list — this
-- module does not enumerate legal actions; that logic lives in the
-- scene because it depends on engine state and private helpers.

require("game.deal_types")

global record ActionPromptOption
   key:    string       -- the key the player presses (e.g. "p", "h", "x")
   label:  string       -- human-readable description
   action: DealAction   -- optional pre-built engine action; may be nil for
                        -- options the scene constructs on dispatch (e.g.
                        -- "discard selected tile").
   has_action: boolean
end

local M = {}

function M.draw(opts: {ActionPromptOption}, title: string, x: number, y: number, w: number, h: number)
   love.graphics.setColor(0.18, 0.18, 0.20, 1.0)
   love.graphics.rectangle("fill", x, y, w, h)
   love.graphics.setColor(0.40, 0.40, 0.45, 1.0)
   love.graphics.rectangle("line", x, y, w, h)

   love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
   love.graphics.print(title, x + 8, y + 4)

   if #opts == 0 then
      love.graphics.setColor(0.55, 0.55, 0.60, 1.0)
      love.graphics.print("(no actions)", x + 12, y + 26)
      return
   end

   local row_y = y + 26
   for _, opt in ipairs(opts) do
      love.graphics.setColor(1.00, 0.92, 0.40, 1.0)
      love.graphics.print("[" .. opt.key:upper() .. "]", x + 12, row_y)
      love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
      love.graphics.print(opt.label, x + 50, row_y)
      row_y = row_y + 18
   end
end

return M
