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
local rng_mod    = require("core.rng")
local engine     = require("game.deal_engine")
local ai         = require("game.ai")
local td         = require("game.ting_distance")
local invariants = require("game.deal_invariants")
local validator  = require("game.hand_validator")
local scorer_mod = require("game.scorer")
local fx_runner  = require("effects.effect_runner")
local wall_mod   = require("game.wall")

local M = {}

-- ── Tunables ──────────────────────────────────────────────────────────────

local AI_PACE_AUTO    <const> = 0.20    -- seconds between AI actions in auto mode
local DEFAULT_SEED    <const> = 42
local LOG_MAX         <const> = 100
local LOG_VISIBLE     <const> = 22

-- ── Tile rendering helper ────────────────────────────────────────────────

local KIND_LABEL: {string:string} = {
   east = "E", south = "S", west = "W", north = "N",
   fa_cai = "F", hong_zhong = "H", bai_ban = "B",
}

local function tile_label(t: Tile): string
   if t == nil then return "??" end
   local k = t.kind_id as string
   local short = KIND_LABEL[k]
   if short ~= nil then return short end
   local suit, rank = k:match("^([a-z]+)_(%d+)$")
   if suit == nil then return k end
   local letter = "?"
   if suit == "tiao" then letter = "T"
   elseif suit == "wan" then letter = "W"
   elseif suit == "bing" then letter = "B" end
   return rank .. letter
end

