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

-- ── The 6 S02 boons ──────────────────────────────────────────────────────

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
      effect              = noop_effect,
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
      effect              = noop_effect,
   },
   {
      id                  = "silent_march",
      cluster             = "concealed",
      name                = "Silent March",
      description         = "Every 3 consecutive no-call turns, gain 1 wall-peek token.",
      eligible_milestones = {"set_1", "set_2"},
      effect_kind         = "token",
      weight              = 1.0,
      listens             = {"on_turn_end"},
      condition           = always_true,
      effect              = noop_effect,
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
