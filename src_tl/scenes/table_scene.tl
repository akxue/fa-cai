-- The deal table scene. Two modes share this rendering:
--   "run"   — seat 1 is the human player; click-driven UI.
--   "debug" — all four seats AI-driven; step/auto pacing, inspector
--             overlay, and a tile-conservation check after each
--             engine transition (F1 / T / S / R / ESC).

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.effect_types")
local rng_mod    = require("core.rng")
local engine     = require("game.deal_engine")
local run_state  = require("game.run_state")
local ai         = require("game.ai")
local td         = require("game.ting_distance")
local invariants = require("game.deal_invariants")
local validator  = require("game.hand_validator")
local fx_runner  = require("effects.effect_runner")
local wall_mod   = require("game.wall")
local content    = require("content.boons")
local boons_init = require("effects.boons.init")
local calls_mod  = require("game.calls")
local tile_render   = require("ui.tile_render")
local action_prompt = require("ui.action_prompt")
local info_panels   = require("ui.info_panels")
local clickable_mod = require("ui.clickable")
local panel         = require("ui.panel")
local button        = require("ui.button")
local scoring       = require("game.scoring")
local scene_stack   = require("app.scene_stack")

-- ── Tunables ──────────────────────────────────────────────────────────────

local AI_PACE_AUTO    <const> = 0.20    -- seconds between AI actions in auto mode
local DEFAULT_SEED    <const> = 42
local DEBUG_ROUND     <const> = 3       -- exercises Momentum opening surplus.
local LOG_MAX         <const> = 100
local LOG_VISIBLE     <const> = 22

-- ── Tile rendering helpers (live in ui/tile_render.tl) ──────────────────

local tile_label     = tile_render.tile_label
local sorted_indices = tile_render.sorted_indices

-- ── Scene state ──────────────────────────────────────────────────────────

local record LogEntry
   text: string
   kind: string   -- "ev" | "ai" | "err" | "sys"
end

local record DiscardItem
   seat: integer
   tile: Tile
end

local enum CachedOptsKind
   ""
   "reaction"
   "self"
end

local record SceneState
   seed:             integer
   deal:             DealState
   mode:             string    -- "debug" | "run"
   step_mode:        boolean
   wait_for_step:    boolean
   ai_pace_left:     number
   inspector_open:   boolean
   log:              {LogEntry}
   conservation_ok:  boolean
   conservation_msg: string
   ticks:            integer
   selected_opening_tile_ids: {TileId}
   last_reason_by_seat: {integer: AiReasoning}
   cursor_tile_id: TileId
   run_state: RunState
   clickables: {Clickable}
   -- Tick-keyed cache for compute_seat1_*_options. See options_cached.
   cached_opts_tick:   integer
   cached_opts_kind:   CachedOptsKind
   cached_opts_cursor: TileId
   cached_opts:        {ActionPromptOption}
   -- Tick-keyed cache for opening_action_by_payload("swap_tiles"). The
   -- enumeration of effect actions runs the full effect runner; without
   -- the cache it fires 3× per frame during opening_actions phase.
   cached_swap_tiles_tick: integer
   cached_swap_tiles_has:  boolean
end

local state: SceneState = nil

