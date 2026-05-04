-- Starter boon content metadata for Milestone 1. Pure data — no behavior.
-- Behavior modules live in src_tl/effects/boons/. Imports core types only.

require("core.types")
require("effects.effect_types")

local M = {}

global record BoonContent
   boon_id:     string         -- canonical id, matches effect_id of behavior module
   label:       string         -- player-facing name
   description: string         -- short description text
   archetype:   string         -- "Sculptor" | "Hunter" | "Caller" | "Reader" | "Grinder"
end

-- Canonical Milestone 1 starter set; offers are sampled from this list.
local STARTER: {BoonContent} = {
   {
      boon_id     = "current",
      label       = "Current",
      description = "Each draw matching your majority suit grants a Suit Counter; +1 fan per 4 counters at Hu.",
      archetype   = "Sculptor",
   },
   {
      boon_id     = "still_water",
      label       = "Still Water",
      description = "Concealed (Men Qian) bonus gives +1 fan on top of base.",
      archetype   = "Hunter",
   },
   {
      boon_id     = "dragons_weight",
      label       = "Dragon's Weight",
      description = "Each Dragon Peng or Kong gives +1 fan on top of base.",
      archetype   = "Caller",
   },
   {
      boon_id     = "open_eyes",
      label       = "Open Eyes",
      description = "After completing a Peng, reveal the next 3 front-Wall tiles.",
      archetype   = "Caller",
   },
   {
      boon_id     = "third_eye",
      label       = "Third Eye",
      description = "After the opening deal, reveal the next 5 front-Wall tiles.",
      archetype   = "Reader",
   },
   {
      boon_id     = "fresh_start",
      label       = "Fresh Start",
      description = "Once at opening: swap 0–3 tiles back into the Wall, reshuffle, draw replacements.",
      archetype   = "Reader",
   },
   {
      boon_id     = "momentum",
      label       = "Momentum",
      description = "Start with one extra opening tile per round won (round_index − 1); discard surplus before play.",
      archetype   = "Grinder",
   },
}

-- Returns the canonical Milestone 1 starter list (a fresh copy is not made;
-- callers must not mutate).
function M.starter(): {BoonContent}
   return STARTER
end

-- Returns the BoonContent for boon_id, or nil if unknown.
function M.find(boon_id: string): BoonContent
   for _, b in ipairs(STARTER) do
      if b.boon_id == boon_id then return b end
   end
   return nil
end

-- Convenience: build an ActiveEffectState from a starter boon for a given owner.
-- active_effect_id defaults to "{boon_id}_{owner_player_index}".
function M.activate_for(boon_id: string, owner_player_index: integer): ActiveEffectState
   local content = M.find(boon_id)
   if content == nil then
      error("activate_for: unknown boon_id: " .. boon_id)
   end
   return {
      active_effect_id   = boon_id .. "_" .. tostring(owner_player_index),
      effect_id          = boon_id,
      source_kind        = "boon" as EffectSourceKind,
      source_id          = boon_id,
      owner_player_index = owner_player_index,
      has_owner          = owner_player_index > 0,
      counters           = {},
      used_this_deal     = false,
   }
end

return M
