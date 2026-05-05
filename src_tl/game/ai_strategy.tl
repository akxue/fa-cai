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
local engine    = require("game.deal_engine")

global type TargetKind = string
-- "default" | "dui_dui_hu" | "hun_yi_se" | "qing_yi_se"

global record AiPersonality
   target_weights:   {string: number}   -- per-target multiplier; default 1.0
   call_appetite:    number             -- 0..1; how aggressively to call
end

-- ── CandidateAction (S07 candidate-pipeline) ────────────────────────────
--
-- One CandidateAction is produced per legal action the AI considers in a
-- decision (one per concealed tile for discards, one per call gate, one per
-- chi combination, etc.). The pipeline ranks accepted candidates by
-- `utility` and the AI picks the top one for its kind.
--
-- Fields by purpose:
--   action               — the DealAction the candidate represents.
--   tag                  — short kind ("discard" | "peng" | "chi" |
--                          "open_kong" | "concealed_kong" | "added_kong" |
--                          "hu_on_discard" | "zi_mo" | "pass").
--   target_distribution  — per-target contribution to expected_fan. Sums to
--                          expected_fan. The "chosen target" for inspector
--                          display is the target with the largest entry.
--   ting_after, ukeire_after — post-action ting / ukeire numbers.
--   expected_fan         — Σ_t P_reach(t | hand_after) × fan(t), the
--                          probability-weighted fan ceiling. Drives utility
--                          for ranking.
--   visible_depletion    — fraction of the chosen target's relevant tile
--                          pool that is publicly consumed (0..1). Populated
--                          on the chosen-target slot for inspector display.
--   danger               — reserved; 0 in M1 (no defense).
--   utility              — single ranking number = expected_fan. Tiebreaks
--                          (ukeire desc, ting asc, id asc) live in
--                          rank_candidates' comparator.
--   accepted             — false ⇒ candidate is rejected (still produced
--                          for inspector display); rejection_reason names
--                          the gate that rejected it.
global record CandidateAction
   action:               DealAction
   tag:                  string
   target_distribution:  {string: number}
   ting_after:           integer
   ukeire_after:         integer
   expected_fan:         number
   visible_depletion:    number
   danger:               number
   utility:              number
   accepted:             boolean
   rejection_reason:     string
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
   compute_live_counts:               function(DealState, integer): {string: integer}
   compute_features:                  function({Tile}, {TileSet}): HandFeatures
   estimate_fan_for_target:           function(DealState, integer, TargetKind): integer
   choose_target:                     function(DealState, integer, AiPersonality, {string: integer}): (TargetKind, integer)
   visible_depletion:                 function(TargetKind, HandFeatures, {string: integer}, Wind, Wind): number
   expected_fan_dist:                 function(DealState, integer, {string: integer}): ({string: number}, number, TargetKind)
   compute_ukeire:                    function(DealState, integer, {string: integer}): integer
   pick_best_discard:                 function(DealState, integer, AiPersonality, TargetKind, {string: integer}): (TileId, integer, integer, integer)
   max_est_fan:                       function(DealState, integer): integer
   max_est_fan_hypothetical:          function(DealState, integer, {Tile}, {TileSet}): integer
   has_three_fan_target:              function(DealState, integer, {string: integer}): boolean
   has_three_fan_target_hypothetical: function(DealState, integer, {Tile}, {TileSet}): boolean
   post_call_ting:                    function({Tile}, {TileSet}, {string: integer}): integer
   evaluate_discard_candidates:       function(DealState, integer, AiPersonality, TargetKind, {string: integer}): {CandidateAction}
   enrich_candidate:                  function(DealState, integer, TargetKind, {string: integer}, CandidateAction)
   rank_candidates:                   function({CandidateAction}): {CandidateAction}
   top_n_candidates:                  function({CandidateAction}, integer): {CandidateAction}
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

-- ── Live-tile bookkeeping ─────────────────────────────────────────────────
-- Returns a `live_counts` map of how many copies of each kind are still
-- drawable from the AI's perspective: 4 minus visible copies in (own
-- concealed, all sets across all players, all discards across all players,
-- pending discard if any). Other players' concealed tiles are intentionally
-- not subtracted — they are not visible to this AI.

