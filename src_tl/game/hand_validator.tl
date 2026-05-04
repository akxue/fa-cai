-- Hand validation: finds all valid WinShapes for a 14-tile winning hand.
-- Pure — no imports from love, ui, scenes, app, or ai.

require("core.types")
require("game.deal_types")

local M = {}

-- ── Helpers ────────────────────────────────────────────────────────────────

local TERMINALS_AND_HONORS: {string:boolean} = {
   tiao_1 = true, tiao_9 = true,
   wan_1  = true, wan_9  = true,
   bing_1 = true, bing_9 = true,
   east   = true, south  = true, west  = true, north = true,
   fa_cai = true, hong_zhong = true, bai_ban = true,
}

local HONOR_KINDS: {string:boolean} = {
   east = true, south = true, west = true, north = true,
   fa_cai = true, hong_zhong = true, bai_ban = true,
}

local DRAGON_KINDS: {string:boolean} = {
   fa_cai = true, hong_zhong = true, bai_ban = true,
}

-- Counts kind_ids in a tile list. Returns {kind_id -> count}.
local function count_kinds(tiles: {Tile}): {string:integer}
   local counts: {string:integer} = {}
   for _, t in ipairs(tiles) do
      local k = t.kind_id as string
      counts[k] = (counts[k] or 0) + 1
   end
   return counts
end

