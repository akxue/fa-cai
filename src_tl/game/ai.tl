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

local M = {}

local PLAYER_COUNT <const> = 4
local NA <const> = -100

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

function M.compute_live_counts(deal: DealState, player_index: integer): {string:integer}
   local live: {string:integer} = {}
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
      local target, est_fan = strategy.choose_target(deal, player_index, strategy.NEUTRAL_PERSONALITY)
      local live = M.compute_live_counts(deal, player_index)

      -- Added Kong: strict gate — declare only if a 3-fan target remains
      -- reachable post-kong.
      local ak_id, ak_ok = find_added_kong_target(concealed, p.hand.sets)
      if ak_ok then
         local rest = tiles_without_id(concealed, ak_id)
         if strategy.has_three_fan_target_hypothetical(deal, player_index, rest, p.hand.sets) then
            local ak_action = engine.declare_added_kong(player_index, ak_id)
            return ak_action, mk_reasoning(
               "added_kong", "added kong",
               target as string, NA, NA, -1, est_fan,
               { mk_simple_candidate(ak_action, "added_kong") }
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
         if after <= before
            and strategy.has_three_fan_target_hypothetical(deal, player_index, rest, sets_after) then
            local ck_action = engine.declare_concealed_kong(player_index, quad_kind)
            return ck_action, mk_reasoning(
               "concealed_kong", "concealed kong " .. (quad_kind as string),
               target as string, before, after, -1, est_fan,
               { mk_simple_candidate(ck_action, "concealed_kong") }
            )
         end
      end

      -- Discard via candidate pipeline. We rank all legal discards by the
      -- candidate utility and enrich the top 3 for inspector display.
      local before = td.ting_distance_live(concealed, p.hand.sets, live)
      local discard_cands = strategy.evaluate_discard_candidates(
         deal, player_index, strategy.NEUTRAL_PERSONALITY, target, live
      )
      local ranked = strategy.rank_candidates(discard_cands)
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
      local target, est_fan = strategy.choose_target(deal, player_index, strategy.NEUTRAL_PERSONALITY)
      -- Strict gate: accept a call only if the post-call hand still has a
      -- 3-fan-reachable target (using fitness × est_fan via choose_target).
      -- Combined with the realized-modifier logic in estimate_fan_for_target,
      -- this means: pengs of dragons / seat-wind / round-wind get accepted
      -- (the new triplet realizes a +1 fan modifier), pengs that progress a
      -- structurally-feasible pattern target get accepted, and pengs that
      -- just shuffle tiles without creating a 3-fan path get rejected.
      --
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
         if strategy.has_three_fan_target_hypothetical(deal, player_index, rest, sets_after) then
            local ok_action = engine.declare_open_kong(player_index, discarded.tile_id)
            return ok_action, mk_reasoning(
               "open_kong", "open kong " .. (discarded.kind_id as string),
               target as string, before, after, -1, est_fan,
               { mk_simple_candidate(ok_action, "open_kong") }
            )
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
         if strategy.has_three_fan_target_hypothetical(deal, player_index, rest, sets_after) then
            local peng_action = engine.declare_peng(player_index, discarded.tile_id)
            return peng_action, mk_reasoning(
               "peng", "peng " .. (discarded.kind_id as string),
               target as string, before, after, -1, est_fan,
               { mk_simple_candidate(peng_action, "peng") }
            )
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
            if strategy.has_three_fan_target_hypothetical(deal, player_index, rest, sets_after) then
               local chi_action = engine.declare_chi(player_index, discarded.tile_id, pair)
               return chi_action, mk_reasoning(
                  "chi", "chi " .. (discarded.kind_id as string),
                  target as string, before, after, -1, est_fan,
                  { mk_simple_candidate(chi_action, "chi") }
               )
            end
         end
      end
   end

   return engine.pass_reaction(player_index), mk_reasoning(
      "pass_reaction", "pass",
      "", NA, NA, -1, -1, {}
   )
end

return M
