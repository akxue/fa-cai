-- S05 debug table scene. Spectator-mode rendering of a deal driven by the
-- vanilla AI for all four seats, with step mode, AI pacing, an inspector
-- overlay, and a tile-conservation check after each engine transition.
--
-- Controls:
--   F1   toggle inspector overlay
--   T    toggle step mode (auto-advance vs single-step)
--   S    advance one AI action (when step mode is on)
--   R    restart the deal with the same seed
--   ESC  quit

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
local scorer_mod = require("game.scorer")
local fx_runner  = require("effects.effect_runner")
local wall_mod   = require("game.wall")
local content    = require("content.boons")
local boons_init = require("effects.boons.init")
local calls_mod  = require("game.calls")
local tile_render   = require("ui.tile_render")
local action_prompt = require("ui.action_prompt")
local info_panels   = require("ui.info_panels")
local scene_stack   = require("app.scene_stack")

local M = {}

-- ── Tunables ──────────────────────────────────────────────────────────────

local AI_PACE_AUTO    <const> = 0.20    -- seconds between AI actions in auto mode
local DEFAULT_SEED    <const> = 42
local DEBUG_ROUND     <const> = 3       -- exercises Momentum surplus in S05.
local LOG_MAX         <const> = 100
local LOG_VISIBLE     <const> = 22

-- ── Tile rendering helpers (live in ui/tile_render.tl) ──────────────────

local tile_label     = tile_render.tile_label
local format_set     = tile_render.format_set
local sorted_indices = tile_render.sorted_indices

-- ── Scene state ──────────────────────────────────────────────────────────

local record LogEntry
   text: string
   kind: string   -- "ev" | "ai" | "err" | "sys"
end

local record SceneState
   seed:             integer
   deal:             DealState
   -- "debug": all four seats AI-driven, all hands revealed by default.
   -- "run":   seat 1 (East) is the human; opponents stay face-down unless
   --          the inspector is toggled on. The AI driver still runs all
   --          seats in commit 3; commit 4 swaps the seat-1 driver for
   --          player input.
   mode:             string
   step_mode:        boolean
   wait_for_step:    boolean
   ai_pace_left:     number
   inspector_open:   boolean
   log:              {LogEntry}
   conservation_ok:  boolean
   conservation_msg: string
   ticks:            integer
   selected_opening_tile_ids: {TileId}
   -- Most recent AI reasoning per seat (1..4). Populated by advance_one_action
   -- so the inspector can render the seat's top-K candidate alternatives.
   last_reason_by_seat: {integer: AiReasoning}
   -- Tile id of the cursor in the player's hand row (run mode). Empty
   -- string when there is no current selection; ensure_cursor_valid()
   -- defaults it to the last drawn tile.
   cursor_tile_id: TileId
   -- Run-state reference so table_scene can decrement lives and route
   -- to reward/result scenes when the deal ends.
   run_state: RunState
   -- One-shot guard so the deal_over → reward/result transition only
   -- fires once per deal.
   transitioned: boolean
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
   -- Use a compact debug boon set so opening_actions, Known Wall, active effect
   -- counters, and surplus trimming are all visible before S06's real run flow.
   rs.active_effects = {
      content.activate_for("fresh_start", 1),
      content.activate_for("third_eye", 1),
      content.activate_for("momentum", 1),
   }
   return rs
end

-- Pending entry passed in by an upstream scene (boon select). When set,
-- the next reset() consumes it instead of building a debug RunState.
local pending_run: RunState = nil
local pending_seed: integer = 0
local has_pending: boolean = false

-- Public entry: call before pushing the table scene to begin a real run
-- with the given RunState and seed. Cleared after consumption.
function M.start_run(rs: RunState, seed: integer)
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
      transitioned     = false,
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

local function next_eligible_reactor(deal: DealState): integer
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

local function selected_contains(tile_id: TileId): boolean
   for _, id in ipairs(state.selected_opening_tile_ids) do
      if id == tile_id then return true end
   end
   return false
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

