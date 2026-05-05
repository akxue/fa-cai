-- LÖVE entry point. Pushes the start scene; all callbacks are routed
-- through the scene stack so future scenes (boon select, reward, result)
-- compose without changes here.
--
-- main.tl is also the only module that statically imports every scene.
-- Cross-scene transitions (deal_over → reward/result, retry → table,
-- back_to_start) are installed as scene_stack handlers below so the
-- scenes themselves stay decoupled.

require("game.deal_types")
require("game.run_state")

local scene_stack       = require("app.scene_stack")
local start_scene       = require("scenes.start_scene")
local table_scene       = require("scenes.table_scene")
local reward_scene      = require("scenes.reward_scene")
local result_scene      = require("scenes.result_scene")
local rng_mod           = require("core.rng")

local VERSION <const> = "0.0.8-s08"

local function on_deal_over(d: DealState, rs: RunState)
   if not d.has_deal_result then
      if rs ~= nil then rs.lives = rs.lives - 1 end
      result_scene.start(rs, "Deal ended without result.")
      scene_stack.replace(result_scene as Scene)
      return
   end
   local res = d.deal_result
   if res.winner_player_index == 1 then
      reward_scene.start(res.score_result, res.has_score_result, res.won_by_zi_mo)
      scene_stack.replace(reward_scene as Scene)
      return
   end
   if rs ~= nil then rs.lives = rs.lives - 1 end
   local label: string
   if res.winner_player_index > 0 then
      local zm = res.won_by_zi_mo and " (zi mo)" or ""
      label = string.format("Player %d won%s.", res.winner_player_index, zm)
   else
      label = "Wall exhausted with no winner."
   end
   result_scene.start(rs, label)
   scene_stack.replace(result_scene as Scene)
end

local function on_retry(rs: RunState)
   local seed = os.time() as integer
   rs.rng = rng_mod.from_seed(seed)
   table_scene.start_run(rs, seed)
   scene_stack.replace(table_scene as Scene)
end

local function on_back_to_start()
   scene_stack.replace(start_scene as Scene)
end

function love.load()
   love.window.setMode(1280, 800, { resizable = true })
   love.window.setTitle("facai " .. VERSION)
   scene_stack.set_deal_over_handler(on_deal_over)
   scene_stack.set_retry_handler(on_retry)
   scene_stack.set_back_to_start_handler(on_back_to_start)
   scene_stack.push(start_scene as Scene)
end

function love.update(dt: number)
   scene_stack.update(dt)
end

function love.draw()
   scene_stack.draw()
end

function love.keypressed(key: string, _scancode: string, _isrepeat: boolean)
   scene_stack.keypressed(key)
end

function love.mousepressed(x: number, y: number, button: integer, _istouch: boolean, _presses: integer)
   scene_stack.mousepressed(x, y, button)
end
