-- Vanilla AI decision module. Pure — no imports from love, ui, scenes, app.
--
-- Two entry points:
--   ai.decide_main(deal, player_index)     — when it's the AI's turn
--   ai.decide_reaction(deal, player_index) — when the AI is in a reaction window
--
-- Both return (DealAction, AiReasoning). The scene drives turn pumping by
-- calling these functions and dispatching the returned action through the
-- engine. The AI never mutates state directly. An AI seat may read its own
-- `players[seat].known_wall_tile_ids` (populated only when that seat owns an
-- info effect like Third Eye / Open Eyes); it must not read another seat's
-- list. M1 vanilla AIs own no info effects, so this read returns empty.

require("core.types")
require("game.deal_types")
local engine     = require("game.deal_engine")
local validator  = require("game.hand_validator")
local scorer_mod = require("game.scorer")
local calls_mod  = require("game.calls")
local td         = require("game.ting_distance")
local fx_runner  = require("effects.effect_runner")
local wall_mod   = require("game.wall")
local strategy   = require("game.ai_strategy")

global record AiReasoning
   tag:         string    -- "draw" | "zi_mo" | "discard" | "concealed_kong"
                          -- | "added_kong" | "hu_on_discard" | "peng" | "open_kong"
                          -- | "chi" | "pass_reaction"
   message:     string
   ting_before: integer   -- ting distance before this decision; -100 if N/A
   ting_after:  integer   -- ting distance after this decision; -100 if N/A
   target:      string    -- chosen target pattern ("default" | "dui_dui_hu" |
                          -- "hun_yi_se" | "qing_yi_se"); "" when reasoning
                          -- has no target (pass_reaction, zi_mo, hu_on_discard).
   ukeire:      integer   -- live ukeire after this decision; -1 if N/A
   est_fan:     integer   -- target's estimated fan ceiling; -1 if N/A
   candidates:  {CandidateAction}   -- top-K alternatives the AI considered;
                                    -- the first entry is the chosen action.
                                    -- Empty for trivial decisions (draw,
                                    -- pass_reaction with no claim window).
end

local record AiModule
   compute_live_counts: function(DealState, integer): {string: integer}
   decide_main:         function(DealState, integer): (DealAction, AiReasoning)
   decide_reaction:     function(DealState, integer): (DealAction, AiReasoning)
end
local M: AiModule = {} as AiModule

local PLAYER_COUNT <const> = 4
local NA <const> = -100

-- Post-call gate (S07 T16, T17). The call is accepted iff the best
-- post-call discard candidate has probability-weighted expected_fan ≥ 3.
local POST_CALL_FAN_FLOOR <const>: integer = 3

-- compute_live_counts now lives in ai_strategy.tl. Re-exported at the
-- bottom of this file so existing callers (table_scene, tests) keep
-- working through the ai.tl boundary.

-- ── Score-context builder ──────────────────────────────────────────────────
-- Mirrors deal_engine.build_score_ctx so AI Hu legality matches the engine
-- exactly. is_men_qian is derived from open-set visibility.

local function build_score_ctx(
   deal:           DealState,
   player_index:   integer,
   is_zi_mo:       boolean,
   is_gang_shang:  boolean,
   is_qiang_gang:  boolean
): ScoreContext
   local open_sets = deal.players[player_index].hand.sets
   local is_men_qian = true
   for _, s in ipairs(open_sets) do
      if (s.visibility as string) == "open" then
         is_men_qian = false
         break
      end
   end
   local is_hai_di = is_zi_mo and wall_mod.remaining(deal.wall) == 0
   return {
      incoming_tile = { tile_id = "" as TileId, kind_id = "" as TileKindId },
      has_incoming  = not is_zi_mo,
      is_zi_mo      = is_zi_mo,
      is_men_qian   = is_men_qian,
      is_hai_di     = is_hai_di,
      is_gang_shang = is_gang_shang,
      is_qiang_gang = is_qiang_gang,
      round_wind    = deal.round_wind,
      seat_wind     = deal.players[player_index].seat_wind,
   }