-- True when run mode and seat 1 must make a decision the AI shouldn't
-- make for them. The auto-advance path stops here.
local function has_seat1_pending_input(d: DealState): boolean
   if state.mode ~= "run" then return false end
   local phase = d.phase as string
   if phase == "awaiting_action" and d.current_player == 1 then return true end
   if seat1_can_react(d) then return true end
   return false
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

-- Reaction window options for seat 1: Hu/Peng/OpenKong/Chi/Pass.
local function compute_seat1_reaction_options(d: DealState): {ActionPromptOption}
   local opts: {ActionPromptOption} = {}
   local p = d.players[1]
   local hand = p.hand.concealed_tiles

   -- Hu on a discard
   if d.has_pending_discard then
      local pd_tile = d.pending_discard.tile
      local shapes = validator.find_win_shapes(hand, pd_tile, p.hand.sets)
      if #shapes > 0 then
         opts[#opts + 1] = {
            key        = "h",
            label      = "Hu (claim " .. tile_label(pd_tile) .. ")",
            action     = engine.declare_hu(1, pd_tile.tile_id, false),
            has_action = true,
         }
      end
   end
   -- Hu on Qiang Gang (rob a kong upgrade)
   if d.has_pending_kong then
      local pk_tile = d.pending_added_kong.tile
      local shapes = validator.find_win_shapes(hand, pk_tile, p.hand.sets)
      if #shapes > 0 then
         opts[#opts + 1] = {
            key        = "h",
            label      = "Hu / Qiang Gang " .. tile_label(pk_tile),
            action     = engine.declare_hu(1, pk_tile.tile_id, false),
            has_action = true,
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
            has_action = true,
         }
      end
      if calls_mod.can_open_kong(pd.tile, hand, pd.discarder, 1) then
         opts[#opts + 1] = {
            key        = "k",
            label      = "Open Kong " .. tile_label(pd.tile),
            action     = engine.declare_open_kong(1, pd.tile.tile_id),
            has_action = true,
         }
      end
      if calls_mod.is_next_player(pd.discarder, 1, 4) then
         local combos = calls_mod.chi_combinations(pd.tile, hand)
         if #combos > 0 then
            opts[#opts + 1] = {
               key        = "c",
               label      = "Chi " .. tile_label(pd.tile),
               action     = engine.declare_chi(1, pd.tile.tile_id, combos[1]),
               has_action = true,
            }
         end
      end
   end
   -- Pass is always offered while seat 1 is eligible
   opts[#opts + 1] = {
      key        = "x",
      label      = "Pass",
      action     = engine.pass_reaction(1),
      has_action = true,
   }
   return opts
end

-- Self-turn options for seat 1 in awaiting_action: Zi Mo / Concealed
-- Kong / Added Kong / Discard.
local function compute_seat1_self_options(d: DealState): {ActionPromptOption}
   local opts: {ActionPromptOption} = {}
   local p = d.players[1]
   local hand = p.hand.concealed_tiles

   -- Zi Mo Hu using the last drawn tile
   if d.has_last_drawn then
      local last_id = d.last_drawn_tile_id
      local last_tile: Tile = nil
      local rest: {Tile} = {}
      for _, t in ipairs(hand) do
         if last_tile == nil and t.tile_id == last_id then
            last_tile = t
         else
            rest[#rest + 1] = t
         end
      end
      if last_tile ~= nil then
         local shapes = validator.find_win_shapes(rest, last_tile, p.hand.sets)
         if #shapes > 0 then
            opts[#opts + 1] = {
               key        = "h",
               label      = "Hu / Zi Mo " .. tile_label(last_tile),
               action     = engine.declare_hu(1, last_id, true),
               has_action = true,
            }
         end
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
         has_action = true,
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
            has_action = true,
         }
         break
      end
   end

   -- Discard the cursor tile. Action is constructed on dispatch using the
   -- current cursor position; offered last so the keybinds above stay
   -- discoverable without scanning past Discard.
   opts[#opts + 1] = {
      key        = "d",
      label      = "Discard selected tile",
      action     = nil,
      has_action = false,
   }
   return opts
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

