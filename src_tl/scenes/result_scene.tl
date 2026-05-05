-- Result scene. Shown after a deal ends without a player Hu — opponent
-- win or wall exhaustion. Decrements the run's lives once on entry; if
-- lives remain, Enter retries Round 1; if 0, the run is over and Enter
-- returns to start.

require("core.types")
require("game.run_state")
require("game.deal_types")
require("app.scene_stack")

local scene_stack = require("app.scene_stack")
-- Transitions go through scene_stack.fire_retry / fire_back_to_start so
-- this scene avoids statically importing start_scene or table_scene.
-- main.tl owns those concrete transitions.

local record ResultState
   run_state:     RunState
   outcome_label: string
end

local pending: ResultState = nil
local has_pending: boolean = false
local state: ResultState = nil

local M = {}

-- Caller should already have decremented run_state.lives. The scene only
-- displays the post-decrement state and routes the retry/end flow.
function M.start(rs: RunState, outcome_label: string)
   pending = { run_state = rs, outcome_label = outcome_label }
   has_pending = true
end

function M.load()
   love.graphics.setBackgroundColor(0.12, 0.10, 0.10, 1.0)
   if has_pending then
      state = pending
      pending = nil
      has_pending = false
   else
      state = { run_state = nil, outcome_label = "" }
   end
end

function M.update(_dt: number)
end

function M.draw()
   if state.run_state == nil then
      love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
      love.graphics.print("(no run in progress)", 40, 30)
      return
   end

   local lives = state.run_state.lives
   if lives > 0 then
      love.graphics.setColor(1.00, 0.55, 0.30, 1.0)
      love.graphics.print("Round 1 lost.", 40, 30)
   else
      love.graphics.setColor(0.95, 0.30, 0.30, 1.0)
      love.graphics.print("Run over.", 40, 30)
   end

   love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
   love.graphics.print(state.outcome_label, 40, 60)
   love.graphics.print(string.format("Lives remaining: %d / 3", lives), 40, 90)

   love.graphics.setColor(0.45, 0.45, 0.50, 1.0)
   if lives > 0 then
      love.graphics.print("return/space  retry Round 1   esc  quit run", 40, 140)
   else
      love.graphics.print("return/space  back to start   esc  back to start", 40, 140)
   end
end

function M.keypressed(key: string)
   if key == "escape" then
      scene_stack.fire_back_to_start()
      return
   end
   if key == "return" or key == "kpenter" or key == "space" then
      local rs = state.run_state
      if rs == nil or rs.lives <= 0 then
         scene_stack.fire_back_to_start()
      else
         scene_stack.fire_retry(rs)
      end
      return
   end
end

return M