end

-- Runs the same validate-and-score path the engine uses for Hu approval.
-- Returns whether the player would have a valid Hu on `incoming` and the
-- best ScoreResult (after boon score modifiers).
local function evaluate_hu(
   deal:           DealState,
   player_index:   integer,
   concealed:      {Tile},
   incoming:       Tile,
   is_zi_mo:       boolean,
   is_gang_shang:  boolean,
   is_qiang_gang:  boolean
): boolean, ScoreResult
   local p      = deal.players[player_index]
   local shapes = validator.find_win_shapes(concealed, incoming, p.hand.sets)
   local ctx    = build_score_ctx(deal, player_index, is_zi_mo, is_gang_shang, is_qiang_gang)
   local output = scorer_mod.score_hand(shapes, ctx)
   if not output.has_best then
      return false, {} as ScoreResult
   end
   local final = fx_runner.apply_score_modifiers(deal, ctx, shapes[1], output.candidates[1], player_index)
   for i = 2, #output.candidates do
      local cand = fx_runner.apply_score_modifiers(deal, ctx, shapes[i], output.candidates[i], player_index)
      local best_rank = final.is_limit and 10000 or final.total_fan
      local cand_rank = cand.is_limit and 10000 or cand.total_fan
      if cand_rank > best_rank then final = cand end
   end
   return final.valid_hu, final
end

-- ── Tile-list helpers ─────────────────────────────────────────────────────