local function format_set(s: TileSet): string
   local parts: {string} = {}
   for _, t in ipairs(s.tiles) do parts[#parts + 1] = tile_label(t) end
   local body = table.concat(parts, " ")
   local kind_short = (s.kind as string):upper()
   if (s.visibility as string) == "concealed" then
      return "[" .. kind_short .. "* " .. body .. "]"
   end
   return "[" .. kind_short .. " " .. body .. "]"
end

-- ── Scene state ──────────────────────────────────────────────────────────

local record LogEntry
   text: string
   kind: string   -- "ev" | "ai" | "err" | "sys"
end

local record SceneState
   seed:             integer
   deal:             DealState
   step_mode:        boolean
   wait_for_step:    boolean
   ai_pace_left:     number
   inspector_open:   boolean
   log:              {LogEntry}
   conservation_ok:  boolean
   conservation_msg: string
   ticks:            integer
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

local function reset(seed: integer)
   state = {
      seed             = seed,
      deal             = engine.new_deal(rng_mod.from_seed(seed)),
      step_mode        = false,
      wait_for_step    = false,
      ai_pace_left     = AI_PACE_AUTO,
      inspector_open   = false,
      log              = {},
      conservation_ok  = true,
      conservation_msg = "OK",
      ticks            = 0,
   }
   push_log("sys", "deal opened (seed=" .. tostring(seed) .. ")")
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

-- ── AI driver ─────────────────────────────────────────────────────────────

local function describe_reasoning(r: AiReasoning, seat: integer): string
   local body = "p" .. tostring(seat) .. " " .. r.tag .. ": " .. r.message
   if r.ting_before > -100 or r.ting_after > -100 then
      local b = r.ting_before > -100 and tostring(r.ting_before) or "-"
      local a = r.ting_after  > -100 and tostring(r.ting_after)  or "-"
      body = body .. " (ting " .. b .. "→" .. a .. ")"
   end
   return body
end

-- Pump one AI action. Returns true if state advanced.
local function advance_one_action(): boolean
   local d = state.deal
   local phase = d.phase as string
   if phase == "deal_over" then return false end

   local seat = 0
   local action: DealAction = nil
   local reason: AiReasoning = nil

   if phase == "awaiting_draw" or phase == "awaiting_action" or phase == "opening_actions" then
      seat = d.current_player
      if phase == "opening_actions" then
         -- Should not happen in S05 (no boons), but handle defensively.
         action = engine.confirm_opening(seat)
         reason = { tag = "confirm_opening", message = "confirm opening", ting_before = -100, ting_after = -100 }
      else
         action, reason = ai.decide_main(d, seat)
      end
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

function M.update(dt: number)
   if state.deal == nil then return end
   if (state.deal.phase as string) == "deal_over" then return end
   if state.step_mode and state.wait_for_step then return end

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
end

-- ── Drawing ───────────────────────────────────────────────────────────────

local SEAT_NAMES: {string} = { "East (P1)", "South (P2)", "West (P3)", "North (P4)" }

local function draw_text(text: string, x: number, y: number)
   love.graphics.print(text, x, y)
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
      local parts: {string} = {}
      for _, t in ipairs(player.hand.concealed_tiles) do
         parts[#parts + 1] = tile_label(t)
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

local function ting_for(player: PlayerState): integer
   return td.ting_distance(player.hand.concealed_tiles, player.hand.sets)
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
   local reveal = p.is_human or state.inspector_open
   draw_text("hand: " .. format_concealed(p, reveal), tx, ty); ty = ty + 16
   if reveal then
      draw_text(string.format("ting: %d", ting_for(p)), tx, ty); ty = ty + 16
   else
      draw_text(string.format("tiles: %d", #p.hand.concealed_tiles), tx, ty); ty = ty + 16
   end
   local sets = format_open_sets(p)
   if sets ~= "" then
      draw_text("sets: " .. sets, tx, ty); ty = ty + 16
   end
   draw_text("disc: " .. format_discards(p), tx, ty); ty = ty + 16
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
   for i = start, #state.log do
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
      draw_text(e.text, x + 8, ty)
      ty = ty + 14
   end
end

local function draw_score_candidates_for(seat: integer, x: number, y: number): number
   local d = state.deal
   local p = d.players[seat]
   if ting_for(p) > -1 then return y end
   -- For inspector preview, walk the wall front to find which upcoming tile would win.
   for i = 1, math.min(8, #d.wall.tiles) do
      local incoming = d.wall.tiles[i]
      local shapes = validator.find_win_shapes(p.hand.concealed_tiles, incoming, p.hand.sets)
      if #shapes > 0 then
         local ctx: ScoreContext = {
            incoming_tile = { tile_id = "" as TileId, kind_id = "" as TileKindId },
            has_incoming  = true,
            is_zi_mo      = false,
            is_men_qian   = (#p.hand.sets == 0),
            is_hai_di     = false,
            is_gang_shang = false,
            is_qiang_gang = false,
            round_wind    = d.round_wind,
            seat_wind     = p.seat_wind,
         }
         local out = scorer_mod.score_hand(shapes, ctx)
         if out.has_best then
            local final = fx_runner.apply_score_modifiers(d, ctx, shapes[1], out.candidates[1], seat)
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

   draw_text("known wall (player only): " .. tostring(#d.known_wall_tile_ids) .. " tiles", tx, ty); ty = ty + 16

   draw_text("active effects: " .. tostring((function(): integer
      local n = 0
      for _ in pairs(d.effect_states) do n = n + 1 end
      return n
   end)()), tx, ty); ty = ty + 16

   ty = ty + 6
   draw_text("score candidates near ting:", tx, ty); ty = ty + 16
   for seat = 1, 4 do
      local p = d.players[seat]
      local t = ting_for(p)
      draw_text(string.format("  p%d ting=%d", seat, t), tx, ty); ty = ty + 14
      if t == -1 then
         ty = draw_score_candidates_for(seat, tx, ty)
      end
   end
end

local function draw_hints(x: number, y: number)
   love.graphics.setColor(0.65, 0.65, 0.70, 1.0)
   draw_text("F1 inspector | T toggle step | S step | R restart | ESC quit", x, y)
end

function M.draw()
   love.graphics.setBackgroundColor(0.10, 0.10, 0.12, 1.0)
   local sw = love.graphics.getWidth()
   local sh = love.graphics.getHeight()

   -- Layout: status bar on top, table grid (3x3) center, log + inspector to the right, hints on bottom.
   local margin = 8
   local hint_h = 20
   local status_h = 24
   local right_w = 360
   local table_w = sw - right_w - margin * 3
   local content_y = margin + status_h + margin
   local content_h = sh - content_y - hint_h - margin * 2

   draw_status_bar(margin, margin, sw - margin * 2)

   -- 3x3 grid for the table area:
   --   .   N   .
   --   W   C   E
   --   .   S   .
   -- Player (P1 = East) sits at the bottom (south of screen).
   local cell_w = table_w / 3
   local cell_h = content_h / 3
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
   -- bottom-center = East (P1, you)
   draw_seat_panel(1, tx + cell_w, ty + cell_h * 2, cell_w, cell_h)

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
