-- Minimal busted 2.x type declarations

global describe:    function(name: string, fn: function())
global it:          function(name: string, fn: function())
global before_each: function(fn: function())
global after_each:  function(fn: function())
global pending:     function(name: string)

global record assert
   record are
      equal:     function(expected: any, actual: any)
      same:      function(expected: any, actual: any)
      not_equal: function(expected: any, actual: any)
   end
   is_true:    function(val: any)
   is_false:   function(val: any)
   is_nil:     function(val: any)
   is_not_nil: function(val: any)
   truthy:     function(val: any)
   falsy:      function(val: any)
end
