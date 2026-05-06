-- Minimal LÖVE 11.x type declarations. Expand per slice as needed.

global record Font
   getWidth:  function(Font, text: string): number
   getHeight: function(Font): number
   getWrap:   function(Font, text: string, wraplimit: number): (number, {string})
end

global record Image
   getWidth:      function(Image): number
   getHeight:     function(Image): number
   getDimensions: function(Image): (number, number)
end

global record love
   load:         function()
   update:       function(dt: number)
   draw:         function()
   keypressed:   function(key: string, scancode: string, isrepeat: boolean)
   mousepressed: function(x: number, y: number, button: integer, istouch: boolean, presses: integer)
   quit:         function(): boolean

   record graphics
      print:                function(text: string, x: number, y: number)
      printf:               function(text: string, x: number, y: number, limit: number, align: string)
      setColor:             function(r: number, g: number, b: number, a: number)
      setBackgroundColor:   function(r: number, g: number, b: number, a: number)
      rectangle:            function(mode: string, x: number, y: number, w: number, h: number)
      line:                 function(x1: number, y1: number, x2: number, y2: number)
      setLineWidth:         function(w: number)
      getWidth:             function(): number
      getHeight:            function(): number
      getDimensions:        function(): (number, number)
      newFont:              function(size: number): Font
      setFont:              function(font: Font)
      getFont:              function(): Font
      newImage:             function(path: string): Image
      draw:                 function(image: Image, x: number, y: number, r: number, sx: number, sy: number)
   end

   record window
      setTitle:      function(title: string)
      setMode:       function(width: number, height: number, flags: {string:any})
      getDimensions: function(): (number, number)
   end

   record timer
      getFPS:   function(): number
      getDelta: function(): number
   end

   record event
      quit: function(exitcode: integer)
   end
end
