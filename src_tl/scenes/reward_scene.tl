-- Reward scene. Shown after the player wins Round 1. Renders the
-- score breakdown (hand patterns, modifiers, and any boon-attributed
-- reasons) so the player can see how the fan total adds up. Pressing
-- Enter returns to the start scene; M1 only ships Round 1, so there is
-- no further round advancement here.

require("core.types")
require("game.deal_types")
require("app.scene_stack")

local scene_stack = require("app.scene_stack")
-- The "continue" transition goes through scene_stack.fire_back_to_start
-- so this scene does not statically import start_scene (which would
-- create a cycle with boon_select_scene → table_scene → reward_scene).
-- main.tl owns the concrete transition.

local record RewardState
   score_result: ScoreResult
   has_score:    boolean
   won_by_zi_mo: boolean
end

local pending: RewardState = nil
local has_pending: boolean = false
local state: RewardState = nil

local M = {}

function M.start(score_result: ScoreResult, has_score: boolean, won_by_zi_mo: boolean)
   pending = {
      score_result = score_result,
      has_score    = has_score,
      won_by_zi_mo = won_by_zi_mo,
   }
   has_pending = true
end

function M.load()
   love.graphics.setBackgroundColor(0.10, 0.12, 0.10, 1.0)
   if has_pending then
      state = pending
      pending = nil
      has_pending = false
   else
      state = { score_result = {} as ScoreResult, has_score = false, won_by_zi_mo = false }
   end
end

function M.update(_dt: number)
end

function M.draw()
   love.graphics.setColor(1.00, 0.92, 0.40, 1.0)
   love.graphics.print("Round 1 Won!", 40, 30)

   if not state.has_score then
      love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
      love.graphics.print("(no score result available)", 40, 70)
      love.graphics.setColor(0.45, 0.45, 0.50, 1.0)
      love.graphics.print("return/space  continue", 40, 110)
      return
   end

   local r = state.score_result
   love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
   local how = state.won_by_zi_mo and "Zi Mo" or "claim"
   love.graphics.print(string.format("Win: %s   Rating: %s   Total fan: %d%s",
      how, r.rating as string, r.total_fan, r.is_limit and "  (LIMIT)" or ""), 40, 60)

   love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
   love.graphics.print("Score breakdown:", 40, 100)

   local y = 124
   for _, reason in ipairs(r.reasons) do
      love.graphics.setColor(0.65, 0.85, 1.00, 1.0)
      love.graphics.print("[" .. (reason.category as string) .. "]", 60, y)
      love.graphics.setColor(0.92, 0.92, 0.92, 1.0)
      local fan_str = reason.is_limit and "limit" or string.format("+%d", reason.fan)
      love.graphics.print(reason.label, 200, y)
      love.graphics.setColor(1.00, 0.92, 0.40, 1.0)
      love.graphics.print(fan_str, 540, y)
      y = y + 18
   end

   love.graphics.setColor(0.45, 0.45, 0.50, 1.0)
   love.graphics.print("return/space continue   esc quit run", 40, y + 24)
end

function M.keypressed(key: string)
   if key == "escape" or key == "return" or key == "kpenter" or key == "space" then
      scene_stack.fire_back_to_start()
      return
   end
end

return M