-- Returns a sorted list of kind_id strings present in a count map.
local function sorted_kinds(counts: {string:integer}): {string}
   local out: {string} = {}
   for k, v in pairs(counts) do
      if v > 0 then out[#out + 1] = k end
   end
   table.sort(out)
   return out
end

-- Shallow-copy a counts map.
local function copy_counts(counts: {string:integer}): {string:integer}
   local out: {string:integer} = {}
   for k, v in pairs(counts) do out[k] = v end
   return out
end

-- Gets the suit of a kind_id ("tiao","wan","bing","honor").
local function suit_of(kind_id: string): string
   if HONOR_KINDS[kind_id] then return "honor" end
   local s = kind_id:match("^([a-z]+)_")
   return s or "honor"
end

-- ── Standard four-sets + pair decomposition ────────────────────────────────

-- Tries to decompose `counts` entirely into Chi/Peng/Kong meld groups (no pair).
-- Returns list of {kind, kind_id(s)} describing each set found, or nil on failure.
-- Sets already declared are not re-decomposed — caller handles that.
local function try_decompose_sets(counts: {string:integer}, kinds: {string}): {{string}} | nil
   -- Find first kind with tiles remaining.
   local first: string = ""
   for _, k in ipairs(kinds) do
      if (counts[k] or 0) > 0 then first = k; break end
   end
   if first == "" then return {} end   -- nothing left, success

   local c = counts[first]

   -- Try Peng (triplet) of `first`
   if c >= 3 then
      local cc = copy_counts(counts)
      cc[first] = c - 3
      local rest = try_decompose_sets(cc, kinds)
      if rest then
         local rest_ok = rest as {{string}}
         local result: {{string}} = { { "peng", first } }
         for _, s in ipairs(rest_ok) do result[#result + 1] = s end
         return result
      end
   end

   -- Try Chi starting with `first` (only for suited tiles with rank)
   if not HONOR_KINDS[first] then
      local suit, rank_s = first:match("^([a-z]+)_(%d+)$")
      if suit and rank_s then
         local rank = tonumber(rank_s) as integer
         if rank <= 7 then
            local k2 = suit .. "_" .. tostring(rank + 1)
            local k3 = suit .. "_" .. tostring(rank + 2)
            if (counts[k2] or 0) >= 1 and (counts[k3] or 0) >= 1 then
               local cc = copy_counts(counts)
               cc[first] = c - 1
               cc[k2] = (cc[k2] as integer) - 1
               cc[k3] = (cc[k3] as integer) - 1
               local rest = try_decompose_sets(cc, kinds)
               if rest then
                  local rest_ok = rest as {{string}}
                  local result: {{string}} = { { "chi", first, k2, k3 } }
                  for _, s in ipairs(rest_ok) do result[#result + 1] = s end
                  return result
               end
            end
         end
      end
   end

   return nil
end

-- Returns all possible standard WinShapes for a full 14-tile hand.
-- open_sets are pre-declared (already count toward the 4 sets).
-- concealed_14 is concealed_tiles + incoming tile (14 - 3*#open_sets tiles).
local function find_standard_shapes(concealed_14: {Tile}, open_sets: {TileSet}): {WinShape}
   local needed_sets = 4 - #open_sets   -- sets to find in concealed tiles
   local counts = count_kinds(concealed_14)
   local kinds = sorted_kinds(counts)
   local results: {WinShape} = {}

   -- Try each kind as the pair.
   for _, pair_kind in ipairs(kinds) do
      if (counts[pair_kind] or 0) >= 2 then
         local cc = copy_counts(counts)
         cc[pair_kind] = (cc[pair_kind] as integer) - 2
         -- Check remaining tile count matches needed_sets * 3
         local remaining = 0
         for _, v in pairs(cc) do remaining = remaining + v end
         if remaining == needed_sets * 3 then
            local decomp = try_decompose_sets(cc, kinds)
            if decomp then
               local decomp_ok = decomp as {{string}}
               if #decomp_ok == needed_sets then
               -- Build WinShape sets list from open + decomposed concealed
               local shape_sets: {TileSet} = {}
               for _, s in ipairs(open_sets) do
                  shape_sets[#shape_sets + 1] = s
               end
               for _, s in ipairs(decomp_ok) do
                  local sk: TileSetKind
                  local fake_tiles: {Tile} = {}
                  if s[1] == "peng" then
                     sk = "peng" as TileSetKind
                     local k = s[2]
                     for _ = 1, 3 do
                        fake_tiles[#fake_tiles + 1] = {
                           tile_id = (k .. "_?") as TileId,
                           kind_id = k as TileKindId,
                        }
                     end
                  else
                     sk = "chi" as TileSetKind
                     for ci = 2, 4 do
                        local k = s[ci]
                        fake_tiles[#fake_tiles + 1] = {
                           tile_id = (k .. "_?") as TileId,
                           kind_id = k as TileKindId,
                        }
                     end
                  end
                  shape_sets[#shape_sets + 1] = {
                     kind = sk,
                     visibility = "concealed" as SetVisibility,
                     tiles = fake_tiles,
                     called_from = -1,
                  }
               end
               results[#results + 1] = {
                  kind = "standard_four_sets_pair" as WinShapeKind,
                  sets = shape_sets,
                  pair_kind = pair_kind as TileKindId,
               }
               end   -- if #decomp_ok == needed_sets
            end   -- if decomp
         end   -- if remaining ==
      end   -- if counts >= 2
   end   -- for pair_kind

   return results
end

-- ── Seven Pairs ────────────────────────────────────────────────────────────

local function find_seven_pairs(concealed_14: {Tile}): {WinShape}
   if #concealed_14 ~= 14 then return {} end
   local counts = count_kinds(concealed_14)
   local pair_kinds: {string} = {}
   for k, n in pairs(counts) do
      if n == 2 then pair_kinds[#pair_kinds + 1] = k
      elseif n ~= 0 then return {} end   -- must be exactly pairs
   end
   if #pair_kinds ~= 7 then return {} end
   -- All seven must be distinct kinds (already guaranteed since each has count 2).
   return {
      {
         kind = "seven_pairs" as WinShapeKind,
         sets = {},
         pair_kind = pair_kinds[1] as TileKindId,
      }
   }
end

-- ── Thirteen Orphans ───────────────────────────────────────────────────────

local ORPHAN_KINDS: {string} = {
   "tiao_1","tiao_9","wan_1","wan_9","bing_1","bing_9",
   "east","south","west","north","fa_cai","hong_zhong","bai_ban",
}

local function find_thirteen_orphans(concealed_14: {Tile}): {WinShape}
   if #concealed_14 ~= 14 then return {} end
   local counts = count_kinds(concealed_14)
   -- Every orphan must appear at least once; exactly one appears twice.
   local dup_kind: string = ""
   for _, k in ipairs(ORPHAN_KINDS) do
      local n = counts[k] or 0
      if n == 0 then return {} end
      if n == 2 then
         if dup_kind ~= "" then return {} end   -- two duplicates, invalid
         dup_kind = k
      elseif n > 2 then
         return {}
      end
   end
   if dup_kind == "" then return {} end
   -- No extra kinds.
   local total = 0
   for _, v in pairs(counts) do total = total + v end
   if total ~= 14 then return {} end
   return {
      {
         kind = "thirteen_orphans" as WinShapeKind,
         sets = {},
         pair_kind = dup_kind as TileKindId,
      }
   }
end

-- ── Nine Gates ────────────────────────────────────────────────────────────
-- Shape: 1112345678999 in one suit + one extra same-suit tile.

local NINE_GATES_BASE: {string:integer} = {
   ["1"] = 3, ["2"] = 1, ["3"] = 1, ["4"] = 1,
   ["5"] = 1, ["6"] = 1, ["7"] = 1, ["8"] = 1, ["9"] = 3,
}

local function find_nine_gates(concealed_14: {Tile}): {WinShape}
   if #concealed_14 ~= 14 then return {} end
   -- All tiles must be the same suit (non-honor).
   local suit: string = ""
   for _, t in ipairs(concealed_14) do
      local k = t.kind_id as string
      if HONOR_KINDS[k] then return {} end
      local s = k:match("^([a-z]+)_")
      if s == nil then return {} end
      if suit == "" then suit = s
      elseif suit ~= s then return {} end
   end
   if suit == "" then return {} end
   -- Build rank counts.
   local rank_counts: {string:integer} = {}
   for _, t in ipairs(concealed_14) do
      local k = t.kind_id as string
      local r = k:match("_(%d+)$")
      if r then rank_counts[r] = (rank_counts[r] or 0) + 1 end
   end
   -- Must have exactly the base counts + one extra rank.
   local extra: string = ""
   for rank, base in pairs(NINE_GATES_BASE) do
      local have = rank_counts[rank] or 0
      if have < base then return {} end
      if have == base + 1 then
         if extra ~= "" then return {} end   -- two extras
         extra = rank
      elseif have ~= base then
         return {}
      end
   end
   if extra == "" then return {} end
   -- No extra ranks outside 1-9.
   for r, _ in pairs(rank_counts) do
      if not NINE_GATES_BASE[r] then return {} end
   end
   return {
      {
         kind = "nine_gates" as WinShapeKind,
         sets = {},
         pair_kind = (suit .. "_" .. extra) as TileKindId,
      }
   }
end

-- ── Public API ─────────────────────────────────────────────────────────────

-- Returns all valid WinShapes for the given winning hand.
-- concealed_tiles: player's concealed tiles EXCLUDING the incoming tile.
-- incoming: the tile just drawn or claimed. Pass as extra tile.
-- open_sets: already-declared sets.
-- For Zi Mo, incoming is the drawn tile (not yet added to concealed_tiles by caller).
function M.find_win_shapes(
   concealed_tiles: {Tile},
   incoming: Tile,
   open_sets: {TileSet}
): {WinShape}
   -- Build the 14-tile material: concealed + incoming tile
   local material: {Tile} = {}
   for _, t in ipairs(concealed_tiles) do material[#material + 1] = t end
   material[#material + 1] = incoming

   local results: {WinShape} = {}

   -- Standard shape is valid for any number of open sets (0-3).
   if #open_sets <= 3 then
      for _, s in ipairs(find_standard_shapes(material, open_sets)) do
         results[#results + 1] = s
      end
   end

   -- Special shapes require no open sets.
   if #open_sets == 0 then
      for _, s in ipairs(find_seven_pairs(material)) do
         results[#results + 1] = s
      end
      for _, s in ipairs(find_thirteen_orphans(material)) do
         results[#results + 1] = s
      end
      for _, s in ipairs(find_nine_gates(material)) do
         results[#results + 1] = s
      end
   end

   return results
end

-- Returns true if the tile kind is an honor.
function M.is_honor(kind_id: TileKindId): boolean
   return HONOR_KINDS[kind_id as string] == true
end

-- Returns true if the tile kind is a dragon.
function M.is_dragon(kind_id: TileKindId): boolean
   return DRAGON_KINDS[kind_id as string] == true
end

-- Returns true if the tile kind is a terminal or honor (used by Thirteen Orphans / Shi San Yao).
function M.is_terminal_or_honor(kind_id: TileKindId): boolean
   return TERMINALS_AND_HONORS[kind_id as string] == true
end

-- Returns the suit string for a kind_id.
function M.suit_of(kind_id: TileKindId): string
   return suit_of(kind_id as string)
end

return M
