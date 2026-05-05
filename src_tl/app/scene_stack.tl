-- Scene stack. Routes LÖVE update/draw/keypressed to the top scene and
-- calls each scene's load() exactly when it becomes the active scene
-- (push or replace from below). Scenes are responsible for their own
-- pre-push setup; the stack only orchestrates dispatch.

global record Scene
   load:       function()
   update:     function(dt: number)
   draw:       function()
   keypressed: function(key: string)
end

local M = {}

local stack: {Scene} = {}

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

return M
