-- Hand scoring: pattern detection, fan calculation, rating derivation.
-- Pure — no imports from love, ui, scenes, app, or ai.

require("core.types")
require("game.deal_types")
local validator = require("game.hand_validator")

local M = {}

-- ── Rating derivation ──────────────────────────────────────────────────────

local function fan_to_rating(fan: integer): Rating
   if fan >= 10 then return "SS" as Rating
   elseif fan >= 8 then return "S" as Rating
   elseif fan >= 6 then return "A" as Rating
   elseif fan >= 4 then return "B" as Rating
   else return "C" as Rating
   end
end

-- ── Set analysis helpers ───────────────────────────────────────────────────

local WIND_KINDS: {string:boolean} = {
   east = true, south = true, west = true, north = true,
}
local DRAGON_KINDS: {string:boolean} = {
   fa_cai = true, hong_zhong = true, bai_ban = true,
}

local function is_honor_kind(k: string): boolean
   return WIND_KINDS[k] == true or DRAGON_KINDS[k] == true
end

local function is_triplet_set(s: TileSet): boolean
   return s.kind == ("peng" as TileSetKind) or s.kind == ("kong" as TileSetKind)
end

-- Returns the kind_id string for a set (all tiles share kind_id for peng/kong).
-- For chi, returns the lowest kind_id in the sequence.
local function set_kind(s: TileSet): string
   if #s.tiles > 0 then return s.tiles[1].kind_id as string end
   -- Fallback for synthetic sets from validator (no physical tiles stored).
   return ""
end

-- ── Pattern detectors ──────────────────────────────────────────────────────

-- Counts how many sets in all_sets are triplets of dragon tiles.
local function count_dragon_triplets(all_sets: {TileSet}): integer
   local n = 0
   for _, s in ipairs(all_sets) do
      if is_triplet_set(s) and DRAGON_KINDS[set_kind(s)] then n = n + 1 end
   end
   return n
end

-- Counts how many sets in all_sets are triplets of wind tiles.
local function count_wind_triplets(all_sets: {TileSet}): integer
   local n = 0
   for _, s in ipairs(all_sets) do
      if is_triplet_set(s) and WIND_KINDS[set_kind(s)] then n = n + 1 end
   end
   return n
end

-- Returns a set of suits used across all sets AND pair.
local function collect_suits(all_sets: {TileSet}, pair_kind: TileKindId): {string:boolean}
   local suits: {string:boolean} = {}
   for _, s in ipairs(all_sets) do
      if #s.tiles > 0 then
         local su = validator.suit_of(s.tiles[1].kind_id as TileKindId)
         suits[su] = true
      end
   end
   suits[validator.suit_of(pair_kind)] = true
   return suits
end

-- ── Score a single WinShape ────────────────────────────────────────────────