function M.load()
   reset(DEFAULT_SEED)
end

-- Hand off to reward/result scenes after deal_over in run mode. Routed
-- through scene_stack.fire_deal_over so this scene does not statically
-- import reward_scene or result_scene (which would create a cycle with
-- start_scene → boon_select_scene → table_scene). main.tl installs the
-- concrete handler at startup.
local function transition_after_deal_over()
   if state.transitioned then return end
   state.transitioned = true
   scene_stack.fire_deal_over(state.deal, state.run_state)
end

function M.update(dt: number)
   if state.deal == nil then return end
   if (state.deal.phase as string) == "deal_over" then
      if state.mode == "run" then transition_after_deal_over() end
      return
   end
   if state.step_mode and state.wait_for_step then return end
   -- In run mode, hand control to the player when seat 1 owes the next
   -- decision. Drawing (awaiting_draw) is automatic and stays AI-driven.
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

function M.keypressed(key: string)
   if key == "escape" then
      love.event.quit(0)
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

   -- Action dispatch: match key against the option list for the current phase.
   local opts: {ActionPromptOption}
   if phase == "reaction_window" then
      opts = compute_seat1_reaction_options(d)
   else
      opts = compute_seat1_self_options(d)
   end
   for _, opt in ipairs(opts) do
      if key == opt.key then
         if opt.has_action then
            apply_player_action(opt.action, opt.label)
         elseif key == "d" and phase == "awaiting_action" and d.current_player == 1 then
            -- Discard the cursor-selected tile.
            if (state.cursor_tile_id as string) == "" then
               push_log("sys", "no tile selected to discard")
               return
            end
            apply_player_action(engine.discard(1, state.cursor_tile_id), "discard " .. (state.cursor_tile_id as string))
         end
         return
      end
   end
end

-- ── Drawing ───────────────────────────────────────────────────────────────

local SEAT_NAMES: {string} = { "East (P1)", "South (P2)", "West (P3)", "North (P4)" }

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

local function draw_panel(x: number, y: number, w: number, h: number, label: string)
   love.graphics.setColor(0.18, 0.18, 0.20, 1.0)
   love.graphics.rectangle("fill", x, y, w, h)
   love.graphics.setColor(0.40, 0.40, 0.45, 1.0)
   love.graphics.rectangle("line", x, y, w, h)
   if label ~= "" then
      love.graphics.setColor(0.85, 0.85, 0.90, 1.0)
      draw_text(label, x + 8, y + 4)
   end
end

