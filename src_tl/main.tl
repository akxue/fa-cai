-- LÖVE entry point. Delegates to the S05 debug table scene.

local table_scene = require("scenes.table_scene")

local VERSION <const> = "0.0.5-s05"

function love.load()
   love.window.setTitle("facai " .. VERSION .. " — debug table")
   table_scene.load()
end

function love.update(dt: number)
   table_scene.update(dt)
end

function love.draw()
   table_scene.draw()
end

function love.keypressed(key: string, _scancode: string, _isrepeat: boolean)
   table_scene.keypressed(key)
end