local function score_shape(shape: WinShape, ctx: ScoreContext): ScoreResult
   local reasons: {ScoreReason} = {}
   local total_fan = 0
   local is_limit = false

   local function add(cat: ScoreReasonCategory, label: string, fan: integer, limit: boolean)
      reasons[#reasons + 1] = {
         category = cat,
         label    = label,
         fan      = fan,
         is_limit = limit,
      }
      if limit then
         is_limit = true
      else
         total_fan = total_fan + fan
      end
   end

   local all_sets = shape.sets
   local pair_kind = shape.pair_kind

   -- ── Standard shape patterns ──────────────────────────────────────────

   if shape.kind == ("standard_four_sets_pair" as WinShapeKind) then

      -- Dui Dui Hu: all four sets are triplets/kongs
      local all_triplets = true
      for _, s in ipairs(all_sets) do
         if not is_triplet_set(s) then all_triplets = false; break end
      end

      -- Ping Hu: four chi (sequences) + non-honor pair, suited only
      local all_chi = true
      for _, s in ipairs(all_sets) do
         if s.kind ~= ("chi" as TileSetKind) then all_chi = false; break end
      end
      local pair_is_honor = is_honor_kind(pair_kind as string)

      local suits = collect_suits(all_sets, pair_kind)
      local has_honor = suits["honor"] == true
      local suited_count = 0
      for su, _ in pairs(suits) do
         if su ~= "honor" then suited_count = suited_count + 1 end
      end

      if all_triplets then
         add("hand_pattern" as ScoreReasonCategory, "Dui Dui Hu (對對胡)", 3, false)
      end

      if all_chi and not pair_is_honor and not has_honor then
         add("hand_pattern" as ScoreReasonCategory, "Ping Hu (平胡)", 1, false)
      end

      -- Qing Yi Se: one suit, no honors
      if suited_count == 1 and not has_honor then
         add("hand_pattern" as ScoreReasonCategory, "Qing Yi Se (清一色)", 6, false)
      -- Hun Yi Se: one suit + honors (but not pure suit)
      elseif suited_count == 1 and has_honor then
         add("hand_pattern" as ScoreReasonCategory, "Hun Yi Se (混一色)", 3, false)
      end

      -- Xiao San Yuan: two dragon triplets + dragon pair
      local dragon_trips = count_dragon_triplets(all_sets)
      local pair_is_dragon = DRAGON_KINDS[pair_kind as string] == true
      local pair_is_wind   = WIND_KINDS[pair_kind as string] == true

      if dragon_trips == 3 then
         add("hand_pattern" as ScoreReasonCategory, "Da San Yuan (大三元)", 0, true)
      elseif dragon_trips == 2 and pair_is_dragon then
         add("hand_pattern" as ScoreReasonCategory, "Xiao San Yuan (小三元)", 4, false)
      end

      -- Xiao Si Xi / Da Si Xi
      local wind_trips = count_wind_triplets(all_sets)
      if wind_trips == 4 then
         add("hand_pattern" as ScoreReasonCategory, "Da Si Xi (大四喜)", 0, true)
      elseif wind_trips == 3 and pair_is_wind then
         add("hand_pattern" as ScoreReasonCategory, "Xiao Si Xi (小四喜)", 6, false)
      end

      -- Si Gang: four kongs
      local kong_count = 0
      for _, s in ipairs(all_sets) do
         if s.kind == ("kong" as TileSetKind) then kong_count = kong_count + 1 end
      end
      if kong_count == 4 then
         add("hand_pattern" as ScoreReasonCategory, "Si Gang (四槓)", 0, true)
      end

      -- Zi Yi Se: all honor tiles (all sets honor + honor pair)
      if has_honor and not (suited_count > 0) then
         add("hand_pattern" as ScoreReasonCategory, "Zi Yi Se (字一色)", 0, true)
      end

   elseif shape.kind == ("seven_pairs" as WinShapeKind) then

      add("hand_pattern" as ScoreReasonCategory, "Qi Dui (七對)", 4, false)

      -- Can stack with Qing Yi Se / Hun Yi Se
      -- For seven pairs we need to check suits across pair tiles.
      -- shape.sets is empty; check via the all-14-tile analysis is not available here.
      -- Suit info is not directly available in WinShape for seven pairs.
      -- We'll re-examine via the pair_kind list embedded in shape.
      -- For now mark suit patterns handled via the context tile list check below.

   elseif shape.kind == ("thirteen_orphans" as WinShapeKind) then
      add("hand_pattern" as ScoreReasonCategory, "Shi San Yao (十三么)", 0, true)

   elseif shape.kind == ("nine_gates" as WinShapeKind) then
      add("hand_pattern" as ScoreReasonCategory, "Jiu Lian Bao Deng (九蓮寶燈)", 0, true)
   end

   -- ── Modifiers ────────────────────────────────────────────────────────

   -- Zi Mo (+1 self-draw)
   if ctx.is_zi_mo then
      add("modifier" as ScoreReasonCategory, "Zi Mo (自摸)", 1, false)
   end

   -- Men Qian (+1 fully concealed)
   if ctx.is_men_qian then
      add("modifier" as ScoreReasonCategory, "Men Qian (門清)", 1, false)
   end

   -- Dragon Pung: +1 per dragon triplet/kong in the sets
   for _, s in ipairs(all_sets) do
      if is_triplet_set(s) and DRAGON_KINDS[set_kind(s)] then
         local label = "Dragon Pung (" .. set_kind(s) .. ")"
         add("modifier" as ScoreReasonCategory, label, 1, false)
      end
   end

   -- Seat Wind Pung: +1 if triplet of seat wind
   for _, s in ipairs(all_sets) do
      if is_triplet_set(s) and set_kind(s) == (ctx.seat_wind as string) then
         add("modifier" as ScoreReasonCategory, "Seat Wind Pung", 1, false)
      end
   end

   -- Round Wind Pung: +1 if triplet of round wind
   for _, s in ipairs(all_sets) do
      if is_triplet_set(s) and set_kind(s) == (ctx.round_wind as string) then
         add("modifier" as ScoreReasonCategory, "Round Wind Pung", 1, false)
      end
   end

   -- Hai Di (+1)
   if ctx.is_hai_di then
      add("modifier" as ScoreReasonCategory, "Hai Di (海底撈月)", 1, false)
   end

   -- Gang Shang (+1)
   if ctx.is_gang_shang then
      add("modifier" as ScoreReasonCategory, "Gang Shang (槓上開花)", 1, false)
   end

   -- Qiang Gang (+1)
   if ctx.is_qiang_gang then
      add("modifier" as ScoreReasonCategory, "Qiang Gang (搶槓)", 1, false)
   end

   -- ── Determine validity and rating ────────────────────────────────────

   local valid_hu = is_limit or total_fan >= 3
   local rating: Rating
   if is_limit then
      rating = "Legend" as Rating
   else
      rating = fan_to_rating(total_fan)
   end

   return {
      win_shape_kind = shape.kind,
      reasons        = reasons,
      total_fan      = total_fan,
      is_limit       = is_limit,
      rating         = rating,
      valid_hu       = valid_hu,
   }
end

-- ── Best-result selection ─────────────────────────────────────────────────

local function result_rank(r: ScoreResult): integer
   if r.is_limit then return 10000 end
   return r.total_fan
end

-- ── Public API ─────────────────────────────────────────────────────────────

-- Returns all ScoreResult candidates (one per WinShape) plus the best result.
global record ScorerOutput
   candidates: {ScoreResult}
   best:       ScoreResult
   has_best:   boolean
end

function M.score_hand(
   win_shapes:  {WinShape},
   ctx:         ScoreContext
): ScorerOutput
   if #win_shapes == 0 then
      return {
         candidates = {},
         best       = {} as ScoreResult,
         has_best   = false,
      }
   end

   local candidates: {ScoreResult} = {}
   for _, shape in ipairs(win_shapes) do
      candidates[#candidates + 1] = score_shape(shape, ctx)
   end

   -- Pick the best: limit > most fan; within same is_limit tier, most fan wins.
   local best = candidates[1]
   for i = 2, #candidates do
      if result_rank(candidates[i]) > result_rank(best) then
         best = candidates[i]
      end
   end

   return { candidates = candidates, best = best, has_best = true }
end

-- Convenience: score from concealed tiles + incoming tile + open sets + context.
function M.score(
   concealed_tiles: {Tile},
   incoming:        Tile,
   open_sets:       {TileSet},
   ctx:             ScoreContext
): ScorerOutput
   local shapes = require("game.hand_validator").find_win_shapes(concealed_tiles, incoming, open_sets)
   return M.score_hand(shapes, ctx)
end

return M
