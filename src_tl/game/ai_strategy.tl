-- AI strategy: target-pattern picker + projected-fan estimator. Pure rules
-- layer; no love/ui/scenes/app imports.
--
-- The strategy module supplies three things to ai.tl:
--   * choose_target — picks one of {default, dui_dui_hu, hun_yi_se, qing_yi_se}
--     based on hand features and a personality bias.
--   * estimate_fan_for_target — fan ceiling for a given target *before* ting.
--     This is the boon-aware filter: routes a synthetic ScoreResult through
--     `effect_runner.apply_score_modifiers` so AI-owned boons contribute.
--   * pick_best_discard — target-aware discard heuristic with ukeire tiebreak.
--
-- Personality is the extension point. Vanilla AI passes NEUTRAL_PERSONALITY.
-- Opponent packages and AI-owned-boon modes plug in via this same record.

require("core.types")
require("game.deal_types")
local td        = require("game.ting_distance")
local fx_runner = require("effects.effect_runner")

global type TargetKind = string
-- "default" | "dui_dui_hu" | "hun_yi_se" | "qing_yi_se"

global record AiPersonality
   target_weights:   {string: number}   -- per-target multiplier; default 1.0
   call_appetite:    number             -- 0..1; how aggressively to call
end

global record HandFeatures
   honor_count:          integer   -- total honor tiles (concealed + open)
   honor_pairs:          integer   -- distinct concealed honor kinds with ≥2 copies
   max_suit:             string    -- dominant suit ("tiao" | "wan" | "bing" | "")
   max_suit_count:       integer   -- count of tiles in max_suit
   off_suit_count:       integer   -- non-honor tiles outside max_suit
   pair_count:           integer   -- distinct concealed kinds with ≥2 copies
   triplet_count:        integer   -- concealed triplets + open peng/kong sets;
                                   -- "structural commitments equivalent to a
                                   -- pung". Open chi sets are NOT counted here.
   open_set_count:       integer
   has_open_set:         boolean
   open_chi_count:       integer   -- open chi sets; disqualifies dui_dui_hu
   committed_suits:      {string}  -- distinct non-honor suits in open sets;
                                   -- if length > 1, qing_yi_se & hun_yi_se die
   has_committed_honor:  boolean   -- any open peng/kong of an honor; kills
                                   -- qing_yi_se (which forbids honors)
end

local record StrategyModule
   NEUTRAL_PERSONALITY: AiPersonality
   compute_features:                  function({Tile}, {TileSet}): HandFeatures
   tile_value:                        function(TileKindId, TargetKind, Wind, Wind): number
   estimate_fan_for_target:           function(DealState, integer, TargetKind): integer
   choose_target:                     function(DealState, integer, AiPersonality): (TargetKind, integer)
   compute_ukeire:                    function(DealState, integer, {string: integer}): integer
   pick_best_discard:                 function(DealState, integer, AiPersonality, TargetKind, {string: integer}): (TileId, integer, integer, integer)
   max_est_fan:                       function(DealState, integer): integer
   max_est_fan_hypothetical:          function(DealState, integer, {Tile}, {TileSet}): integer
   has_three_fan_target:              function(DealState, integer): boolean
   has_three_fan_target_hypothetical: function(DealState, integer, {Tile}, {TileSet}): boolean
   post_call_ting:                    function({Tile}, {TileSet}, {string: integer}): integer
end

local M: StrategyModule = {} as StrategyModule

M.NEUTRAL_PERSONALITY = {
   target_weights = {
      default     = 1.0,
      dui_dui_hu  = 1.0,
      hun_yi_se   = 1.0,
      qing_yi_se  = 1.0,
   },
   call_appetite = 0.5,
}

-- ── Constants ─────────────────────────────────────────────────────────────

local HONOR_KINDS: {string: boolean} = {
   east = true, south = true, west = true, north = true,
   fa_cai = true, hong_zhong = true, bai_ban = true,
}

