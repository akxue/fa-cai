-- LÖVE source-root entry. Hand-authored shim: LÖVE looks for a top-level
-- main.lua in its source root, but we keep generated Lua under src/. This
-- file just adds src/ and lua_compat/ to package.path, then requires the
-- generated src/main.lua, which sets the love.* callbacks.
--
-- Running LÖVE from the project root (rather than src/) lets the game
-- access assets/ via love.graphics.newImage("assets/...") — assets sit
-- alongside src/ at the repo root, not inside the generated tree.

package.path = "src/?.lua;src/?/init.lua;lua_compat/?.lua;" .. package.path
-- dofile (not require) to avoid the circular module-name conflict: LÖVE
-- already cached this file as `package.loaded.main` when it required us
-- to boot, so a second require("main") here resolves to ourselves.
dofile("src/main.lua")
