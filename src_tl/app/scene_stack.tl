-- Scene stack. Routes LÖVE update/draw/keypressed to the top scene and
-- calls each scene's load() exactly when it becomes the active scene
-- (push or replace from below). Scenes are responsible for their own
-- pre-push setup; the stack only orchestrates dispatch.
--
-- Also hosts a small set of cross-scene event handlers (deal_over, retry,
-- back_to_start). Scenes fire events through this module instead of
-- statically importing each other, which avoids cycles like
--   table_scene → reward_scene → start_scene → boon_select_scene →
--   table_scene
-- The application root (main.tl) installs concrete handlers at startup;
-- it is the only module that statically imports every scene.

require("game.deal_types")
require("game.run_state")

global record Scene
   load:         function()
   update:       function(dt: number)
   draw:         function()
   keypressed:   function(key: string)
   mousepressed: function(x: number, y: number, button: integer)
end

local M = {}

local stack: {Scene} = {}

local deal_over_handler:     function(d: DealState, rs: RunState) = nil
local retry_handler:         function(rs: RunState) = nil
local back_to_start_handler: function() = nil

function M.set_deal_over_handler(fn: function(d: DealState, rs: RunState))
   deal_over_handler = fn
end

function M.set_retry_handler(fn: function(rs: RunState))
   retry_handler = fn
end

function M.set_back_to_start_handler(fn: function())
   back_to_start_handler = fn
end

function M.fire_deal_over(d: DealState, rs: RunState)
   assert(deal_over_handler ~= nil, "scene_stack.fire_deal_over: no handler installed (call set_deal_over_handler in love.load)")
   deal_over_handler(d, rs)
end

function M.fire_retry(rs: RunState)
   assert(retry_handler ~= nil, "scene_stack.fire_retry: no handler installed")
   retry_handler(rs)
end

function M.fire_back_to_start()
   assert(back_to_start_handler ~= nil, "scene_stack.fire_back_to_start: no handler installed")
   back_to_start_handler()
end

function M.push(s: Scene)
   stack[#stack + 1] = s
   s.load()
end

function M.pop()
   if #stack == 0 then return end
   stack[#stack] = nil
   local top = stack[#stack]
   if top ~= nil then top.load() end
end

function M.replace(s: Scene)
   if #stack > 0 then stack[#stack] = nil end
   stack[#stack + 1] = s
   s.load()
end

-- Drops the entire stack and pushes `s` as the only scene. Use for
-- "back to start" transitions that need a guaranteed depth-1 stack —
-- replace() only rewrites the top, so repeated round-trips to start
-- would otherwise accumulate scenes underneath.
function M.reset_to(s: Scene)
   stack = { s }
   s.load()
end

function M.depth(): integer
   return #stack
end

function M.top(): Scene
   return stack[#stack]
end

function M.update(dt: number)
   local s = stack[#stack]
   if s ~= nil then s.update(dt) end
end

function M.draw()
   local s = stack[#stack]
   if s ~= nil then s.draw() end
end

function M.keypressed(key: string)
   local s = stack[#stack]
   if s ~= nil then s.keypressed(key) end
end

function M.mousepressed(x: number, y: number, button: integer)
   local s = stack[#stack]
   if s ~= nil then s.mousepressed(x, y, button) end
end

return M
