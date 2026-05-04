-- Minimal LÖVE 11.x type declarations (S00 scope — expand per slice as needed)

global record Font
end

global record love
   load:       function()
   update:     function(dt: number)
   draw:       function()
   keypressed: function(key: string, scancode: string, isrepeat: boolean)
   quit:       function(): boolean

   record graphics
      print:                function(text: string, x: number, y: number)
      setColor:             function(r: number, g: number, b: number, a: number)
      setBackgroundColor:   function(r: number, g: number, b: number, a: number)
      rectangle:            function(mode: string, x: number, y: number, w: number, h: number)
      getWidth:             function(): number
      getHeight:            function(): number
      getDimensions:        function(): (number, number)
      newFont:              function(size: number): Font
      setFont:              function(font: Font)
      getFont:              function(): Font
   end

   record window
      setTitle:      function(title: string)
      getDimensions: function(): (number, number)
   end

   record timer
      getFPS: function(): number
   end

   record event
      quit: function(exitcode: integer)
   end
end