local function push_log(kind: string, text: string)
   state.log[#state.log + 1] = { text = text, kind = kind }
   while #state.log > LOG_MAX do
      table.remove(state.log, 1)
   end
end

local function check_conservation()
   local r = invariants.validate_tile_conservation(state.deal)
   state.conservation_ok = r.ok
   state.conservation_msg = r.ok and "OK" or (r.error .. ": " .. r.details)
   if not r.ok then
      push_log("err", "tile-conservation FAIL: " .. r.error)
   end
end

local function make_debug_run(seed: integer): RunState
   local rs = run_state.new_run(rng_mod.from_seed(seed))
   rs.round_index = DEBUG_ROUND
   -- Compact set that exercises opening_actions, Known Wall reveals,
   -- active-effect counters, and surplus trimming.
   rs.active_effects = {
      content.activate_for("fresh_start", 1),
      content.activate_for("third_eye", 1),
      content.activate_for("momentum", 1),
   }
   return rs
end

-- Set by an upstream scene (boon_select) and consumed by the next
-- reset(). When unset, reset() builds a debug RunState instead.
local pending_run: RunState = nil
local pending_seed: integer = 0
local has_pending: boolean = false

local function start_run(rs: RunState, seed: integer)
   pending_run = rs
   pending_seed = seed
   has_pending = true
end

local function reset(seed: integer)
   boons_init.reset_and_register_all()
   local rs: RunState
   local effective_seed = seed
   local mode = "debug"
   if has_pending then
      rs = pending_run
      effective_seed = pending_seed
      mode = "run"
      has_pending = false
      pending_run = nil
   else
      rs = make_debug_run(seed)
   end
   state = {
      seed             = effective_seed,
      deal             = engine.new_deal_with_run(rng_mod.from_seed(effective_seed), rs),
      mode             = mode,
      step_mode        = false,
      wait_for_step    = false,
      ai_pace_left     = AI_PACE_AUTO,
      inspector_open   = false,
      log              = {},
      conservation_ok  = true,
      conservation_msg = "OK",
      ticks            = 0,
      selected_opening_tile_ids = {},
      last_reason_by_seat = {},
      cursor_tile_id   = "" as TileId,
      run_state        = rs,
      clickables       = {},
      cached_opts_tick   = -1,
      cached_opts_kind   = "",
      cached_opts_cursor = "" as TileId,
      cached_opts        = {},
      cached_swap_tiles_tick = -1,
      cached_swap_tiles_has  = false,
   }
   push_log("sys", "deal opened (seed=" .. tostring(effective_seed) .. " mode=" .. mode .. ")")
   check_conservation()
end

-- ── Eligibility helpers for reaction window ──────────────────────────────

local function has_responded(deal: DealState, player_index: integer): boolean
   for _, pi in ipairs(deal.reaction_passes) do
      if pi == player_index then return true end
   end
   for _, c in ipairs(deal.pending_claims) do
      if c.player_index == player_index then return true end
   end
   return false
end

local function is_excluded(deal: DealState, player_index: integer): boolean
   if deal.has_pending_discard and deal.pending_discard.discarder == player_index then return true end
   if deal.has_pending_kong and deal.pending_added_kong.declarer == player_index then return true end
   return false
end

-- Picks the next reactor for the AI driver to advance. In run mode AI
-- reactors (seats 2-4) respond before the player so the visible reaction
-- order matches HK mahjong's priority: opponents declare Peng/Kong/Hu
-- first, and only after they pass does the next player get the Chi
-- prompt. The engine resolves correctly either way (pending_claims is
-- collected before resolve_window picks a winner), but offering the
-- player Chi too early caused confusion when an AI then queued a Peng
-- that won at resolve time.
local function next_eligible_reactor(deal: DealState): integer
   if state.mode == "run" then
      for i = 2, 4 do
         if not is_excluded(deal, i) and not has_responded(deal, i) then
            return i
         end
      end
      if not is_excluded(deal, 1) and not has_responded(deal, 1) then
         return 1
      end
      return 0
   end
   for i = 1, 4 do
      if not is_excluded(deal, i) and not has_responded(deal, i) then
         return i
      end
   end
   return 0
end

-- ── Opening-actions interaction ───────────────────────────────────────────

local function opening_action_by_payload(payload_kind: string): EffectAction, boolean
   local actions = fx_runner.collect_available_actions(state.deal, state.deal.dealer)
   for _, a in ipairs(actions) do
      if a.payload_kind == payload_kind then return a, true end
   end
   return {} as EffectAction, false
end

-- Tick-keyed cached predicate for "is the Fresh Start swap_tiles action
-- available?" The render path asks this 3× per frame in opening_actions
-- phase (hand row, center info, hint line); the cache collapses those
-- to a single effect-runner enumeration per tick.
local function has_swap_tiles_action(): boolean
   if state.cached_swap_tiles_tick == state.ticks then
      return state.cached_swap_tiles_has
   end
   local _, ok = opening_action_by_payload("swap_tiles")
   state.cached_swap_tiles_tick = state.ticks
   state.cached_swap_tiles_has  = ok
   return ok
end

local function clear_opening_selection()
   state.selected_opening_tile_ids = {}
end

local function toggle_opening_tile(slot: integer)
   if (state.deal.phase as string) ~= "opening_actions" then return end
   local tiles = state.deal.players[state.deal.dealer].hand.concealed_tiles
   local t = tiles[slot]
   if t == nil then return end
   local out: {TileId} = {}
   local removed = false
   for _, id in ipairs(state.selected_opening_tile_ids) do
      if id == t.tile_id then removed = true
      else out[#out + 1] = id end
   end
   if not removed then
      if #out >= 3 then
         push_log("sys", "Fresh Start can swap at most 3 tiles")
      else
         out[#out + 1] = t.tile_id
      end
   end
   state.selected_opening_tile_ids = out
end

local function apply_opening_transition(action: DealAction, label: string): boolean
   local tr = engine.apply_action(state.deal, action)
   if not tr.ok then
      push_log("err", label .. " failed: " .. tr.error)
      return false
   end
   state.deal = tr.deal
   push_log("sys", label)
   for _, e in ipairs(tr.events) do
      push_log("ev", e.message)
   end
   state.ticks = state.ticks + 1
   check_conservation()
   return true
end

local function use_fresh_start()
   if (state.deal.phase as string) ~= "opening_actions" then return end
   local act, ok = opening_action_by_payload("swap_tiles")
   if not ok then
      push_log("sys", "Fresh Start is not available")
      return
   end
   local ids: {TileId} = {}
   for _, id in ipairs(state.selected_opening_tile_ids) do ids[#ids + 1] = id end
   if apply_opening_transition(engine.use_effect_action(state.deal.dealer, act.active_effect_id, ids), "Fresh Start used") then
      clear_opening_selection()
   end
end

local function trim_opening_surplus()
   if (state.deal.phase as string) ~= "opening_actions" then return end
   local dealer = state.deal.dealer
   local hand = state.deal.players[dealer].hand.concealed_tiles
   if #hand <= 13 then
      push_log("sys", "no opening surplus to trim")
      return
   end
   local trim_id = hand[#hand].tile_id
   if #state.selected_opening_tile_ids > 0 then
      trim_id = state.selected_opening_tile_ids[1]
   end
   if apply_opening_transition(engine.discard_opening_surplus(dealer, trim_id), "trimmed opening surplus") then
      clear_opening_selection()
   end
end

local function confirm_opening()
   if (state.deal.phase as string) ~= "opening_actions" then return end
   if apply_opening_transition(engine.confirm_opening(state.deal.dealer), "opening confirmed") then
      clear_opening_selection()
   end
end

-- ── AI driver ─────────────────────────────────────────────────────────────

local function describe_reasoning(r: AiReasoning, seat: integer): string
   local body = "p" .. tostring(seat) .. " " .. r.tag .. ": " .. r.message
   if r.ting_before > -100 or r.ting_after > -100 then
      local b = r.ting_before > -100 and tostring(r.ting_before) or "-"
      local a = r.ting_after  > -100 and tostring(r.ting_after)  or "-"
      body = body .. " (ting " .. b .. "→" .. a .. ")"
   end
   if r.target ~= "" then
      body = body .. " [" .. r.target
      if r.est_fan >= 0 then
         body = body .. " est=" .. tostring(r.est_fan) .. "f"
      end
      if r.ukeire >= 0 then
         body = body .. " uke=" .. tostring(r.ukeire)
      end
      body = body .. "]"
   end
   return body
end

-- ── Seat-1 (player) input helpers ────────────────────────────────────────

local function seat1_can_react(d: DealState): boolean
   if (d.phase as string) ~= "reaction_window" then return false end
   if is_excluded(d, 1) then return false end
   if has_responded(d, 1) then return false end
   return true
end

-- Forward decls; bodies below.
local compute_seat1_reaction_options: function(d: DealState): {ActionPromptOption}
local options_cached:                 function(d: DealState, kind: CachedOptsKind): {ActionPromptOption}

local would_be_valid_hu = scoring.would_be_valid_hu

-- True when run mode and seat 1 must make a decision the AI shouldn't
-- make for them. The auto-advance path stops here. Skip the pause when
-- the only legal reaction is Pass — the AI driver auto-passes for
-- seat 1 in that case so the player isn't bothered. During the reaction
-- window we also wait for AI reactors (seats 2-4) to respond first;
-- that way the player's Chi prompt isn't shown only to be silently
-- overridden when an AI then queues a Peng. See next_eligible_reactor.
local function has_seat1_pending_input(d: DealState): boolean
   if state.mode ~= "run" then return false end
   local phase = d.phase as string
   if phase == "awaiting_action" and d.current_player == 1 then return true end
   if not seat1_can_react(d) then return false end
   for seat = 2, 4 do
      if not is_excluded(d, seat) and not has_responded(d, seat) then
         return false
      end
   end
   return #options_cached(d, "reaction") > 1
end

local function default_cursor_tile_id(d: DealState): TileId
   if d.has_last_drawn then return d.last_drawn_tile_id end
   local hand = d.players[1].hand.concealed_tiles
   if #hand > 0 then return hand[1].tile_id end
   return "" as TileId
end

local function ensure_cursor_valid()
   local hand = state.deal.players[1].hand.concealed_tiles
   if (state.cursor_tile_id as string) ~= "" then
      for _, t in ipairs(hand) do
         if t.tile_id == state.cursor_tile_id then return end
      end
   end
   state.cursor_tile_id = default_cursor_tile_id(state.deal)
end

local function cursor_slot(): integer
   local hand = state.deal.players[1].hand.concealed_tiles
   local idxs = sorted_indices(hand)
   for i, src in ipairs(idxs) do
      if hand[src].tile_id == state.cursor_tile_id then return i end
   end
   return 0
end

local function move_cursor(delta: integer)
   local hand = state.deal.players[1].hand.concealed_tiles
   if #hand == 0 then return end
   local slot = cursor_slot()
   if slot == 0 then slot = 1 end
   slot = slot + delta
   if slot < 1 then slot = #hand end
   if slot > #hand then slot = 1 end
   local idxs = sorted_indices(hand)
   state.cursor_tile_id = hand[idxs[slot]].tile_id
end

local function jump_cursor(slot: integer)
   local hand = state.deal.players[1].hand.concealed_tiles
   if slot < 1 or slot > #hand then return end
   local idxs = sorted_indices(hand)
   state.cursor_tile_id = hand[idxs[slot]].tile_id
end

function compute_seat1_reaction_options(d: DealState): {ActionPromptOption}
   local opts: {ActionPromptOption} = {}
   local p = d.players[1]
   local hand = p.hand.concealed_tiles

   -- Hu on a discard. Gate on would_be_valid_hu so the prompt never
   -- offers a click that the engine would reject (3-fan minimum).
   if d.has_pending_discard then
      local pd_tile = d.pending_discard.tile
      if would_be_valid_hu(d, 1, pd_tile, false, false) then
         opts[#opts + 1] = {
            key        = "h",
            label      = "Hu (claim " .. tile_label(pd_tile) .. ")",
            action     = engine.declare_hu(1, pd_tile.tile_id, false),
         }
      end
   end
   -- Hu on Qiang Gang (rob a kong upgrade)
   if d.has_pending_kong then
      local pk_tile = d.pending_added_kong.tile
      if would_be_valid_hu(d, 1, pk_tile, false, true) then
         opts[#opts + 1] = {
            key        = "h",
            label      = "Hu / Qiang Gang " .. tile_label(pk_tile),
            action     = engine.declare_hu(1, pk_tile.tile_id, false),
         }
      end
   end
   -- Peng / Open Kong / Chi only on a real discard
   if d.has_pending_discard then
      local pd = d.pending_discard
      if calls_mod.can_peng(pd.tile, hand, pd.discarder, 1) then
         opts[#opts + 1] = {
            key        = "p",
            label      = "Peng " .. tile_label(pd.tile),
            action     = engine.declare_peng(1, pd.tile.tile_id),
         }
      end
      if calls_mod.can_open_kong(pd.tile, hand, pd.discarder, 1) then
         opts[#opts + 1] = {
            key        = "k",
            label      = "Open Kong " .. tile_label(pd.tile),
            action     = engine.declare_open_kong(1, pd.tile.tile_id),
         }
      end
      -- Chi is the lowest reaction priority and loses to any other
      -- queued claim. By the time seat 1 is prompted, AI reactors have
      -- already responded (see has_seat1_pending_input), so a non-empty
      -- pending_claims list means a higher-priority claim is locked in.
      -- Hiding Chi here prevents the player from clicking it just to
      -- watch the engine pick the AI's Peng/Kong/Hu instead.
      if #d.pending_claims == 0 and calls_mod.is_next_player(pd.discarder, 1, 4) then
         local combos = calls_mod.chi_combinations(pd.tile, hand)
         if #combos > 0 then
            opts[#opts + 1] = {
               key        = "c",
               label      = "Chi " .. tile_label(pd.tile),
               action     = engine.declare_chi(1, pd.tile.tile_id, combos[1]),
            }
         end
      end
   end
   -- Pass is always offered while seat 1 is eligible
   opts[#opts + 1] = {
      key        = "x",
      label      = "Pass",
      action     = engine.pass_reaction(1),
   }
   return opts
end

-- Self-turn options for seat 1 in awaiting_action: Zi Mo / Concealed
-- Kong / Added Kong / Discard.
local function compute_seat1_self_options(d: DealState): {ActionPromptOption}
   local opts: {ActionPromptOption} = {}
   local p = d.players[1]
   local hand = p.hand.concealed_tiles

   -- Zi Mo Hu using the last drawn tile (gated on fan threshold).
   if d.has_last_drawn then
      local last_id = d.last_drawn_tile_id
      local last_tile: Tile = nil
      for _, t in ipairs(hand) do
         if t.tile_id == last_id then last_tile = t; break end
      end
      if last_tile ~= nil and would_be_valid_hu(d, 1, last_tile, true, false) then
         opts[#opts + 1] = {
            key        = "h",
            label      = "Hu / Zi Mo " .. tile_label(last_tile),
            action     = engine.declare_hu(1, last_id, true),
         }
      end
   end

   -- Concealed Kong: any kind with 4 copies in hand (sorted for determinism).
   local kind_count: {string:integer} = {}
   for _, t in ipairs(hand) do
      local k = t.kind_id as string
      kind_count[k] = (kind_count[k] or 0) + 1
   end
   local quad_kinds: {string} = {}
   for k, n in pairs(kind_count) do
      if n >= 4 then quad_kinds[#quad_kinds + 1] = k end
   end
   table.sort(quad_kinds)
   if #quad_kinds > 0 then
      opts[#opts + 1] = {
         key        = "k",
         label      = "Concealed Kong (" .. quad_kinds[1] .. ")",
         action     = engine.declare_concealed_kong(1, quad_kinds[1] as TileKindId),
      }
   end

   -- Added Kong: a tile in hand whose kind matches an open peng.
   local peng_kinds: {string:boolean} = {}
   for _, s in ipairs(p.hand.sets) do
      if (s.kind as string) == "peng" and (s.visibility as string) == "open" and #s.tiles > 0 then
         peng_kinds[s.tiles[1].kind_id as string] = true
      end
   end
   for _, src in ipairs(sorted_indices(hand)) do
      local t = hand[src]
      if peng_kinds[t.kind_id as string] then
         opts[#opts + 1] = {
            key        = "u",
            label      = "Added Kong " .. tile_label(t),
            action     = engine.declare_added_kong(1, t.tile_id),
         }
         break
      end
   end

   -- Discard the cursor tile. The button doubles as the confirm step
   -- for two-click discarding: clicking a tile in the hand sets it as
   -- the cursor; clicking this button (or clicking the cursored tile
   -- again) commits the discard.
   if (state.cursor_tile_id as string) ~= "" then
      local cursor_tile: Tile = nil
      for _, t in ipairs(hand) do
         if t.tile_id == state.cursor_tile_id then cursor_tile = t; break end
      end
      if cursor_tile ~= nil then
         opts[#opts + 1] = {
            key    = "d",
            label  = "Discard " .. tile_label(cursor_tile),
            action = engine.discard(1, state.cursor_tile_id),
         }
      end
   end
   return opts
end

-- Tick-keyed cache. compute_seat1_*_options runs find_win_shapes +
-- scorer + boon modifiers per Hu candidate; without the cache it fires
-- 3-5 times per frame in M.update / M.draw / draw_hints. The result
-- only changes on engine transitions (ticks bump) or, for "self", when
-- the cursor moves.
function options_cached(d: DealState, kind: CachedOptsKind): {ActionPromptOption}
   local cursor = state.cursor_tile_id
   if state.cached_opts_tick == state.ticks
      and state.cached_opts_kind == kind
      and (kind ~= "self" or state.cached_opts_cursor == cursor)
   then
      return state.cached_opts
   end
   if kind == "reaction" then
      state.cached_opts = compute_seat1_reaction_options(d)
   else
      state.cached_opts = compute_seat1_self_options(d)
   end
   state.cached_opts_tick   = state.ticks
   state.cached_opts_kind   = kind
   state.cached_opts_cursor = cursor
   return state.cached_opts
end

local function apply_player_action(action: DealAction, label: string): boolean
   local d = state.deal
   local phase = d.phase as string
   local tr = engine.apply_action(d, action)
   if not tr.ok then
      push_log("err", "player " .. label .. " failed at " .. phase .. ": " .. tr.error)
      return false
   end
   state.deal = tr.deal
   push_log("sys", "player p1 " .. label)
   for _, e in ipairs(tr.events) do
      push_log("ev", e.message)
   end
   state.ticks = state.ticks + 1
   check_conservation()
   return true
end

-- Pump one AI action. Returns true if state advanced.
local function advance_one_action(): boolean
   local d = state.deal
   local phase = d.phase as string
   if phase == "deal_over" then return false end

   local seat = 0
   local action: DealAction = nil
   local reason: AiReasoning = nil

   if phase == "opening_actions" then
      return false
   end

   if phase == "awaiting_draw" or phase == "awaiting_action" then
      seat = d.current_player
      action, reason = ai.decide_main(d, seat)
   elseif phase == "reaction_window" then
      seat = next_eligible_reactor(d)
      if seat == 0 then
         push_log("err", "reaction window with no eligible reactor")
         return false
      end
      action, reason = ai.decide_reaction(d, seat)
   else
      return false
   end

   local tr = engine.apply_action(d, action)
   if not tr.ok then
      push_log("err", "apply_action failed at " .. phase .. " seat " .. tostring(seat) .. ": " .. tr.error)
      return false
   end
   state.deal = tr.deal
   state.last_reason_by_seat[seat] = reason
   push_log("ai", describe_reasoning(reason, seat))
   for _, e in ipairs(tr.events) do
      push_log("ev", e.message)
   end
   state.ticks = state.ticks + 1
   check_conservation()
   return true
end

-- ── LÖVE lifecycle ────────────────────────────────────────────────────────

local function on_load()
   reset(DEFAULT_SEED)
end

local function on_update(dt: number)
   if state.deal == nil then return end
   if (state.deal.phase as string) == "deal_over" then
      if state.mode == "run" then
         scene_stack.fire_deal_over(state.deal, state.run_state)
      end
      return
   end
   if state.step_mode and state.wait_for_step then return end
   if has_seat1_pending_input(state.deal) then
      ensure_cursor_valid()
      return
   end

   state.ai_pace_left = state.ai_pace_left - dt
   if state.ai_pace_left > 0 then return end
   state.ai_pace_left = AI_PACE_AUTO

   local advanced = advance_one_action()
   if not advanced then return end
   if state.step_mode then state.wait_for_step = true end
end

local function on_mousepressed(x: number, y: number, mouse_button: integer)
   if mouse_button ~= 1 then return end
   if state.deal == nil then return end
   local hit = clickable_mod.find(state.clickables, x, y)
   if hit ~= nil then hit.callback() end
end

local function on_keypressed(key: string)
   if key == "escape" then
      -- Abandon the deal and return to the title screen. Mirrors the
      -- "Quit run" button on result_scene — no life is decremented; the
      -- run is simply discarded. ESC quitting the application from
      -- mid-deal was the legacy debug-table behavior; it surprised
      -- players who expected ESC to mean "back/cancel."
      scene_stack.fire_back_to_start()
      return
   end
   if key == "f1" then
      state.inspector_open = not state.inspector_open
      push_log("sys", "inspector " .. (state.inspector_open and "ON" or "OFF"))
      return
   end
   if key == "t" then
      state.step_mode = not state.step_mode
      state.wait_for_step = false
      push_log("sys", "step mode " .. (state.step_mode and "ON" or "OFF"))
      return
   end
   if key == "s" then
      if state.step_mode then
         state.wait_for_step = false
         state.ai_pace_left = 0
      end
      return
   end
   if key == "r" then
      reset(state.seed)
      return
   end
   if (state.deal.phase as string) == "opening_actions" then
      local slot = tonumber(key)
      if slot ~= nil and slot >= 1 and slot <= 9 then
         toggle_opening_tile(slot as integer)
         return
      end
      if key == "0" then
         toggle_opening_tile(10)
         return
      end
      if key == "u" then
         use_fresh_start()
         return
      end
      if key == "x" then
         trim_opening_surplus()
         return
      end
      if key == "c" then
         confirm_opening()
         return
      end
   end

   if not has_seat1_pending_input(state.deal) then return end
   ensure_cursor_valid()
   local d = state.deal
   local phase = d.phase as string

   -- Cursor navigation (own-turn discard only)
   if phase == "awaiting_action" and d.current_player == 1 then
      if key == "left" then move_cursor(-1); return end
      if key == "right" then move_cursor(1); return end
      local n = tonumber(key)
      if n ~= nil and n >= 1 and n <= 9 then jump_cursor(n as integer); return end
      if key == "0" then jump_cursor(10); return end
      if key == "q" then jump_cursor(11); return end
      if key == "w" then jump_cursor(12); return end
      if key == "e" then jump_cursor(13); return end
      if key == "r" then jump_cursor(14); return end
   end

   local opts = options_cached(d, phase == "reaction_window" and "reaction" or "self")
   for _, opt in ipairs(opts) do
      if key == opt.key then
         apply_player_action(opt.action, opt.label)
         return
      end
   end
end

-- ── Drawing ───────────────────────────────────────────────────────────────

local SEAT_NAMES: {string} = { "East (P1)", "South (P2)", "West (P3)", "North (P4)" }

-- Per-seat discard color (used to tint each tile's border in the center
-- discard pile so players can see at a glance who threw what).
local record SeatColor
   r: number
   g: number
   b: number
end
local SEAT_COLORS: {SeatColor} = {
   { r = 0.42, g = 0.62, b = 0.95 },  -- P1 East   = blue (you)
   { r = 0.95, g = 0.45, b = 0.40 },  -- P2 South  = red
   { r = 0.55, g = 0.85, b = 0.50 },  -- P3 West   = green
   { r = 0.95, g = 0.85, b = 0.40 },  -- P4 North  = gold
}

local function draw_text(text: string, x: number, y: number)
   love.graphics.print(text, x, y)
end

-- Prints `text` wrapped to `limit` pixels wide and returns the height used.
-- Use this for hand/sets/discards/log entries that can grow past their panel
-- and get painted over by adjacent panels.
local function draw_text_wrapped(text: string, x: number, y: number, limit: number): number
   if limit < 16 then limit = 16 end
   love.graphics.printf(text, x, y, limit, "left")
   local font = love.graphics.getFont()
   local _w, lines = font:getWrap(text, limit)
   local n = #lines
   if n < 1 then n = 1 end
   return n * font:getHeight()
end

local draw_panel = panel.draw

local function opening_selection_label(): string
   if #state.selected_opening_tile_ids == 0 then return "(none)" end
   local labels: {string} = {}
   local hand = state.deal.players[state.deal.dealer].hand.concealed_tiles
   for _, id in ipairs(state.selected_opening_tile_ids) do
      for _, t in ipairs(hand) do
         if t.tile_id == id then
            labels[#labels + 1] = tile_label(t)
            break
         end
      end
   end
   return table.concat(labels, " ")
end

local function ting_for(seat_index: integer): integer
   local p = state.deal.players[seat_index]
   local live = ai.compute_live_counts(state.deal, seat_index)
   return td.ting_distance_live(p.hand.concealed_tiles, p.hand.sets, live)
end

-- Friendly label: -1 → "TING (live)", N → "(N+1)t away", high N → "dead".
local function ting_label(seat_index: integer): string
   local t = ting_for(seat_index)
   if t >= 90 then return "dead" end
   if t == -1 then return "TING" end
   return string.format("%dt away", t + 1)
end

-- Toggle a tile in the Fresh Start swap selection by tile_id (used by
-- click handling, since visual order is sorted while toggle_opening_tile
-- uses storage-order slots).
local function toggle_opening_tile_by_id(tile_id: TileId)
   if (state.deal.phase as string) ~= "opening_actions" then return end
   local out: {TileId} = {}
   local removed = false
   for _, id in ipairs(state.selected_opening_tile_ids) do
      if id == tile_id then
         removed = true
      else
         out[#out + 1] = id
      end
   end
   if not removed then
      if #out >= 3 then
         push_log("sys", "Fresh Start can swap at most 3 tiles")
      else
         out[#out + 1] = tile_id
      end
   end
   state.selected_opening_tile_ids = out
end

local function title_with_marker(seat_index: integer): string
   local d = state.deal
   local is_current = (d.current_player == seat_index) and (d.phase as string) ~= "deal_over"
   local title = SEAT_NAMES[seat_index]
   if is_current then title = "▶ " .. title end
   return title
end

-- Opponent hand renderers. Tiles are face-down by default; if the F1
-- inspector is on we reveal them so the developer can see the actual
-- hand. Horizontal variant for top seats (P3), vertical for side seats
-- (P2 right, P4 left).

local function draw_opponent_hand_row(seat_index: integer, x: number, y: number, w: number, h: number)
   local p = state.deal.players[seat_index]
   draw_panel(x, y, w, h, title_with_marker(seat_index))
   local n = #p.hand.concealed_tiles
   if n == 0 then return end

   local pad = 8
   local gap = 2
   local avail = w - 2 * pad
   local tile_w = math.min(28, (avail - gap * (n - 1)) / n)
   if tile_w < 12 then tile_w = 12 end
   local tile_h = h - 22
   if tile_h > tile_w * 1.5 then tile_h = math.floor(tile_w * 1.5) end
   local row_w = tile_w * n + gap * (n - 1)
   local start_x = x + pad + math.max(0, (avail - row_w) / 2)
   local row_y = y + 18

   if state.inspector_open then
      local idxs = sorted_indices(p.hand.concealed_tiles)
      for slot, src in ipairs(idxs) do
         local t = p.hand.concealed_tiles[src]
         local tx = start_x + (slot - 1) * (tile_w + gap)
         tile_render.draw_tile_box(t, tx, row_y, tile_w, tile_h, 0.92, 0.90, 0.82, 0.55, 0.50, 0.40)
      end
   else
      for i = 1, n do
         local tx = start_x + (i - 1) * (tile_w + gap)
         tile_render.draw_facedown_box(tx, row_y, tile_w, tile_h)
      end
   end
end

local function draw_opponent_hand_col(seat_index: integer, x: number, y: number, w: number, h: number)
   local p = state.deal.players[seat_index]
   draw_panel(x, y, w, h, title_with_marker(seat_index))
   local n = #p.hand.concealed_tiles
   if n == 0 then return end

   local pad = 8
   local gap = 2
   local avail = h - 22 - pad
   local tile_h = math.min(20, (avail - gap * (n - 1)) / n)
   if tile_h < 10 then tile_h = 10 end
   local tile_w = w - 14
   local col_h = tile_h * n + gap * (n - 1)
   local start_y = y + 22 + math.max(0, (avail - col_h) / 2)

   if state.inspector_open then
      local idxs = sorted_indices(p.hand.concealed_tiles)
      for slot, src in ipairs(idxs) do
         local t = p.hand.concealed_tiles[src]
         local ty = start_y + (slot - 1) * (tile_h + gap)
         tile_render.draw_tile_box(t, x + 7, ty, tile_w, tile_h, 0.92, 0.90, 0.82, 0.55, 0.50, 0.40)
      end
   else
      for i = 1, n do
         local ty = start_y + (i - 1) * (tile_h + gap)
         tile_render.draw_facedown_box(x + 7, ty, tile_w, tile_h)
      end
   end
end

-- Open-sets strips (formerly "public" strips). Discards live in the
-- central pile now; these only show open sets next to each player so
-- claimed groupings are visible adjacent to the seat that owns them.

local function draw_seat_open_sets_row(seat_index: integer, x: number, y: number, w: number, h: number)
   draw_panel(x, y, w, h, "")
   local p = state.deal.players[seat_index]
   if #p.hand.sets == 0 then return end
   local pad = 8
   local gap = 2
   local set_gap = 10
   local tile_w = 22
   local tile_h = h - 14
   local cx = x + pad
   local row_y = y + 8
   for _, s in ipairs(p.hand.sets) do
      for _, t in ipairs(s.tiles) do
         tile_render.draw_tile_box(t, cx, row_y, tile_w, tile_h, 0.86, 0.92, 0.86, 0.40, 0.55, 0.45)
         cx = cx + tile_w + gap
      end
      cx = cx + set_gap
   end
end

local function draw_seat_open_sets_col(seat_index: integer, x: number, y: number, w: number, h: number)
   draw_panel(x, y, w, h, "")
   local p = state.deal.players[seat_index]
   if #p.hand.sets == 0 then return end
   local pad = 8
   local gap = 2
   local set_gap = 8
   local tile_w = w - 14
   local tile_h = 22
   local cx = x + 7
   local cy = y + 8
   for _, s in ipairs(p.hand.sets) do
      for _, t in ipairs(s.tiles) do
         if cy + tile_h > y + h - pad then return end
         tile_render.draw_tile_box(t, cx, cy, tile_w, tile_h, 0.86, 0.92, 0.86, 0.40, 0.55, 0.45)
         cy = cy + tile_h + gap
      end
      cy = cy + set_gap
   end
end

-- Center discard pile. Iterates discards round-robin (P1[i], P2[i],
-- P3[i], P4[i], P1[i+1], …) so the draw-order approximates the actual
-- chronology — later tiles render on top of earlier ones, like a real
-- pile. Each tile lands at a deterministic pseudo-random offset within
-- a bounded pile region so tiles cluster and overlap; the border color
-- still identifies the discarder.
local function draw_center_discard_pile(x: number, y: number, w: number, h: number)
   love.graphics.setColor(0.13, 0.16, 0.18, 1.0)
   love.graphics.rectangle("fill", x, y, w, h)
   love.graphics.setColor(0.30, 0.32, 0.36, 1.0)
   love.graphics.rectangle("line", x, y, w, h)

   local d = state.deal
   local max_n = 0
   for seat = 1, 4 do
      local k = #d.players[seat].hand.discards
      if k > max_n then max_n = k end
   end
   if max_n == 0 then
      love.graphics.setColor(0.45, 0.45, 0.50, 1.0)
      love.graphics.print("(no discards yet)", x + 14, y + 12)
      return
   end

   -- Round-robin interleave for an approximately-chronological order.
   local items: {DiscardItem} = {}
   for i = 1, max_n do
      for seat = 1, 4 do
         local list = d.players[seat].hand.discards
         if i <= #list then
            items[#items + 1] = { seat = seat, tile = list[i] }
         end
      end
   end

   -- Pile region: a centered rectangle smaller than the full panel so
   -- tiles cluster rather than spread to the edges. Scaled to the
   -- shorter dimension so the pile looks compact and "thrown" rather
   -- than orderly.
   local tile_w = 30
   local tile_h = 38
   local pile_w = math.min(w - 24, 480)
   local pile_h = math.min(h - 24, 280)
   local pile_cx = x + w / 2
   local pile_cy = y + h / 2
   local span_x = pile_w / 2 - tile_w / 2
   local span_y = pile_h / 2 - tile_h / 2

   for i, item in ipairs(items) do
      -- Hash incorporates the chronological index so identical tile
      -- copies (the wall has 4 of each kind) land in different spots.
      local s = item.tile.tile_id as string
      local h1 = i * 257
      local h2 = i * 263
      for j = 1, #s do
         h1 = (h1 * 31 + s:byte(j)) % 65536
         h2 = (h2 * 37 + s:byte(j)) % 65536
      end
      local fx = (h1 / 65535) - 0.5  -- in [-0.5, 0.5]
      local fy = (h2 / 65535) - 0.5
      local tx = pile_cx + fx * 2 * span_x - tile_w / 2
      local ty = pile_cy + fy * 2 * span_y - tile_h / 2

      local color = SEAT_COLORS[item.seat]
      tile_render.draw_tile_box(item.tile, tx, ty, tile_w, tile_h,
         0.94, 0.92, 0.84, color.r, color.g, color.b)
   end
end

-- Player hand row. Renders seat 1's concealed tiles as boxes and
-- registers a Clickable per tile so single-clicks discard during
-- awaiting_action (or toggle Fresh Start selection during
-- opening_actions). The keyboard cursor highlight (orange border) and
-- Fresh Start selection highlight (yellow border) still draw so the
-- keyboard fallback flow remains discoverable.
local function draw_player_hand_row(x: number, y: number, w: number, h: number)
   draw_panel(x, y, w, h, "Your Hand")
   local d = state.deal
   local p = d.players[1]
   local tiles = p.hand.concealed_tiles
   local n = #tiles
   if n == 0 then return end

   local pad_x = 12
   local pad_y = 28
   local gap = 4
   local avail_w = w - pad_x * 2
   local avail_h = h - pad_y - 8
   local tile_w_calc = (avail_w - gap * (n - 1)) / n
   local tile_w = math.min(48, tile_w_calc)
   if tile_w < 16 then tile_w = 16 end
   local tile_h = math.min(56, avail_h)
   if tile_h < 24 then tile_h = 24 end

   local row_w = tile_w * n + gap * (n - 1)
   local start_x = x + pad_x + math.max(0, (avail_w - row_w) / 2)
   local row_y = y + pad_y

   local phase = d.phase as string
   local can_click_discard = state.mode == "run"
      and phase == "awaiting_action"
      and d.current_player == 1
   -- Tile click in opening_actions only toggles Fresh Start selection
   -- when the Fresh Start swap_tiles action is actually available
   -- (i.e., the player took the Fresh Start boon and hasn't used it).
   local can_click_swap = phase == "opening_actions" and has_swap_tiles_action()

   local idxs = sorted_indices(tiles)
   for slot, src_i in ipairs(idxs) do
      local t = tiles[src_i]
      local tx = start_x + (slot - 1) * (tile_w + gap)
      local fr, fg, fb = 0.92, 0.90, 0.82
      local br, bg, bb = 0.55, 0.50, 0.40
      local selected = false
      for _, id in ipairs(state.selected_opening_tile_ids) do
         if id == t.tile_id then selected = true; break end
      end
      local is_cursor = (state.cursor_tile_id as string) ~= ""
         and t.tile_id == state.cursor_tile_id
         and can_click_discard
      if selected then
         br, bg, bb = 1.00, 0.90, 0.30
      end
      if is_cursor then
         fr, fg, fb = 1.00, 0.97, 0.78
         br, bg, bb = 1.00, 0.55, 0.20
      end
      tile_render.draw_tile_box(t, tx, row_y, tile_w, tile_h, fr, fg, fb, br, bg, bb)

      if can_click_discard then
         -- Two-click confirm: a click on a non-selected tile sets it as
         -- the cursor (highlight); a click on the already-cursored tile
         -- commits the discard. The action prompt's "Discard …" row
         -- offers a redundant click target.
         local tid = t.tile_id
         state.clickables[#state.clickables + 1] = {
            x = tx, y = row_y, w = tile_w, h = tile_h,
            callback = function()
               if state.cursor_tile_id == tid then
                  apply_player_action(engine.discard(1, tid), "discard " .. (tid as string))
               else
                  state.cursor_tile_id = tid
               end
            end,
         }
      elseif can_click_swap then
         local tid = t.tile_id
         state.clickables[#state.clickables + 1] = {
            x = tx, y = row_y, w = tile_w, h = tile_h,
            callback = function() toggle_opening_tile_by_id(tid) end,
         }
      end
   end
end

local function draw_status_bar(x: number, y: number, w: number)
   local d = state.deal
   local phase = d.phase as string
   local wall_left = wall_mod.remaining(d.wall)
   local current = "p" .. tostring(d.current_player)
   local mode = state.step_mode and "STEP" or "AUTO"
   local s = string.format("seed=%d  phase=%s  current=%s  wall=%d  ticks=%d  mode=%s",
      state.seed, phase, current, wall_left, state.ticks, mode)
   draw_panel(x, y, w, 24, "")
   love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
   draw_text(s, x + 8, y + 4)
end

-- Center info panel. Shows current turn / phase / wall on the first
-- line and any pending discard, kong, or deal-over banner below. In
-- opening_actions phase shows clickable buttons for the actually-
-- available actions (Use Fresh Start, Trim surplus, Confirm) — the
-- panel never advertises Fresh Start unless the boon is active.
local function draw_button(label: string, x: number, y: number, w: number, h: number, accent_r: number, accent_g: number, accent_b: number, callback: function())
   button.draw(label, x, y, w, h, accent_r, accent_g, accent_b, state.clickables, callback)
end

local function draw_center_info(x: number, y: number, w: number, h: number)
   draw_panel(x, y, w, h, "")
   local d = state.deal
   local tx = x + 12
   local ty = y + 10

   if (d.phase as string) == "opening_actions" then
      local has_fresh_start = has_swap_tiles_action()
      local surplus = #d.players[d.dealer].hand.concealed_tiles - 13

      love.graphics.setColor(1.0, 0.92, 0.40, 1.0)
      draw_text("Opening Setup", tx, ty); ty = ty + 22
      love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
      if has_fresh_start then
         draw_text("Fresh Start: click tiles in your hand to mark up to 3 for swap.", tx, ty); ty = ty + 16
         love.graphics.setColor(0.65, 0.65, 0.70, 1.0)
         draw_text("selected: " .. opening_selection_label(), tx, ty); ty = ty + 18
      else
         love.graphics.setColor(0.65, 0.65, 0.70, 1.0)
         draw_text("No setup actions available — click Confirm to begin play.", tx, ty); ty = ty + 18
      end

      local btn_w = 200
      local btn_h = 30
      local btn_x = tx
      local btn_y = ty + 6
      if has_fresh_start then
         draw_button("Use Fresh Start", btn_x, btn_y, btn_w, btn_h, 0.55, 0.85, 0.55,
            function() use_fresh_start() end)
         btn_y = btn_y + btn_h + 6
      end
      if surplus > 0 then
         draw_button("Trim opening (" .. tostring(surplus) .. " extra)", btn_x, btn_y, btn_w, btn_h, 1.00, 0.75, 0.40,
            function() trim_opening_surplus() end)
         btn_y = btn_y + btn_h + 6
      else
         draw_button("Confirm and begin play", btn_x, btn_y, btn_w, btn_h, 1.00, 0.92, 0.40,
            function() confirm_opening() end)
      end
      return
   end

   love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
   draw_text(string.format("Turn: P%d   Phase: %s   Wall: %d",
      d.current_player, d.phase as string, wall_mod.remaining(d.wall)), tx, ty)
   ty = ty + 20

   if d.has_pending_discard then
      love.graphics.setColor(1.00, 0.85, 0.45, 1.0)
      draw_text(string.format("Pending discard: %s by P%d",
         tile_label(d.pending_discard.tile), d.pending_discard.discarder), tx, ty)
      ty = ty + 18
   end
   if d.has_pending_kong then
      love.graphics.setColor(1.00, 0.85, 0.45, 1.0)
      draw_text(string.format("Pending added kong by P%d", d.pending_added_kong.declarer), tx, ty)
      ty = ty + 18
   end
   if d.has_deal_result then
      local res = d.deal_result
      love.graphics.setColor(0.65, 0.85, 1.00, 1.0)
      if res.winner_player_index == -1 then
         draw_text("DEAL OVER — wall exhaustion (no winner)", tx, ty); ty = ty + 16
      else
         local zm = res.won_by_zi_mo and " (zi mo)" or ""
         draw_text(string.format("DEAL OVER — P%d wins%s", res.winner_player_index, zm), tx, ty); ty = ty + 16
      end
   end
end

local function draw_log(x: number, y: number, w: number, h: number)
   draw_panel(x, y, w, h, "Log")
   local start = math.max(1, #state.log - LOG_VISIBLE + 1)
   local ty = y + 22
   local limit = w - 16
   local bottom = y + h - 4
   for i = start, #state.log do
      if ty >= bottom then break end
      local e = state.log[i]
      if e.kind == "err" then
         love.graphics.setColor(1.0, 0.55, 0.55, 1.0)
      elseif e.kind == "ai" then
         love.graphics.setColor(0.65, 0.85, 1.0, 1.0)
      elseif e.kind == "sys" then
         love.graphics.setColor(0.85, 0.85, 0.55, 1.0)
      else
         love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
      end
      ty = ty + draw_text_wrapped(e.text, x + 8, ty, limit)
   end
end

local function draw_score_candidates_for(seat: integer, x: number, y: number): number
   local d = state.deal
   local p = d.players[seat]
   if ting_for(seat) > -1 then return y end
   for i = 1, math.min(8, #d.wall.tiles) do
      local incoming = d.wall.tiles[i]
      local shapes = validator.find_win_shapes(p.hand.concealed_tiles, incoming, p.hand.sets)
      if #shapes > 0 then
         local valid, final = scoring.evaluate_hu(d, seat, p.hand.concealed_tiles, incoming, false, false, false)
         draw_text(string.format("    cand: +%s → fan=%d valid=%s", tile_label(incoming), final.total_fan, tostring(valid)), x, y)
         y = y + 14
      end
   end
   return y
end

local function draw_inspector(x: number, y: number, w: number, h: number)
   draw_panel(x, y, w, h, "Inspector (F1)")
   local d = state.deal
   local tx = x + 8
   local ty = y + 22

   draw_text(string.format("seed=%d  ticks=%d  step=%s",
      state.seed, state.ticks, tostring(state.step_mode)), tx, ty); ty = ty + 16

   local cons_color = state.conservation_ok and "OK" or "FAIL"
   draw_text("tile conservation: " .. cons_color, tx, ty); ty = ty + 16
   if not state.conservation_ok then
      draw_text("  " .. state.conservation_msg, tx, ty); ty = ty + 16
   end

   draw_text("known wall (player): " .. tostring(#d.players[1].known_wall_tile_ids) .. " tiles", tx, ty); ty = ty + 16

   draw_text("active effects: " .. tostring((function(): integer
      local n = 0
      for _ in pairs(d.effect_states) do n = n + 1 end
      return n
   end)()), tx, ty); ty = ty + 16

   ty = ty + 6
   draw_text("score candidates near ting:", tx, ty); ty = ty + 16
   for seat = 1, 4 do
      local t = ting_for(seat)
      draw_text(string.format("  p%d %s", seat, ting_label(seat)), tx, ty); ty = ty + 14
      if t == -1 then
         ty = draw_score_candidates_for(seat, tx, ty)
      end
   end

   -- AI candidate top-K per seat. Discard path produces rich top-3
   -- alternatives; call paths show a single chosen candidate.
   ty = ty + 6
   draw_text("AI candidates (last decision):", tx, ty); ty = ty + 16
   for seat = 1, 4 do
      local r = state.last_reason_by_seat[seat]
      if r ~= nil and #r.candidates > 0 then
         draw_text(string.format("  p%d %s [%s]", seat, r.tag, r.target ~= "" and r.target or "-"), tx, ty); ty = ty + 14
         for i, c in ipairs(r.candidates) do
            local label = c.tag
            if c.tag == "discard" then
               local da = c.action as DiscardAction
               label = "discard " .. (da.tile_id as string)
            end
            local marker = (i == 1) and "★" or " "
            local fan = (c.expected_fan >= 0) and tostring(c.expected_fan) or "-"
            local uke = (c.ukeire_after >= 0) and tostring(c.ukeire_after) or "-"
            local ting_a = (c.ting_after > -100) and tostring(c.ting_after) or "-"
            local status = c.accepted and "" or (" reject=" .. c.rejection_reason)
            draw_text(string.format("    %s %s ting=%s uke=%s fan=%s%s", marker, label, ting_a, uke, fan, status), tx, ty)
            ty = ty + 14
         end
      else
         draw_text(string.format("  p%d (no decision yet)", seat), tx, ty); ty = ty + 14
      end
   end
end

local function draw_hints(x: number, y: number)
   love.graphics.setColor(0.65, 0.65, 0.70, 1.0)
   if (state.deal.phase as string) == "opening_actions" then
      if has_swap_tiles_action() then
         draw_text("Click tiles to mark for swap   /   click Use Fresh Start, then Confirm   /   F1 debug   ESC menu", x, y)
      else
         draw_text("Click Confirm to begin play   /   F1 debug   ESC menu", x, y)
      end
   elseif state.mode == "run" and has_seat1_pending_input(state.deal) then
      if (state.deal.phase as string) == "awaiting_action" and state.deal.current_player == 1 then
         draw_text("Click a tile to select, click again to discard   /   buttons: Hu / Kong / Discard   /   F1 debug   ESC menu", x, y)
      else
         draw_text("Click an action button   /   keys: H P K C X   /   F1 debug   ESC menu", x, y)
      end
   else
      draw_text("F1 debug overlay   /   T step  S advance  R restart   /   ESC menu", x, y)
   end
end

local function dispatch_option(opt: ActionPromptOption)
   apply_player_action(opt.action, opt.label)
end

local function on_draw()
   love.graphics.setBackgroundColor(0.10, 0.10, 0.12, 1.0)
   local sw = love.graphics.getWidth()
   local sh = love.graphics.getHeight()

   -- Keep the cursor pointing at a real tile; this also runs in update
   -- and keypressed but we re-check here so click-only flows have a
   -- valid cursor when the prompt panel renders the Discard button.
   if has_seat1_pending_input(state.deal) then ensure_cursor_valid() end

   -- Reset clickables; populated by draw helpers below.
   state.clickables = {}

   local margin = 8
   local hint_h = 20
   local status_h = 24

   -- Right side panel (log + inspector) is hidden in run mode unless F1
   -- toggles it, and always shown in debug mode.
   local show_debug_panel = state.mode == "debug" or state.inspector_open
   local right_w = show_debug_panel and 360 or 0
   local right_x = sw - right_w - margin

   draw_status_bar(margin, margin, sw - 2 * margin)

   local table_x = margin
   local table_y = margin + status_h + margin
   local table_w = sw - 2 * margin - (right_w > 0 and right_w + margin or 0)
   local table_h = sh - table_y - hint_h - margin

   -- Edge thicknesses
   local edge_short  = 56  -- opponent hand strip
   local public_short = 48  -- discards + open-sets strip
   local p1_hand_h   = 96  -- player hand strip (face-up)
   local p1_public_h = 56

   -- P3 (top): hand row, then open-sets row below it.
   local p3_hand_y   = table_y
   local p3_public_y = p3_hand_y + edge_short + 4
   draw_opponent_hand_row(3, table_x, p3_hand_y, table_w, edge_short)
   draw_seat_open_sets_row(3, table_x, p3_public_y, table_w, public_short)

   -- P1 (bottom): open-sets row, then hand row.
   local p1_hand_y   = table_y + table_h - p1_hand_h
   local p1_public_y = p1_hand_y - p1_public_h - 4
   draw_seat_open_sets_row(1, table_x, p1_public_y, table_w, p1_public_h)
   draw_player_hand_row(table_x, p1_hand_y, table_w, p1_hand_h)

   -- Side region between top and bottom strips.
   local side_y = p3_public_y + public_short + 8
   local side_h = p1_public_y - 8 - side_y

   -- P4 (left): hand col + open-sets col.
   local p4_hand_x   = table_x
   local p4_public_x = p4_hand_x + edge_short + 4
   draw_opponent_hand_col(4, p4_hand_x, side_y, edge_short, side_h)
   draw_seat_open_sets_col(4, p4_public_x, side_y, public_short, side_h)

   -- P2 (right): hand col + open-sets col.
   local p2_hand_x   = table_x + table_w - edge_short
   local p2_public_x = p2_hand_x - public_short - 4
   draw_opponent_hand_col(2, p2_hand_x, side_y, edge_short, side_h)
   draw_seat_open_sets_col(2, p2_public_x, side_y, public_short, side_h)

   -- Center area inside the side strips. Stacks vertically:
   --   info strip (top)   →  discard pile (middle)  → boon + known wall
   local center_x = p4_public_x + public_short + 8
   local center_w = p2_public_x - center_x - 8
   local center_y = side_y
   local info_strip_h = 26
   local info_h = 130
   local pile_h = side_h - info_h - info_strip_h * 2 - 8
   if pile_h < 80 then pile_h = 80 end

   draw_center_info(center_x, center_y, center_w, info_h)

   local pile_y = center_y + info_h + 4
   draw_center_discard_pile(center_x, pile_y, center_w, pile_h)

   -- Boon strip + known wall at the bottom of the center column.
   info_panels.draw_boon_strip(state.deal, 1, center_x, pile_y + pile_h + 4, center_w, info_strip_h)
   info_panels.draw_known_wall(state.deal, 1, center_x, pile_y + pile_h + 4 + info_strip_h, center_w, info_strip_h)

   -- Action prompt overlay — drawn inside the center area when seat 1
   -- has a decision. Each option becomes a Clickable.
   if has_seat1_pending_input(state.deal) then
      local d = state.deal
      local phase = d.phase as string
      local kind: CachedOptsKind = phase == "reaction_window" and "reaction" or "self"
      local opts = options_cached(d, kind)
      local title = kind == "reaction" and "Reaction — choose an action" or "Your turn"
      local panel_w = math.min(360, center_w - 16)
      local panel_h = 36 + #opts * 24 + 8
      local panel_x = center_x + (center_w - panel_w) / 2
      -- Anchor near the top of the discard pile so the prompt is the
      -- visual focus when the player has a decision; the pile shows
      -- behind it. Falls back inside the pile area if it doesn't fit.
      local panel_y = pile_y + math.max(8, (pile_h - panel_h) / 2)
      local rects = action_prompt.draw(opts, title, panel_x, panel_y, panel_w, panel_h)
      for i, r in ipairs(rects) do
         local opt = opts[i]
         state.clickables[#state.clickables + 1] = {
            x = r.x, y = r.y, w = r.w, h = r.h,
            callback = function() dispatch_option(opt) end,
         }
      end
   end

   -- Right column: log + inspector when visible.
   if show_debug_panel then
      local content_h = table_h
      if state.inspector_open then
         local log_h = math.floor(content_h * 0.5)
         draw_log(right_x, table_y, right_w, log_h)
         draw_inspector(right_x, table_y + log_h + margin, right_w, content_h - log_h - margin)
      else
         draw_log(right_x, table_y, right_w, content_h)
      end
   end

   draw_hints(margin, sh - hint_h)
end

return {
   scene     = scene_stack.make_scene(on_load, on_update, on_draw, on_keypressed, on_mousepressed),
   start_run = start_run,
}
