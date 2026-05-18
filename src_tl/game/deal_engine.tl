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
require("effects.boon_types")
local wall_mod          = require("game.wall")
local tiles_mod         = require("game.tiles")
local calls_mod         = require("game.calls")
local scorer_mod        = require("game.scorer")
local fx_runner         = require("effects.effect_runner")
local scoring           = require("game.scoring")
local boon_registry     = require("effects.boon_registry")
local boon_offer        = require("effects.boon_offer")
local milestones        = require("game.milestone_detection")
local ting_distance_mod = require("game.ting_distance")

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

local function copy_kind_ids(ids: {TileKindId}): {TileKindId}
   local out: {TileKindId} = {}
   for _, id in ipairs(ids) do out[#out + 1] = id end
   return out
end

local function copy_player(p: PlayerState): PlayerState
   return {
      hand                       = copy_hand(p.hand),
      opening_trim               = copy_tiles(p.opening_trim),
      seat_wind                  = p.seat_wind,
      is_human                   = p.is_human,
      known_wall_tile_ids        = copy_tile_ids(p.known_wall_tile_ids),
      concealed_pung_kinds_seen  = copy_kind_ids(p.concealed_pung_kinds_seen),
      turn_extra_discards_owed   = p.turn_extra_discards_owed,
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

local function copy_string_int_map(m: {string: integer}): {string: integer}
   local out: {string: integer} = {}
   for k, v in pairs(m) do out[k] = v end
   return out
end

local function copy_string_bool_map(m: {string: boolean}): {string: boolean}
   local out: {string: boolean} = {}
   for k, v in pairs(m) do out[k] = v end
   return out
end

local function copy_active_boon(b: ActiveBoon): ActiveBoon
   return {
      boon_id     = b.boon_id,
      acquired_at = b.acquired_at,
      counters    = copy_string_int_map(b.counters),
      flags       = copy_string_bool_map(b.flags),
      tokens      = copy_string_int_map(b.tokens),
   }
end

local function copy_active_boons(list: {ActiveBoon}): {ActiveBoon}
   local out: {ActiveBoon} = {}
   for _, b in ipairs(list) do out[#out + 1] = copy_active_boon(b) end
   return out
end

local function copy_string_list(list: {string}): {string}
   local out: {string} = {}
   for _, s in ipairs(list) do out[#out + 1] = s end
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
      active_boons             = copy_active_boons(d.active_boons),
      set_count_high_water     = d.set_count_high_water,
      reached_ting             = d.reached_ting,
      declined_boons_this_deal = copy_string_list(d.declined_boons_this_deal),
      pending_forks            = copy_string_list(d.pending_forks),
      pending_offer            = copy_string_list(d.pending_offer),
      pending_offer_milestone  = d.pending_offer_milestone,
   }
end

-- ── M2 event emission helpers ─────────────────────────────────────────────
--
-- Boon listeners run in place on the deal reference. Emission happens at
-- well-defined hook points inside action handlers; M1's effect runner runs
-- in parallel and is unaffected. Player is seat 1 in M1 (PLAYER_OWNER_INDEX).

local PLAYER_OWNER_INDEX <const> = 1

local function emit_event(d: DealState, event: EventData)
   if #d.active_boons == 0 then return end
   boon_registry.emit(d, d.active_boons, PLAYER_OWNER_INDEX, event)
end

local function is_honor_kind(kind_id: TileKindId): boolean
   local s = kind_id as string
   return s == "east" or s == "south" or s == "west" or s == "north"
      or  s == "fa_cai" or s == "hong_zhong" or s == "bai_ban"
end

local function is_dragon_kind(kind_id: TileKindId): boolean
   local s = kind_id as string
   return s == "fa_cai" or s == "hong_zhong" or s == "bai_ban"
end

-- Fans a base draw event out to derived tile-property events. The base
-- event has already fired; this only emits the auto-derived variants.
local function emit_player_draw_derived(d: DealState, tile: Tile)
   if is_honor_kind(tile.kind_id) then
      local ev: TilePropertyEvent = { event_name = "on_honor_drawn", tile = tile }
      emit_event(d, ev as EventData)
   end
   if is_dragon_kind(tile.kind_id) then
      local ev: TilePropertyEvent = { event_name = "on_dragon_drawn", tile = tile }
      emit_event(d, ev as EventData)
   end
end

local function emit_player_discard_derived(d: DealState, tile: Tile)
   if is_honor_kind(tile.kind_id) then
      local ev: TilePropertyEvent = { event_name = "on_honor_discarded", tile = tile }
      emit_event(d, ev as EventData)
   end
end

local function emit_opponent_discard_derived(d: DealState, opponent_index: integer, tile: Tile)
   if is_honor_kind(tile.kind_id) then
      local ev: OpponentTilePropertyEvent = {
         event_name     = "on_opponent_honor_discarded",
         opponent_index = opponent_index,
         tile           = tile,
      }
      emit_event(d, ev as EventData)
   end
end

-- ── M2-S01 milestone fork evaluation ──────────────────────────────────────
--
-- End-of-turn evaluation for the player's hand. Fires on_set_formed for each
-- newly crossed threshold (1, 2, 3) and on_ting_reached when ting is hit for
-- the first time this deal. set events fire before ting events when both
-- cross on the same turn (plan §327).
--
-- High-water tracking means thresholds don't re-fire if the player drops
-- below and climbs back (plan §326). reached_ting is one-shot per deal.

-- Materializes the next non-empty offer from pending_forks. Skips milestones
-- whose eligible pool is empty (§369 exhaustion fallback applied at the
-- queue level so the player is never stuck on a fork with nothing to pick).
-- Does nothing if pending_forks is empty or pending_offer is already
-- non-empty. Advances deal.rng (offer pool is deterministic from current
-- RNG state — see plan §282 and the deferred-determinism note in PR #18).
local function materialize_next_offer(d: DealState)
   if #d.pending_offer > 0 then return end
   while #d.pending_forks > 0 do
      local milestone = d.pending_forks[1]
      table.remove(d.pending_forks, 1)
      local offer, new_rng = boon_offer.compose_offer(d.rng, milestone, d, 3)
      d.rng = new_rng
      if #offer > 0 then
         d.pending_offer           = boon_offer.offer_ids(offer)
         d.pending_offer_milestone = milestone
         return
      end
      -- Empty offer for this fork — skip and try the next queued milestone.
   end
   d.pending_offer_milestone = "" as MilestoneId
end

-- Scans the player's concealed_tiles for newly-present 3-of-a-kind groups and
-- emits on_concealed_pung_formed for each kind not previously seen this deal.
-- Records seen kinds permanently on PlayerState so a broken-and-reformed pung
-- does not re-trigger (Hidden Strength contract).
local function emit_concealed_pung_events(d: DealState)
   local p = d.players[PLAYER_OWNER_INDEX]
   local counts: {string:integer} = {}
   local samples: {string:{Tile}} = {}
   for _, t in ipairs(p.hand.concealed_tiles) do
      local k = t.kind_id as string
      counts[k] = (counts[k] or 0) + 1
      local sample = samples[k]
      if sample == nil then
         sample = {}
         samples[k] = sample
      end
      if #sample < 3 then sample[#sample + 1] = t end
   end
   local seen_set: {string:boolean} = {}
   for _, k in ipairs(p.concealed_pung_kinds_seen) do
      seen_set[k as string] = true
   end
   -- Sort eligible kinds for deterministic emission order. pairs() iteration
   -- in Lua is unspecified; sorted order keeps multi-pung emission
   -- reproducible across runs (and across listeners with side effects).
   local eligible: {string} = {}
   for k, c in pairs(counts) do
      if c >= 3 and not seen_set[k] then
         eligible[#eligible + 1] = k
      end
   end
   table.sort(eligible)
   for _, k in ipairs(eligible) do
      local ev: ConcealedPungFormedEvent = {
         event_name = "on_concealed_pung_formed",
         kind_id    = k as TileKindId,
         tiles      = samples[k],
      }
      emit_event(d, ev as EventData)
      p.concealed_pung_kinds_seen[#p.concealed_pung_kinds_seen + 1] = k as TileKindId
   end
end

local function evaluate_milestones(d: DealState)
   local p = d.players[PLAYER_OWNER_INDEX]
   local set_count = milestones.total_set_count(p.hand)

   -- Fire set milestones for each crossed threshold up to 3. Each newly
   -- crossed milestone is queued for fork resolution (S02-T04 flow) in
   -- addition to firing the listener event (S01).
   while d.set_count_high_water < set_count and d.set_count_high_water < 3 do
      d.set_count_high_water = d.set_count_high_water + 1
      local ev_set: SetFormedEvent = {
         event_name = "on_set_formed",
         set_index  = d.set_count_high_water,
      }
      emit_event(d, ev_set as EventData)
      local m_id: MilestoneId = ("set_" .. tostring(d.set_count_high_water)) as MilestoneId
      d.pending_forks[#d.pending_forks + 1] = m_id
   end
   -- Track set_count past 3 so debug/UI can show full progression toward 4
   -- (pair-wait ting). No fork exists for set_4.
   if set_count > d.set_count_high_water then
      d.set_count_high_water = set_count
   end

   -- Ting check after set events so set_3 + ting fires in the right order.
   if not d.reached_ting then
      local td = ting_distance_mod.ting_distance(p.hand.concealed_tiles, p.hand.sets)
      -- Use `<= -1` defensively: ting_distance returns -1 for "in ting" on a
      -- post-discard 13-tile hand; if this helper ever runs on a 14-tile
      -- mid-turn snapshot it can return -2 ("already won"). Either condition
      -- means ting has been reached for milestone purposes.
      if td <= -1 then
         d.reached_ting = true
         local ev_ting: TingReachedEvent = { event_name = "on_ting_reached" }
         emit_event(d, ev_ting as EventData)
         d.pending_forks[#d.pending_forks + 1] = "ting" as MilestoneId
      end
   end

   -- Materialize the first queued fork into an offer the UI/test can read.
   materialize_next_offer(d)
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

local function remove_known_from_all(players: {PlayerState}, tile_id: TileId)
   for _, p in ipairs(players) do
      p.known_wall_tile_ids = remove_known(p.known_wall_tile_ids, tile_id)
   end
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

   local ev_end: DealLifecycleEvent = { event_name = "on_deal_end" }
   emit_event(d, ev_end as EventData)

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
   remove_known_from_all(d.players, dr.tile.tile_id)
   d.last_draw_was_supplement = true
   d.last_drawn_tile_id       = dr.tile.tile_id
   d.has_last_drawn           = true
   local cmds = fx_runner.dispatch_after_draw(d, player_index, dr.tile, true)
   fx_runner.apply_commands(d, cmds)
   return d, false
end

-- ── Effect score modifier integration ─────────────────────────────────────

local apply_score_modifiers = scoring.apply_score_modifiers
local build_score_ctx       = scoring.build_score_ctx

local function score_passes_threshold(r: ScoreResult): boolean
   return r.valid_hu
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
         hand                       = { concealed_tiles = hand_tiles, sets = {}, discards = {} },
         opening_trim               = {},
         seat_wind                  = SEAT_WINDS[i],
         is_human                   = (i == 1),
         known_wall_tile_ids        = {},
         concealed_pung_kinds_seen  = {},
         turn_extra_discards_owed   = 0,
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
      active_boons             = {},
      set_count_high_water     = 0,
      reached_ting             = false,
      declined_boons_this_deal = {},
      pending_forks            = {},
      pending_offer            = {},
      pending_offer_milestone  = "" as MilestoneId,
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
   d.active_boons = copy_active_boons(run_state.active_boons)

   local cmds = fx_runner.dispatch_opening_deal_complete(d, run_state.round_index)
   fx_runner.apply_commands(d, cmds)

   local ev_start: DealLifecycleEvent = { event_name = "on_deal_start" }
   emit_event(d, ev_start as EventData)
   emit_concealed_pung_events(d)

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

function M.pick_boon_offer(player_index: integer, boon_id: string): DealAction
   local a: PickBoonOfferAction = {
      kind         = "pick_boon_offer",
      player_index = player_index,
      boon_id      = boon_id,
   }
   return a as DealAction
end

function M.spend_boon_token(player_index: integer, boon_id: string, token_kind: string, params: {string:string}): DealAction
   local a: SpendBoonTokenAction = {
      kind         = "spend_boon_token",
      player_index = player_index,
      boon_id      = boon_id,
      token_kind   = token_kind,
      params       = params or {},
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
   -- Plan §357: mandatory pick. If a fork offer is materialized for the
   -- player, they must resolve it before drawing again. (Opponents draw
   -- normally; only the boon owner is gated.)
   if action.player_index == PLAYER_OWNER_INDEX and #deal.pending_offer > 0 then
      return err(deal, "draw: must resolve pending boon offer first (milestone " .. (deal.pending_offer_milestone as string) .. ")")
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
   remove_known_from_all(d.players, dr.tile.tile_id)
   d.last_draw_was_supplement = false
   d.last_drawn_tile_id       = dr.tile.tile_id
   d.has_last_drawn           = true
   d.phase                    = "awaiting_action" as DealPhase
   -- Reset bonus-discard counter at turn start (defensive: voids any owed
   -- count left stale by a prior turn ending via call-cuts-in).
   d.players[action.player_index].turn_extra_discards_owed = 0

   local cmds = fx_runner.dispatch_after_draw(d, action.player_index, dr.tile, false)
   local fx_events = fx_runner.apply_commands(d, cmds)

   if action.player_index == PLAYER_OWNER_INDEX then
      local ev_draw: PlayerDrawEvent = { event_name = "on_player_draw", tile = dr.tile }
      emit_event(d, ev_draw as EventData)
      emit_player_draw_derived(d, dr.tile)
   else
      local ev_draw: OpponentDrawEvent = {
         event_name     = "on_opponent_draw",
         opponent_index = action.player_index,
         tile           = dr.tile,
      }
      emit_event(d, ev_draw as EventData)
   end

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

   if action.player_index == PLAYER_OWNER_INDEX then
      local ev_disc: PlayerDiscardEvent = { event_name = "on_player_discard", tile = tile_obj }
      emit_event(d, ev_disc as EventData)
      emit_player_discard_derived(d, tile_obj)
      emit_concealed_pung_events(d)
      evaluate_milestones(d)
   else
      local ev_disc: OpponentDiscardEvent = {
         event_name     = "on_opponent_discard",
         opponent_index = action.player_index,
         tile           = tile_obj,
      }
      emit_event(d, ev_disc as EventData)
      emit_opponent_discard_derived(d, action.player_index, tile_obj)
   end

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

   if winner_index == PLAYER_OWNER_INDEX then
      local ev_hu: HuEvent = { event_name = "on_hu", fan_total = final.total_fan }
      emit_event(d, ev_hu as EventData)
   end
   local ev_end: DealLifecycleEvent = { event_name = "on_deal_end" }
   emit_event(d, ev_end as EventData)

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

   if winner_index == PLAYER_OWNER_INDEX then
      local ev_hu: HuEvent = { event_name = "on_hu", fan_total = final.total_fan }
      emit_event(d, ev_hu as EventData)
   end
   local ev_end: DealLifecycleEvent = { event_name = "on_deal_end" }
   emit_event(d, ev_end as EventData)

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
   d.players[winner_index].turn_extra_discards_owed = 0   -- new turn via call
   local cmds = fx_runner.dispatch_after_peng(d, winner_index)
   local fx_events = fx_runner.apply_commands(d, cmds)

   local peng_set = d.players[winner_index].hand.sets[#d.players[winner_index].hand.sets]
   if winner_index == PLAYER_OWNER_INDEX then
      local ev_peng: CallEvent = {
         event_name    = "on_peng",
         tile_set      = peng_set,
         source_player = discarder,
         kong_kind     = "",
      }
      emit_event(d, ev_peng as EventData)
   else
      local ev_peng: OpponentCallEvent = {
         event_name     = "on_opponent_call",
         opponent_index = winner_index,
         call_kind      = "peng",
         tile_set       = peng_set,
      }
      emit_event(d, ev_peng as EventData)
   end

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
   d2.players[winner_index].turn_extra_discards_owed = 0   -- new turn via open kong

   local kong_set = d2.players[winner_index].hand.sets[#d2.players[winner_index].hand.sets]
   if winner_index == PLAYER_OWNER_INDEX then
      local ev_kong: CallEvent = {
         event_name    = "on_kong",
         tile_set      = kong_set,
         source_player = discarder,
         kong_kind     = "open",
      }
      emit_event(d2, ev_kong as EventData)
   else
      local ev_kong: OpponentCallEvent = {
         event_name     = "on_opponent_call",
         opponent_index = winner_index,
         call_kind      = "kong",
         tile_set       = kong_set,
      }
      emit_event(d2, ev_kong as EventData)
   end

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
   d.players[claim.player_index].turn_extra_discards_owed = 0   -- new turn via chi

   local chi_set = d.players[claim.player_index].hand.sets[#d.players[claim.player_index].hand.sets]
   if claim.player_index == PLAYER_OWNER_INDEX then
      local ev_chi: CallEvent = {
         event_name    = "on_chi",
         tile_set      = chi_set,
         source_player = discarder,
         kong_kind     = "",
      }
      emit_event(d, ev_chi as EventData)
   else
      local ev_chi: OpponentCallEvent = {
         event_name     = "on_opponent_call",
         opponent_index = claim.player_index,
         call_kind      = "chi",
         tile_set       = chi_set,
      }
      emit_event(d, ev_chi as EventData)
   end

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
      -- Plan B (P8): if the discarder owes more bonus discards from
      -- extra_draw, hold their turn open. Decrement, return to
      -- awaiting_action so they pick another discard. Otherwise advance
      -- to the next seat normally.
      local owed = d.players[discarder].turn_extra_discards_owed
      if owed > 0 then
         d.players[discarder].turn_extra_discards_owed = owed - 1
         d.current_player = discarder
         d.phase          = "awaiting_action" as DealPhase
         d.has_last_drawn = false
         return ok_t(d, { ev("extra_discard_owed", "player " .. tostring(discarder) .. " owes " .. tostring(owed - 1) .. " more bonus discard(s)") })
      end
      d.current_player = (discarder % PLAYER_COUNT) + 1
      d.phase          = "awaiting_draw" as DealPhase
      d.has_last_drawn = false
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

      local kong_set = d2.players[declarer].hand.sets[#d2.players[declarer].hand.sets]
      if declarer == PLAYER_OWNER_INDEX then
         local ev_kong: CallEvent = {
            event_name    = "on_kong",
            tile_set      = kong_set,
            source_player = -1,
            kong_kind     = "added",
         }
         emit_event(d2, ev_kong as EventData)
         emit_concealed_pung_events(d2)   -- supplement may form a new concealed pung
      else
         local ev_kong: OpponentCallEvent = {
            event_name     = "on_opponent_call",
            opponent_index = declarer,
            call_kind      = "kong",
            tile_set       = kong_set,
         }
         emit_event(d2, ev_kong as EventData)
      end

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

      if action.player_index == PLAYER_OWNER_INDEX then
         local ev_hu: HuEvent = { event_name = "on_hu", fan_total = final.total_fan }
         emit_event(d, ev_hu as EventData)
      end
      local ev_end: DealLifecycleEvent = { event_name = "on_deal_end" }
      emit_event(d, ev_end as EventData)

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

   local ankan_set = d2.players[action.player_index].hand.sets[#d2.players[action.player_index].hand.sets]
   if action.player_index == PLAYER_OWNER_INDEX then
      local ev_ankan: CallEvent = {
         event_name    = "on_ankan",
         tile_set      = ankan_set,
         source_player = -1,
         kong_kind     = "",
      }
      emit_event(d2, ev_ankan as EventData)
      emit_concealed_pung_events(d2)   -- supplement may form a new concealed pung
   else
      local ev_ankan: OpponentCallEvent = {
         event_name     = "on_opponent_call",
         opponent_index = action.player_index,
         call_kind      = "ankan",
         tile_set       = ankan_set,
      }
      emit_event(d2, ev_ankan as EventData)
   end

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

-- ── Boon-offer pick (M2-S02-T04) ──────────────────────────────────────────
--
-- Resolves the head fork offer materialized on DealState. The picked boon
-- is added to deal.active_boons (deal-scoped); the other offered ids are
-- appended to declined_boons_this_deal so they cannot reappear this deal.
-- After the pick resolves, the next queued fork (if any) is materialized
-- automatically so the UI/test can chain picks without engine bookkeeping.
--
-- Phase-agnostic by design: a fork modal can pop while the deal sits in
-- reaction_window, awaiting_action, or awaiting_draw — the §357 mandatory
-- pick is enforced by handle_draw's gate, not by phase. The pick itself
-- only depends on pending_offer being non-empty.

local function handle_pick_boon_offer(deal: DealState, action: PickBoonOfferAction): DealTransition
   if #deal.pending_offer == 0 then
      return err(deal, "pick_boon_offer: no offer is currently pending")
   end
   if action.player_index ~= PLAYER_OWNER_INDEX then
      return err(deal, "pick_boon_offer: only the boon owner may pick")
   end
   local in_offer = false
   for _, id in ipairs(deal.pending_offer) do
      if id == action.boon_id then in_offer = true; break end
   end
   if not in_offer then
      return err(deal, "pick_boon_offer: boon_id not in current offer: " .. action.boon_id)
   end

   local d = copy_deal(deal)
   local ok = boon_offer.accept_offer(d, d.pending_offer, d.pending_offer_milestone, action.boon_id)
   if not ok then
      return err(deal, "pick_boon_offer: accept_offer rejected the pick (internal)")
   end
   d.pending_offer           = {}
   d.pending_offer_milestone = "" as MilestoneId
   materialize_next_offer(d)

   return ok_t(d, { ev("boon_picked", "player picked " .. action.boon_id) })
end

-- Player-initiated token spend. Validates phase (must be the player's own
-- awaiting_action turn, no pending offer materialized), boon-active, and
-- token-available — then emits on_token_spent so the boon's own listener
-- can validate params + deduct via spend_token + run the spend's effect.
-- The engine never deducts the token directly; the listener owns that.
local function handle_spend_boon_token(deal: DealState, action: SpendBoonTokenAction): DealTransition
   if action.player_index ~= PLAYER_OWNER_INDEX then
      return err(deal, "spend_boon_token: only the boon owner (player 1) may spend")
   end
   if (deal.phase as string) ~= "awaiting_action" then
      return err(deal, "spend_boon_token: requires awaiting_action phase, got " .. (deal.phase as string))
   end
   if deal.current_player ~= action.player_index then
      return err(deal, "spend_boon_token: not the player's turn")
   end
   if #deal.pending_offer > 0 then
      return err(deal, "spend_boon_token: must resolve pending boon offer first")
   end

   local matched_boon: ActiveBoon = nil
   for _, b in ipairs(deal.active_boons) do
      if b.boon_id == action.boon_id then matched_boon = b; break end
   end
   if matched_boon == nil then
      return err(deal, "spend_boon_token: boon not active: " .. action.boon_id)
   end
   local have = matched_boon.tokens[action.token_kind] or 0
   if have <= 0 then
      return err(deal, "spend_boon_token: no " .. action.token_kind .. " token to spend on " .. action.boon_id)
   end

   local d = copy_deal(deal)
   local ev_spend: TokenSpendEvent = {
      event_name = "on_token_spent",
      boon_id    = action.boon_id,
      token_kind = action.token_kind,
      params     = action.params,
   }
   emit_event(d, ev_spend as EventData)

   return ok_t(d, { ev("token_spent", "player spent " .. action.token_kind .. " on " .. action.boon_id) })
end

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
   elseif kind == "pick_boon_offer" then
      return handle_pick_boon_offer(deal, action as PickBoonOfferAction)
   elseif kind == "spend_boon_token" then
      return handle_spend_boon_token(deal, action as SpendBoonTokenAction)
   else
      return err(deal, "apply_action: unknown action kind: " .. kind)
   end
end

return M
