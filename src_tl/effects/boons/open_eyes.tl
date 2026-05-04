-- Open Eyes: after the owner completes a Peng, reveal the next 3 front-Wall
-- tiles into known_wall_tile_ids.

require("core.types")
require("game.deal_types")
require("effects.effect_types")
local runner = require("effects.effect_runner")

local M: EffectModule = {} as EffectModule

M.metadata = {
   effect_id   = "open_eyes",
   label       = "Open Eyes",
   description = "Reveal the next 3 front-Wall tiles after a Peng.",
   source_kind = "boon" as EffectSourceKind,
   source_id   = "open_eyes",
   priority    = 100,
}

function M.on_after_peng(_hctx: EffectAfterPengContext, _deal: DealState): {EffectCommand}
   return { runner.cmd_reveal_wall_front(3) }
end

return M
