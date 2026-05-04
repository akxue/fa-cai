-- Momentum: start with one extra opening tile per round won so far in the
-- tournament (rounds played − 1, equivalent because progressing requires a
-- win). The dealer trims surplus down to 13 before play begins.

require("core.types")
require("game.deal_types")
require("effects.effect_types")

local M: EffectModule = {} as EffectModule

M.metadata = {
   effect_id   = "momentum",
   label       = "Momentum",
   description = "Extra opening tiles equal to round_index − 1.",
   source_kind = "boon" as EffectSourceKind,
   source_id   = "momentum",
   priority    = 100,
}

function M.collect_opening_modifiers(_active: ActiveEffectState, round_index: integer): OpeningModifiers
   local extra = round_index - 1
   if extra < 0 then extra = 0 end
   return { extra_opening_tiles = extra }
end

return M
