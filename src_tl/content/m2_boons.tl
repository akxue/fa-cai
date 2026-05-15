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
         if n > 0 and n % 3 == 0 then
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
         if n > 0 and n % 5 == 0 then
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
   elseif name == "on_player_discard" then
      if ctx:get_flag("disqualified") then return end
      local n = ctx:get_counter("no_call_discards") + 1
      ctx:set_counter("no_call_discards", n)
      if n > 0 and n % 4 == 0 then
         mark_wall_known(ctx.deal.players[ctx.player_index], ctx:peek_wall(1))
      end
   end
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
      listens             = {"on_deal_start"},
      condition           = always_true,
      effect              = noop_effect,
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
      effect              = noop_effect,
   },
   {
      id                  = "cleanse",
      cluster             = "suit",
      name                = "Cleanse",
      description         = "Once per deal, swap an off-suit hand tile for the next wall tile.",
      eligible_milestones = {"set_1", "set_2"},
      effect_kind         = "swap",
      weight              = 1.0,
      listens             = {"on_player_draw"},
      condition           = always_true,
      effect              = noop_effect,
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
