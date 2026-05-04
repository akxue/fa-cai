-- Fresh Start: once during opening_actions, swap 0–3 tiles back into the
-- Wall, reshuffle the remaining wall, draw the same number of replacements,
-- and clear Known Wall.

require("core.types")
require("game.deal_types")
require("effects.effect_types")
local runner = require("effects.effect_runner")

local M: EffectModule = {} as EffectModule

M.metadata = {
   effect_id   = "fresh_start",
   label       = "Fresh Start",
   description = "Swap 0–3 opening tiles back into the Wall (reshuffles, draws replacements).",
   source_kind = "boon" as EffectSourceKind,
   source_id   = "fresh_start",
   priority    = 100,
}

function M.collect_available_actions(active: ActiveEffectState, deal: DealState, player_index: integer): {EffectAction}
   if active.used_this_deal then return {} end
   if (deal.phase as string) ~= "opening_actions" then return {} end
   if active.has_owner and active.owner_player_index ~= player_index then return {} end
   local out: EffectAction = {
      active_effect_id = active.active_effect_id,
      label            = "Fresh Start: swap opening tiles",
      payload_kind     = "swap_tiles",
   }
   return { out }
end

function M.on_use_action(uctx: EffectUseContext, _deal: DealState): {EffectCommand}
   if uctx.active.used_this_deal then return {} end
   if #uctx.tile_ids > 3 then
      error("fresh_start: at most 3 tiles may be swapped, got " .. tostring(#uctx.tile_ids))
   end
   local cmds: {EffectCommand} = {}
   if #uctx.tile_ids > 0 then
      cmds[#cmds + 1] = runner.cmd_replace_concealed_tiles(uctx.player_index, uctx.tile_ids, true)
   end
   cmds[#cmds + 1] = runner.cmd_mark_used(uctx.active.active_effect_id)
   return cmds
end

return M
