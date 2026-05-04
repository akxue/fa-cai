-- bit32 polyfill: needed because Teal generates 5.1-compat code that requires
-- `bit32`, but neither LuaJIT (ships `bit`) nor Lua 5.4 (dropped `bit32`)
-- provides it.
--
-- Strategy:
--   * If LuaJIT's `bit` is available, alias its functions to bit32's API.
--   * Otherwise (Lua 5.3/5.4), build the functions via `load()` so this file
--     itself stays parseable under Lua 5.1.

local ok, bit = pcall(require, "bit")
if ok and bit then
   return {
      band    = bit.band,
      bor     = bit.bor,
      bxor    = bit.bxor,
      bnot    = bit.bnot,
      lshift  = bit.lshift,
      rshift  = bit.rshift,
      arshift = bit.arshift,
   }
end

return assert(load([[
   local function u32(x) return x & 0xffffffff end
   return {
      band    = function(a, b)  return u32(a & b)  end,
      bor     = function(a, b)  return u32(a | b)  end,
      bxor    = function(a, b)  return u32(a ~ b)  end,
      bnot    = function(a)     return u32(~a)     end,
      lshift  = function(a, n)  return u32(a << n) end,
      rshift  = function(a, n)  return u32(a >> n) end,
      arshift = function(a, n)  return a >> n      end,
   }
]]))()
