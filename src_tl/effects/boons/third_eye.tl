-- Third Eye: after the opening deal, reveal the next 5 front-Wall tiles into
-- known_wall_tile_ids.

require("core.types")
require("game.deal_types")
require("effects.effect_types")
local runner = require("effects.effect_runner")

local M: EffectModule = {} as EffectModule

M.metadata = {
   effect_id   = "third_eye",
   label       = "Third Eye",
   description = "Reveal the next 5 front-Wall tiles after the opening deal.",
   source_kind = "boon" as EffectSourceKind,
   source_id   = "third_eye",
   priority    = 100,
}

function M.on_opening_deal_complete(_hctx: EffectOpeningContext, _deal: DealState): {EffectCommand}
   return { runner.cmd_reveal_wall_front(5) }
end

return M