local function tiles_without_id(tiles: {Tile}, tile_id: TileId): {Tile}
   local out: {Tile} = {}
   for _, t in ipairs(tiles) do
      if t.tile_id ~= tile_id then out[#out + 1] = t end
   end
   return out
end

local function tiles_without_kind(tiles: {Tile}, kind_id: TileKindId, max_remove: integer): {Tile}
   local out: {Tile} = {}
   local removed = 0
   for _, t in ipairs(tiles) do
      if removed < max_remove and t.kind_id == kind_id then
         removed = removed + 1
      else
         out[#out + 1] = t
      end
   end
   return out
end

local function tiles_remove_id_pair(tiles: {Tile}, id_a: TileId, id_b: TileId): {Tile}
   local out: {Tile} = {}
   for _, t in ipairs(tiles) do
      if t.tile_id ~= id_a and t.tile_id ~= id_b then
         out[#out + 1] = t
      end
   end
   return out
end

-- ── AiReasoning constructor ───────────────────────────────────────────────

-- Builds a placeholder CandidateAction for a non-discard action (Hu, kong,
-- peng, chi, pass). Discards have rich candidates produced by the strategy
-- pipeline; calls go through the gates inline in decide_main /
-- decide_reaction and produce a single chosen candidate. The richer
-- post-call-best-candidate evaluation lands in commit 4 (T16).
local function mk_simple_candidate(action: DealAction, tag: string): CandidateAction
   return {
      action               = action,
      tag                  = tag,
      target_distribution  = { default = 0.0, dui_dui_hu = 0.0, hun_yi_se = 0.0, qing_yi_se = 0.0 },
      ting_after           = NA,
      ukeire_after         = -1,
      expected_fan         = -1,
      visible_depletion    = 0.0,
      danger               = 0.0,
      utility              = 0.0,
      accepted             = true,
      rejection_reason     = "",
   }
end

local function mk_call_candidate(
   action:           DealAction,
   tag:              string,
   best_after:       CandidateAction,
   ting_after:       integer,
   accepted:         boolean,
   rejection_reason: string
): CandidateAction
   return {
      action               = action,
      tag                  = tag,
      target_distribution  = best_after.target_distribution,
      ting_after           = ting_after,
      ukeire_after         = best_after.ukeire_after,
      expected_fan         = best_after.expected_fan,
      visible_depletion    = best_after.visible_depletion,
      danger               = best_after.danger,
      utility              = best_after.utility,
      accepted             = accepted,
      rejection_reason     = rejection_reason,
   }
end

local function upgraded_added_kong_sets(sets: {TileSet}, fourth_tile: Tile): {TileSet}
   local out: {TileSet} = {}
   local upgraded = false
   for _, s in ipairs(sets) do
      if not upgraded and (s.kind as string) == "peng" and #s.tiles > 0 and s.tiles[1].kind_id == fourth_tile.kind_id then
         local tiles: {Tile} = {}
         for _, t in ipairs(s.tiles) do tiles[#tiles + 1] = t end
         tiles[#tiles + 1] = fourth_tile
         out[#out + 1] = {
            kind        = "kong" as TileSetKind,
            visibility  = s.visibility,
            tiles       = tiles,
            called_from = s.called_from,
         }
         upgraded = true
      else
         out[#out + 1] = s
      end
   end
   return out
end

local function mk_reasoning(
   tag:        string,
   message:    string,
   target:     string,
   ting_before: integer,
   ting_after:  integer,
   ukeire:      integer,
   est_fan:     integer,
   candidates:  {CandidateAction}
): AiReasoning
   return {
      tag         = tag,
      message     = message,
      target      = target,
      ting_before = ting_before,
      ting_after  = ting_after,
      ukeire      = ukeire,
      est_fan     = est_fan,
      candidates  = candidates or {},
   }
end

-- ── Discard heuristic ─────────────────────────────────────────────────────
-- Delegates to ai_strategy: picks a target via `choose_target`, then ranks
-- candidate discards on (live ting after, ukeire after, tile-value, tile_id).

-- ── Concealed/added Kong evaluation ───────────────────────────────────────

-- Find a kind held 4 times in concealed tiles, if any.
local function find_concealed_quad_kind(concealed: {Tile}): TileKindId, boolean
   local counts: {string:integer} = {}
   for _, t in ipairs(concealed) do
      local k = t.kind_id as string
      counts[k] = (counts[k] or 0) + 1
   end
   for k, n in pairs(counts) do
      if n >= 4 then return k as TileKindId, true end
   end
   return "" as TileKindId, false
end

-- Find a tile in concealed whose kind matches an existing open Peng. Returns
-- the tile_id and true on hit.
local function find_added_kong_target(concealed: {Tile}, sets: {TileSet}): TileId, boolean
   for _, s in ipairs(sets) do
      if (s.kind as string) == "peng" and #s.tiles > 0 then
         local pk = s.tiles[1].kind_id
         for _, t in ipairs(concealed) do
            if t.kind_id == pk then return t.tile_id, true end
         end
      end
   end
   return "" as TileId, false
end

-- ── Public entry: main turn decision ──────────────────────────────────────

-- Returns the AI's chosen action for its own turn.
-- Phase contract:
--   awaiting_draw  → returns a DrawAction.
--   awaiting_action → considers Zi Mo, then concealed/added Kong, then discard.
-- Other phases return a discard placeholder; callers should not poll AI in
-- non-AI phases.
function M.decide_main(deal: DealState, player_index: integer): DealAction, AiReasoning
   local phase = deal.phase as string

   if phase == "awaiting_draw" then
      local p = deal.players[player_index]
      local live = M.compute_live_counts(deal, player_index)
      local before = td.ting_distance_live(p.hand.concealed_tiles, p.hand.sets, live)
      return engine.draw(player_index), mk_reasoning(
         "draw", "draw (ting=" .. tostring(before) .. ")",
         "", before, NA, -1, -1, {}
      )
   end

   if phase == "awaiting_action" then
      local p        = deal.players[player_index]
      local concealed = p.hand.concealed_tiles

      -- Zi Mo: split off last drawn tile and check Hu.
      if deal.has_last_drawn then
         local drawn_id = deal.last_drawn_tile_id
         local drawn_tile: Tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }
         for _, t in ipairs(concealed) do
            if t.tile_id == drawn_id then drawn_tile = t; break end
         end
         if (drawn_tile.tile_id as string) ~= "" then
            local rest = tiles_without_id(concealed, drawn_id)
            local ok, _final = evaluate_hu(deal, player_index, rest, drawn_tile, true, deal.last_draw_was_supplement, false)
            if ok then
               local zm_action = engine.declare_hu(player_index, "" as TileId, true)
               return zm_action, mk_reasoning(
                  "zi_mo", "zi mo on " .. (drawn_tile.kind_id as string),
                  "", NA, NA, -1, -1,
                  { mk_simple_candidate(zm_action, "zi_mo") }
               )
            end
         end
      end

      -- Choose target up front; downstream decisions use it.
      local live = M.compute_live_counts(deal, player_index)
      local target, est_fan = strategy.choose_target(deal, player_index, strategy.NEUTRAL_PERSONALITY, live)
      -- Added Kong gate (S07 T16): declare only if the post-kong best
      -- discard candidate's expected_fan ≥ 3. Probability-weighted check;
      -- catches kongs that empty the AI's hand of useful tiles even if a
      -- 3-fan target is technically still feasible.
      local ak_id, ak_ok = find_added_kong_target(concealed, p.hand.sets)
      if ak_ok then
         local rest = tiles_without_id(concealed, ak_id)
         local fourth_tile: Tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }
         for _, t in ipairs(concealed) do
            if t.tile_id == ak_id then fourth_tile = t; break end
         end
         local sets_after = upgraded_added_kong_sets(p.hand.sets, fourth_tile)
         -- T19: kong gate uses supplement-draw averaging since the kong
         -- triggers a supplement draw before the next discard.
         local post_avg = strategy.kong_post_supplement_avg_fan(deal, player_index, rest, sets_after, live, strategy.NEUTRAL_PERSONALITY)
         local ak_action = engine.declare_added_kong(player_index, ak_id)
         if post_avg >= POST_CALL_FAN_FLOOR then
            return ak_action, mk_reasoning(
               "added_kong", "added kong",
               target as string, NA, NA, -1, est_fan,
               {
                  {
                     action               = ak_action,
                     tag                  = "added_kong",
                     target_distribution  = { default = 0.0, dui_dui_hu = 0.0, hun_yi_se = 0.0, qing_yi_se = 0.0 },
                     ting_after           = NA,
                     ukeire_after         = -1,
                     expected_fan         = post_avg,
                     visible_depletion    = 0.0,
                     danger               = 0.0,
                     utility              = post_avg,
                     accepted             = true,
                     rejection_reason     = "",
                  },
               }
            )
         end
      end

      -- Concealed Kong: strict gate (no ting regression + 3-fan path remains).
      -- Concealed kong preserves men_qian (it's a "concealed" set) so it's
      -- structurally clean; the risk is locking 4 tiles into a kong when
      -- they could have been better used elsewhere — caught by the
      -- ting-not-regress check. Build the kong set with the 4 actual tiles
      -- so realized-modifier counting captures dragon/wind kongs.
      local quad_kind, has_quad = find_concealed_quad_kind(concealed)
      if has_quad then
         local before = td.ting_distance_live(concealed, p.hand.sets, live)
         local rest   = tiles_without_kind(concealed, quad_kind, 4)
         local kong_tiles: {Tile} = {}
         for _, t in ipairs(concealed) do
            if t.kind_id == quad_kind and #kong_tiles < 4 then
               kong_tiles[#kong_tiles + 1] = t
            end
         end
         local fake_set: TileSet = {
            kind        = "kong" as TileSetKind,
            visibility  = "concealed" as SetVisibility,
            tiles       = kong_tiles,
            called_from = -1,
         }
         local sets_after: {TileSet} = {}
         for _, s in ipairs(p.hand.sets) do sets_after[#sets_after + 1] = s end
         sets_after[#sets_after + 1] = fake_set
         local after = td.ting_distance_live(rest, sets_after, live)
         local post_avg = strategy.kong_post_supplement_avg_fan(deal, player_index, rest, sets_after, live, strategy.NEUTRAL_PERSONALITY)
         if after <= before and post_avg >= POST_CALL_FAN_FLOOR then
            local ck_action = engine.declare_concealed_kong(player_index, quad_kind)
            return ck_action, mk_reasoning(
               "concealed_kong", "concealed kong " .. (quad_kind as string),
               target as string, before, after, -1, est_fan,
               {
                  {
                     action               = ck_action,
                     tag                  = "concealed_kong",
                     target_distribution  = { default = 0.0, dui_dui_hu = 0.0, hun_yi_se = 0.0, qing_yi_se = 0.0 },
                     ting_after           = after,
                     ukeire_after         = -1,
                     expected_fan         = post_avg,
                     visible_depletion    = 0.0,
                     danger               = 0.0,
                     utility              = post_avg,
                     accepted             = true,
                     rejection_reason     = "",
                  },
               }
            )
         end
      end

      -- Discard via candidate pipeline. We rank all legal discards by the
      -- candidate utility and enrich the top 3 for inspector display.
      local before = td.ting_distance_live(concealed, p.hand.sets, live)
      local discard_cands = strategy.evaluate_discard_candidates(
         deal, player_index, strategy.NEUTRAL_PERSONALITY, target, live
      )
      local ranked = strategy.rank_candidates(discard_cands, strategy.NEUTRAL_PERSONALITY)
      local top3 = strategy.top_n_candidates(ranked, 3)
      for _, c in ipairs(top3) do
         strategy.enrich_candidate(deal, player_index, target, live, c)
      end
      local chosen = top3[1]
      local discard_action = chosen.action as DiscardAction
      return chosen.action, mk_reasoning(
         "discard", "discard " .. (discard_action.tile_id as string),
         target as string, before, chosen.ting_after, chosen.ukeire_after, est_fan,
         top3
      )
   end

   -- Unknown phase: defensive — return a draw with NA reasoning. Callers should
   -- not invoke decide_main outside the AI's turn.
   return engine.draw(player_index), mk_reasoning(
      "draw", "unexpected phase: " .. phase,
      "", NA, NA, -1, -1, {}
   )
end

-- ── Public entry: reaction-window decision ────────────────────────────────

-- Picks the AI's response to a pending discard or pending added kong. Order
-- of consideration: Hu > open_kong > Peng > Chi > pass. A call is only made
-- if it does not regress ting distance compared to the no-call state. Hu is
-- evaluated through the engine's same scoring path, so the 3-fan minimum
-- and boon modifiers apply.
function M.decide_reaction(deal: DealState, player_index: integer): DealAction, AiReasoning
   if (deal.phase as string) ~= "reaction_window" then
      return engine.pass_reaction(player_index), mk_reasoning(
         "pass_reaction", "not in reaction window",
         "", NA, NA, -1, -1, {}
      )
   end

   local p = deal.players[player_index]
   local concealed = p.hand.concealed_tiles
   local rejected_candidates: {CandidateAction} = {}

   -- Hu on discard (or qiang gang on pending added kong).
   if deal.has_pending_discard then
      if player_index ~= deal.pending_discard.discarder then
         local incoming = deal.pending_discard.tile
         local ok, _final = evaluate_hu(deal, player_index, concealed, incoming, false, false, false)
         if ok then
            local hu_action = engine.declare_hu(player_index, incoming.tile_id, false)
            return hu_action, mk_reasoning(
               "hu_on_discard", "hu on " .. (incoming.kind_id as string),
               "", NA, NA, -1, -1,
               { mk_simple_candidate(hu_action, "hu_on_discard") }
            )
         end
      end
   elseif deal.has_pending_kong then
      if player_index ~= deal.pending_added_kong.declarer then
         local kong_tile = deal.pending_added_kong.tile
         local ok, _final = evaluate_hu(deal, player_index, concealed, kong_tile, false, false, true)
         if ok then
            local hu_action = engine.declare_hu(player_index, deal.pending_added_kong.tile_id, false)
            return hu_action, mk_reasoning(
               "hu_on_discard", "qiang gang on " .. (kong_tile.kind_id as string),
               "", NA, NA, -1, -1,
               { mk_simple_candidate(hu_action, "hu_on_discard") }
            )
         end
      end
      -- No legal Peng/Chi/Open Kong on a pending added kong.
      return engine.pass_reaction(player_index), mk_reasoning(
         "pass_reaction", "pass on added kong",
         "", NA, NA, -1, -1, {}
      )
   end

   -- Discard-driven calls: open_kong → peng → chi.
   -- A call is accepted only if (a) it does not regress live ting and
   -- (b) the resulting hand still has a 3-fan-reachable target.
   if deal.has_pending_discard then
      if player_index == deal.pending_discard.discarder then
         return engine.pass_reaction(player_index), mk_reasoning(
            "pass_reaction", "discarder passes own window",
            "", NA, NA, -1, -1, {}
         )
      end
      local discarded = deal.pending_discard.tile
      local discarder = deal.pending_discard.discarder
      local live   = M.compute_live_counts(deal, player_index)
      local before = td.ting_distance_live(concealed, p.hand.sets, live)
      local target, est_fan = strategy.choose_target(deal, player_index, strategy.NEUTRAL_PERSONALITY, live)
      -- Earlier tried "permissive accept" (reject only if call DESTROYS a
      -- pre-existing 3-fan path). On 10 seeds it dropped Hu rate from 6/10
      -- to 1/10 — junk hands accepted too many sub-strategic calls and lost
      -- their concealed-path optionality without converging on anything.

      -- Open Kong: 3 in hand + 1 from discard. Set absorbs all 3 matching tiles.
      -- After kong, concealed = 10 tiles (= K=1 ting hand size). Use plain
      -- standard ting (no post-call adjustment needed); the algorithm models
      -- "needs 1 added tile" naturally via the supplement draw.
      if calls_mod.can_open_kong(discarded, concealed, discarder, player_index) then
         local rest = tiles_without_kind(concealed, discarded.kind_id, 3)
         local sets_after = {} as {TileSet}
         for _, s in ipairs(p.hand.sets) do sets_after[#sets_after + 1] = s end
         sets_after[#sets_after + 1] = {
            kind        = "kong" as TileSetKind,
            visibility  = "open" as SetVisibility,
            tiles       = { discarded, discarded, discarded, discarded },
            called_from = discarder,
         }
         local after = td.ting_distance_standard_live(rest, sets_after, live)
         local post_avg = strategy.kong_post_supplement_avg_fan(deal, player_index, rest, sets_after, live, strategy.NEUTRAL_PERSONALITY)
         local ok_action = engine.declare_open_kong(player_index, discarded.tile_id)
         local ok_candidate: CandidateAction = {
            action               = ok_action,
            tag                  = "open_kong",
            target_distribution  = { default = 0.0, dui_dui_hu = 0.0, hun_yi_se = 0.0, qing_yi_se = 0.0 },
            ting_after           = after,
            ukeire_after         = -1,
            expected_fan         = post_avg,
            visible_depletion    = 0.0,
            danger               = 0.0,
            utility              = post_avg,
            accepted             = post_avg >= POST_CALL_FAN_FLOOR,
            rejection_reason     = post_avg >= POST_CALL_FAN_FLOOR and "" or "post_kong_expected_fan_below_floor",
         }
         if post_avg >= POST_CALL_FAN_FLOOR then
            return ok_action, mk_reasoning(
               "open_kong", "open kong " .. (discarded.kind_id as string),
               target as string, before, after, -1, est_fan,
               { ok_candidate }
            )
         else
            rejected_candidates[#rejected_candidates + 1] = ok_candidate
         end
      end

      -- Peng: 2 in hand + 1 from discard. After peng, concealed = 11 tiles
      -- (1 over ting hand size). The player will discard 1 next; use
      -- `post_call_ting` which accounts for that forced discard.
      if calls_mod.can_peng(discarded, concealed, discarder, player_index) then
         local rest = tiles_without_kind(concealed, discarded.kind_id, 2)
         local sets_after = {} as {TileSet}
         for _, s in ipairs(p.hand.sets) do sets_after[#sets_after + 1] = s end
         sets_after[#sets_after + 1] = {
            kind        = "peng" as TileSetKind,
            visibility  = "open" as SetVisibility,
            tiles       = { discarded, discarded, discarded },
            called_from = discarder,
         }
         local after = strategy.post_call_ting(rest, sets_after, live)
         local best_after, best_ok = strategy.post_call_best_candidate_hypothetical(
            deal, player_index, rest, sets_after, live, strategy.NEUTRAL_PERSONALITY
         )
         local peng_action = engine.declare_peng(player_index, discarded.tile_id)
         local accepted = best_ok and best_after.expected_fan >= POST_CALL_FAN_FLOOR
         local rejection = accepted and "" or "post_call_expected_fan_below_floor"
         local peng_candidate = mk_call_candidate(peng_action, "peng", best_after, after, accepted, rejection)
         if accepted then
            return peng_action, mk_reasoning(
               "peng", "peng " .. (discarded.kind_id as string),
               target as string, before, after, -1, est_fan,
               { peng_candidate, best_after }
            )
         else
            rejected_candidates[#rejected_candidates + 1] = peng_candidate
         end
      end

      -- Chi: only the next player can chi. Stricter gate than peng — chi
      -- commits to a sequence orientation, which can lock the hand into the
      -- wrong direction. Require the post-chi hand to still have a 3-fan
      -- path (not just "doesn't destroy an existing one"). This means chi
      -- is rejected on hands that have no 3-fan path either way; the AI
      -- doesn't flail with chis on doomed hands.
      if calls_mod.is_next_player(discarder, player_index, PLAYER_COUNT) then
         local combos = calls_mod.chi_combinations(discarded, concealed)
         for _, pair in ipairs(combos) do
            local rest = tiles_remove_id_pair(concealed, pair[1], pair[2])
            -- Find the two concealed tiles named in this chi combo so the
            -- simulated set carries real tiles. Without these, compute_features
            -- can't tell what suit the chi committed to, and the qing_yi_se /
            -- hun_yi_se feasibility gates miscount committed_suits.
            local pair_a: Tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }
            local pair_b: Tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }
            for _, t in ipairs(concealed) do
               if t.tile_id == pair[1] then pair_a = t end
               if t.tile_id == pair[2] then pair_b = t end
            end
            local sets_after = {} as {TileSet}
            for _, s in ipairs(p.hand.sets) do sets_after[#sets_after + 1] = s end
            sets_after[#sets_after + 1] = {
               kind        = "chi" as TileSetKind,
               visibility  = "open" as SetVisibility,
               tiles       = { pair_a, pair_b, discarded },
               called_from = discarder,
            }
            local after = strategy.post_call_ting(rest, sets_after, live)
            local best_after, best_ok = strategy.post_call_best_candidate_hypothetical(
               deal, player_index, rest, sets_after, live, strategy.NEUTRAL_PERSONALITY
            )
            local chi_action = engine.declare_chi(player_index, discarded.tile_id, pair)
            local accepted = best_ok and best_after.expected_fan >= POST_CALL_FAN_FLOOR
            local rejection = accepted and "" or "post_call_expected_fan_below_floor"
            local chi_candidate = mk_call_candidate(chi_action, "chi", best_after, after, accepted, rejection)
            if accepted then
               return chi_action, mk_reasoning(
                  "chi", "chi " .. (discarded.kind_id as string),
                  target as string, before, after, -1, est_fan,
                  { chi_candidate, best_after }
               )
            else
               rejected_candidates[#rejected_candidates + 1] = chi_candidate
            end
         end
      end
   end

   return engine.pass_reaction(player_index), mk_reasoning(
      "pass_reaction", "pass",
      "", NA, NA, -1, -1, rejected_candidates
   )
end

M.compute_live_counts = strategy.compute_live_counts

return M
