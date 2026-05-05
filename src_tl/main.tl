-- LÖVE entry point. Pushes the start scene; all callbacks are routed
-- through the scene stack so future scenes (boon select, reward, result)
-- compose without changes here.

local scene_stack = require("app.scene_stack")
local start_scene = require("scenes.start_scene")

local VERSION <const> = "0.0.8-s08"

function love.load()
   love.window.setTitle("facai " .. VERSION)
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
