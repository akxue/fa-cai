-- ID generation helpers. Pure — no side effects.

require("core.types")

local M = {}

local COPY_SUFFIXES <const>: {string} = {"a", "b", "c", "d"}

-- Returns the physical tile ID for the nth copy (1-indexed) of a kind.
function M.tile_id(kind_id: TileKindId, copy: integer): TileId
   return ((kind_id as string) .. "_" .. COPY_SUFFIXES[copy]) as TileId
end

return M