local DRAGON_KINDS: {string: boolean} = {
   fa_cai = true, hong_zhong = true, bai_ban = true,
}

-- ── Tile-value tables (tiebreakers when ting and ukeire tie) ──────────────

-- sequence_value: prefers middle suited tiles for chi-building.
-- terminal=1, edge(2,8)=2, near(3,7)=3, mid(4,5,6)=4, honors=0
local SEQUENCE_VALUE: {string: number} = {
   tiao_1 = 1, tiao_9 = 1, wan_1 = 1, wan_9 = 1, bing_1 = 1, bing_9 = 1,
   tiao_2 = 2, tiao_8 = 2, wan_2 = 2, wan_8 = 2, bing_2 = 2, bing_8 = 2,
   tiao_3 = 3, tiao_7 = 3, wan_3 = 3, wan_7 = 3, bing_3 = 3, bing_7 = 3,
   tiao_4 = 4, tiao_5 = 4, tiao_6 = 4,
   wan_4 = 4, wan_5 = 4, wan_6 = 4,
   bing_4 = 4, bing_5 = 4, bing_6 = 4,
   east = 0, south = 0, west = 0, north = 0,
   fa_cai = 0, hong_zhong = 0, bai_ban = 0,
}

-- triplet_value: prefers honors and dragons for peng-building.
-- non-yakuhai-honor=1, suited terminal=2, suited mid=3, dragon=4, seat/round wind=4 (computed)
local TRIPLET_VALUE: {string: number} = {
   tiao_1 = 2, tiao_9 = 2, wan_1 = 2, wan_9 = 2, bing_1 = 2, bing_9 = 2,
   tiao_2 = 3, tiao_3 = 3, tiao_4 = 3, tiao_5 = 3, tiao_6 = 3, tiao_7 = 3, tiao_8 = 3,
   wan_2 = 3, wan_3 = 3, wan_4 = 3, wan_5 = 3, wan_6 = 3, wan_7 = 3, wan_8 = 3,
   bing_2 = 3, bing_3 = 3, bing_4 = 3, bing_5 = 3, bing_6 = 3, bing_7 = 3, bing_8 = 3,
   east = 1, south = 1, west = 1, north = 1,
   fa_cai = 4, hong_zhong = 4, bai_ban = 4,
}

-- Tile-value lookup for a target. Sequence-leaning targets use SEQUENCE_VALUE;
-- triplet-leaning use TRIPLET_VALUE. seat/round wind get +1 in triplet table.
function M.tile_value(kind_id: TileKindId, target: TargetKind, seat_wind: Wind, round_wind: Wind): number
   local key = kind_id as string
   if (target as string) == "dui_dui_hu" then
      local v = TRIPLET_VALUE[key] or 0
      if key == (seat_wind as string) or key == (round_wind as string) then
         v = v + 1
      end
      return v
   end
   return SEQUENCE_VALUE[key] or 0
end

-- ── Composition features ───────────────────────────────────────────────────

local function suit_of(kind_id: string): string
   if HONOR_KINDS[kind_id] then return "" end
   local suit = kind_id:match("^([a-z]+)_%d+$")
   return suit or ""
end

