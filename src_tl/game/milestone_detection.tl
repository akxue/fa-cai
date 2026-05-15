-- Milestone fork detection for M2-S01.
-- Pure rules layer — no love/ui/scenes/app imports.
--
-- A "set" for milestone purposes is any of:
--   - Chi (run of 3 consecutive same-suit tiles)
--   - Peng (3 of a kind)
--   - Kong (4 of a kind, declared as kong)
--   - Concealed pung (3 of a kind in concealed_tiles, evaluated for milestones)
--
-- The total set count is `#hand.sets + max_concealed_sets(hand.concealed_tiles)`
-- evaluated at end-of-turn. M1's hand_validator looks for complete Hu shapes;
-- this module looks for the MAXIMUM number of disjoint sets that can be
-- carved from concealed_tiles regardless of leftover singletons or pairs.
--
-- See MILESTONE-2-PLAN.md §307 for the algorithm spec.

require("core.types")
require("game.deal_types")

local M = {}

local HONOR_KINDS: {string:boolean} = {
   east = true, south = true, west = true, north = true,
   fa_cai = true, hong_zhong = true, bai_ban = true,
}

local function count_kinds(tiles: {Tile}): {string:integer}
   local counts: {string:integer} = {}
   for _, t in ipairs(tiles) do
      local k = t.kind_id as string
      counts[k] = (counts[k] or 0) + 1
   end
   return counts
end

local function copy_counts(c: {string:integer}): {string:integer}
   local out: {string:integer} = {}
   for k, v in pairs(c) do out[k] = v end
   return out
end

local function sorted_kinds(counts: {string:integer}): {string}
   -- Caller (max_concealed_sets) builds counts from a tile list, so every
   -- entry is non-zero by construction. Sorting all keys is sufficient;
   -- max_sets_recursive advances past zero-count entries on its own.
   local out: {string} = {}
   for k in pairs(counts) do
      out[#out + 1] = k
   end
   table.sort(out)
   return out
end

-- ── Max-set decomposition ─────────────────────────────────────────────────
--
-- Recursive search: for the lowest-keyed remaining tile, try (a) consuming it
-- as part of a peng, (b) consuming it as the head of a chi, (c) discarding
-- it from the search (it stays in the hand but contributes no set). Return
-- the max over all branches.
--
-- Honor tiles can only be in peng (no chi). The sorted_kinds ordering keeps
-- the search deterministic.
--
-- For a 14-tile concealed hand this completes well under a millisecond; the
-- branching factor is at most 3 and the depth is bounded by tile count.

local function max_sets_recursive(counts: {string:integer}, kinds: {string}, idx: integer): integer
   -- Advance idx to the next kind with remaining tiles.
   while idx <= #kinds and (counts[kinds[idx]] or 0) == 0 do
      idx = idx + 1
   end
   if idx > #kinds then return 0 end

   local k = kinds[idx]
   local c = counts[k] as integer
   local best = 0

   -- Branch (a): form a peng of k.
   if c >= 3 then
      counts[k] = c - 3
      local sub = 1 + max_sets_recursive(counts, kinds, idx)
      if sub > best then best = sub end
      counts[k] = c
   end

   -- Branch (b): form a chi starting at k (suited tiles only).
   if not HONOR_KINDS[k] then
      local suit, rank_s = k:match("^([a-z]+)_(%d+)$")
      if suit and rank_s then
         local rank = tonumber(rank_s) as integer
         if rank <= 7 then
            local k2 = suit .. "_" .. tostring(rank + 1)
            local k3 = suit .. "_" .. tostring(rank + 2)
            if (counts[k2] or 0) >= 1 and (counts[k3] or 0) >= 1 then
               counts[k]  = c - 1
               counts[k2] = (counts[k2] as integer) - 1
               counts[k3] = (counts[k3] as integer) - 1
               local sub = 1 + max_sets_recursive(counts, kinds, idx)
               if sub > best then best = sub end
               counts[k]  = c
               counts[k2] = (counts[k2] as integer) + 1
               counts[k3] = (counts[k3] as integer) + 1
            end
         end
      end
   end

   -- Branch (c): skip this tile (still in hand but contributes no set).
   counts[k] = c - 1
   local sub = max_sets_recursive(counts, kinds, idx)
   if sub > best then best = sub end
   counts[k] = c

   return best
end

-- Returns the maximum number of disjoint sets (chi/pung) that can be carved
-- from concealed_tiles. Leftover singletons and pairs are ignored.
function M.max_concealed_sets(concealed_tiles: {Tile}): integer
   if #concealed_tiles == 0 then return 0 end
   local counts = count_kinds(concealed_tiles)
   local kinds  = sorted_kinds(counts)
   return max_sets_recursive(copy_counts(counts), kinds, 1)
end

-- Total set count for the player at end-of-turn:
--   #hand.sets (open + concealed kongs already declared)
--   + max_concealed_sets(hand.concealed_tiles)
function M.total_set_count(hand: PlayerHand): integer
   return #hand.sets + M.max_concealed_sets(hand.concealed_tiles)
end

return M
