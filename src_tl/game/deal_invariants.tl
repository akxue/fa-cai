-- Tile conservation invariant checks for DealState.
-- Pure — no imports from love, ui, scenes, or app.

require("core.types")
require("game.deal_types")

local M = {}

global record InvariantResult
   ok:      boolean
   error:   string
   details: string
end

-- Collects all tile_id strings from a list of tiles into a set.
local function collect_tile_ids(tiles: {Tile}, into: {string:integer})
   for _, t in ipairs(tiles) do
      local id = t.tile_id as string
      into[id] = (into[id] or 0) + 1
   end
end

-- Validates that the full set of 136 physical tiles is accounted for exactly once
-- across: wall, all player concealed tiles, all player open/concealed sets,
-- all player discards, all player opening_trim tiles, and any pending discard.
function M.validate_tile_conservation(deal: DealState): InvariantResult
   local counts: {string:integer} = {}

   -- Wall tiles
   collect_tile_ids(deal.wall.tiles, counts)

   for _, player in ipairs(deal.players) do
      -- Concealed tiles
      collect_tile_ids(player.hand.concealed_tiles, counts)
      -- All sets (open or concealed)
      for _, s in ipairs(player.hand.sets) do
         collect_tile_ids(s.tiles, counts)
      end
      -- Player discard pile
      collect_tile_ids(player.hand.discards, counts)
      -- Opening trim zone
      collect_tile_ids(player.opening_trim, counts)
   end

   -- Pending discard (if any)
   if deal.has_pending_discard then
      local id = deal.pending_discard.tile.tile_id as string
      counts[id] = (counts[id] or 0) + 1
   end

   -- The pending added-kong tile stays in concealed_tiles during the Qiang Gang
   -- window, so no extra accounting is needed here.

   -- Check exactly 136 unique tiles, each appearing exactly once.
   local total = 0
   local duplicates: {string} = {}
   for id, n in pairs(counts) do
      total = total + n
      if n > 1 then
         duplicates[#duplicates + 1] = id .. "(x" .. tostring(n) .. ")"
      end
   end

   if total ~= 136 then
      return {
         ok      = false,
         error   = "tile count mismatch",
         details = "expected 136 tiles, found " .. tostring(total),
      }
   end

   if #duplicates > 0 then
      table.sort(duplicates)
      return {
         ok      = false,
         error   = "duplicate tile_ids",
         details = table.concat(duplicates, ", "),
      }
   end

   return { ok = true, error = "", details = "" }
end

-- Checks that a TileSet has the expected structure.
function M.validate_set_structure(s: TileSet): InvariantResult
   local kind = s.kind as string
   local n = #s.tiles
   if kind == "chi" then
      if n ~= 3 then
         return { ok = false, error = "chi must have 3 tiles", details = "got " .. tostring(n) }
      end
   elseif kind == "peng" then
      if n ~= 3 then
         return { ok = false, error = "peng must have 3 tiles", details = "got " .. tostring(n) }
      end
      -- All tiles must share kind_id.
      local ref = s.tiles[1].kind_id
      for i = 2, n do
         if s.tiles[i].kind_id ~= ref then
            return { ok = false, error = "peng tiles not all same kind", details = "" }
         end
      end
   elseif kind == "kong" then
      if n ~= 4 then
         return { ok = false, error = "kong must have 4 tiles", details = "got " .. tostring(n) }
      end
      local ref = s.tiles[1].kind_id
      for i = 2, n do
         if s.tiles[i].kind_id ~= ref then
            return { ok = false, error = "kong tiles not all same kind", details = "" }
         end
      end
   else
      return { ok = false, error = "unknown set kind: " .. kind, details = "" }
   end
   return { ok = true, error = "", details = "" }
end

return M