function M.compute_features(concealed: {Tile}, sets: {TileSet}): HandFeatures
   local counts: {string: integer} = {}
   for _, t in ipairs(concealed) do
      local k = t.kind_id as string
      counts[k] = (counts[k] or 0) + 1
   end

   local honor_count = 0
   local honor_pairs = 0
   local pair_count  = 0
   local triplet_count = 0
   local suit_counts: {string: integer} = { tiao = 0, wan = 0, bing = 0 }

   for k, n in pairs(counts) do
      if HONOR_KINDS[k] then
         honor_count = honor_count + n
         if n >= 2 then honor_pairs = honor_pairs + 1 end
      else
         local s = suit_of(k)
         if s ~= "" then suit_counts[s] = (suit_counts[s] or 0) + n end
      end
      if n >= 2 then pair_count = pair_count + 1 end
      if n >= 3 then triplet_count = triplet_count + 1 end
   end

   local max_suit = ""
   local max_suit_count = 0
   for s, n in pairs(suit_counts) do
      if n > max_suit_count then
         max_suit = s
         max_suit_count = n
      end
   end

   local off_suit = 0
   for s, n in pairs(suit_counts) do
      if s ~= max_suit then off_suit = off_suit + n end
   end

   -- Iterate sets:
   --   * Credit each open peng/kong as a triplet (a structural commitment
   --     equivalent to a concealed triplet for dui_dui_hu fitness).
   --   * Track open_chi_count separately — chis disqualify dui_dui_hu.
   --   * Track which suits / honors have been committed via open sets, so
   --     qing_yi_se and hun_yi_se feasibility can be gated.
   --   * Add open-set tiles to max_suit_count / off_suit_count / honor_count
   --     so target_fitness sees the full committed picture.
   local open_set_count = #sets
   local has_open = false
   local open_chi_count = 0
   local has_committed_honor = false
   local committed_suits_set: {string: boolean} = {}

   for _, sset in ipairs(sets) do
      if (sset.visibility as string) == "open" then has_open = true end
      local sk = sset.kind as string
      if sk == "peng" or sk == "kong" then
         triplet_count = triplet_count + 1
      elseif sk == "chi" then
         open_chi_count = open_chi_count + 1
      end
      for _, t in ipairs(sset.tiles) do
         local k = t.kind_id as string
         if HONOR_KINDS[k] then
            honor_count = honor_count + 1
            if sk == "peng" or sk == "kong" then has_committed_honor = true end
         else
            local s = suit_of(k)
            if s ~= "" then committed_suits_set[s] = true end
            if s == max_suit then
               max_suit_count = max_suit_count + 1
            else
               off_suit = off_suit + 1
            end
         end
      end
   end

   local committed_suits: {string} = {}
   for s in pairs(committed_suits_set) do
      committed_suits[#committed_suits + 1] = s
   end

   return {
      honor_count          = honor_count,
      honor_pairs          = honor_pairs,
      max_suit             = max_suit,
      max_suit_count       = max_suit_count,
      off_suit_count       = off_suit,
      pair_count           = pair_count,
      triplet_count        = triplet_count,
      open_set_count       = open_set_count,
      has_open_set         = has_open,
      open_chi_count       = open_chi_count,
      committed_suits      = committed_suits,
      has_committed_honor  = has_committed_honor,
   }
end

-- ── Synthetic-shape construction for boon-aware fan estimation ────────────

-- Builds a placeholder WinShape for a target. Used to feed
-- `effect_runner.apply_score_modifiers` so AI-owned boons contribute even
-- before the hand reaches ting. Approximate: real Hu fan is recomputed at
-- ting via evaluate_hu in ai.tl.
local function synthetic_shape(_target: TargetKind, sets: {TileSet}, pair_kind: TileKindId): WinShape
   local out_sets: {TileSet} = {}
   for _, s in ipairs(sets) do out_sets[#out_sets + 1] = s end
   -- Pad with placeholder concealed sets (no tiles). Boon modules read
   -- shape.sets for things like dragon-pung counts; empty placeholders mean
   -- no contribution from those modules, which is the correct conservative
   -- behavior for an estimate.
   while #out_sets < 4 do
      out_sets[#out_sets + 1] = {
         kind        = "peng" as TileSetKind,
         visibility  = "concealed" as SetVisibility,
         tiles       = {},
         called_from = -1,
      }
   end
   return {
      kind      = "standard_four_sets_pair" as WinShapeKind,
      sets      = out_sets,
      pair_kind = pair_kind,
   }
end

-- Returns a baseline fan number for the target's hand pattern alone.
local function target_base_fan(target: TargetKind): integer
   local t = target as string
   if t == "dui_dui_hu" then return 3
   elseif t == "hun_yi_se" then return 3
   elseif t == "qing_yi_se" then return 6
   else return 1   -- default → Ping Hu base
   end
end

-- Counts realized (committed) hand-pattern modifiers from the current hand.
-- "Realized" means the structure is locked in: completed pengs/kongs in open
-- sets, or 3+ copies in concealed (a concealed triplet is committed for
-- scoring purposes since the player can declare it as a concealed kong or
-- it'll be scored as a triplet at Hu). Pairs are NOT counted — they're
-- aspirational, not committed.
--
-- Modifiers counted:
--   +1 per dragon (fa_cai / hong_zhong / bai_ban) triplet/kong (Dragon Pung).
--   +1 per triplet/kong of seat wind (Seat Wind Pung).
--   +1 per triplet/kong of round wind (Round Wind Pung).
local function count_realized_modifiers(
   concealed:  {Tile},
   sets:       {TileSet},
   seat_wind:  Wind,
   round_wind: Wind
): integer
   local total = 0
   local sw = seat_wind as string
   local rw = round_wind as string

   for _, s in ipairs(sets) do
      local sk = s.kind as string
      if (sk == "peng" or sk == "kong") and #s.tiles > 0 then
         local k = s.tiles[1].kind_id as string
         if DRAGON_KINDS[k] then total = total + 1
         elseif k == sw then total = total + 1
         elseif k == rw then total = total + 1 end
      end
   end

   local counts: {string: integer} = {}
   for _, t in ipairs(concealed) do
      local k = t.kind_id as string
      counts[k] = (counts[k] or 0) + 1
   end
   for k, n in pairs(counts) do
      if n >= 3 then
         if DRAGON_KINDS[k] then total = total + 1
         elseif k == sw then total = total + 1
         elseif k == rw then total = total + 1 end
      end
   end
   return total
end

-- Fan ceiling for `target` from the current hand state. Routes through the
-- effect runner so AI-owned boons contribute.
--
-- The estimate sums:
--   + the target's base hand-pattern fan (1 / 3 / 3 / 6 for default /
--     dui_dui_hu / hun_yi_se / qing_yi_se).
--   + realized fan modifiers from triplets/pengs/kongs already in the hand
--     (Dragon Pung, Seat Wind Pung, Round Wind Pung).
--   + boon contributions via `effect_runner.apply_score_modifiers`.
--
-- It does NOT count men_qian. Banking on men_qian + zi_mo + Ping Hu is
-- statistically dominated by any path that calls to lock structural fan;
-- the AI plans for the open-hand ceiling and treats men_qian as a bonus
-- if it happens to survive. Boons that read `ctx.is_men_qian` (e.g., Still
-- Water) still see the correct value and contribute through the runner.
function M.estimate_fan_for_target(deal: DealState, player_index: integer, target: TargetKind): integer
   local p = deal.players[player_index]
   local t = target as string

   -- Feasibility gates: if the target's win shape is structurally impossible
   -- given what's already been committed via open sets, return 0. Without
   -- this, the AI happily accepts a chi that destroys its own dui_dui_hu
   -- path because target_base_fan still reports 3 fan for dead shapes.
   --
   -- default is intentionally not gated here. Default represents "Ping Hu
   -- base / no specific shape claim" and is the AI's safety-net target;
   -- gating it would just push every junk hand to has_three_fan_target =
   -- false and reject all calls regardless of merit.
   local feat = M.compute_features(p.hand.concealed_tiles, p.hand.sets)
   if t == "dui_dui_hu" then
      -- Pung-only: any open chi makes the win shape impossible.
      if feat.open_chi_count > 0 then return 0 end
   elseif t == "qing_yi_se" then
      -- Pure single suit, no honors: dies on any committed honor or any
      -- second committed suit.
      if feat.has_committed_honor then return 0 end
      if #feat.committed_suits > 1 then return 0 end
   elseif t == "hun_yi_se" then
      -- One suit + honors: dies if two suits are already committed.
      -- (Committed honors are fine — that's the "hun" part.)
      if #feat.committed_suits > 1 then return 0 end
   end

   local base_fan = target_base_fan(target)

   local is_men_qian = true
   for _, s in ipairs(p.hand.sets) do
      if (s.visibility as string) == "open" then is_men_qian = false; break end
   end

   local mod_count = count_realized_modifiers(p.hand.concealed_tiles, p.hand.sets, p.seat_wind, deal.round_wind)
   base_fan = base_fan + mod_count

   -- Pick a pair kind from concealed (first kind with ≥2 copies) for the
   -- synthetic shape; falls back to first concealed tile.
   local pair_kind: TileKindId = "" as TileKindId
   if #p.hand.concealed_tiles > 0 then
      pair_kind = p.hand.concealed_tiles[1].kind_id
   end
   local counts: {string: integer} = {}
   for _, t in ipairs(p.hand.concealed_tiles) do
      local k = t.kind_id as string
      counts[k] = (counts[k] or 0) + 1
   end
   for k, n in pairs(counts) do
      if n >= 2 then pair_kind = k as TileKindId; break end
   end

   local shape = synthetic_shape(target, p.hand.sets, pair_kind)

   local incoming: Tile = { tile_id = "" as TileId, kind_id = pair_kind }
   local ctx: ScoreContext = {
      incoming_tile = incoming,
      has_incoming  = true,
      is_zi_mo      = false,
      is_men_qian   = is_men_qian,   -- correctly set so men_qian-reading boons can fire
      is_hai_di     = false,
      is_gang_shang = false,
      is_qiang_gang = false,
      round_wind    = deal.round_wind,
      seat_wind     = p.seat_wind,
   }

   local base_reasons: {ScoreReason} = {
      {
         category = "hand_pattern" as ScoreReasonCategory,
         label    = (target as string),
         fan      = target_base_fan(target),
         is_limit = false,
      },
   }
   if mod_count > 0 then
      base_reasons[#base_reasons + 1] = {
         category = "modifier" as ScoreReasonCategory,
         label    = "realized_modifiers",
         fan      = mod_count,
         is_limit = false,
      }
   end

   local synthetic_base: ScoreResult = {
      win_shape_kind = shape.kind,
      reasons        = base_reasons,
      total_fan      = base_fan,
      is_limit       = false,
      rating         = "C" as Rating,
      valid_hu       = base_fan >= 3,
   }

   local final = fx_runner.apply_score_modifiers(deal, ctx, shape, synthetic_base, player_index)
   if final.is_limit then return 100 end
   return final.total_fan
end

-- ── Target selection ──────────────────────────────────────────────────────

-- Computes a per-target fitness score from features. Higher = better fit.
-- Tuned so:
--   - qing_yi_se beats hun_yi_se when no honors are present.
--   - hun_yi_se beats qing_yi_se when honors are present.
--   - default is a baseline that wins for genuinely mixed hands.
local function target_fitness(target: TargetKind, f: HandFeatures): number
   local t = target as string
   if t == "dui_dui_hu" then
      -- Fits when many pairs/triplets, few sequences.
      return (f.pair_count * 2.0) + (f.triplet_count * 3.0) + (f.honor_pairs * 1.0)
   elseif t == "qing_yi_se" then
      -- Fits when one suit dominates and zero honors. Heavy honor penalty
      -- because qing_yi_se forbids honors entirely.
      return (f.max_suit_count * 1.0) - (f.off_suit_count * 0.5) - (f.honor_count * 2.0)
   elseif t == "hun_yi_se" then
      -- Fits when one suit dominates AND honors are present. The 0.7
      -- multiplier on max_suit_count means hun_yi_se needs honors to beat
      -- qing_yi_se's pure suit fitness.
      return (f.max_suit_count * 0.7) + (f.honor_count * 1.0) - (f.off_suit_count * 0.5)
   else   -- default
      -- Universally feasible; modest baseline so it wins for genuinely
      -- mixed hands with no strong shape signal.
      return 6.0
   end
end

local TARGETS: {TargetKind} = {
   "default" as TargetKind, "dui_dui_hu" as TargetKind,
   "hun_yi_se" as TargetKind, "qing_yi_se" as TargetKind,
}

-- Picks a target: highest (fitness * weight) among those with est_fan ≥ 3.
-- Falls through to "default" if every other target fails the fan filter.
function M.choose_target(deal: DealState, player_index: integer, personality: AiPersonality): TargetKind, integer
   local p = deal.players[player_index]
   local f = M.compute_features(p.hand.concealed_tiles, p.hand.sets)

   local best: TargetKind = "default" as TargetKind
   local best_score = -1.0e9
   local best_est_fan = 0

   for _, t in ipairs(TARGETS) do
      local est_fan = M.estimate_fan_for_target(deal, player_index, t)
      if est_fan >= 3 or (t as string) == "default" then
         local fit = target_fitness(t, f)
         local weight = personality.target_weights[t as string] or 1.0
         local score = fit * weight
         if score > best_score then
            best = t
            best_score = score
            best_est_fan = est_fan
         end
      end
   end
   return best, best_est_fan
end

-- ── Ukeire ────────────────────────────────────────────────────────────────

-- Counts the number of distinct kinds whose addition would improve ting
-- distance, weighted by remaining live copies.
function M.compute_ukeire(deal: DealState, player_index: integer, live: {string: integer}): integer
   local p = deal.players[player_index]
   local concealed = p.hand.concealed_tiles
   local sets = p.hand.sets
   local current = td.ting_distance_live(concealed, sets, live)
   if current >= 100 then return 0 end

   local total = 0
   for kind, n_live in pairs(live) do
      if n_live > 0 then
         local hypothetical: {Tile} = {}
         for _, t in ipairs(concealed) do hypothetical[#hypothetical + 1] = t end
         hypothetical[#hypothetical + 1] = {
            tile_id = ("__probe_" .. kind) as TileId,
            kind_id = kind as TileKindId,
         }
         -- After adding one more tile, we'd have to discard something to keep
         -- the same total. The cheapest interpretation: ting on the current
         -- 13-tile hand if `kind` is the one tile that completes a 4+pair
         -- decomposition. For an estimate, we count kinds whose addition
         -- *strictly improves* ting on the (concealed+1) set.
         local new_ting = td.ting_distance_live(hypothetical, sets, live)
         if new_ting < current then
            total = total + n_live
         end
      end
   end
   return total
end

-- ── Discard heuristic ─────────────────────────────────────────────────────

local function tiles_without_id(tiles: {Tile}, tile_id: TileId): {Tile}
   local out: {Tile} = {}
   for _, t in ipairs(tiles) do
      if t.tile_id ~= tile_id then out[#out + 1] = t end
   end
   return out
end

-- discard_priority: returns "how much this tile fights the chosen target."
-- Higher = drop this tile first. Used as a secondary rank key in
-- pick_best_discard so that within equal-ting candidates the AI follows
-- through on its target instead of dropping a structurally adjacent tile by
-- coincidence of tile-value tiebreak.
--
-- The numbers are unitless rank weights — only their ordering matters.
--
--   dui_dui_hu  — singletons that aren't seat/round/dragon are pure waste
--                 (pung-only forbids sequences and won't pair into modifier
--                 fan). Pairs and triplets are gold; keep.
--   qing_yi_se  — honors and off-suit tiles are dead in a one-suit-no-honor
--                 shape; max-suit tiles keep.
--   hun_yi_se   — off-suit non-honor tiles are dead; honors and max-suit
--                 tiles keep.
--   default     — target-blind. Returns 0 so generic ting + tile-value
--                 ranking takes over (existing behavior).
local function discard_priority(
   kind:        TileKindId,
   count:       integer,
   target:      TargetKind,
   features:    HandFeatures,
   seat_wind:   Wind,
   round_wind:  Wind
): integer
   local k = kind as string
   local t = target as string
   local is_honor = HONOR_KINDS[k]
   local is_dragon = DRAGON_KINDS[k]
   local is_seat_wind = (k == (seat_wind as string))
   local is_round_wind = (k == (round_wind as string))
   local is_value_honor = is_dragon or is_seat_wind or is_round_wind
   local kind_suit = suit_of(k)

   if t == "dui_dui_hu" then
      if count >= 2 then return 0 end       -- pair/triplet, keep
      if is_value_honor then return 30 end  -- could pair into a +1 fan triplet
      return 100                             -- singleton, sequence-only material
   elseif t == "qing_yi_se" then
      if is_honor then return 100 end
      if kind_suit ~= features.max_suit then return 80 end
      return 0
   elseif t == "hun_yi_se" then
      if is_honor then return 0 end
      if kind_suit ~= features.max_suit then return 80 end
      return 0
   end
   return 0
end

-- Rank candidate discards by:
--   1. live ting after discard (asc) — never go dead just to satisfy the
--      target; ting is still primary.
--   2. discard_priority (desc) — drop high-fight tiles first. This is the
--      target-aware layer: among equal-ting candidates, follow through on
--      the chosen target's shape.
--   3. tile-value of the discarded tile (asc) — prefer to drop low-value
--      tiles for the target (terminals/honors for sequence targets;
--      non-yakuhai-honors for triplet targets).
--   4. tile_id (asc) for determinism.
--
-- Ukeire is computed once for the *chosen* candidate (used in reasoning /
-- inspector display), not per-candidate. Per-candidate ukeire is too
-- expensive for a 30-kind × 14-candidate inner loop and rarely changes the
-- ranking outcome that ting + priority + tile-value already captures.
--
-- Returns: tile_id, ting_before, ting_after, ukeire_after.
function M.pick_best_discard(
   deal:         DealState,
   player_index: integer,
   _personality: AiPersonality,
   target:       TargetKind,
   live:         {string: integer}
): TileId, integer, integer, integer
   local p = deal.players[player_index]
   local concealed = p.hand.concealed_tiles
   local before = td.ting_distance_live(concealed, p.hand.sets, live)

   local features = M.compute_features(concealed, p.hand.sets)
   local counts: {string: integer} = {}
   for _, t in ipairs(concealed) do
      local k = t.kind_id as string
      counts[k] = (counts[k] or 0) + 1
   end

   local best_id: TileId = concealed[1].tile_id
   local best_ting = 1000
   local best_priority = -1
   local best_value = 1.0e9

   for _, t in ipairs(concealed) do
      local rest = tiles_without_id(concealed, t.tile_id)
      local after_ting = td.ting_distance_live(rest, p.hand.sets, live)
      local value = M.tile_value(t.kind_id, target, p.seat_wind, deal.round_wind)
      local priority = discard_priority(
         t.kind_id, counts[t.kind_id as string] or 1,
         target, features, p.seat_wind, deal.round_wind
      )

      local better = false
      if after_ting < best_ting then
         better = true
      elseif after_ting == best_ting then
         if priority > best_priority then
            better = true
         elseif priority == best_priority then
            if value < best_value then
               better = true
            elseif value == best_value then
               if (t.tile_id as string) < (best_id as string) then
                  better = true
               end
            end
         end
      end

      if better then
         best_id = t.tile_id
         best_ting = after_ting
         best_priority = priority
         best_value = value
      end
   end

   -- Compute ukeire on the chosen post-discard hand for reasoning display.
   local rest = tiles_without_id(concealed, best_id)
   local saved = p.hand.concealed_tiles
   p.hand.concealed_tiles = rest
   local best_uke = M.compute_ukeire(deal, player_index, live)
   p.hand.concealed_tiles = saved

   return best_id, before, best_ting, best_uke
end

-- ── Used by ai.tl to gate call/kong decisions ────────────────────────────
--
-- max_est_fan returns the raw maximum est_fan across all four targets,
-- ignoring fitness. The gate question is "does any 3-fan path exist for
-- this hand state?", not "does my preferred target reach 3 fan?" Using the
-- raw max means a hand with weak fitness for hun_yi_se but est_fan=4 there
-- still counts as "has a 3-fan path" — appropriate for gating decisions
-- about whether to PROTECT a 3-fan-reachable state.

function M.max_est_fan(deal: DealState, player_index: integer): integer
   local best = 0
   for _, t in ipairs(TARGETS) do
      local f = M.estimate_fan_for_target(deal, player_index, t)
      if f > best then best = f end
   end
   return best
end

function M.max_est_fan_hypothetical(
   deal:                   DealState,
   player_index:           integer,
   hypothetical_concealed: {Tile},
   hypothetical_sets:      {TileSet}
): integer
   local p = deal.players[player_index]
   local saved_concealed = p.hand.concealed_tiles
   local saved_sets      = p.hand.sets
   p.hand.concealed_tiles = hypothetical_concealed
   p.hand.sets            = hypothetical_sets
   local v = M.max_est_fan(deal, player_index)
   p.hand.concealed_tiles = saved_concealed
   p.hand.sets            = saved_sets
   return v
end

-- Returns true if the AI's *chosen* target (best fitness × est_fan) has
-- est_fan ≥ 3. Mirrors choose_target's semantics so the gate aligns with
-- what the AI will actually pursue. Using raw max_est_fan instead would
-- always pass because qing_yi_se's base of 6 inflates the ceiling on
-- every hand regardless of structural reachability.
function M.has_three_fan_target(deal: DealState, player_index: integer): boolean
   local _t, est_fan = M.choose_target(deal, player_index, M.NEUTRAL_PERSONALITY)
   return est_fan >= 3
end

-- Hypothetical variant: temporarily swaps the player's hand and runs
-- has_three_fan_target.
function M.has_three_fan_target_hypothetical(
   deal:                   DealState,
   player_index:           integer,
   hypothetical_concealed: {Tile},
   hypothetical_sets:      {TileSet}
): boolean
   local p = deal.players[player_index]
   local saved_concealed = p.hand.concealed_tiles
   local saved_sets      = p.hand.sets
   p.hand.concealed_tiles = hypothetical_concealed
   p.hand.sets            = hypothetical_sets
   local v = M.has_three_fan_target(deal, player_index)
   p.hand.concealed_tiles = saved_concealed
   p.hand.sets            = saved_sets
   return v
end

-- Post-call ting: after a peng / chi / open kong the player has one extra
-- concealed tile to discard before reaching standard ting hand size.
-- `ting_distance_standard_live` requires every concealed tile to fit into
-- a set or pair, so for an 11-tile post-peng concealed it returns INF for
-- nearly every hand — wrongly treating the to-be-discarded tile as a
-- structural failure.
--
-- This helper computes the minimum standard ting after dropping any one
-- tile from `concealed`. That's the AI's best-case post-discard state
-- and the apples-to-apples comparison against pre-call ting. Use this for
-- peng / chi gates where the player will discard right after the call.
function M.post_call_ting(
   concealed: {Tile},
   sets:      {TileSet},
   live:      {string: integer}
): integer
   local best = 100
   for i = 1, #concealed do
      local without: {Tile} = {}
      for j, t in ipairs(concealed) do
         if j ~= i then without[#without + 1] = t end
      end
      local ting = td.ting_distance_standard_live(without, sets, live)
      if ting < best then best = ting end
   end
   return best
end


return M
