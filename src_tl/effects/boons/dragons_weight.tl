-- Dragon's Weight: +1 fan per Dragon Peng or Kong in the winning shape, on
-- top of the base scorer's Dragon Peng modifier. Net effect is +2 fan per
-- Dragon Peng/Kong when this boon is active.

require("core.types")
require("game.deal_types")
require("effects.effect_types")
local validator = require("game.hand_validator")

local M: EffectModule = {} as EffectModule

M.metadata = {
   effect_id   = "dragons_weight",
   label       = "Dragon's Weight",
   description = "+1 fan per Dragon Peng or Kong on top of base.",
   source_kind = "boon" as EffectSourceKind,
   source_id   = "dragons_weight",
   priority    = 100,
}

function M.on_score(sctx: EffectScoreContext, _deal: DealState): {ScoreReason}
   local count = 0
   for _, s in ipairs(sctx.shape.sets) do
      local kind = s.kind as string
      if kind == "peng" or kind == "kong" then
         if #s.tiles > 0 and validator.is_dragon(s.tiles[1].kind_id) then
            count = count + 1
         end
      end
   end
   if count == 0 then return {} end
   local reason: ScoreReason = {
      category = "boon" as ScoreReasonCategory,
      label    = "Dragon's Weight (x" .. tostring(count) .. ")",
      fan      = count,
      is_limit = false,
   }
   return { reason }
end

return M
