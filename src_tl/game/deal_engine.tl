-- Deal engine: deterministic state machine for one mahjong deal.
-- Implements opening deal, draw/discard flow, reaction windows with engine-enforced
-- priority resolution (Hu > Kong/Peng > Chi, ties broken by nearest-next from the
-- discarder), all Kong flows, Hu resolution, and wall exhaustion.
-- No imports from love, ui, scenes, or app.

require("core.types")
require("core.rng")
require("game.deal_types")
require("game.run_state")
require("effects.effect_types")
local wall_mod    = require("game.wall")
local tiles_mod   = require("game.tiles")
local calls_mod   = require("game.calls")
local scorer_mod  = require("game.scorer")
local fx_runner   = require("effects.effect_runner")

local M = {}

local PLAYER_COUNT <const> = 4

local SEAT_WINDS: {Wind} = {
   "east" as Wind, "south" as Wind, "west" as Wind, "north" as Wind,
}

-- Reaction priority. Higher beats lower. Ties broken by nearest-next from the actor.
local CLAIM_PRIORITY: {string:integer} = {
   hu        = 3,
   peng      = 2,
   open_kong = 2,
   chi       = 1,
}

-- ── Deep copy helpers ──────────────────────────────────────────────────────

local function copy_tiles(tiles: {Tile}): {Tile}
   local out: {Tile} = {}
   for _, t in ipairs(tiles) do out[#out + 1] = t end
   return out
end

local function copy_tile_ids(ids: {TileId}): {TileId}
   local out: {TileId} = {}
   for _, id in ipairs(ids) do out[#out + 1] = id end
   return out
end

local function copy_set(s: TileSet): TileSet
   return {
      kind        = s.kind,
      visibility  = s.visibility,
      tiles       = copy_tiles(s.tiles),
      called_from = s.called_from,
   }
end

local function copy_hand(h: PlayerHand): PlayerHand
   local sets: {TileSet} = {}
   for _, s in ipairs(h.sets) do sets[#sets + 1] = copy_set(s) end
   return {
      concealed_tiles = copy_tiles(h.concealed_tiles),
      sets            = sets,
      discards        = copy_tiles(h.discards),
   }
end

local function copy_player(p: PlayerState): PlayerState
   return {
      hand                = copy_hand(p.hand),
      opening_trim        = copy_tiles(p.opening_trim),
      seat_wind           = p.seat_wind,
      is_human            = p.is_human,
      known_wall_tile_ids = copy_tile_ids(p.known_wall_tile_ids),
   }
end

local function copy_claim(c: PendingClaim): PendingClaim
   return {
      player_index       = c.player_index,
      kind               = c.kind,
      chi_other_tile_ids = copy_tile_ids(c.chi_other_tile_ids),
   }
end

local function copy_counters(c: {string: integer}): {string: integer}
   local out: {string: integer} = {}
   for k, v in pairs(c) do out[k] = v end
   return out
end

local function copy_active_effect(a: ActiveEffectState): ActiveEffectState
   return {
      active_effect_id   = a.active_effect_id,
      effect_id          = a.effect_id,
      source_kind        = a.source_kind,
      source_id          = a.source_id,
      owner_player_index = a.owner_player_index,
      has_owner          = a.has_owner,
      counters           = copy_counters(a.counters),
      used_this_deal     = a.used_this_deal,
   }
end

local function copy_effect_states(states: {string: ActiveEffectState}): {string: ActiveEffectState}
   local out: {string: ActiveEffectState} = {}
   for k, a in pairs(states) do out[k] = copy_active_effect(a) end
   return out
end

local function copy_deal(d: DealState): DealState
   local players: {PlayerState} = {}
   for _, p in ipairs(d.players) do players[#players + 1] = copy_player(p) end
   local passes: {integer} = {}
   for _, pi in ipairs(d.reaction_passes) do passes[#passes + 1] = pi end
   local claims: {PendingClaim} = {}
   for _, c in ipairs(d.pending_claims) do claims[#claims + 1] = copy_claim(c) end
   return {
      players                  = players,
      wall                     = { tiles = copy_tiles(d.wall.tiles) },
      phase                    = d.phase,
      current_player           = d.current_player,
      dealer                   = d.dealer,
      round_wind               = d.round_wind,
      pending_discard          = d.pending_discard,
      has_pending_discard      = d.has_pending_discard,
      pending_added_kong       = d.pending_added_kong,
      has_pending_kong         = d.has_pending_kong,
      rng                      = d.rng,
      deal_result              = d.deal_result,
      has_deal_result          = d.has_deal_result,
      reaction_passes          = passes,
      pending_claims           = claims,
      last_draw_was_supplement = d.last_draw_was_supplement,
      last_drawn_tile_id       = d.last_drawn_tile_id,
      has_last_drawn           = d.has_last_drawn,
      effect_states            = copy_effect_states(d.effect_states),
   }
end

-- ── Tile manipulation helpers ──────────────────────────────────────────────

local function find_tile(tiles: {Tile}, tile_id: TileId): Tile, boolean
   for _, t in ipairs(tiles) do
      if (t.tile_id as string) == (tile_id as string) then return t, true end
   end
   return { tile_id = "" as TileId, kind_id = "" as TileKindId }, false
end

local function remove_tile(tiles: {Tile}, tile_id: TileId): {Tile}, boolean
   local out: {Tile} = {}
   local found = false
   for _, t in ipairs(tiles) do
      if not found and (t.tile_id as string) == (tile_id as string) then
         found = true
      else
         out[#out + 1] = t
      end
   end
   return out, found
end

local function remove_by_kind(tiles: {Tile}, kind_id: TileKindId, count: integer): {Tile}, {Tile}
   local remaining: {Tile} = {}
   local removed: {Tile}   = {}
   for _, t in ipairs(tiles) do
      if #removed < count and t.kind_id == kind_id then
         removed[#removed + 1] = t
      else
         remaining[#remaining + 1] = t
      end
   end
   return remaining, removed
end

local function remove_known(known: {TileId}, tile_id: TileId): {TileId}
   local out: {TileId} = {}
   local done = false
   for _, id in ipairs(known) do
      if not done and (id as string) == (tile_id as string) then done = true
      else out[#out + 1] = id end
   end
   return out
end

local function has_passed(passes: {integer}, player_index: integer): boolean
   for _, pi in ipairs(passes) do
      if pi == player_index then return true end
   end
   return false
end

local function has_claimed(claims: {PendingClaim}, player_index: integer): boolean
   for _, c in ipairs(claims) do
      if c.player_index == player_index then return true end
   end
   return false
end

local function has_responded(d: DealState, player_index: integer): boolean
   return has_passed(d.reaction_passes, player_index) or has_claimed(d.pending_claims, player_index)
end

local function all_reactors_responded(d: DealState): boolean
   return #d.reaction_passes + #d.pending_claims >= PLAYER_COUNT - 1
end

-- Reaction-window actor: discarder during a discard window, declarer during a kong window.
local function reaction_actor(d: DealState): integer
   if d.has_pending_discard then return d.pending_discard.discarder end
   if d.has_pending_kong then return d.pending_added_kong.declarer end
   return -1
end

-- Distance from actor to claimant, with the actor's next player at distance 1.
local function turn_distance(actor: integer, claimant: integer): integer
   local diff = (claimant - actor) % PLAYER_COUNT
   if diff == 0 then return PLAYER_COUNT end
   return diff
end

-- ── Transition builders ────────────────────────────────────────────────────

local function err(deal: DealState, msg: string): DealTransition
   return { ok = false, deal = deal, events = {}, error = msg }
end

local function ok_t(deal: DealState, events: {DealEvent}): DealTransition
   return { ok = true, deal = deal, events = events, error = "" }
end

local function ev(kind: string, msg: string): DealEvent
   return { kind = kind, message = msg }
end

-- ── Empty value constructors ───────────────────────────────────────────────

local function empty_score_result(): ScoreResult
   return {
      win_shape_kind = "" as WinShapeKind,
      reasons        = {},
      total_fan      = 0,
      is_limit       = false,
      rating         = "" as Rating,
      valid_hu       = false,
   }
end

local function empty_deal_result(): DealResult
   return {
      winner_player_index = 0,
      won_by_zi_mo        = false,
      score_result        = empty_score_result(),
      has_score_result    = false,
   }
end

local function empty_pending_discard(): PendingDiscard
   return { tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }, discarder = 0 }
end

local function empty_pending_kong(): PendingAddedKong
   return {
      tile_id  = "" as TileId,
      tile     = { tile_id = "" as TileId, kind_id = "" as TileKindId },
      declarer = 0,
   }
end

-- ── Wall exhaustion ────────────────────────────────────────────────────────

local function wall_exhaustion(d: DealState): DealTransition
   d.phase = "deal_over" as DealPhase
   d.deal_result = {
      winner_player_index = -1,
      won_by_zi_mo        = false,
      score_result        = empty_score_result(),
      has_score_result    = false,
   }
   d.has_deal_result = true
   return ok_t(d, { ev("wall_exhaustion", "wall exhausted — no winner") })
end

-- ── Supplement draw ────────────────────────────────────────────────────────

-- Draws a supplement tile from the back of the wall into player_index's hand.
-- Returns updated DealState and whether the wall was already empty.
local function draw_supplement(d: DealState, player_index: integer): DealState, boolean
   if wall_mod.remaining(d.wall) == 0 then
      return d, true
   end
   local dr = wall_mod.draw_back(d.wall)
   d.wall = dr.wall
   d.players[player_index].hand.concealed_tiles[
      #d.players[player_index].hand.concealed_tiles + 1
   ] = dr.tile
   d.last_draw_was_supplement = true
   d.last_drawn_tile_id       = dr.tile.tile_id
   d.has_last_drawn           = true
   local cmds = fx_runner.dispatch_after_draw(d, player_index, dr.tile, true)
   fx_runner.apply_commands(d, cmds)
   return d, false
end

-- ── Effect score modifier integration ─────────────────────────────────────

-- Routes the best ScoreResult through the effect runner so registered boons
-- can append ScoreReasons before total_fan/valid_hu are recomputed. Boons
-- cannot bypass shape validation (input is the scorer's chosen shape).
local function apply_score_modifiers(
   deal:           DealState,
   ctx:            ScoreContext,
   shapes:         {WinShape},
   output:         ScorerOutput,
   winner_index:   integer
): ScoreResult
   if not output.has_best then return output.best end

   local best = fx_runner.apply_score_modifiers(deal, ctx, shapes[1], output.candidates[1], winner_index)
   for i = 2, #output.candidates do
      local candidate = fx_runner.apply_score_modifiers(deal, ctx, shapes[i], output.candidates[i], winner_index)
      local best_rank = best.total_fan
      local candidate_rank = candidate.total_fan
      if best.is_limit then best_rank = 10000 end
      if candidate.is_limit then candidate_rank = 10000 end
      if candidate_rank > best_rank then
         best = candidate
      end
   end
   return best
end

-- Re-evaluates valid_hu after boon ScoreReasons; mirrors scorer's threshold.
local function score_passes_threshold(r: ScoreResult): boolean
   return r.valid_hu
end

-- ── Score context ──────────────────────────────────────────────────────────

local function build_score_ctx(deal: DealState, player_index: integer, is_zi_mo: boolean, is_gang_shang: boolean, is_qiang_gang: boolean): ScoreContext
   local open_sets = deal.players[player_index].hand.sets
   local is_men_qian = true
   for _, s in ipairs(open_sets) do
      if (s.visibility as string) == "open" then is_men_qian = false; break end
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

-- ── Opening deal ──────────────────────────────────────────────────────────

-- Builds the raw shell of a deal: 136 tiles shuffled, 13 dealt to each
-- non-dealer, and (13 + dealer_extra) dealt to the dealer. Phase is left to
-- the caller to set. effect_states starts empty.
local function build_initial_deal(rng: RngState, dealer_extra: integer): DealState
   local all_tiles = tiles_mod.make_full_tile_set()
   local wall_result = wall_mod.make_wall(all_tiles, rng)
   local w = wall_result.wall
   local cur_rng = wall_result.rng

   local players: {PlayerState} = {}
   for i = 1, PLAYER_COUNT do
      local count = 13
      if i == 1 then count = 13 + dealer_extra end
      local hand_tiles: {Tile} = {}
      for _ = 1, count do
         local dr = wall_mod.draw_front(w)
         hand_tiles[#hand_tiles + 1] = dr.tile
         w = dr.wall
      end
      players[i] = {
         hand                = { concealed_tiles = hand_tiles, sets = {}, discards = {} },
         opening_trim        = {},
         seat_wind           = SEAT_WINDS[i],
         is_human            = (i == 1),
         known_wall_tile_ids = {},
      }
   end

   return {
      players                  = players,
      wall                     = w,
      phase                    = "awaiting_draw" as DealPhase,
      current_player           = 1,
      dealer                   = 1,
      round_wind               = "east" as Wind,
      pending_discard          = empty_pending_discard(),
      has_pending_discard      = false,
      pending_added_kong       = empty_pending_kong(),
      has_pending_kong         = false,
      rng                      = cur_rng,
      deal_result              = empty_deal_result(),
      has_deal_result          = false,
      reaction_passes          = {},
      pending_claims           = {},
      last_draw_was_supplement = false,
      last_drawn_tile_id       = "" as TileId,
      has_last_drawn           = false,
      effect_states            = {},
   }
end

-- Creates a new DealState with 136 tiles shuffled and 13 dealt to each player.
-- No active effects. Phase = awaiting_draw. Use this for boon-free smoke
-- tests. Production code should prefer new_deal_with_run.
function M.new_deal(rng: RngState): DealState
   return build_initial_deal(rng, 0)
end

-- Creates a new DealState seeded with active effects from the run. Applies
-- opening modifiers (Momentum dealer extras), seeds DealState.effect_states,
-- fires opening_deal_complete hooks (Third Eye reveals), and leaves the deal
-- in the opening_actions phase awaiting confirm_opening or use_effect_action.
function M.new_deal_with_run(rng: RngState, run_state: RunState): DealState
   local opening = fx_runner.collect_opening_modifiers(run_state.active_effects, run_state.round_index)
   local d = build_initial_deal(rng, opening.extra_opening_tiles)

   d.phase = "opening_actions" as DealPhase
   for _, a in ipairs(run_state.active_effects) do
      d.effect_states[a.active_effect_id] = copy_active_effect(a)
   end

   local cmds = fx_runner.dispatch_opening_deal_complete(d, run_state.round_index)
   fx_runner.apply_commands(d, cmds)
   return d
end

-- ── Action builders (typed boundary) ──────────────────────────────────────
--
-- Builders return DealAction so the apply_action signature stays typed without
-- exposing concrete action records to callers. The dispatcher casts back to the
-- concrete record at runtime; the kind tag carries the discriminant.

function M.draw(player_index: integer): DealAction
   local a: DrawAction = { kind = "draw", player_index = player_index }
   return a as DealAction
end

function M.discard(player_index: integer, tile_id: TileId): DealAction
   local a: DiscardAction = { kind = "discard", player_index = player_index, tile_id = tile_id }
   return a as DealAction
end

function M.declare_hu(player_index: integer, incoming_tile_id: TileId, is_zi_mo: boolean): DealAction
   local a: DeclareHuAction = {
      kind             = "declare_hu",
      player_index     = player_index,
      incoming_tile_id = incoming_tile_id,
      is_zi_mo         = is_zi_mo,
   }
   return a as DealAction
end

function M.declare_chi(player_index: integer, tile_id: TileId, other_tile_ids: {TileId}): DealAction
   local a: DeclareChiAction = {
      kind           = "declare_chi",
      player_index   = player_index,
      tile_id        = tile_id,
      other_tile_ids = other_tile_ids,
   }
   return a as DealAction
end

function M.declare_peng(player_index: integer, tile_id: TileId): DealAction
   local a: DeclarePengAction = { kind = "declare_peng", player_index = player_index, tile_id = tile_id }
   return a as DealAction
end

function M.declare_open_kong(player_index: integer, tile_id: TileId): DealAction
   local a: DeclareOpenKongAction = { kind = "declare_open_kong", player_index = player_index, tile_id = tile_id }
   return a as DealAction
end

function M.declare_concealed_kong(player_index: integer, tile_kind_id: TileKindId): DealAction
   local a: DeclareConcealedKongAction = {
      kind         = "declare_concealed_kong",
      player_index = player_index,
      tile_kind_id = tile_kind_id,
   }
   return a as DealAction
end

function M.declare_added_kong(player_index: integer, tile_id: TileId): DealAction
   local a: DeclareAddedKongAction = { kind = "declare_added_kong", player_index = player_index, tile_id = tile_id }
   return a as DealAction
end

function M.pass_reaction(player_index: integer): DealAction
   local a: PassReactionAction = { kind = "pass_reaction", player_index = player_index }
   return a as DealAction
end

function M.confirm_opening(player_index: integer): DealAction
   local a: ConfirmOpeningAction = { kind = "confirm_opening", player_index = player_index }
   return a as DealAction
end

function M.discard_opening_surplus(player_index: integer, tile_id: TileId): DealAction
   local a: DiscardOpeningSurplusAction = {
      kind         = "discard_opening_surplus",
      player_index = player_index,
      tile_id      = tile_id,
   }
   return a as DealAction
end

function M.use_effect_action(player_index: integer, active_effect_id: string, tile_ids: {TileId}): DealAction
   local copied: {TileId} = {}
   for _, id in ipairs(tile_ids) do copied[#copied + 1] = id end
   local a: UseEffectAction = {
      kind             = "use_effect_action",
      player_index     = player_index,
      active_effect_id = active_effect_id,
      tile_ids         = copied,
   }
   return a as DealAction
end

-- ── Draw ──────────────────────────────────────────────────────────────────

local function handle_draw(deal: DealState, action: DrawAction): DealTransition
   if (deal.phase as string) ~= "awaiting_draw" then
      return err(deal, "draw requires awaiting_draw phase, got: " .. (deal.phase as string))
   end
   if action.player_index ~= deal.current_player then
      return err(deal, "draw: wrong player " .. tostring(action.player_index) .. ", expected " .. tostring(deal.current_player))
   end
   if wall_mod.remaining(deal.wall) == 0 then
      local d = copy_deal(deal)
      return wall_exhaustion(d)
   end

   local dr = wall_mod.draw_front(deal.wall)
   local d = copy_deal(deal)
   d.wall = dr.wall
   d.players[action.player_index].hand.concealed_tiles[
      #d.players[action.player_index].hand.concealed_tiles + 1
   ] = dr.tile
   d.players[action.player_index].known_wall_tile_ids =
      remove_known(d.players[action.player_index].known_wall_tile_ids, dr.tile.tile_id)
   d.last_draw_was_supplement = false
   d.last_drawn_tile_id       = dr.tile.tile_id
   d.has_last_drawn           = true
   d.phase                    = "awaiting_action" as DealPhase

   local cmds = fx_runner.dispatch_after_draw(d, action.player_index, dr.tile, false)
   local fx_events = fx_runner.apply_commands(d, cmds)
   local events: {DealEvent} = { ev("draw", "player " .. tostring(action.player_index) .. " draws " .. (dr.tile.tile_id as string)) }
   for _, e in ipairs(fx_events) do events[#events + 1] = e end
   return ok_t(d, events)
end

-- ── Discard ───────────────────────────────────────────────────────────────

local function handle_discard(deal: DealState, action: DiscardAction): DealTransition
   if (deal.phase as string) ~= "awaiting_action" then
      return err(deal, "discard requires awaiting_action phase")
   end
   if action.player_index ~= deal.current_player then
      return err(deal, "discard: wrong player")
   end

   local tile_obj, found = find_tile(deal.players[action.player_index].hand.concealed_tiles, action.tile_id)
   if not found then
      return err(deal, "discard: tile not in hand: " .. (action.tile_id as string))
   end

   local d = copy_deal(deal)
   local new_c, _ = remove_tile(d.players[action.player_index].hand.concealed_tiles, action.tile_id)
   d.players[action.player_index].hand.concealed_tiles = new_c
   d.pending_discard          = { tile = tile_obj, discarder = action.player_index }
   d.has_pending_discard      = true
   d.reaction_passes          = {}
   d.pending_claims           = {}
   d.last_draw_was_supplement = false
   d.phase                    = "reaction_window" as DealPhase

   return ok_t(d, { ev("discard", "player " .. tostring(action.player_index) .. " discards " .. (action.tile_id as string)) })
end

-- ── Apply a winning claim (called by resolve_window) ───────────────────────

-- Apply a hu-on-discard win after priority resolution.
local function apply_hu_on_discard(d: DealState, winner_index: integer): DealTransition
   local validator = require("game.hand_validator")
   local p        = d.players[winner_index]
   local incoming = d.pending_discard.tile
   local discarder = d.pending_discard.discarder
   local ctx      = build_score_ctx(d, winner_index, false, false, false)
   local shapes   = validator.find_win_shapes(p.hand.concealed_tiles, incoming, p.hand.sets)
   local output   = scorer_mod.score_hand(shapes, ctx)
   if not output.has_best then
      return err(d, "resolve: hu on discard no longer valid")
   end
   local final = apply_score_modifiers(d, ctx, shapes, output, winner_index)
   if not score_passes_threshold(final) then
      return err(d, "resolve: hu on discard no longer valid after modifiers")
   end
   -- Move the discarded tile into the discarder's discards so it stays
   -- accounted for after we clear pending_discard (the invariant only
   -- counts pending_discard when has_pending_discard is true).
   d.players[discarder].hand.discards[#d.players[discarder].hand.discards + 1] = incoming
   d.phase = "deal_over" as DealPhase
   d.deal_result = {
      winner_player_index = winner_index,
      won_by_zi_mo        = false,
      score_result        = final,
      has_score_result    = true,
   }
   d.has_deal_result     = true
   d.has_pending_discard = false
   d.pending_claims      = {}
   d.reaction_passes     = {}
   return ok_t(d, { ev("hu", "player " .. tostring(winner_index) .. " wins on discard (" .. (final.rating as string) .. ")") })
end

-- Apply a qiang-gang win after priority resolution.
local function apply_qiang_gang(d: DealState, winner_index: integer): DealTransition
   local validator = require("game.hand_validator")
   local p         = d.players[winner_index]
   local kong_tile = d.pending_added_kong.tile
   local ctx       = build_score_ctx(d, winner_index, false, false, true)
   local shapes    = validator.find_win_shapes(p.hand.concealed_tiles, kong_tile, p.hand.sets)
   local output   = scorer_mod.score_hand(shapes, ctx)
   if not output.has_best then
      return err(d, "resolve: qiang gang no longer valid")
   end
   local final = apply_score_modifiers(d, ctx, shapes, output, winner_index)
   if not score_passes_threshold(final) then
      return err(d, "resolve: qiang gang no longer valid after modifiers")
   end
   d.phase = "deal_over" as DealPhase
   d.deal_result = {
      winner_player_index = winner_index,
      won_by_zi_mo        = false,
      score_result        = final,
      has_score_result    = true,
   }
   d.has_deal_result   = true
   d.has_pending_kong  = false
   d.pending_claims    = {}
   d.reaction_passes   = {}
   return ok_t(d, { ev("qiang_gang", "player " .. tostring(winner_index) .. " wins by qiang gang") })
end

-- Apply a Peng claim after priority resolution.
local function apply_peng(d: DealState, winner_index: integer): DealTransition
   local discard_tile = d.pending_discard.tile
   local discarder    = d.pending_discard.discarder
   local h            = d.players[winner_index].hand
   local new_c, removed = remove_by_kind(h.concealed_tiles, discard_tile.kind_id, 2)
   h.concealed_tiles = new_c
   h.sets[#h.sets + 1] = {
      kind        = "peng" as TileSetKind,
      visibility  = "open" as SetVisibility,
      tiles       = {removed[1], removed[2], discard_tile},
      called_from = discarder,
   }
   d.pending_discard          = empty_pending_discard()
   d.has_pending_discard      = false
   d.pending_claims           = {}
   d.reaction_passes          = {}
   d.current_player           = winner_index
   d.phase                    = "awaiting_action" as DealPhase
   d.last_draw_was_supplement = false
   d.has_last_drawn           = false
   local cmds = fx_runner.dispatch_after_peng(d, winner_index)
   local fx_events = fx_runner.apply_commands(d, cmds)
   local events: {DealEvent} = { ev("peng", "player " .. tostring(winner_index) .. " claims peng of " .. (discard_tile.kind_id as string)) }
   for _, e in ipairs(fx_events) do events[#events + 1] = e end
   return ok_t(d, events)
end

-- Apply an Open Kong claim after priority resolution.
local function apply_open_kong(d: DealState, winner_index: integer): DealTransition
   if wall_mod.remaining(d.wall) == 0 then
      return wall_exhaustion(d)
   end

   local discard_tile = d.pending_discard.tile
   local discarder    = d.pending_discard.discarder
   local h            = d.players[winner_index].hand
   local new_c, removed = remove_by_kind(h.concealed_tiles, discard_tile.kind_id, 3)
   h.concealed_tiles = new_c
   h.sets[#h.sets + 1] = {
      kind        = "kong" as TileSetKind,
      visibility  = "open" as SetVisibility,
      tiles       = {removed[1], removed[2], removed[3], discard_tile},
      called_from = discarder,
   }
   d.pending_discard     = empty_pending_discard()
   d.has_pending_discard = false
   d.pending_claims      = {}
   d.reaction_passes     = {}

   local d2, was_empty = draw_supplement(d, winner_index)
   if was_empty then return wall_exhaustion(d2) end
   d2.current_player = winner_index
   d2.phase          = "awaiting_action" as DealPhase
   return ok_t(d2, { ev("open_kong", "player " .. tostring(winner_index) .. " claims open kong of " .. (discard_tile.kind_id as string)) })
end

-- Apply a Chi claim after priority resolution.
local function apply_chi(d: DealState, claim: PendingClaim): DealTransition
   local discard_tile = d.pending_discard.tile
   local discarder    = d.pending_discard.discarder
   local h            = d.players[claim.player_index].hand
   local ot1, ok1 = find_tile(h.concealed_tiles, claim.chi_other_tile_ids[1])
   local ot2, ok2 = find_tile(h.concealed_tiles, claim.chi_other_tile_ids[2])
   if not ok1 or not ok2 then return err(d, "resolve: chi tiles lost") end
   local c1, _ = remove_tile(h.concealed_tiles, claim.chi_other_tile_ids[1])
   local c2, _ = remove_tile(c1, claim.chi_other_tile_ids[2])
   h.concealed_tiles = c2
   h.sets[#h.sets + 1] = {
      kind        = "chi" as TileSetKind,
      visibility  = "open" as SetVisibility,
      tiles       = {discard_tile, ot1, ot2},
      called_from = discarder,
   }
   d.pending_discard          = empty_pending_discard()
   d.has_pending_discard      = false
   d.pending_claims           = {}
   d.reaction_passes          = {}
   d.current_player           = claim.player_index
   d.phase                    = "awaiting_action" as DealPhase
   d.last_draw_was_supplement = false
   d.has_last_drawn           = false
   return ok_t(d, { ev("chi", "player " .. tostring(claim.player_index) .. " claims chi") })
end

-- ── All-pass resolution ────────────────────────────────────────────────────

-- Called when the reaction window closes with no claims.
local function apply_all_pass(d: DealState): DealTransition
   if d.has_pending_discard then
      local discarder = d.pending_discard.discarder
      d.players[discarder].hand.discards[#d.players[discarder].hand.discards + 1] = d.pending_discard.tile
      d.pending_discard     = empty_pending_discard()
      d.has_pending_discard = false
      d.pending_claims      = {}
      d.reaction_passes     = {}
      d.current_player      = (discarder % PLAYER_COUNT) + 1
      d.phase               = "awaiting_draw" as DealPhase
      d.has_last_drawn      = false
      return ok_t(d, { ev("pass_all", "all passed — discard resolved, player " .. tostring(d.current_player) .. " to draw") })
   end

   if d.has_pending_kong then
      if wall_mod.remaining(d.wall) == 0 then
         return wall_exhaustion(d)
      end

      local declarer = d.pending_added_kong.declarer
      local tile_id  = d.pending_added_kong.tile_id
      local fourth, ft_ok = find_tile(d.players[declarer].hand.concealed_tiles, tile_id)
      if not ft_ok then return err(d, "all_pass kong: fourth tile not found") end
      local new_c, _ = remove_tile(d.players[declarer].hand.concealed_tiles, tile_id)
      d.players[declarer].hand.concealed_tiles = new_c
      local upgraded = false
      for i = 1, #d.players[declarer].hand.sets do
         local s = d.players[declarer].hand.sets[i]
         if (s.kind as string) == "peng" and (s.visibility as string) == "open"
            and #s.tiles > 0 and s.tiles[1].kind_id == fourth.kind_id
         then
            d.players[declarer].hand.sets[i].kind = "kong" as TileSetKind
            d.players[declarer].hand.sets[i].tiles[#d.players[declarer].hand.sets[i].tiles + 1] = fourth
            upgraded = true
            break
         end
      end
      if not upgraded then return err(d, "all_pass kong: matching peng not found") end
      d.pending_added_kong = empty_pending_kong()
      d.has_pending_kong   = false
      d.pending_claims     = {}
      d.reaction_passes    = {}
      local d2, was_empty = draw_supplement(d, declarer)
      if was_empty then return wall_exhaustion(d2) end
      d2.current_player = declarer
      d2.phase          = "awaiting_action" as DealPhase
      return ok_t(d2, { ev("kong_resolved", "added kong resolved — player " .. tostring(declarer) .. " draws supplement") })
   end

   return err(d, "all_pass: no pending discard or kong")
end

-- ── Resolve reaction window ────────────────────────────────────────────────

-- Picks the highest-priority claim. Human Hu beats AI Hu per Milestone 1 prompt
-- priority; other ties are broken by nearest-next from the actor.
local function pick_winning_claim(claims: {PendingClaim}, actor: integer, players: {PlayerState}): PendingClaim
   local best = claims[1]
   local best_p = CLAIM_PRIORITY[best.kind] or 0
   local best_d = turn_distance(actor, best.player_index)
   local best_human_hu = best.kind == "hu" and players[best.player_index].is_human
   for i = 2, #claims do
      local c = claims[i]
      local p = CLAIM_PRIORITY[c.kind] or 0
      local d = turn_distance(actor, c.player_index)
      local c_human_hu = c.kind == "hu" and players[c.player_index].is_human
      if p > best_p
         or (p == best_p and c_human_hu and not best_human_hu)
         or (p == best_p and c_human_hu == best_human_hu and d < best_d)
      then
         best = c
         best_p = p
         best_d = d
         best_human_hu = c_human_hu
      end
   end
   return best
end

local function resolve_window(d: DealState): DealTransition
   if #d.pending_claims == 0 then
      return apply_all_pass(d)
   end

   local actor = reaction_actor(d)
   if actor == -1 then return err(d, "resolve: no reaction actor") end
   local winner = pick_winning_claim(d.pending_claims, actor, d.players)

   if winner.kind == "hu" then
      if d.has_pending_kong then
         return apply_qiang_gang(d, winner.player_index)
      end
      return apply_hu_on_discard(d, winner.player_index)
   elseif winner.kind == "peng" then
      return apply_peng(d, winner.player_index)
   elseif winner.kind == "open_kong" then
      return apply_open_kong(d, winner.player_index)
   elseif winner.kind == "chi" then
      return apply_chi(d, winner)
   end
   return err(d, "resolve: unknown claim kind " .. winner.kind)
end

-- Re-checks closure and dispatches to resolve_window if all reactors have responded.
local function maybe_resolve(d: DealState, queued_event: DealEvent): DealTransition
   if all_reactors_responded(d) then
      local tr = resolve_window(d)
      if tr.ok then
         local events: {DealEvent} = { queued_event }
         for _, e in ipairs(tr.events) do events[#events + 1] = e end
         return { ok = true, deal = tr.deal, events = events, error = "" }
      end
      return tr
   end
   return ok_t(d, { queued_event })
end

-- ── Hu (queue or zi mo) ────────────────────────────────────────────────────

local function handle_hu(deal: DealState, action: DeclareHuAction): DealTransition
   local validator = require("game.hand_validator")

   -- Zi Mo (self-draw, awaiting_action) resolves immediately — no reaction window.
   if action.is_zi_mo then
      if (deal.phase as string) ~= "awaiting_action" then
         return err(deal, "zi mo requires awaiting_action phase")
      end
      if action.player_index ~= deal.current_player then
         return err(deal, "zi mo: wrong player")
      end
      if not deal.has_last_drawn then
         return err(deal, "zi mo: no drawn tile available")
      end
      local p = deal.players[action.player_index]
      local incoming, tile_ok = find_tile(p.hand.concealed_tiles, deal.last_drawn_tile_id)
      if not tile_ok then return err(deal, "zi mo: last drawn tile not in hand") end
      local rest, _ = remove_tile(p.hand.concealed_tiles, deal.last_drawn_tile_id)
      local shapes  = validator.find_win_shapes(rest, incoming, p.hand.sets)
      local ctx     = build_score_ctx(deal, action.player_index, true, deal.last_draw_was_supplement, false)
      local output  = scorer_mod.score_hand(shapes, ctx)
      if not output.has_best then
         return err(deal, "zi mo: not a valid hu")
      end
      local d = copy_deal(deal)
      local final = apply_score_modifiers(d, ctx, shapes, output, action.player_index)
      if not score_passes_threshold(final) then
         return err(deal, "zi mo: not a valid hu after modifiers")
      end
      d.phase = "deal_over" as DealPhase
      d.deal_result = {
         winner_player_index = action.player_index,
         won_by_zi_mo        = true,
         score_result        = final,
         has_score_result    = true,
      }
      d.has_deal_result = true
      return ok_t(d, { ev("hu", "player " .. tostring(action.player_index) .. " wins by zi mo (" .. (final.rating as string) .. ")") })
   end

   -- Hu on discard or qiang gang: queue claim, defer resolution to window close.
   if (deal.phase as string) ~= "reaction_window" then
      return err(deal, "declare_hu: invalid phase (" .. (deal.phase as string) .. ")")
   end
   if has_responded(deal, action.player_index) then
      return err(deal, "declare_hu: player already responded this window")
   end

   if deal.has_pending_discard then
      if action.player_index == deal.pending_discard.discarder then
         return err(deal, "hu on discard: discarder cannot win on own discard")
      end
      local p        = deal.players[action.player_index]
      local incoming = deal.pending_discard.tile
      local ctx      = build_score_ctx(deal, action.player_index, false, false, false)
      local shapes   = require("game.hand_validator").find_win_shapes(p.hand.concealed_tiles, incoming, p.hand.sets)
      local output   = scorer_mod.score_hand(shapes, ctx)
      local final    = apply_score_modifiers(deal, ctx, shapes, output, action.player_index)
      if not output.has_best or not score_passes_threshold(final) then
         return err(deal, "hu on discard: not a valid hu")
      end
   elseif deal.has_pending_kong then
      if action.player_index == deal.pending_added_kong.declarer then
         return err(deal, "qiang gang: cannot rob own kong")
      end
      local p        = deal.players[action.player_index]
      local kong_tile = deal.pending_added_kong.tile
      local ctx    = build_score_ctx(deal, action.player_index, false, false, true)
      local shapes = require("game.hand_validator").find_win_shapes(p.hand.concealed_tiles, kong_tile, p.hand.sets)
      local output = scorer_mod.score_hand(shapes, ctx)
      local final  = apply_score_modifiers(deal, ctx, shapes, output, action.player_index)
      if not output.has_best or not score_passes_threshold(final) then
         return err(deal, "qiang gang: not a valid hu")
      end
   else
      return err(deal, "declare_hu: no pending discard or kong")
   end

   local d = copy_deal(deal)
   d.pending_claims[#d.pending_claims + 1] = {
      player_index       = action.player_index,
      kind               = "hu",
      chi_other_tile_ids = {},
   }
   return maybe_resolve(d, ev("hu_queued", "player " .. tostring(action.player_index) .. " queues hu claim"))
end

-- ── Pass reaction ──────────────────────────────────────────────────────────

local function handle_pass_reaction(deal: DealState, action: PassReactionAction): DealTransition
   if (deal.phase as string) ~= "reaction_window" then
      return err(deal, "pass_reaction requires reaction_window phase")
   end
   if has_responded(deal, action.player_index) then
      return err(deal, "pass_reaction: player already responded this window")
   end
   if deal.has_pending_discard and action.player_index == deal.pending_discard.discarder then
      return err(deal, "pass_reaction: discarder cannot pass own reaction window")
   end
   if deal.has_pending_kong and action.player_index == deal.pending_added_kong.declarer then
      return err(deal, "pass_reaction: kong declarer cannot pass own reaction window")
   end

   local d = copy_deal(deal)
   d.reaction_passes[#d.reaction_passes + 1] = action.player_index
   return maybe_resolve(d, ev("pass", "player " .. tostring(action.player_index) .. " passes"))
end

-- ── Chi ───────────────────────────────────────────────────────────────────

local function handle_chi(deal: DealState, action: DeclareChiAction): DealTransition
   if (deal.phase as string) ~= "reaction_window" or not deal.has_pending_discard then
      return err(deal, "declare_chi requires reaction_window with pending discard")
   end
   if has_responded(deal, action.player_index) then
      return err(deal, "declare_chi: player already responded this window")
   end
   if #action.other_tile_ids ~= 2 then
      return err(deal, "declare_chi: need exactly 2 other tile ids")
   end

   local discard_tile = deal.pending_discard.tile
   local discarder    = deal.pending_discard.discarder
   local hand_tiles   = deal.players[action.player_index].hand.concealed_tiles

   local ot1, ok1 = find_tile(hand_tiles, action.other_tile_ids[1])
   if not ok1 then return err(deal, "declare_chi: tile not in hand: " .. (action.other_tile_ids[1] as string)) end
   local ot2, ok2 = find_tile(hand_tiles, action.other_tile_ids[2])
   if not ok2 then return err(deal, "declare_chi: tile not in hand: " .. (action.other_tile_ids[2] as string)) end

   if not calls_mod.can_chi(discard_tile, {ot1, ot2}, discarder, action.player_index, PLAYER_COUNT) then
      return err(deal, "declare_chi: illegal chi")
   end

   local d = copy_deal(deal)
   d.pending_claims[#d.pending_claims + 1] = {
      player_index       = action.player_index,
      kind               = "chi",
      chi_other_tile_ids = { action.other_tile_ids[1], action.other_tile_ids[2] },
   }
   return maybe_resolve(d, ev("chi_queued", "player " .. tostring(action.player_index) .. " queues chi claim"))
end

-- ── Peng ──────────────────────────────────────────────────────────────────

local function handle_peng(deal: DealState, action: DeclarePengAction): DealTransition
   if (deal.phase as string) ~= "reaction_window" or not deal.has_pending_discard then
      return err(deal, "declare_peng requires reaction_window with pending discard")
   end
   if has_responded(deal, action.player_index) then
      return err(deal, "declare_peng: player already responded this window")
   end

   local discard_tile = deal.pending_discard.tile
   local discarder    = deal.pending_discard.discarder
   local hand_tiles   = deal.players[action.player_index].hand.concealed_tiles

   if (action.tile_id as string) ~= (discard_tile.tile_id as string) then
      return err(deal, "declare_peng: tile_id does not match pending discard")
   end
   if not calls_mod.can_peng(discard_tile, hand_tiles, discarder, action.player_index) then
      return err(deal, "declare_peng: illegal peng")
   end

   local d = copy_deal(deal)
   d.pending_claims[#d.pending_claims + 1] = {
      player_index       = action.player_index,
      kind               = "peng",
      chi_other_tile_ids = {},
   }
   return maybe_resolve(d, ev("peng_queued", "player " .. tostring(action.player_index) .. " queues peng claim"))
end

-- ── Open Kong (from discard) ───────────────────────────────────────────────

local function handle_open_kong(deal: DealState, action: DeclareOpenKongAction): DealTransition
   if (deal.phase as string) ~= "reaction_window" or not deal.has_pending_discard then
      return err(deal, "declare_open_kong requires reaction_window with pending discard")
   end
   if has_responded(deal, action.player_index) then
      return err(deal, "declare_open_kong: player already responded this window")
   end

   local discard_tile = deal.pending_discard.tile
   local discarder    = deal.pending_discard.discarder
   local hand_tiles   = deal.players[action.player_index].hand.concealed_tiles

   if (action.tile_id as string) ~= (discard_tile.tile_id as string) then
      return err(deal, "declare_open_kong: tile_id does not match pending discard")
   end
   if not calls_mod.can_open_kong(discard_tile, hand_tiles, discarder, action.player_index) then
      return err(deal, "declare_open_kong: illegal open kong")
   end

   local d = copy_deal(deal)
   d.pending_claims[#d.pending_claims + 1] = {
      player_index       = action.player_index,
      kind               = "open_kong",
      chi_other_tile_ids = {},
   }
   return maybe_resolve(d, ev("open_kong_queued", "player " .. tostring(action.player_index) .. " queues open kong claim"))
end

-- ── Concealed Kong ────────────────────────────────────────────────────────

local function handle_concealed_kong(deal: DealState, action: DeclareConcealedKongAction): DealTransition
   if (deal.phase as string) ~= "awaiting_action" then
      return err(deal, "declare_concealed_kong requires awaiting_action phase")
   end
   if action.player_index ~= deal.current_player then
      return err(deal, "declare_concealed_kong: wrong player")
   end
   local hand_tiles = deal.players[action.player_index].hand.concealed_tiles
   if not calls_mod.can_concealed_kong(action.tile_kind_id, hand_tiles) then
      return err(deal, "declare_concealed_kong: need 4 matching tiles in hand")
   end

   local d = copy_deal(deal)
   if wall_mod.remaining(d.wall) == 0 then
      return wall_exhaustion(d)
   end

   local h = d.players[action.player_index].hand
   local new_c, removed = remove_by_kind(h.concealed_tiles, action.tile_kind_id, 4)
   h.concealed_tiles = new_c
   h.sets[#h.sets + 1] = {
      kind        = "kong" as TileSetKind,
      visibility  = "concealed" as SetVisibility,
      tiles       = {removed[1], removed[2], removed[3], removed[4]},
      called_from = -1,
   }

   local d2, was_empty = draw_supplement(d, action.player_index)
   if was_empty then return wall_exhaustion(d2) end
   d2.phase = "awaiting_action" as DealPhase

   return ok_t(d2, { ev("concealed_kong", "player " .. tostring(action.player_index) .. " declares concealed kong of " .. (action.tile_kind_id as string)) })
end

-- ── Added Kong ────────────────────────────────────────────────────────────

local function handle_added_kong(deal: DealState, action: DeclareAddedKongAction): DealTransition
   if (deal.phase as string) ~= "awaiting_action" then
      return err(deal, "declare_added_kong requires awaiting_action phase")
   end
   if action.player_index ~= deal.current_player then
      return err(deal, "declare_added_kong: wrong player")
   end
   local hand_tiles = deal.players[action.player_index].hand.concealed_tiles
   local open_sets  = deal.players[action.player_index].hand.sets
   local tile_obj, tile_ok = find_tile(hand_tiles, action.tile_id)
   if not tile_ok then
      return err(deal, "declare_added_kong: tile not in hand: " .. (action.tile_id as string))
   end
   if not calls_mod.can_added_kong(tile_obj, hand_tiles, open_sets) then
      return err(deal, "declare_added_kong: need matching open peng")
   end

   -- The fourth tile stays in concealed tiles until the Qiang Gang window resolves.
   local d = copy_deal(deal)
   d.pending_added_kong = { tile_id = action.tile_id, tile = tile_obj, declarer = action.player_index }
   d.has_pending_kong   = true
   d.reaction_passes    = {}
   d.pending_claims     = {}
   d.phase              = "reaction_window" as DealPhase

   return ok_t(d, { ev("added_kong", "player " .. tostring(action.player_index) .. " declares added kong — qiang gang window open") })
end

-- ── Opening phase actions ─────────────────────────────────────────────────

local function handle_confirm_opening(deal: DealState, action: ConfirmOpeningAction): DealTransition
   if (deal.phase as string) ~= "opening_actions" then
      return err(deal, "confirm_opening requires opening_actions phase")
   end
   if action.player_index ~= deal.dealer then
      return err(deal, "confirm_opening: only dealer may confirm")
   end
   local n = #deal.players[action.player_index].hand.concealed_tiles
   if n ~= 13 then
      return err(deal, "confirm_opening: dealer must hold exactly 13 tiles, has " .. tostring(n))
   end
   local d = copy_deal(deal)
   d.phase          = "awaiting_draw" as DealPhase
   d.current_player = deal.dealer
   return ok_t(d, { ev("opening_confirmed", "opening confirmed — dealer to draw") })
end

local function handle_discard_opening_surplus(deal: DealState, action: DiscardOpeningSurplusAction): DealTransition
   if (deal.phase as string) ~= "opening_actions" then
      return err(deal, "discard_opening_surplus requires opening_actions phase")
   end
   if action.player_index ~= deal.dealer then
      return err(deal, "discard_opening_surplus: only dealer trims surplus")
   end
   local n = #deal.players[action.player_index].hand.concealed_tiles
   if n <= 13 then
      return err(deal, "discard_opening_surplus: no surplus to trim (have " .. tostring(n) .. ")")
   end
   local tile_obj, found = find_tile(deal.players[action.player_index].hand.concealed_tiles, action.tile_id)
   if not found then
      return err(deal, "discard_opening_surplus: tile not in hand: " .. (action.tile_id as string))
   end
   local d = copy_deal(deal)
   local new_c, _ = remove_tile(d.players[action.player_index].hand.concealed_tiles, action.tile_id)
   d.players[action.player_index].hand.concealed_tiles = new_c
   d.players[action.player_index].opening_trim[
      #d.players[action.player_index].opening_trim + 1
   ] = tile_obj
   return ok_t(d, { ev("opening_trim", "player " .. tostring(action.player_index) .. " trims " .. (action.tile_id as string)) })
end

local function handle_use_effect_action(deal: DealState, action: UseEffectAction): DealTransition
   local active = deal.effect_states[action.active_effect_id]
   if active == nil then
      return err(deal, "use_effect_action: unknown active_effect_id: " .. action.active_effect_id)
   end
   if active.has_owner and active.owner_player_index ~= action.player_index then
      return err(deal, "use_effect_action: not the owner")
   end
   local registry = require("effects.effect_registry")
   local mod = registry.get(active.effect_id)
   if mod == nil or mod.on_use_action == nil then
      return err(deal, "use_effect_action: effect has no on_use_action handler: " .. active.effect_id)
   end
   local available = false
   local actions = fx_runner.collect_available_actions(deal, action.player_index)
   for _, effect_action in ipairs(actions) do
      if effect_action.active_effect_id == action.active_effect_id then
         available = true
         break
      end
   end
   if not available then
      return err(deal, "use_effect_action: effect action is not available: " .. active.effect_id)
   end
   local d = copy_deal(deal)
   local uctx: EffectUseContext = {
      active       = d.effect_states[action.active_effect_id],
      player_index = action.player_index,
      tile_ids     = action.tile_ids,
   }
   local cmds = mod.on_use_action(uctx, d)
   local fx_events = fx_runner.apply_commands(d, cmds)
   local events: {DealEvent} = { ev("use_effect", "player " .. tostring(action.player_index) .. " uses " .. active.effect_id) }
   for _, e in ipairs(fx_events) do events[#events + 1] = e end
   return ok_t(d, events)
end

-- ── Main dispatch ──────────────────────────────────────────────────────────

function M.apply_action(deal: DealState, action: DealAction): DealTransition
   if deal.has_deal_result then
      return err(deal, "apply_action: deal is already over")
   end

   local kind = action.kind

   if kind == "draw" then
      return handle_draw(deal, action as DrawAction)
   elseif kind == "discard" then
      return handle_discard(deal, action as DiscardAction)
   elseif kind == "declare_hu" then
      return handle_hu(deal, action as DeclareHuAction)
   elseif kind == "pass_reaction" then
      return handle_pass_reaction(deal, action as PassReactionAction)
   elseif kind == "declare_chi" then
      return handle_chi(deal, action as DeclareChiAction)
   elseif kind == "declare_peng" then
      return handle_peng(deal, action as DeclarePengAction)
   elseif kind == "declare_open_kong" then
      return handle_open_kong(deal, action as DeclareOpenKongAction)
   elseif kind == "declare_concealed_kong" then
      return handle_concealed_kong(deal, action as DeclareConcealedKongAction)
   elseif kind == "declare_added_kong" then
      return handle_added_kong(deal, action as DeclareAddedKongAction)
   elseif kind == "confirm_opening" then
      return handle_confirm_opening(deal, action as ConfirmOpeningAction)
   elseif kind == "discard_opening_surplus" then
      return handle_discard_opening_surplus(deal, action as DiscardOpeningSurplusAction)
   elseif kind == "use_effect_action" then
      return handle_use_effect_action(deal, action as UseEffectAction)
   else
      return err(deal, "apply_action: unknown action kind: " .. kind)
   end
end

return M
