-- Action prompt panel. Renders a list of player-facing options as
-- (key, label) rows with the keybind highlighted on the left, the
-- description on the right. Caller supplies the option list — this
-- module does not enumerate legal actions; that logic lives in the
-- scene because it depends on engine state and private helpers.
--
-- M.draw returns one rectangle per option in the same order so the
-- caller can register Clickables that dispatch each option.

require("game.deal_types")
local panel = require("ui.panel")

global record ActionPromptOption
   key:    string       -- the key the player presses (e.g. "p", "h", "x")
   label:  string       -- human-readable description
   action: DealAction   -- nil for placeholder options the scene
                        -- constructs at dispatch time
end

local record OptionRect
   x: number
   y: number
   w: number
   h: number
end

local M = {}

local ROW_H <const> = 24

function M.draw(opts: {ActionPromptOption}, title: string, x: number, y: number, w: number, h: number): {OptionRect}
   panel.draw(x, y, w, h, title)

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

-- Horizontal layout: bigger buttons in a row, sized to fill (x, y, w, h).
-- Used in the outer bottom-bar action strip where vertical real-estate is
-- limited but horizontal isn't. Each button shows the keybind on top and
-- the label below. No frame around the row — caller provides any
-- surrounding chrome.
local BTN_MAX_W <const>: integer = 160
local BTN_MIN_W <const>: integer = 80
local BTN_GAP   <const>: integer = 8

function M.draw_horizontal(opts: {ActionPromptOption}, x: number, y: number, w: number, h: number): {OptionRect}
   local rects: {OptionRect} = {}
   if #opts == 0 then return rects end

   local n = #opts
   local btn_w = math.floor((w - BTN_GAP * (n - 1)) / n)
   if btn_w > BTN_MAX_W then btn_w = BTN_MAX_W end
   if btn_w < BTN_MIN_W then btn_w = BTN_MIN_W end
   local btn_h = h
   local total_w = btn_w * n + BTN_GAP * (n - 1)
   local start_x = x + (w - total_w) / 2
   local font = love.graphics.getFont()
   local font_h = font:getHeight()

   for i, opt in ipairs(opts) do
      local bx = start_x + (i - 1) * (btn_w + BTN_GAP)
      local by = y

      love.graphics.setColor(0.22, 0.24, 0.30, 0.92)
      love.graphics.rectangle("fill", bx, by, btn_w, btn_h)
      love.graphics.setColor(0.55, 0.60, 0.70, 1.0)
      love.graphics.rectangle("line", bx, by, btn_w, btn_h)

      local keystr = "[" .. opt.key:upper() .. "]"
      local kw = font:getWidth(keystr)
      love.graphics.setColor(1.00, 0.92, 0.40, 1.0)
      love.graphics.print(keystr, bx + (btn_w - kw) / 2, by + 6)

      local lw = font:getWidth(opt.label)
      love.graphics.setColor(0.95, 0.95, 0.95, 1.0)
      love.graphics.print(opt.label, bx + (btn_w - lw) / 2, by + btn_h - font_h - 6)

      rects[i] = { x = bx, y = by, w = btn_w, h = btn_h }
   end
   return rects
end

return M