local ALL_KINDS: {string} = {
   "tiao_1","tiao_2","tiao_3","tiao_4","tiao_5","tiao_6","tiao_7","tiao_8","tiao_9",
   "wan_1","wan_2","wan_3","wan_4","wan_5","wan_6","wan_7","wan_8","wan_9",
   "bing_1","bing_2","bing_3","bing_4","bing_5","bing_6","bing_7","bing_8","bing_9",
   "east","south","west","north","fa_cai","hong_zhong","bai_ban",
}

local PLAYER_COUNT <const> = 4

function M.compute_live_counts(deal: DealState, player_index: integer): {string: integer}
   local live: {string: integer} = {}
   for _, k in ipairs(ALL_KINDS) do live[k] = 4 end
   local function dec(k: TileKindId)
      local s = k as string
      live[s] = (live[s] or 0) - 1
   end
   for _, t in ipairs(deal.players[player_index].hand.concealed_tiles) do dec(t.kind_id) end
   for i = 1, PLAYER_COUNT do
      local p = deal.players[i]
      for _, s in ipairs(p.hand.sets) do
         for _, t in ipairs(s.tiles) do dec(t.kind_id) end
      end
      for _, t in ipairs(p.hand.discards) do dec(t.kind_id) end
   end
   if deal.has_pending_discard then dec(deal.pending_discard.tile.kind_id) end
   return live
end

-- ── Constants ─────────────────────────────────────────────────────────────

local HONOR_KINDS: {string: boolean} = {
   east = true, south = true, west = true, north = true,
   fa_cai = true, hong_zhong = true, bai_ban = true,
}

local DRAGON_KINDS: {string: boolean} = {
   fa_cai = true, hong_zhong = true, bai_ban = true,
}

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

   -- Iterate sets:
   --   * Credit each open peng/kong as a triplet (a structural commitment
   --     equivalent to a concealed triplet for dui_dui_hu fitness).
   --   * Track open_chi_count separately — chis disqualify dui_dui_hu.
   --   * Track which suits / honors have been committed via open sets, so
   --     qing_yi_se and hun_yi_se feasibility can be gated.
   --   * Add open-set tiles to suit_counts / honor_count before choosing the
   --     dominant suit, so target_fitness sees the full committed picture.
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
            if s ~= "" then suit_counts[s] = (suit_counts[s] or 0) + 1 end
         end
      end
   end

   -- Iterate in fixed order so ties produce a deterministic max_suit. Lua's
   -- pairs() does not guarantee iteration order across runs, which would
   -- make the AI non-deterministic when two suits tie on count.
   local SUIT_ORDER: {string} = { "tiao", "wan", "bing" }
   for _, s in ipairs(SUIT_ORDER) do
      local n = suit_counts[s] or 0
      if n > max_suit_count then
         max_suit = s
         max_suit_count = n
      end
   end

   local off_suit = 0
   for _, s in ipairs(SUIT_ORDER) do
      local n = suit_counts[s] or 0
      if s ~= max_suit then off_suit = off_suit + n end
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
         end
         if k == sw then total = total + 1 end
         if k == rw then total = total + 1 end
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
         end
         if k == sw then total = total + 1 end
         if k == rw then total = total + 1 end
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
   local target_name = target as string

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
   if target_name == "dui_dui_hu" then
      -- Pung-only: any open chi makes the win shape impossible.
      if feat.open_chi_count > 0 then return 0 end
   elseif target_name == "qing_yi_se" then
      -- Pure single suit, no honors: dies on any committed honor or any
      -- second committed suit.
      if feat.has_committed_honor then return 0 end
      if #feat.committed_suits > 1 then return 0 end
   elseif target_name == "hun_yi_se" then
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
   -- Iterate kinds in fixed order so pair_kind is deterministic across
   -- runs. This feeds synthetic_shape and the score-context incoming tile;
   -- boon modules that look up by kind would otherwise see a non-stable
   -- pair_kind from pairs() iteration order.
   for _, k in ipairs(ALL_KINDS) do
      if (counts[k] or 0) >= 2 then pair_kind = k as TileKindId; break end
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

