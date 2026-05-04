-- Chi/Peng/Kong legality helpers. Pure — no imports from love, ui, scenes, or app.

require("core.types")
require("game.deal_types")

local M = {}

local HONOR_KINDS: {string:boolean} = {
   east = true, south = true, west = true, north = true,
   fa_cai = true, hong_zhong = true, bai_ban = true,
}

-- Returns true if the player is the immediately next player in turn order.
-- player_count is total players (usually 4); turns wrap around.
function M.is_next_player(discarder: integer, caller: integer, player_count: integer): boolean
   return ((discarder % player_count) + 1) == caller
end

-- ── Chi ───────────────────────────────────────────────────────────────────

-- Returns true if `caller` can Chi `discarded_tile` using the two `other_tiles`
-- from their hand.
-- Validation:
--   - discarded tile must be a suited (non-honor) tile
--   - caller must be the next player in turn order
--   - other_tiles must be exactly 2 tiles
--   - the three tiles together must form a valid Chi (consecutive same suit)
function M.can_chi(
   discarded:    Tile,
   other_tiles:  {Tile},
   discarder:    integer,
   caller:       integer,
   player_count: integer
): boolean
   if not M.is_next_player(discarder, caller, player_count) then
      return false
   end
   if HONOR_KINDS[discarded.kind_id as string] then
      return false
   end
   if #other_tiles ~= 2 then return false end

   -- Collect the three kind_ids and verify they form a consecutive same-suit sequence.
   local all_three: {string} = {
      discarded.kind_id as string,
      other_tiles[1].kind_id as string,
      other_tiles[2].kind_id as string,
   }
   -- Extract suits and ranks.
   local suit: string = ""
   local ranks: {integer} = {}
   for _, k in ipairs(all_three) do
      if HONOR_KINDS[k] then return false end
      local s, r_s = k:match("^([a-z]+)_(%d+)$")
      if not s or not r_s then return false end
      if suit == "" then suit = s
      elseif suit ~= s then return false end
      ranks[#ranks + 1] = tonumber(r_s) as integer
   end
   table.sort(ranks)
   return ranks[2] == ranks[1] + 1 and ranks[3] == ranks[2] + 1
end

-- ── Peng ──────────────────────────────────────────────────────────────────

-- Returns true if `caller` can Peng `discarded_tile` using two matching tiles from hand.
-- Caller cannot be the discarder themselves.
function M.can_peng(
   discarded:   Tile,
   hand_tiles:  {Tile},
   discarder:   integer,
   caller:      integer
): boolean
   if caller == discarder then return false end
   local matching = 0
   for _, t in ipairs(hand_tiles) do
      if t.kind_id == discarded.kind_id then matching = matching + 1 end
   end
   return matching >= 2
end

-- ── Open Kong (from discard) ───────────────────────────────────────────────

-- Returns true if `caller` can declare an open Kong on `discarded_tile`.
-- Requires 3 matching tiles in hand (plus the 4th from discard = 4 total).
function M.can_open_kong(
   discarded:   Tile,
   hand_tiles:  {Tile},
   discarder:   integer,
   caller:      integer
): boolean
   if caller == discarder then return false end
   local matching = 0
   for _, t in ipairs(hand_tiles) do
      if t.kind_id == discarded.kind_id then matching = matching + 1 end
   end
   return matching >= 3
end

-- ── Concealed Kong ────────────────────────────────────────────────────────

-- Returns true if `caller` can declare a concealed Kong of `kind_id` from their hand.
-- Requires 4 matching tiles in hand.
function M.can_concealed_kong(
   kind_id:    TileKindId,
   hand_tiles: {Tile}
): boolean
   local matching = 0
   for _, t in ipairs(hand_tiles) do
      if t.kind_id == kind_id then matching = matching + 1 end
   end
   return matching >= 4
end

-- ── Added Kong ────────────────────────────────────────────────────────────

-- Returns true if `caller` can declare an added Kong (upgrading an open Peng).
-- Requires: an open Peng of the same kind AND the fourth tile in concealed hand.
function M.can_added_kong(
   tile:       Tile,
   hand_tiles: {Tile},
   open_sets:  {TileSet}
): boolean
   -- Find a matching open Peng.
   local has_peng = false
   for _, s in ipairs(open_sets) do
      if s.kind == ("peng" as TileSetKind) and #s.tiles > 0 then
         if s.tiles[1].kind_id == tile.kind_id then
            has_peng = true
            break
         end
      end
   end
   if not has_peng then return false end
   -- Check the fourth tile is in hand.
   for _, t in ipairs(hand_tiles) do
      if t.kind_id == tile.kind_id then return true end
   end
   return false
end

-- ── Legal Chi combinations ─────────────────────────────────────────────────

-- Returns all pairs of tile_ids from hand_tiles that can form a Chi
-- together with `discarded`, as a list of {TileId, TileId} pairs.
function M.chi_combinations(discarded: Tile, hand_tiles: {Tile}): {{TileId}}
   local results: {{TileId}} = {}
   if HONOR_KINDS[discarded.kind_id as string] then return results end

   local dk = discarded.kind_id as string
   local dsuite, drank_s = dk:match("^([a-z]+)_(%d+)$")
   if not dsuite or not drank_s then return results end
   local drank = tonumber(drank_s) as integer

   -- Find all suited tiles from the same suit in hand (exclude duplicates of discarded).
   -- We need two more tiles that together with discard form consecutive ranks.
   -- Possible sequences: (d-2,d-1,d), (d-1,d,d+1), (d,d+1,d+2).
   local patterns: {{integer}} = {}
   if drank >= 3 then patterns[#patterns + 1] = {drank - 2, drank - 1} end
   if drank >= 2 and drank <= 8 then patterns[#patterns + 1] = {drank - 1, drank + 1} end
   if drank <= 7 then patterns[#patterns + 1] = {drank + 1, drank + 2} end

   for _, pair_ranks in ipairs(patterns) do
      local r1 = pair_ranks[1]
      local r2 = pair_ranks[2]
      local k1 = dsuite .. "_" .. tostring(r1)
      local k2 = dsuite .. "_" .. tostring(r2)
      -- Find one tile of k1 and one tile of k2 in hand.
      local tid1: TileId = "" as TileId
      local tid2: TileId = "" as TileId
      for _, t in ipairs(hand_tiles) do
         if (t.kind_id as string) == k1 and (tid1 as string) == "" then
            tid1 = t.tile_id
         elseif (t.kind_id as string) == k2 and (tid2 as string) == "" then
            tid2 = t.tile_id
         end
      end
      if (tid1 as string) ~= "" and (tid2 as string) ~= "" then
         results[#results + 1] = {tid1, tid2}
      end
   end

   return results
end

return M
