-- Ting distance: how many tiles away from reaching ting (one tile from a valid Hu).
-- -1 means already in ting (need 0 more tiles, i.e. draw any winning tile to complete).
-- Pure — no imports from love, ui, scenes, app, or ai.
--
-- Convention (matching plan vocab):
--   ting_distance = -1  →  already ting (hand wins on next matching draw)
--   ting_distance =  0  →  one tile away from ting
--   ting_distance =  n  →  n+1 tiles away from ting
--
-- Internally we compute "sets_needed" (how many more set tiles are required to fully
-- decompose into 4-sets+pair or a special shape) and subtract 1 for the ting definition.

require("core.types")
require("game.deal_types")

local M = {}

-- ── Helpers ────────────────────────────────────────────────────────────────

local HONOR_KINDS: {string:boolean} = {
   east = true, south = true, west = true, north = true,
   fa_cai = true, hong_zhong = true, bai_ban = true,
}

local ORPHAN_KINDS: {string} = {
   "tiao_1","tiao_9","wan_1","wan_9","bing_1","bing_9",
   "east","south","west","north","fa_cai","hong_zhong","bai_ban",
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
   local out: {string} = {}
   for k, v in pairs(counts) do
      if v > 0 then out[#out + 1] = k end
   end
   table.sort(out)
   return out
end

-- ── Standard shape ting distance ──────────────────────────────────────────
-- Returns the minimum number of additional tiles needed beyond what is in `counts`
-- to reach a decomposable hand (4 sets + pair).
-- `open_set_count` sets are already declared; we only need (4 - open_set_count) more.

-- Minimum tiles needed to finish `n` complete sets from the given counts.
-- Uses DFS with memoisation via the (sorted counts, need) signature.
local function min_sets_needed(counts: {string:integer}, need: integer): integer
   if need == 0 then
      -- Check that counts is now empty (all tiles accounted for).
      for _, v in pairs(counts) do
         if v > 0 then return 100 end   -- leftover tiles = invalid path
      end
      return 0
   end

   local kinds = sorted_kinds(counts)
   if #kinds == 0 then
      -- No tiles left but still need sets — each missing set costs 3 tiles,
      -- but we express cost as tiles-to-add: a missing triplet costs 3, a missing
      -- chi costs 3. Return a large number to indicate this path is suboptimal.
      return need * 3
   end

   local first = kinds[1]
   local c = counts[first]
   local best = need * 3   -- worst case

   -- Option A: complete a triplet using `first` (need up to 3, pay for missing copies).
   -- We can always "pretend" to complete a triplet by adding (3 - min(c,3)) tiles.
   do
      local have = math.min(c, 3)
      local cost = 3 - have
      local cc = copy_counts(counts)
      cc[first] = c - have
      local sub = min_sets_needed(cc, need - 1)
      if cost + sub < best then best = cost + sub end
   end

   -- Option B: complete a chi starting at `first` (only suited tiles, rank <= 7).
   if not HONOR_KINDS[first] then
      local suit, rank_s = first:match("^([a-z]+)_(%d+)$")
      if suit and rank_s then
         local rank = tonumber(rank_s) as integer
         if rank <= 7 then
            local k2 = suit .. "_" .. tostring(rank + 1)
            local k3 = suit .. "_" .. tostring(rank + 2)
            local have2 = math.min(counts[k2] or 0, 1)
            local have3 = math.min(counts[k3] or 0, 1)
            local cost = (1 - math.min(c, 1)) + (1 - have2) + (1 - have3)
            local cc = copy_counts(counts)
            cc[first] = c - math.min(c, 1)
            cc[k2] = (counts[k2] or 0) - have2
            cc[k3] = (counts[k3] or 0) - have3
            local sub = min_sets_needed(cc, need - 1)
            if cost + sub < best then best = cost + sub end
         end
      end
   end

   return best
end

-- Returns ting distance for the standard four-sets-pair shape.
-- concealed_tiles: the player's current concealed tiles (not including incoming tile).
-- open_sets: already-declared open/concealed sets.
function M.ting_distance_standard(concealed_tiles: {Tile}, open_sets: {TileSet}): integer
   local need_sets = 4 - #open_sets
   local counts = count_kinds(concealed_tiles)
   local kinds = sorted_kinds(counts)
   local best = 100

   -- Try each kind as the pair candidate.
   for _, pair_kind in ipairs(kinds) do
      local c = counts[pair_kind]
      -- Pair cost: 0 if have >=2, 1 if have 1, 2 if have 0 (but we'd never try 0).
      if c >= 1 then
         local pair_cost = (c >= 2) and 0 or 1
         local cc = copy_counts(counts)
         cc[pair_kind] = c - math.min(c, 2)
         local sets_cost = min_sets_needed(cc, need_sets)
         local total = pair_cost + sets_cost
         if total < best then best = total end
      end
   end

   -- Also try adding a new pair kind (cost 2).
   -- This handles the case where we have no pair candidate in hand yet.
   -- Cost = 2 (need two tiles) + min_sets for all counts.
   do
      local sets_cost = min_sets_needed(copy_counts(counts), need_sets)
      local total = 2 + sets_cost
      if total < best then best = total end
   end

   -- Convert "tiles needed to reach valid Hu" to ting distance.
   -- ting_distance = (tiles needed to win) - 1
   -- (tiles needed to win) = tiles needed to become ting + 1 (the winning draw)
   -- But ting distance = how far from ting, not from winning.
   -- ting = need 1 more tile to complete → tiles_needed_to_reach_ting = best - 1... wait.
   --
   -- Let's align with the plan:
   -- ting_distance = -1  means already ting (can win on next tile).
   -- A hand in ting needs 0 tiles added (already has 13, needs 1 draw to win).
   -- min_sets_needed returns tiles-to-add to make a *complete* 14-tile winning hand.
   -- So: if best == 1  → needs 1 more tile to complete → already ting → distance = -1.
   --     if best == 0  → already complete (14 tiles with open sets accounted for) → ting, win now.
   --     if best == 2  → needs 2 more tiles → distance = 0.
   --     if best == n  → distance = n - 2.
   --
   -- Wait — concealed_tiles is the hand WITHOUT an incoming tile. A 13-tile hand
   -- (3 open sets × 3 tiles = 9, concealed = 4? No...) Let me reconsider.
   --
   -- A player with k open sets has (13 - 3k) concealed tiles before drawing.
   -- ting means: the 13 - 3k concealed tiles, together with one specific incoming tile,
   -- form a complete winning hand (4-k sets + pair from concealed).
   -- So `best` = tiles needed to add to the current concealed_tiles to make a full
   -- decomposable block (needs (4-k)*3 + 2 tiles for sets+pair).
   -- current concealed count = 13 - 3k.
   -- needed for full = (4-k)*3 + 2 = 12 - 3k + 2 = 14 - 3k.
   -- tiles to add = (14 - 3k) - (13 - 3k) = 1 → one incoming tile.
   -- So a ting hand has best == 1 → ting_distance = -1.
   -- A hand needing 2 more has best == 2 → ting_distance = 0.
   -- Generalising: ting_distance = best - 2.

   return best - 2
end

-- ── Seven Pairs ────────────────────────────────────────────────────────────

function M.ting_distance_seven_pairs(concealed_tiles: {Tile}): integer
   local counts = count_kinds(concealed_tiles)
   local pair_count = 0
   for _, v in pairs(counts) do
      if v >= 2 then pair_count = pair_count + 1 end
   end
   -- Need 7 pairs. tiles_needed = 7 - pair_count.
   -- ting_distance = tiles_needed - 2.
   local tiles_needed = 7 - pair_count
   return tiles_needed - 2
end

-- ── Thirteen Orphans ───────────────────────────────────────────────────────

function M.ting_distance_thirteen_orphans(concealed_tiles: {Tile}): integer
   local counts = count_kinds(concealed_tiles)
   local have_orphan = 0
   local has_dup = false
   for _, k in ipairs(ORPHAN_KINDS) do
      local n = counts[k] or 0
      if n >= 1 then
         have_orphan = have_orphan + 1
         if n >= 2 then has_dup = true end
      end
   end
   -- Need all 13 orphan types + one duplicate.
   -- Missing orphan types: 13 - have_orphan.
   -- Need a dup: if has_dup already, 0 extra; otherwise need 1 extra.
   local missing_types = 13 - have_orphan
   local dup_cost = has_dup and 0 or 1
   local tiles_needed = missing_types + dup_cost
   return tiles_needed - 2
end

-- ── Combined ───────────────────────────────────────────────────────────────

-- Returns the minimum ting distance across all applicable shapes.
function M.ting_distance(concealed_tiles: {Tile}, open_sets: {TileSet}): integer
   local d = M.ting_distance_standard(concealed_tiles, open_sets)
   -- Seven Pairs and Thirteen Orphans only apply when no open sets.
   if #open_sets == 0 then
      local d7 = M.ting_distance_seven_pairs(concealed_tiles)
      local d13 = M.ting_distance_thirteen_orphans(concealed_tiles)
      if d7 < d then d = d7 end
      if d13 < d then d = d13 end
   end
   return d
end

-- ── Live-aware variant ────────────────────────────────────────────────────
-- The plain ting_distance treats every kind as if it has 4 copies available.
-- The live-aware variant takes a `live_counts` map of how many copies of each
-- kind are still drawable from the AI's perspective (4 minus visible copies in
-- own hand, all sets, and all discards) and prunes paths that would require
-- adding a tile with no remaining live copies.
--
-- A path is INF when no decomposition is possible without dead waits.

local INF <const> = 100

local function copy_live(live: {string:integer}): {string:integer}
   local out: {string:integer} = {}
   for k, v in pairs(live) do out[k] = v end
   return out
end

local function dec_live(live: {string:integer}, k: string, n: integer): {string:integer}
   if n == 0 then return live end
   local out = copy_live(live)
   out[k] = (out[k] or 0) - n
   return out
end

-- Live version of min_sets_needed: prunes triplet/chi options whose required
-- additions exceed remaining live copies.
local function min_sets_needed_live(counts: {string:integer}, live: {string:integer}, need: integer): integer
   if need == 0 then
      for _, v in pairs(counts) do
         if v > 0 then return INF end
      end
      return 0
   end

   local kinds = sorted_kinds(counts)
   if #kinds == 0 then
      -- Need more sets but no tiles to seed from. Each set is 3 unrelated
      -- tiles, so cost is at least need*3 — but we'd also need each kind to
      -- have live >= the requested copies, which is hard to express here.
      -- Return INF to discourage these paths; the caller's outer loop covers
      -- "add brand-new pair/sets" cases via the pair-only branch.
      return INF
   end

   local first = kinds[1]
   local c = counts[first]
   local best = INF

   -- Option A: complete a triplet using `first`.
   do
      local have = math.min(c, 3)
      local cost = 3 - have
      if (live[first] or 0) >= cost then
         local cc = copy_counts(counts)
         cc[first] = c - have
         local ll = dec_live(live, first, cost)
         local sub = min_sets_needed_live(cc, ll, need - 1)
         if cost + sub < best then best = cost + sub end
      end
   end

   -- Option B: complete a chi starting at `first`.
   if not HONOR_KINDS[first] then
      local suit, rank_s = first:match("^([a-z]+)_(%d+)$")
      if suit and rank_s then
         local rank = tonumber(rank_s) as integer
         if rank <= 7 then
            local k2 = suit .. "_" .. tostring(rank + 1)
            local k3 = suit .. "_" .. tostring(rank + 2)
            local have1 = math.min(c, 1)
            local have2 = math.min(counts[k2] or 0, 1)
            local have3 = math.min(counts[k3] or 0, 1)
            local cost1 = 1 - have1
            local cost2 = 1 - have2
            local cost3 = 1 - have3
            if (live[first] or 0) >= cost1
               and (live[k2] or 0) >= cost2
               and (live[k3] or 0) >= cost3 then
               local cc = copy_counts(counts)
               cc[first] = c - have1
               cc[k2] = (counts[k2] or 0) - have2
               cc[k3] = (counts[k3] or 0) - have3
               local ll = dec_live(live, first, cost1)
               ll = dec_live(ll, k2, cost2)
               ll = dec_live(ll, k3, cost3)
               local sub = min_sets_needed_live(cc, ll, need - 1)
               local total_cost = cost1 + cost2 + cost3
               if total_cost + sub < best then best = total_cost + sub end
            end
         end
      end
   end

   return best
end

function M.ting_distance_standard_live(
   concealed_tiles: {Tile},
   open_sets:       {TileSet},
   live_counts:     {string:integer}
): integer
   local need_sets = 4 - #open_sets
   local counts = count_kinds(concealed_tiles)
   local kinds = sorted_kinds(counts)
   local best = INF

   for _, pair_kind in ipairs(kinds) do
      local c = counts[pair_kind]
      if c >= 1 then
         local pair_cost = (c >= 2) and 0 or 1
         if (live_counts[pair_kind] or 0) >= pair_cost then
            local cc = copy_counts(counts)
            cc[pair_kind] = c - math.min(c, 2)
            local ll = dec_live(live_counts, pair_kind, pair_cost)
            local sets_cost = min_sets_needed_live(cc, ll, need_sets)
            local total = pair_cost + sets_cost
            if total < best then best = total end
         end
      end
   end

   -- Try a brand-new pair (kind not in hand) when at least one kind has live >= 2.
   local new_pair_kinds: {string} = {}
   for k, lv in pairs(live_counts) do
      if lv >= 2 and (counts[k] or 0) == 0 then
         new_pair_kinds[#new_pair_kinds + 1] = k
      end
   end
   table.sort(new_pair_kinds)
   for _, k in ipairs(new_pair_kinds) do
      local sets_cost = min_sets_needed_live(copy_counts(counts), dec_live(live_counts, k, 2), need_sets)
      local total = 2 + sets_cost
      if total < best then best = total end
   end

   if best >= INF then return INF end
   return best - 2
end

function M.ting_distance_seven_pairs_live(
   concealed_tiles: {Tile},
   live_counts:     {string:integer}
): integer
   local counts = count_kinds(concealed_tiles)
   local pair_count = 0
   local singles: {string} = {}
   for k, v in pairs(counts) do
      if v >= 2 then pair_count = pair_count + 1
      elseif v == 1 then singles[#singles + 1] = k end
   end
   table.sort(singles)

   local needed = 7 - pair_count
   if needed <= 0 then return -1 end
   local total_tiles = 0

   -- Greedy: upgrade existing singles where live allows (cost 1 each).
   for _, k in ipairs(singles) do
      if needed <= 0 then break end
      if (live_counts[k] or 0) >= 1 then
         total_tiles = total_tiles + 1
         needed = needed - 1
      end
   end

   -- Then brand-new pairs from any kind with live >= 2 not already in hand (cost 2 each).
   if needed > 0 then
      local new_kinds: {string} = {}
      for k, lv in pairs(live_counts) do
         if lv >= 2 and (counts[k] or 0) == 0 then
            new_kinds[#new_kinds + 1] = k
         end
      end
      table.sort(new_kinds)
      for _, _k in ipairs(new_kinds) do
         if needed <= 0 then break end
         total_tiles = total_tiles + 2
         needed = needed - 1
      end
   end

   if needed > 0 then return INF end
   return total_tiles - 2
end

function M.ting_distance_thirteen_orphans_live(
   concealed_tiles: {Tile},
   live_counts:     {string:integer}
): integer
   local counts = count_kinds(concealed_tiles)
   local have_orphan = 0
   local has_dup = false
   local missing_kinds: {string} = {}
   local single_kinds: {string} = {}
   for _, k in ipairs(ORPHAN_KINDS) do
      local n = counts[k] or 0
      if n >= 1 then
         have_orphan = have_orphan + 1
         if n >= 2 then has_dup = true
         else single_kinds[#single_kinds + 1] = k end
      else
         missing_kinds[#missing_kinds + 1] = k
      end
   end

   -- Need every missing orphan kind to have at least 1 live copy.
   for _, k in ipairs(missing_kinds) do
      if (live_counts[k] or 0) < 1 then return INF end
   end

   -- Need a duplicate: if not present, at least one orphan kind in hand needs live >= 1.
   local dup_cost = 0
   if not has_dup then
      dup_cost = 1
      local can_dup = false
      for _, k in ipairs(single_kinds) do
         if (live_counts[k] or 0) >= 1 then can_dup = true; break end
      end
      -- If no single can be duplicated, try drawing a brand-new dup of any
      -- already-held orphan kind with live >= 1.
      if not can_dup then return INF end
   end

   local missing_types = 13 - have_orphan
   local tiles_needed = missing_types + dup_cost
   return tiles_needed - 2
end

-- Combined live ting distance — minimum across all applicable shapes.
function M.ting_distance_live(
   concealed_tiles: {Tile},
   open_sets:       {TileSet},
   live_counts:     {string:integer}
): integer
   local d = M.ting_distance_standard_live(concealed_tiles, open_sets, live_counts)
   if #open_sets == 0 then
      local d7 = M.ting_distance_seven_pairs_live(concealed_tiles, live_counts)
      local d13 = M.ting_distance_thirteen_orphans_live(concealed_tiles, live_counts)
      if d7 < d then d = d7 end
      if d13 < d then d = d13 end
   end
   return d
end

return M
