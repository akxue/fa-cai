-- M2 boon catalog (D012). Pure data — no behavior beyond stub effects.
--
-- Coexists with `content/boons.tl` (M1 BoonContent). M1's file is removed in
-- S05; this file becomes the canonical catalog at that point. M2-S02 ships
-- with 6 stub boons (one starter + one set_1 per cluster) to validate the
-- offer-pool composition and decline-exclusion flow. Full boon effect logic
-- arrives in S04.
--
-- Imports core types + boon_types only — no game/engine dependency.

require("core.types")
require("game.deal_types")
require("effects.boon_types")

-- Plan C wait-shape query used by Suit Sentry (and future Sacred Eye).
-- Pure game helper with no engine state side effects; safe import from
-- content/ — same precedent as game.deal_types.
local validator = require("game.hand_validator")

local M = {}

-- A no-op effect placeholder. Replaced with real behavior in S04 per the
-- 24-boon library spec in MILESTONE-2-PLAN.md §450.
local function noop_effect(_ctx: BoonContext, _ev: EventData)
end

local function always_true(_ctx: BoonContext, _ev: EventData): boolean
   return true
end

-- ── Helpers used across effect implementations ───────────────────────────

-- Appends each tile's id to the player's known_wall_tile_ids, deduping
-- against ids already in the list. Used by peek-style boons (Honor's Eye,
-- Honor Sense, etc.) so repeated emissions against the same wall front
-- don't pile duplicates into the Known Wall UI strip.
--
-- Takes a PlayerState directly rather than a BoonContext so the helper is
-- usable from non-boon paths (debug tools, future M3+ opponent peeks)
-- without an artificial context. Boon effects pass
-- `ctx.deal.players[ctx.player_index]`.
local function mark_wall_known(player: PlayerState, peeked: {Tile})
   for _, t in ipairs(peeked) do
      local already_known = false
      for _, id in ipairs(player.known_wall_tile_ids) do
         if id == t.tile_id then already_known = true; break end
      end
      if not already_known then
         player.known_wall_tile_ids[#player.known_wall_tile_ids + 1] = t.tile_id
      end
   end
end

local DRAGON_KINDS: {string: boolean} = {
   fa_cai = true, hong_zhong = true, bai_ban = true,
}

local HONOR_KINDS: {string: boolean} = {
   east = true, south = true, west = true, north = true,
   fa_cai = true, hong_zhong = true, bai_ban = true,
}

-- Counts honor tiles across a player's concealed tiles + all set tiles
-- (including kongs and called sets). Used by ting-activated honor boons.
local function count_honors_in_hand(hand: PlayerHand): integer
   local n = 0
   for _, t in ipairs(hand.concealed_tiles) do
      if HONOR_KINDS[t.kind_id as string] then n = n + 1 end
   end
   for _, s in ipairs(hand.sets) do
      for _, t in ipairs(s.tiles) do
         if HONOR_KINDS[t.kind_id as string] then n = n + 1 end
      end
   end
   return n
end

-- Returns true if the player has zero open sets (concealed kongs count
-- as concealed). Used to detect "concealed ting" for Closed Eye.
local function is_fully_concealed(hand: PlayerHand): boolean
   for _, s in ipairs(hand.sets) do
      if (s.visibility as string) == "open" then return false end
   end
   return true
end

-- Suited tile-kind prefixes. Used by dominant-suit detection for the
-- suit cluster boons (Pure Path, Pure Vision, etc.).
local SUITED_PREFIXES: {string} = {"tiao", "wan", "bing"}

-- Encoding for storing dominant suit in counters[]. Integer counter
-- values translate to suit strings via IDX_TO_SUIT. ActiveBoon's
-- counters/flags/tokens are typed as integer/boolean/integer respectively
-- — there's no native string-state slot, so we encode.
local SUIT_TO_IDX: {string: integer} = { tiao = 1, wan = 2, bing = 3 }
local IDX_TO_SUIT: {integer: string} = { [1] = "tiao", [2] = "wan", [3] = "bing" }

-- Returns the player's most-numerous suit in their concealed hand +
-- set tiles. Ties broken canonically tiao > wan > bing. Honors are
-- never returned (suit cluster boons key off "suit" specifically).
local function dominant_suit_of_hand(hand: PlayerHand): string
   local counts: {string: integer} = { tiao = 0, wan = 0, bing = 0 }
   local function bump(kind_id: string)
      for _, p in ipairs(SUITED_PREFIXES) do
         if kind_id:sub(1, #p) == p then
            counts[p] = (counts[p] or 0) + 1
            return
         end
      end
   end
   for _, t in ipairs(hand.concealed_tiles) do
      bump(t.kind_id as string)
   end
   for _, s in ipairs(hand.sets) do
      for _, t in ipairs(s.tiles) do
         bump(t.kind_id as string)
      end
   end
   local best_suit = "tiao"
   local best_count = counts["tiao"]
   if (counts["wan"]  or 0) > best_count then best_suit = "wan";  best_count = counts["wan"]  end
   if (counts["bing"] or 0) > best_count then best_suit = "bing"; best_count = counts["bing"] end
   return best_suit
end

-- Counts tiles whose kind_id begins with the given suit prefix.
local function count_suit_in_tiles(tiles_list: {Tile}, suit: string): integer
   local n = 0
   for _, t in ipairs(tiles_list) do
      local k = t.kind_id as string
      if k:sub(1, #suit) == suit then n = n + 1 end
   end
   return n
end

-- ── Effect implementations (S04 — incremental) ───────────────────────────
--
-- Each implemented boon converts its `effect` from `noop_effect` to a real
-- implementation here. The remaining 20 boons in the audit library follow
-- in subsequent slices/PRs.

-- Honor's Eye (set_1, honor): on every honor draw, peek the next wall tile
-- and add it to the player's known-wall view. Result surfaces in the
-- Known Wall info strip rendered by ui.info_panels.
local function effect_honors_eye(ctx: BoonContext, _ev: EventData)
   mark_wall_known(ctx.deal.players[ctx.player_index], ctx:peek_wall(1))
end

-- Hidden Path (starter, concealed): grants 1 mulligan + 1 wall-peek token
-- at deal start.
--
-- TODO (P14 gating): per plan §486 / §515, tokens should be spendable
-- only while the player has made no calls. The gate is NOT enforced
-- today — boon_primitives.spend_token deducts unconditionally. The gate
-- will land alongside the spend-action UI surface in a later S04 slice.
local function effect_hidden_path(ctx: BoonContext, _ev: EventData)
   ctx:grant_token("mulligan", 1)
   ctx:grant_token("peek", 1)
end

-- Honor Sense (set_1 / set_2 flex, honor): every 3rd opponent honor
-- discard you observe, peek the next 2 wall tiles.
local function effect_honor_sense(ctx: BoonContext, _ev: EventData)
   local count = ctx:get_counter("opp_honor_discards") + 1
   ctx:set_counter("opp_honor_discards", count)
   if count % 3 == 0 then
      mark_wall_known(ctx.deal.players[ctx.player_index], ctx:peek_wall(2))
   end
end

-- Dragon Pulse (set_2, honor): every dragon set you form (peng / open
-- kong / concealed kong), gain 1 mulligan + 1 peek token. The boon
-- listens on the call events and inspects the tile_set kind to detect
-- dragons; no separate on_dragon_set_formed event needed. Chi is
-- naturally filtered by DRAGON_KINDS (dragons can't form chi in HK).
local function effect_dragon_pulse(ctx: BoonContext, ev: EventData)
   local call_ev = ev as CallEvent
   if #call_ev.tile_set.tiles == 0 then return end
   if not DRAGON_KINDS[call_ev.tile_set.tiles[1].kind_id as string] then return end
   ctx:grant_token("mulligan", 1)
   ctx:grant_token("peek", 1)
end

-- Helper: is this event a player call (chi/peng/kong/ankan)?
local function is_player_call_event(event_name: string): boolean
   return event_name == "on_chi"
      or event_name == "on_peng"
      or event_name == "on_kong"
      or event_name == "on_ankan"
end

-- Silent March (set_1 / set_2 flex, concealed): every 3 consecutive
-- no-call turns, gain 1 peek token. Per plan §488, "consecutive" means
-- the counter resets on any of the player's calls but the boon stays
-- alive (later quiet streaks still earn tokens). Tracks per-turn call
-- state via a transient flag that the next discard clears.
--
-- TODO(S07): the `called_this_turn` transient flag persists on the
-- ActiveBoon record. For a deal-scoped boon this is fine — flags reset
-- via boon_context.new_active at deal start. For run-scoped (carried)
-- boons, the run→deal copy in deal_engine.new_deal_with_run carries
-- residual flags forward; a stale called_this_turn=true would cause
-- the next deal's first discard to spuriously reset the streak. Same
-- caveat applies to silent_stand below. Resolve at carry-forward time.
local function effect_silent_march(ctx: BoonContext, ev: EventData)
   local name = ev.event_name as string
   if is_player_call_event(name) then
      ctx:set_flag("called_this_turn", true)
   elseif name == "on_player_discard" then
      if ctx:get_flag("called_this_turn") then
         ctx:set_flag("called_this_turn", false)
         ctx:set_counter("consecutive_no_call", 0)
      else
         local n = ctx:get_counter("consecutive_no_call") + 1
         ctx:set_counter("consecutive_no_call", n)
         if n % 3 == 0 then
            ctx:grant_token("peek", 1)
         end
      end
   end
end

-- Silent Stand (set_3, concealed): same pattern as Silent March but
-- every 5 consecutive no-call turns grants 1 mulligan token.
local function effect_silent_stand(ctx: BoonContext, ev: EventData)
   local name = ev.event_name as string
   if is_player_call_event(name) then
      ctx:set_flag("called_this_turn", true)
   elseif name == "on_player_discard" then
      if ctx:get_flag("called_this_turn") then
         ctx:set_flag("called_this_turn", false)
         ctx:set_counter("consecutive_no_call", 0)
      else
         local n = ctx:get_counter("consecutive_no_call") + 1
         ctx:set_counter("consecutive_no_call", n)
         if n % 5 == 0 then
            ctx:grant_token("mulligan", 1)
         end
      end
   end
end

-- Concealed Insight (set_1 / set_2 flex, concealed): every 4 of your
-- discards while you have made no calls, peek 1 wall tile. Per plan
-- §489, "while no calls" means the boon permanently disqualifies on
-- the first player call — unlike Silent March's reset-on-call pattern.
local function effect_concealed_insight(ctx: BoonContext, ev: EventData)
   local name = ev.event_name as string
   if is_player_call_event(name) then
      ctx:set_flag("disqualified", true)
      -- Clear the in-flight counter so a debug-UI surfacing tokens/
      -- counters doesn't show "3/4 toward peek" on a permanently dead
      -- boon. Harmless either way — the early-return on the discard
      -- path makes the counter inert from here on.
      ctx:set_counter("no_call_discards", 0)
   elseif name == "on_player_discard" then
      if ctx:get_flag("disqualified") then return end
      local n = ctx:get_counter("no_call_discards") + 1
      ctx:set_counter("no_call_discards", n)
      if n % 4 == 0 then
         mark_wall_known(ctx.deal.players[ctx.player_index], ctx:peek_wall(1))
      end
   end
end

-- Honor Sanctum (ting, honor): when you reach ting holding 4+ honor
-- tiles (across concealed + sets), peek 1 wall tile each turn for the
-- rest of the deal. Two-phase: on on_ting_reached, check the honor
-- count and latch an `active` flag; thereafter every on_player_draw
-- peeks one tile while active.
--
-- TODO(S07): the `active` flag persists for the rest of the deal but
-- carry-forward (run-scoped boons crossing deals) must reset it —
-- otherwise a boon latched in deal N auto-peeks from turn 1 of deal
-- N+1 without a fresh ting. Same caveat applies to Closed Eye below.
local function effect_honor_sanctum(ctx: BoonContext, ev: EventData)
   local name = ev.event_name as string
   if name == "on_ting_reached" then
      local hand = ctx.deal.players[ctx.player_index].hand
      if count_honors_in_hand(hand) >= 4 then
         ctx:set_flag("active", true)
      end
   elseif name == "on_player_draw" then
      if ctx:get_flag("active") then
         mark_wall_known(ctx.deal.players[ctx.player_index], ctx:peek_wall(1))
      end
   end
end

-- Closed Eye (ting, concealed): when you reach concealed ting (no open
-- sets — concealed kongs OK), peek 1 wall tile each turn for the rest
-- of the deal. Same two-phase latch as Honor Sanctum with a different
-- activation predicate.
local function effect_closed_eye(ctx: BoonContext, ev: EventData)
   local name = ev.event_name as string
   if name == "on_ting_reached" then
      local hand = ctx.deal.players[ctx.player_index].hand
      if is_fully_concealed(hand) then
         ctx:set_flag("active", true)
      end
   elseif name == "on_player_draw" then
      if ctx:get_flag("active") then
         mark_wall_known(ctx.deal.players[ctx.player_index], ctx:peek_wall(1))
      end
   end
end

-- Honor Hunt (set_2 / set_3 flex, honor): every 4 of your honor-tile
-- draws, on your next turn take an extra wall tile (matched discard
-- per P8 enforced by the engine). No cap.
--
-- State (on the ActiveBoon):
--   counters["honor_draws"]         — running total of honor draws this deal
--   counters["pending_extra_draws"] — number of bonus draws owed on future turns
--
-- Timing: counter increments on on_honor_drawn (derived event fires AFTER
-- on_player_draw — see emit_player_draw_derived in deal_engine.tl). So
-- the bonus draw is taken at the START of the FOLLOWING turn's
-- on_player_draw, which is the "on your next turn" semantic the spec
-- describes. Multiple owed draws stack and drain one per turn.
local function effect_honor_hunt(ctx: BoonContext, ev: EventData)
   local name = ev.event_name as string
   if name == "on_player_draw" then
      local owed = ctx:get_counter("pending_extra_draws")
      if owed <= 0 then return end
      if #ctx.deal.wall.tiles == 0 then return end   -- wall exhausted
      ctx:set_counter("pending_extra_draws", owed - 1)
      ctx:extra_draw()
      return
   end
   if name == "on_honor_drawn" then
      local n = ctx:get_counter("honor_draws") + 1
      ctx:set_counter("honor_draws", n)
      if n % 4 == 0 then
         ctx:set_counter("pending_extra_draws",
            ctx:get_counter("pending_extra_draws") + 1)
      end
   end
end

-- Honor Heart (set_3, honor): every honor peng or kong you complete,
-- take the next wall tile as a free extra draw (matched discard per P8
-- enforced by the engine). No cap.
--
-- Triggers on the player's own call events when the called tile is an
-- honor kind. Concealed kong (on_ankan) qualifies too — any 3-or-4 of
-- an honor that becomes a declared set fires. Chi cannot form on honors
-- in HK so on_chi never qualifies; filtering by HONOR_KINDS is enough.
local function effect_honor_heart(ctx: BoonContext, ev: EventData)
   local call_ev = ev as CallEvent
   if #call_ev.tile_set.tiles == 0 then return end
   if not HONOR_KINDS[call_ev.tile_set.tiles[1].kind_id as string] then return end
   if #ctx.deal.wall.tiles == 0 then return end
   ctx:extra_draw()
end

-- Pure Path (starter, suit): at deal start, auto-pick the player's
-- dominant suit (most-numerous in starting hand, ties tiao>wan>bing)
-- and snapshot the opponent dominant-suit counts. Plan §473 calls for
-- a player prompt to choose the suit; the auto-pick is a defensible
-- default until the prompt UI ships.
--
-- Stored state (on the ActiveBoon):
--   counters["dominant_suit_idx"]  — 1=tiao / 2=wan / 3=bing
--   counters["opp_2_count"]         — opponent seat 2's count of suit
--   counters["opp_3_count"]         — opponent seat 3's count of suit
--   counters["opp_4_count"]         — opponent seat 4's count of suit
local function effect_pure_path(ctx: BoonContext, _ev: EventData)
   local hand = ctx.deal.players[ctx.player_index].hand
   local suit = dominant_suit_of_hand(hand)
   ctx:set_counter("dominant_suit_idx", SUIT_TO_IDX[suit] or 0)
   for opp = 1, 4 do
      if opp ~= ctx.player_index then
         local opp_hand = ctx.deal.players[opp].hand
         ctx:set_counter("opp_" .. tostring(opp) .. "_count",
            count_suit_in_tiles(opp_hand.concealed_tiles, suit))
      end
   end
end

-- Pure Vision (set_2, suit): live count of dominant-suit tiles remaining
-- in the wall. Recomputes the count on every on_player_draw and stores
-- it on counters["wall_dominant_count"] for the UI/debug surface to
-- read. Dominant suit is computed independently from the player's
-- current hand each time (S04 simplification — see plan §476 note).
local function effect_pure_vision(ctx: BoonContext, _ev: EventData)
   local hand = ctx.deal.players[ctx.player_index].hand
   local suit = dominant_suit_of_hand(hand)
   ctx:set_counter("dominant_suit_idx", SUIT_TO_IDX[suit] or 0)
   ctx:set_counter("wall_dominant_count",
      count_suit_in_tiles(ctx.deal.wall.tiles, suit))
end

-- Suit Sentry (ting, suit): when you reach ting on a "pure dominant-
-- suit wait" (every completing tile kind is in the dominant suit), peek
-- 1 wall tile each turn for the rest of the deal. Two-phase latch
-- pattern (same shape as Honor Sanctum / Closed Eye), keyed off Plan C's
-- compute_waits + a suit-membership check.
--
-- Wait shape is computed once at on_ting_reached. If the player later
-- breaks ting and re-reaches it on a different wait, this boon stays
-- latched (per the boon's "rest of the deal" language). That mirrors
-- Honor Sanctum's behavior.
local function effect_suit_sentry(ctx: BoonContext, ev: EventData)
   local name = ev.event_name as string
   if name == "on_ting_reached" then
      local hand = ctx.deal.players[ctx.player_index].hand
      local dom = dominant_suit_of_hand(hand)
      local waits = validator.compute_waits(hand.concealed_tiles, hand.sets)
      if #waits == 0 then return end   -- defensive: shouldn't happen at ting
      local all_dominant = true
      for _, k in ipairs(waits) do
         local ks = k as string
         if ks:sub(1, #dom) ~= dom then all_dominant = false; break end
      end
      if all_dominant then
         ctx:set_flag("active", true)
      end
   elseif name == "on_player_draw" then
      if ctx:get_flag("active") then
         mark_wall_known(ctx.deal.players[ctx.player_index], ctx:peek_wall(1))
      end
   end
end

-- Cleanse (set_1 / set_2 flex, suit): once-per-deal swap of an off-suit
-- hand tile for the next wall tile. Modeled as a token-spend (Plan A):
--   on_deal_start AND on_boon_acquired → grant 1 "cleanse_charge" token
--     idempotently. Cleanse is set_1/set_2-eligible (mid-deal pick), so
--     on_boon_acquired closes the gap that on_deal_start alone leaves.
--   on_token_spent (boon_id == "cleanse") → validate params.tile_id is
--     in the player's concealed hand and is NOT in the dominant suit AND
--     the wall has a tile; deduct token + swap.
-- Off-suit means: not in the auto-picked dominant suit (honors qualify
-- as off-suit). Dominant is recomputed from the current hand at spend
-- time — same auto-pick pattern as pure_path/pure_vision.
local function effect_cleanse(ctx: BoonContext, ev: EventData)
   local name = ev.event_name as string
   if name == "on_deal_start" then
      if ctx:get_tokens("cleanse_charge") == 0 then
         ctx:grant_token("cleanse_charge", 1)
      end
      return
   end
   if name == "on_boon_acquired" then
      local acq = ev as BoonAcquiredEvent
      if acq.boon_id ~= "cleanse" then return end
      if ctx:get_tokens("cleanse_charge") == 0 then
         ctx:grant_token("cleanse_charge", 1)
      end
      return
   end
   if name ~= "on_token_spent" then return end
   local spend = ev as TokenSpendEvent
   if spend.boon_id ~= "cleanse" then return end
   if spend.token_kind ~= "cleanse_charge" then return end

   local tile_id_raw = spend.params["tile_id"]
   if tile_id_raw == nil or tile_id_raw == "" then return end
   local tile_id = tile_id_raw as TileId

   local hand = ctx.deal.players[ctx.player_index].hand
   local target_kind: string = ""
   for _, t in ipairs(hand.concealed_tiles) do
      if t.tile_id == tile_id then
         target_kind = t.kind_id as string
         break
      end
   end
   if target_kind == "" then return end   -- tile not in hand

   local dom = dominant_suit_of_hand(hand)
   if target_kind:sub(1, #dom) == dom then return end   -- tile IS dominant; not off-suit
   if #ctx.deal.wall.tiles == 0 then return end          -- wall empty; can't draw replacement

   if not ctx:spend_token("cleanse_charge", 1) then return end
   ctx:swap_hand_for_wall(tile_id)
end

-- Honor encoding for honors_gift's "marked honor" counter. Mirrors the
-- SUIT_TO_IDX / IDX_TO_SUIT pattern: integer-encoded so the chosen kind
-- can ride on the ActiveBoon's integer counters map. Canonical order is
-- winds then dragons: east > south > west > north > fa_cai > hong_zhong > bai_ban.
local HONOR_ORDER: {string} = {
   "east", "south", "west", "north", "fa_cai", "hong_zhong", "bai_ban",
}
local HONOR_TO_IDX: {string: integer} = {}
local IDX_TO_HONOR: {integer: string} = {}
for i, k in ipairs(HONOR_ORDER) do
   HONOR_TO_IDX[k] = i
   IDX_TO_HONOR[i] = k
end

-- Returns the player's most-numerous honor across concealed + sets. Ties
-- broken canonically (HONOR_ORDER). Returns "" when the hand has no
-- honors at all — the boon stores 0 in that case and never recomputes
-- (marked honor is latched at deal start).
local function marked_honor_of_hand(hand: PlayerHand): string
   local counts: {string: integer} = {}
   for _, t in ipairs(hand.concealed_tiles) do
      local k = t.kind_id as string
      if HONOR_KINDS[k] then counts[k] = (counts[k] or 0) + 1 end
   end
   for _, s in ipairs(hand.sets) do
      for _, t in ipairs(s.tiles) do
         local k = t.kind_id as string
         if HONOR_KINDS[k] then counts[k] = (counts[k] or 0) + 1 end
      end
   end
   local best_kind: string = ""
   local best_count = 0
   for _, k in ipairs(HONOR_ORDER) do   -- canonical iteration for tie-break
      local c = counts[k] or 0
      if c > best_count then
         best_kind  = k
         best_count = c
      end
   end
   return best_kind
end

-- Honor's Gift (starter, honor): at deal start, auto-pick the player's
-- most-numerous honor (ties: east > south > west > north > dragons in
-- canonical order). Thereafter, recompute the wall's live count of that
-- marked honor on every on_player_draw so the UI/debug surface can
-- display "N remaining". Plan §460 envisions a player prompt to choose
-- the honor; the auto-pick is a defensible default until prompt UI ships.
--
-- Stored state (on the ActiveBoon):
--   counters["marked_honor_idx"]   — 1..7 per HONOR_ORDER, or 0 if hand had no honors
--   counters["wall_marked_count"]  — live count of marked honor in wall
local function effect_honors_gift(ctx: BoonContext, ev: EventData)
   local name = ev.event_name as string
   local hand = ctx.deal.players[ctx.player_index].hand
   if name == "on_deal_start" then
      local kind = marked_honor_of_hand(hand)
      ctx:set_counter("marked_honor_idx", HONOR_TO_IDX[kind] or 0)
      -- Initial wall count for the marked honor, so UI has a value before
      -- the first draw fires the recomputation listener below.
      if kind ~= "" then
         local n = 0
         for _, t in ipairs(ctx.deal.wall.tiles) do
            if (t.kind_id as string) == kind then n = n + 1 end
         end
         ctx:set_counter("wall_marked_count", n)
      end
      return
   end
   if name ~= "on_player_draw" then return end
   local idx = ctx:get_counter("marked_honor_idx")
   if idx == 0 then return end   -- no honors at deal start; nothing to track
   local kind = IDX_TO_HONOR[idx] or ""
   if kind == "" then return end
   local n = 0
   for _, t in ipairs(ctx.deal.wall.tiles) do
      if (t.kind_id as string) == kind then n = n + 1 end
   end
   ctx:set_counter("wall_marked_count", n)
end

-- Hidden Strength (set_2, concealed): every concealed pung formed (3rd
-- matching tile present in concealed_tiles at end-of-turn), peek 3 wall
-- tiles. The engine fires on_concealed_pung_formed once per distinct
-- kind; a broken-and-reformed pung does not re-trigger (engine-side
-- guard via PlayerState.concealed_pung_kinds_seen). No boon-side state
-- needed.
local function effect_hidden_strength(ctx: BoonContext, _ev: EventData)
   mark_wall_known(ctx.deal.players[ctx.player_index], ctx:peek_wall(3))
end

-- ── Catalog ──────────────────────────────────────────────────────────────
-- 6 S02 plumbing-validation boons + S04 additions as effect logic lands.

local BOONS: {Boon} = {
   -- Honor cluster
   {
      id                  = "honors_gift",
      cluster             = "honor",
      name                = "Honor's Gift",
      description         = "At deal start, choose one honor type. See live count of marked honor in the wall.",
      eligible_milestones = {"starter"},
      effect_kind         = "info",
      weight              = 1.0,
      listens             = {"on_deal_start", "on_player_draw"},
      condition           = always_true,
      effect              = effect_honors_gift,
   },
   {
      id                  = "honors_eye",
      cluster             = "honor",
      name                = "Honor's Eye",
      description         = "When you draw any honor tile, peek the next wall tile.",
      eligible_milestones = {"set_1"},
      effect_kind         = "peek",
      weight              = 1.0,
      listens             = {"on_honor_drawn"},
      condition           = always_true,
      effect              = effect_honors_eye,
   },
   {
      id                  = "honor_sense",
      cluster             = "honor",
      name                = "Honor Sense",
      description         = "Every 3rd opponent honor discard, peek 2 wall tiles.",
      eligible_milestones = {"set_1", "set_2"},
      effect_kind         = "peek",
      weight              = 1.0,
      listens             = {"on_opponent_honor_discarded"},
      condition           = always_true,
      effect              = effect_honor_sense,
   },
   {
      id                  = "dragon_pulse",
      cluster             = "honor",
      name                = "Dragon Pulse",
      description         = "Every dragon set you form (peng/kong), gain 1 mulligan + 1 peek token.",
      eligible_milestones = {"set_2"},
      effect_kind         = "token",
      weight              = 1.0,
      listens             = {"on_peng", "on_kong", "on_ankan"},
      condition           = always_true,
      effect              = effect_dragon_pulse,
   },
   {
      id                  = "honor_sanctum",
      cluster             = "honor",
      name                = "Honor Sanctum",
      description         = "When you reach ting holding 4+ honor tiles, peek 1 wall tile each turn for the rest of the deal.",
      eligible_milestones = {"ting"},
      effect_kind         = "peek",
      weight              = 1.0,
      listens             = {"on_ting_reached", "on_player_draw"},
      condition           = always_true,
      effect              = effect_honor_sanctum,
   },
   {
      id                  = "honor_hunt",
      cluster             = "honor",
      name                = "Honor Hunt",
      description         = "Every 4 of your honor-tile draws, on your next turn take an extra wall tile.",
      eligible_milestones = {"set_2", "set_3"},
      effect_kind         = "extra_draw",
      weight              = 1.0,
      listens             = {"on_honor_drawn", "on_player_draw"},
      condition           = always_true,
      effect              = effect_honor_hunt,
   },
   {
      id                  = "honor_heart",
      cluster             = "honor",
      name                = "Honor Heart",
      description         = "Every honor peng or kong you complete, take the next wall tile as a free extra draw.",
      eligible_milestones = {"set_3"},
      effect_kind         = "extra_draw",
      weight              = 1.0,
      listens             = {"on_peng", "on_kong", "on_ankan"},
      condition           = always_true,
      effect              = effect_honor_heart,
   },

   -- Suit cluster
   {
      id                  = "pure_path",
      cluster             = "suit",
      name                = "Pure Path",
      description         = "At deal start, choose one suit (dominant suit). See count in each opponent's starting hand.",
      eligible_milestones = {"starter"},
      effect_kind         = "info",
      weight              = 1.0,
      listens             = {"on_deal_start"},
      condition           = always_true,
      effect              = effect_pure_path,
   },
   {
      id                  = "pure_vision",
      cluster             = "suit",
      name                = "Pure Vision",
      description         = "Live count of dominant-suit tiles remaining in the wall.",
      eligible_milestones = {"set_2"},
      effect_kind         = "info",
      weight              = 1.0,
      listens             = {"on_player_draw"},
      condition           = always_true,
      effect              = effect_pure_vision,
   },
   {
      id                  = "cleanse",
      cluster             = "suit",
      name                = "Cleanse",
      description         = "Once per deal, swap an off-suit hand tile for the next wall tile.",
      eligible_milestones = {"set_1", "set_2"},
      effect_kind         = "swap",
      weight              = 1.0,
      listens             = {"on_deal_start", "on_boon_acquired", "on_token_spent"},
      condition           = always_true,
      effect              = effect_cleanse,
   },
   {
      id                  = "suit_sentry",
      cluster             = "suit",
      name                = "Suit Sentry",
      description         = "When you reach ting on a pure dominant-suit wait, peek 1 wall tile each turn for the rest of the deal.",
      eligible_milestones = {"ting"},
      effect_kind         = "peek",
      weight              = 1.0,
      listens             = {"on_ting_reached", "on_player_draw"},
      condition           = always_true,
      effect              = effect_suit_sentry,
   },

   -- Concealed cluster
   {
      id                  = "hidden_path",
      cluster             = "concealed",
      name                = "Hidden Path",
      description         = "Start the deal with 1 mulligan token and 1 wall-peek token.",
      eligible_milestones = {"starter"},
      effect_kind         = "token",
      weight              = 1.0,
      listens             = {"on_deal_start"},
      condition           = always_true,
      effect              = effect_hidden_path,
   },
   {
      id                  = "silent_march",
      cluster             = "concealed",
      name                = "Silent March",
      description         = "Every 3 consecutive no-call turns, gain 1 wall-peek token.",
      eligible_milestones = {"set_1", "set_2"},
      effect_kind         = "token",
      weight              = 1.0,
      listens             = {"on_player_discard", "on_chi", "on_peng", "on_kong", "on_ankan"},
      condition           = always_true,
      effect              = effect_silent_march,
   },
   {
      id                  = "silent_stand",
      cluster             = "concealed",
      name                = "Silent Stand",
      description         = "Every 5 consecutive no-call turns, gain 1 mulligan token.",
      eligible_milestones = {"set_3"},
      effect_kind         = "token",
      weight              = 1.0,
      listens             = {"on_player_discard", "on_chi", "on_peng", "on_kong", "on_ankan"},
      condition           = always_true,
      effect              = effect_silent_stand,
   },
   {
      id                  = "hidden_strength",
      cluster             = "concealed",
      name                = "Hidden Strength",
      description         = "Every concealed pung formed in your hand, peek 3 wall tiles.",
      eligible_milestones = {"set_2"},
      effect_kind         = "peek",
      weight              = 1.0,
      listens             = {"on_concealed_pung_formed"},
      condition           = always_true,
      effect              = effect_hidden_strength,
   },
   {
      id                  = "concealed_insight",
      cluster             = "concealed",
      name                = "Concealed Insight",
      description         = "Every 4 of your discards while you have made no calls, peek 1 wall tile.",
      eligible_milestones = {"set_1", "set_2"},
      effect_kind         = "peek",
      weight              = 1.0,
      listens             = {"on_player_discard", "on_chi", "on_peng", "on_kong", "on_ankan"},
      condition           = always_true,
      effect              = effect_concealed_insight,
   },
   {
      id                  = "closed_eye",
      cluster             = "concealed",
      name                = "Closed Eye",
      description         = "When you reach concealed ting, peek 1 wall tile each turn for the rest of the deal.",
      eligible_milestones = {"ting"},
      effect_kind         = "peek",
      weight              = 1.0,
      listens             = {"on_ting_reached", "on_player_draw"},
      condition           = always_true,
      effect              = effect_closed_eye,
   },
}

-- ── Public API ────────────────────────────────────────────────────────────

function M.all(): {Boon}
   local out: {Boon} = {}
   for _, b in ipairs(BOONS) do
      out[#out + 1] = b
   end
   return out
end

function M.find(boon_id: string): Boon
   for _, b in ipairs(BOONS) do
      if b.id == boon_id then return b end
   end
   return nil
end

-- Registers every M2 boon into the runtime boon_registry. Idempotent in the
-- sense that re-registering the same id overwrites (consistent with M1).
function M.register_all()
   local registry = require("effects.boon_registry")
   for _, b in ipairs(BOONS) do
      registry.register(b)
   end
end

-- Test/utility: reset the catalog (forwards to registry.reset).
function M.reset()
   local registry = require("effects.boon_registry")
   registry.reset()
end

return M