local function format_concealed(player: PlayerState, reveal: boolean): string
   if reveal then
      local tiles = player.hand.concealed_tiles
      local idxs = sorted_indices(tiles)
      local parts: {string} = {}
      for _, i in ipairs(idxs) do
         local t = tiles[i]
         local label = tile_label(t)
         if (state.deal.phase as string) == "opening_actions"
            and player.is_human
            and i <= 10
         then
            label = tostring(i % 10) .. ":" .. label
            if selected_contains(t.tile_id) then label = "*" .. label end
         end
         parts[#parts + 1] = label
      end
      return table.concat(parts, " ")
   end
   return string.rep("?? ", #player.hand.concealed_tiles)
end

local function format_discards(player: PlayerState): string
   local parts: {string} = {}
   for _, t in ipairs(player.hand.discards) do
      parts[#parts + 1] = tile_label(t)
   end
   return table.concat(parts, " ")
end

local function format_open_sets(player: PlayerState): string
   if #player.hand.sets == 0 then return "" end
   local parts: {string} = {}
   for _, s in ipairs(player.hand.sets) do
      parts[#parts + 1] = format_set(s)
   end
   return table.concat(parts, " ")
end

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

local function is_men_qian(player: PlayerState): boolean
   for _, s in ipairs(player.hand.sets) do
      if (s.visibility as string) == "open" then return false end
   end
   return true
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

local function draw_seat_panel(seat_index: integer, x: number, y: number, w: number, h: number)
   local d = state.deal
   local p = d.players[seat_index]
   local is_current = (d.current_player == seat_index) and (d.phase as string) ~= "deal_over"
   local title = SEAT_NAMES[seat_index]
   if is_current then title = "▶ " .. title end
   if p.is_human then title = title .. " [you]" end
   draw_panel(x, y, w, h, title)

   local tx = x + 8
   local ty = y + 22
   local limit = w - 16
   local reveal = p.is_human or state.inspector_open
   -- Seat 1's concealed tiles are rendered as boxes in draw_player_hand_row;
   -- the panel only shows the metadata (ting, sets, discards).
   if seat_index ~= 1 then
      ty = ty + draw_text_wrapped("hand: " .. format_concealed(p, reveal), tx, ty, limit) + 2
   end
   if reveal then
      draw_text("ting: " .. ting_label(seat_index), tx, ty); ty = ty + 16
   else
      draw_text(string.format("tiles: %d", #p.hand.concealed_tiles), tx, ty); ty = ty + 16
   end
   local sets = format_open_sets(p)
   if sets ~= "" then
      ty = ty + draw_text_wrapped("sets: " .. sets, tx, ty, limit) + 2
   end
   ty = ty + draw_text_wrapped("disc: " .. format_discards(p), tx, ty, limit) + 2
end

-- Player hand row. Renders seat 1's concealed tiles as boxes inside the
-- supplied rectangle. Tiles are sorted with sorted_indices so the row is
-- stable across draws and matches the panel's text view (when shown).
-- Selected_opening tile_ids are highlighted with a yellow border so the
-- Fresh Start swap interaction is legible.
local function draw_player_hand_row(x: number, y: number, w: number, h: number)
   draw_panel(x, y, w, h, "Your Hand")
   local p = state.deal.players[1]
   local tiles = p.hand.concealed_tiles
   local n = #tiles
   if n == 0 then return end

   local pad_x = 12
   local pad_y = 28
   local gap = 4
   local avail_w = w - pad_x * 2
   local avail_h = h - pad_y - 8
   -- size tiles to fit `n` boxes within avail_w, capped to a sane max
   local tile_w_calc = (avail_w - gap * (n - 1)) / n
   local tile_w = math.min(48, tile_w_calc)
   if tile_w < 16 then tile_w = 16 end
   local tile_h = math.min(56, avail_h)
   if tile_h < 24 then tile_h = 24 end

   -- center the row horizontally
   local row_w = tile_w * n + gap * (n - 1)
   local start_x = x + pad_x + math.max(0, (avail_w - row_w) / 2)
   local row_y = y + pad_y

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
         and state.mode == "run"
         and state.deal.current_player == 1
         and (state.deal.phase as string) == "awaiting_action"
      if selected then
         br, bg, bb = 1.00, 0.90, 0.30
      end
      if is_cursor then
         fr, fg, fb = 1.00, 0.97, 0.78
         br, bg, bb = 1.00, 0.55, 0.20
      end
      tile_render.draw_tile_box(t, tx, row_y, tile_w, tile_h, fr, fg, fb, br, bg, bb)
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

local function draw_center(x: number, y: number, w: number, h: number)
   draw_panel(x, y, w, h, "Center")
   local d = state.deal
   local tx = x + 8
   local ty = y + 22
   if (d.phase as string) == "opening_actions" then
      local actions = fx_runner.collect_available_actions(d, d.dealer)
      draw_text("opening actions", tx, ty); ty = ty + 16
      draw_text("selected: " .. opening_selection_label(), tx, ty); ty = ty + 16
      draw_text("actions available: " .. tostring(#actions), tx, ty); ty = ty + 16
      for _, a in ipairs(actions) do
         draw_text("  U " .. a.label, tx, ty); ty = ty + 14
      end
      local surplus = #d.players[d.dealer].hand.concealed_tiles - 13
      if surplus > 0 then
         draw_text("X trim surplus: " .. tostring(surplus), tx, ty); ty = ty + 16
      else
         draw_text("C confirm opening", tx, ty); ty = ty + 16
      end
      draw_text("1-0 toggle first 10 tiles", tx, ty); ty = ty + 16
      return
   end
   if d.has_pending_discard then
      local pd = d.pending_discard
      draw_text(string.format("pending discard: %s by p%d", tile_label(pd.tile), pd.discarder), tx, ty)
      ty = ty + 16
      draw_text("passes: " .. tostring(#d.reaction_passes) .. "  claims: " .. tostring(#d.pending_claims), tx, ty)
      ty = ty + 16
   end
   if d.has_pending_kong then
      draw_text(string.format("pending kong by p%d", d.pending_added_kong.declarer), tx, ty)
      ty = ty + 16
   end
   if d.has_last_drawn then
      draw_text("last draw: " .. (d.last_drawn_tile_id as string), tx, ty)
      ty = ty + 16
   end
   if d.has_deal_result then
      local res = d.deal_result
      local who = res.winner_player_index
      if who == -1 then
         draw_text("DEAL OVER: wall exhaustion (no winner)", tx, ty); ty = ty + 16
      else
         local zm = res.won_by_zi_mo and " (zi mo)" or ""
         local rating = res.has_score_result and (res.score_result.rating as string) or "?"
         draw_text(string.format("DEAL OVER: p%d wins%s rating=%s", who, zm, rating), tx, ty); ty = ty + 16
         if res.has_score_result then
            draw_text(string.format("fan=%d limit=%s", res.score_result.total_fan, tostring(res.score_result.is_limit)), tx, ty)
            ty = ty + 16
         end
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

local function score_with_modifiers(
   d: DealState,
   seat: integer,
   shapes: {WinShape},
   ctx: ScoreContext
): ScoreResult, boolean
   local out = scorer_mod.score_hand(shapes, ctx)
   if not out.has_best then return {} as ScoreResult, false end
   local best = fx_runner.apply_score_modifiers(d, ctx, shapes[1], out.candidates[1], seat)
   for i = 2, #out.candidates do
      local candidate = fx_runner.apply_score_modifiers(d, ctx, shapes[i], out.candidates[i], seat)
      local best_rank = best.is_limit and 10000 or best.total_fan
      local candidate_rank = candidate.is_limit and 10000 or candidate.total_fan
      if candidate_rank > best_rank then best = candidate end
   end
   return best, true
end

local function draw_score_candidates_for(seat: integer, x: number, y: number): number
   local d = state.deal
   local p = d.players[seat]
   if ting_for(seat) > -1 then return y end
   -- For inspector preview, walk the wall front to find which upcoming tile would win.
   for i = 1, math.min(8, #d.wall.tiles) do
      local incoming = d.wall.tiles[i]
      local shapes = validator.find_win_shapes(p.hand.concealed_tiles, incoming, p.hand.sets)
      if #shapes > 0 then
         local ctx: ScoreContext = {
            incoming_tile = { tile_id = "" as TileId, kind_id = "" as TileKindId },
            has_incoming  = true,
            is_zi_mo      = false,
            is_men_qian   = is_men_qian(p),
            is_hai_di     = false,
            is_gang_shang = false,
            is_qiang_gang = false,
            round_wind    = d.round_wind,
            seat_wind     = p.seat_wind,
         }
         local final, ok = score_with_modifiers(d, seat, shapes, ctx)
         if ok then
            draw_text(string.format("    cand: +%s → fan=%d valid=%s", tile_label(incoming), final.total_fan, tostring(final.valid_hu)), x, y)
            y = y + 14
         end
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

   -- AI candidate top-K per seat (S07 candidate-pipeline scaffold). Only the
   -- discard path produces rich top-3 alternatives in commit 2; calls show a
   -- single chosen candidate. Later commits expand this as more gates move
   -- into the candidate pipeline.
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
      draw_text("1-0 select | U Fresh Start | X trim | C confirm | F1 inspector | R restart | ESC quit", x, y)
   elseif state.mode == "run" and has_seat1_pending_input(state.deal) then
      if (state.deal.phase as string) == "awaiting_action" and state.deal.current_player == 1 then
         draw_text("← → / 1-9 0 q-r select | D discard | H Hu | K Concealed Kong | U Added Kong | F1 inspector | R restart | ESC quit", x, y)
      else
         draw_text("H Hu | P Peng | K Open Kong | C Chi | X Pass | F1 inspector | R restart | ESC quit", x, y)
      end
   else
      draw_text("F1 inspector | T toggle step | S step | R restart | ESC quit", x, y)
   end
end

function M.draw()
   love.graphics.setBackgroundColor(0.10, 0.10, 0.12, 1.0)
   local sw = love.graphics.getWidth()
   local sh = love.graphics.getHeight()

   -- Layout: status bar on top, table grid (3x3) in the middle, two
   -- info strips (boons / known wall) above the player hand row, the
   -- player hand row at the bottom, log + inspector on the right, hints
   -- at the very bottom.
   local margin = 8
   local hint_h = 20
   local status_h = 24
   local hand_row_h = 80
   local info_strip_h = 26
   local right_w = 360
   local table_w = sw - right_w - margin * 3
   local content_y = margin + status_h + margin
   local content_h = sh - content_y - hint_h - margin * 2
   local grid_h = content_h - hand_row_h - info_strip_h * 2 - margin * 2

   draw_status_bar(margin, margin, sw - margin * 2)

   -- 3x3 grid for the table area:
   --   .   N   .
   --   W   C   E
   --   .   S   .
   -- Player (P1 = East) sits at the bottom (south of screen).
   local cell_w = table_w / 3
   local cell_h = grid_h / 3
   local tx = margin
   local ty = content_y

   -- top-center = West (P3)
   draw_seat_panel(3, tx + cell_w, ty, cell_w, cell_h)
   -- middle-left = North (P4)
   draw_seat_panel(4, tx, ty + cell_h, cell_w, cell_h)
   -- middle-center = center
   draw_center(tx + cell_w, ty + cell_h, cell_w, cell_h)
   -- middle-right = South (P2)
   draw_seat_panel(2, tx + cell_w * 2, ty + cell_h, cell_w, cell_h)
   -- bottom-center = East (P1, you) — sets/discards/ting only; concealed
   -- tiles render in draw_player_hand_row below.
   draw_seat_panel(1, tx + cell_w, ty + cell_h * 2, cell_w, cell_h)

   -- Two info strips above the hand row: boons (with counters) and the
   -- player's known-wall reveals.
   local boon_y = content_y + grid_h + margin
   info_panels.draw_boon_strip(state.deal, 1, tx, boon_y, table_w, info_strip_h)
   local kw_y = boon_y + info_strip_h
   info_panels.draw_known_wall(state.deal, 1, tx, kw_y, table_w, info_strip_h)

   -- Player hand row spans the full table width below the info strips.
   local hand_y = kw_y + info_strip_h + margin
   draw_player_hand_row(tx, hand_y, table_w, hand_row_h)

   -- Action prompt panel overlay — sits above the hand row, anchored
   -- to the right, when seat 1 owes a decision in run mode.
   if has_seat1_pending_input(state.deal) then
      local d = state.deal
      local phase = d.phase as string
      local opts: {ActionPromptOption}
      local title: string
      if phase == "reaction_window" then
         opts = compute_seat1_reaction_options(d)
         title = "Reaction"
      else
         opts = compute_seat1_self_options(d)
         title = "Your turn"
      end
      local panel_w = 260
      local panel_h = 28 + #opts * 18 + 8
      local panel_x = tx + table_w - panel_w - 8
      local panel_y = hand_y - panel_h - 6
      action_prompt.draw(opts, title, panel_x, panel_y, panel_w, panel_h)
   end

   -- Right panel: log on top, inspector below if open, otherwise full log.
   local right_x = sw - right_w - margin
   if state.inspector_open then
      local log_h = math.floor(content_h * 0.5)
      draw_log(right_x, content_y, right_w, log_h)
      draw_inspector(right_x, content_y + log_h + margin, right_w, content_h - log_h - margin)
   else
      draw_log(right_x, content_y, right_w, content_h)
   end

   draw_hints(margin, sh - hint_h)
end

return M
