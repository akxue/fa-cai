-- Still Water: +1 fan when the hand is concealed (Men Qian) at Hu, on top of
-- the base Men Qian modifier from the scorer. Net effect is +2 fan total for
-- Men Qian when Still Water is active.

require("core.types")
require("game.deal_types")
require("effects.effect_types")

local M: EffectModule = {} as EffectModule

M.metadata = {
   effect_id   = "still_water",
   label       = "Still Water",
   description = "+1 fan on top of base Men Qian.",
   source_kind = "boon" as EffectSourceKind,
   source_id   = "still_water",
   priority    = 100,
}

function M.on_score(sctx: EffectScoreContext, _deal: DealState): {ScoreReason}
   if not sctx.ctx.is_men_qian then return {} end
   local reason: ScoreReason = {
      category = "boon" as ScoreReasonCategory,
      label    = "Still Water",
      fan      = 1,
      is_limit = false,
   }
   return { reason }
end

return M
