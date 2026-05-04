-- LÖVE entry point — minimal debug screen for S00

local VERSION <const> = "0.0.1-s00"

function love.load()
   love.window.setTitle("facai " .. VERSION)
end

function love.update(_dt: number)
end

function love.draw()
   local w = love.graphics.getWidth()
   local h = love.graphics.getHeight()
   local fps = love.timer.getFPS()

   love.graphics.setColor(0.9, 0.9, 0.9, 1.0)
   love.graphics.print("facai (發財) — debug screen", 20, 20)
   love.graphics.print("version: " .. VERSION, 20, 44)
   love.graphics.print("S00: toolchain and repo skeleton", 20, 68)
   love.graphics.print(string.format("window: %gx%g   fps: %g", w, h, fps), 20, 92)
end

function love.keypressed(key: string, _scancode: string, _isrepeat: boolean)
   if key == "escape" then
      love.event.quit(0)
   end
end