-- ── Visible depletion (S07 commit 3) ─────────────────────────────────────
--
-- visible_depletion returns the fraction (0..1) of a target's relevant tile
-- pool that is publicly consumed (own concealed + everyone's open sets +
-- everyone's discards). Higher depletion ⇒ less wall to draw from for that
-- target. Computed from `live` directly since live[k] = 4 - (own_concealed
-- + opens + discards).
--
-- Pool by target:
--   default      — empty pool, depletion always 0 (no specific tile need).
--   dui_dui_hu   — kinds the player already has ≥2 of (pair candidates),
--                  plus dragons + seat wind + round wind (pung material).
--                  Pool size = 4 × |pool|.
--   hun_yi_se    — dominant suit (9 kinds × 4) + all honors (7 × 4) = 64.
--   qing_yi_se   — dominant suit only (9 × 4) = 36.
--
-- The dominant suit is feat.max_suit (already computed by compute_features
-- on the post-action hand).
local SUITS: {string} = { "tiao", "wan", "bing" }
local SUIT_KINDS: {string: {string}} = {
   tiao = { "tiao_1","tiao_2","tiao_3","tiao_4","tiao_5","tiao_6","tiao_7","tiao_8","tiao_9" },
   wan  = { "wan_1","wan_2","wan_3","wan_4","wan_5","wan_6","wan_7","wan_8","wan_9" },
   bing = { "bing_1","bing_2","bing_3","bing_4","bing_5","bing_6","bing_7","bing_8","bing_9" },
}
local HONOR_LIST: {string} = { "east", "south", "west", "north", "fa_cai", "hong_zhong", "bai_ban" }

function M.visible_depletion(
   target:    TargetKind,
   feat:      HandFeatures,
   live:      {string: integer},
   seat_wind: Wind,
   round_wind: Wind
): number
   local t = target as string
   local pool: {string} = {}

   if t == "qing_yi_se" then
      if feat.max_suit == "" then return 0.0 end
      for _, k in ipairs(SUIT_KINDS[feat.max_suit]) do pool[#pool + 1] = k end
   elseif t == "hun_yi_se" then
      if feat.max_suit == "" then
         -- No dominant suit yet — pool is all suits + honors which is the
         -- whole wall. Depletion would be misleading; return 0.
         return 0.0
      end
      for _, k in ipairs(SUIT_KINDS[feat.max_suit]) do pool[#pool + 1] = k end
      for _, k in ipairs(HONOR_LIST) do pool[#pool + 1] = k end
   elseif t == "dui_dui_hu" then
      -- Pool = pung-material kinds: dragons + seat wind + round wind +
      -- whatever the player already pairs (the pair candidates that could
      -- form a third copy). Falls back to all 34 kinds if the player has
      -- no pair commitments yet (early-deal hands).
      local seen: {string: boolean} = {}
      for _, k in ipairs(HONOR_LIST) do
         if DRAGON_KINDS[k] or k == (seat_wind as string) or k == (round_wind as string) then
            if not seen[k] then seen[k] = true; pool[#pool + 1] = k end
         end
      end
      -- Pair candidates: kinds in concealed with ≥2 copies (we don't have
      -- the post-discard hand here, but live carries the public state, so
      -- this is approximated through the live count: kinds where live[k]
      -- ≥ 2 are still grow-able).
      for _, k in ipairs(HONOR_LIST) do
         if not seen[k] and (live[k] or 0) >= 2 then
            seen[k] = true; pool[#pool + 1] = k
         end
      end
      for _, suit in ipairs(SUITS) do
         for _, k in ipairs(SUIT_KINDS[suit]) do
            if not seen[k] and (live[k] or 0) >= 2 then
               seen[k] = true; pool[#pool + 1] = k
            end
         end
      end
      if #pool == 0 then return 0.0 end
   else
      return 0.0
   end

   local total = 4 * #pool
   if total == 0 then return 0.0 end
   local remaining = 0
   for _, k in ipairs(pool) do remaining = remaining + (live[k] or 0) end
   local consumed = total - remaining
   if consumed < 0 then consumed = 0 end
   return consumed / total
end

-- ── Expected-fan distribution (S07 commit 3) ─────────────────────────────
--
-- For each target, computes:
--   feasible(t) ∈ {0, 1}   — same gates as estimate_fan_for_target
--   ting_t                 — post-action ting distance (target-blind first
--                            cut; future iteration adds target-specific
--                            shape ting)
--   depletion_t            — visible_depletion(t)
--   fan_t                  — estimate_fan_for_target(t) (post-action hand)
--   p_reach(t)             = feasible × 1 / (ting_t + 1)² × (1 - depletion)
--   contribution_t         = p_reach(t) × fan_t
--
-- Returns: (target_distribution: {t → contribution}, expected_fan: total,
-- dominant_target: argmax). The caller reads p.hand AFTER setting it to
-- the post-action hand (matching enrich_candidate's pattern).
local TARGETS: {TargetKind} = {
   "default" as TargetKind, "dui_dui_hu" as TargetKind,
   "hun_yi_se" as TargetKind, "qing_yi_se" as TargetKind,
}

local function target_feasible(target: TargetKind, feat: HandFeatures): boolean
   local t = target as string
   if t == "dui_dui_hu" then
      return feat.open_chi_count == 0
   elseif t == "qing_yi_se" then
      return (not feat.has_committed_honor) and #feat.committed_suits <= 1
   elseif t == "hun_yi_se" then
      return #feat.committed_suits <= 1
   end
   return true   -- default
end

-- target_misfit(t) returns an additional ting-distance penalty representing
-- "off-target tiles in the hand that would need to be discarded." Standard
-- ting captures progress toward a generic win shape but doesn't penalize
-- tiles the target forbids. Without this, qing_yi_se looks great on a hand
-- full of honors (high standard fan, low standard ting) when in fact all
-- those honors must be thrown away.
--
-- First-cut heuristic; iterate per harness data:
--   default     — 0
--   dui_dui_hu  — 2 × max(0, 4 - (pair_count + triplet_count)). A pair-heavy
--                 hand with 5+ pair-or-triplet kinds is at low penalty;
--                 sequence-heavy hands take a hit.
--   qing_yi_se  — 2 × (honor_count + off_suit_count). Heavy because every
--                 non-pure-suit tile is a throwaway.
--   hun_yi_se   — 2 × off_suit_count. Honors are kept; only off-suit
--                 non-honors are dead weight.
local function target_misfit(target: TargetKind, feat: HandFeatures): number
   local t = target as string
   if t == "qing_yi_se" then
      return 2.0 * ((feat.honor_count + feat.off_suit_count) as number)
   elseif t == "hun_yi_se" then
      return 2.0 * (feat.off_suit_count as number)
   elseif t == "dui_dui_hu" then
      local groups = feat.pair_count   -- includes triplets (counted by ≥2)
      local short = 4 - groups
      if short < 0 then short = 0 end
      return 2.0 * (short as number)
   end
   return 0.0
end

function M.expected_fan_dist(
   deal:         DealState,
   player_index: integer,
   live:         {string: integer}
): {string: number}, number, TargetKind
   local p    = deal.players[player_index]
   local feat = M.compute_features(p.hand.concealed_tiles, p.hand.sets)
   local ting = td.ting_distance_live(p.hand.concealed_tiles, p.hand.sets, live)
   -- Clamp to [0, 100]. ting can return -1 for seven_pairs "almost there"
   -- offsets; clamp negatives to 0 so 1/(ting+1)² is finite. Clamp the
   -- dead-hand sentinel (≥100) to 100 so depleted shapes still get a
   -- (vanishingly small) non-zero probability rather than a divide-by-zero.
   if ting < 0 then ting = 0 end
   if ting >= 100 then ting = 100 end

   local dist: {string: number} = {
      default     = 0.0,
      dui_dui_hu  = 0.0,
      hun_yi_se   = 0.0,
      qing_yi_se  = 0.0,
   }
   local total: number = 0.0
   local best_t: TargetKind = "default" as TargetKind
   local best_c: number = -1.0

   for _, t in ipairs(TARGETS) do
      local contribution: number = 0.0
      if target_feasible(t, feat) then
         local fan_t = M.estimate_fan_for_target(deal, player_index, t)
         if fan_t > 0 then
            local depletion = M.visible_depletion(t, feat, live, p.seat_wind, deal.round_wind)
            local effective_ting = (ting as number) + target_misfit(t, feat)
            local denom = (effective_ting + 1.0) * (effective_ting + 1.0)
            local p_reach = (1.0 - depletion) / denom
            contribution = p_reach * (fan_t as number)
         end
      end
      dist[t as string] = contribution
      total = total + contribution
      if contribution > best_c then
         best_c = contribution
         best_t = t
      end
   end
   return dist, total, best_t
end

-- ── Target selection ──────────────────────────────────────────────────────

-- Picks the target whose expected-fan contribution is highest on the
-- player's current (pre-action) hand. The chosen target is informational —
-- it surfaces in the inspector and the AiReasoning log. The candidate
-- pipeline ranks by full target_distribution, not just the chosen target.
function M.choose_target(
   deal:         DealState,
   player_index: integer,
   _personality: AiPersonality,
   live:         {string: integer}
): TargetKind, integer
   local _dist, _total, dominant = M.expected_fan_dist(deal, player_index, live)
   local est_fan = M.estimate_fan_for_target(deal, player_index, dominant)
   return dominant, est_fan
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

-- Builds one CandidateAction per legal discard. Each candidate's utility
-- is its expected_fan = Σ_t [P_reach(t | hand_after) × fan(t)] across all
-- four targets. The candidate also carries its full target_distribution
-- (per-target contribution to expected_fan) for inspector display and
-- downstream "AI picked X for the dui_dui_hu reason" logic.
--
-- Cost: per candidate, expected_fan_dist runs ting_distance + 4 ×
-- estimate_fan_for_target. For 14 candidates this is ~14× the work of
-- pre-T10's single ting calc. Tests stay under 30s.
function M.evaluate_discard_candidates(
   deal:         DealState,
   player_index: integer,
   _personality: AiPersonality,
   _target:      TargetKind,
   live:         {string: integer}
): {CandidateAction}
   local p = deal.players[player_index]
   local concealed = p.hand.concealed_tiles
   local saved = concealed

   -- tile_id → sorted-position for deterministic tiebreaking in rank.
   local sorted_ids: {string} = {}
   for _, t in ipairs(concealed) do sorted_ids[#sorted_ids + 1] = t.tile_id as string end
   table.sort(sorted_ids)
   local id_index: {string: integer} = {}
   for i, sid in ipairs(sorted_ids) do id_index[sid] = i end

   local out: {CandidateAction} = {}
   for _, t in ipairs(concealed) do
      local rest = tiles_without_id(concealed, t.tile_id)
      p.hand.concealed_tiles = rest
      local dist, expected_fan, dominant = M.expected_fan_dist(deal, player_index, live)
      local feat_after = M.compute_features(rest, p.hand.sets)
      local depletion = M.visible_depletion(dominant, feat_after, live, p.seat_wind, deal.round_wind)
      local after_ting = td.ting_distance_live(rest, p.hand.sets, live)
      p.hand.concealed_tiles = saved

      out[#out + 1] = {
         action               = engine.discard(player_index, t.tile_id),
         tag                  = "discard",
         target_distribution  = dist,
         ting_after           = after_ting,
         ukeire_after         = -1,    -- enriched on demand for top-K
         expected_fan         = expected_fan,
         visible_depletion    = depletion,
         danger               = 0.0,
         utility              = expected_fan + (id_index[t.tile_id as string] as number) * -1e-9,
         accepted             = true,
         rejection_reason     = "",
      }
   end
   return out
end

-- Populates ukeire_after on a discard candidate (compute_ukeire is the
-- expensive remaining piece; expected_fan / target_distribution are now
-- populated at evaluate time). No-op for non-discard candidates.
function M.enrich_candidate(
   deal:         DealState,
   player_index: integer,
   _target:      TargetKind,
   live:         {string: integer},
   c:            CandidateAction
)
   if c.tag ~= "discard" then return end
   if c.ukeire_after >= 0 then return end   -- already enriched
   local p = deal.players[player_index]
   local discard_action = c.action as DiscardAction
   local rest = tiles_without_id(p.hand.concealed_tiles, discard_action.tile_id)
   local saved = p.hand.concealed_tiles
   p.hand.concealed_tiles = rest
   c.ukeire_after = M.compute_ukeire(deal, player_index, live)
   p.hand.concealed_tiles = saved
end

-- Sorts candidates by utility descending. Tiebreak: ukeire desc (more
-- improving kinds), ting asc (closer to ting), tag asc, id asc — all
-- already encoded into utility's tiny id_index term so utility-only
-- ordering is sufficient when discards drove the comparison. Distinct
-- tags (discard vs call vs hu) typically do not share utility scales;
-- callers pick by tag priority before ranking utilities within a tag.
function M.rank_candidates(cands: {CandidateAction}): {CandidateAction}
   local out: {CandidateAction} = {}
   for _, c in ipairs(cands) do out[#out + 1] = c end
   table.sort(out, function(a: CandidateAction, b: CandidateAction): boolean
      if a.utility ~= b.utility then return a.utility > b.utility end
      if a.ukeire_after ~= b.ukeire_after then return a.ukeire_after > b.ukeire_after end
      if a.ting_after ~= b.ting_after then return a.ting_after < b.ting_after end
      if a.tag ~= b.tag then return a.tag < b.tag end
      return false
   end)
   return out
end

-- Returns the first n entries of `cands` (assumes already ranked).
function M.top_n_candidates(cands: {CandidateAction}, n: integer): {CandidateAction}
   local out: {CandidateAction} = {}
   for i = 1, math.min(n, #cands) do out[#out + 1] = cands[i] end
   return out
end

-- Backwards-compatible shim used by ai.tl. Delegates to the candidate
-- pipeline so the chosen tile is the highest-utility CandidateAction's
-- action. Returns the historical 4-tuple for callers that haven't moved
-- to the candidate API yet.
function M.pick_best_discard(
   deal:         DealState,
   player_index: integer,
   personality:  AiPersonality,
   target:       TargetKind,
   live:         {string: integer}
): TileId, integer, integer, integer
   local p = deal.players[player_index]
   local before = td.ting_distance_live(p.hand.concealed_tiles, p.hand.sets, live)
   local cands = M.evaluate_discard_candidates(deal, player_index, personality, target, live)
   local ranked = M.rank_candidates(cands)
   local top = ranked[1]
   M.enrich_candidate(deal, player_index, target, live, top)
   local discard_action = top.action as DiscardAction
   return discard_action.tile_id, before, top.ting_after, top.ukeire_after
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

-- Returns true if at least one target is structurally feasible AND has
-- est_fan ≥ 3 on the current hand. This is a feasibility gate, not a
-- preference: the call gate accepts calls that *could* lead to any 3-fan
-- target, even if the probability ranker currently prefers a different
-- target. Commit 4 replaces these gates with a post-call candidate-
-- pipeline rerun; this function exists for call/kong gates in commit 3.
function M.has_three_fan_target(deal: DealState, player_index: integer, _live: {string: integer}): boolean
   local p = deal.players[player_index]
   local feat = M.compute_features(p.hand.concealed_tiles, p.hand.sets)
   for _, t in ipairs(TARGETS) do
      if target_feasible(t, feat) then
         local fan = M.estimate_fan_for_target(deal, player_index, t)
         if fan >= 3 then return true end
      end
   end
   return false
end

-- Hypothetical variant: temporarily swaps the player's hand and runs
-- has_three_fan_target. `live` is recomputed inside since it depends on the
-- swapped concealed tile count.
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
   local live = M.compute_live_counts(deal, player_index)
   local v = M.has_three_fan_target(deal, player_index, live)
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
