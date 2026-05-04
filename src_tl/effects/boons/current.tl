-- Current: each draw matching the player's majority suit grants 1 Suit
-- Counter; +1 fan per 4 counters at Hu. Counts supplement draws too. Honors
-- are not a suit, so honor draws never increment.

require("core.types")
require("game.deal_types")
require("effects.effect_types")
local validator = require("game.hand_validator")
local runner = require("effects.effect_runner")

local M: EffectModule = {} as EffectModule

M.metadata = {
   effect_id   = "current",
   label       = "Current",
   description = "Suit Counter on majority-suit draws; +1 fan per 4 counters.",
   source_kind = "boon" as EffectSourceKind,
   source_id   = "current",
   priority    = 100,
}

local SUITS: {string} = {"tiao", "wan", "bing"}

local function suit_counts_excluding(deal: DealState, player_index: integer, exclude_id: TileId): {string: integer}
   local counts: {string: integer} = { tiao = 0, wan = 0, bing = 0 }
   local p = deal.players[player_index]
   for _, t in ipairs(p.hand.concealed_tiles) do
      if t.tile_id ~= exclude_id then
         local s = validator.suit_of(t.kind_id)
         if counts[s] ~= nil then counts[s] = counts[s] + 1 end
      end
   end
   for _, set in ipairs(p.hand.sets) do
      for _, t in ipairs(set.tiles) do
         local s = validator.suit_of(t.kind_id)
         if counts[s] ~= nil then counts[s] = counts[s] + 1 end
      end
   end
   return counts
end

function M.on_after_draw(hctx: EffectAfterDrawContext, deal: DealState): {EffectCommand}
   local drawn_suit = validator.suit_of(hctx.drawn_tile.kind_id)
   if drawn_suit == "honor" then return {} end

   local counts = suit_counts_excluding(deal, hctx.player_index, hctx.drawn_tile.tile_id)
   local max_count = 0
   for _, s in ipairs(SUITS) do
      if counts[s] > max_count then max_count = counts[s] end
   end
   if max_count == 0 then return {} end

   local in_majority = counts[drawn_suit] == max_count
   if not in_majority then return {} end

   return {
      runner.cmd_increment_counter(hctx.active.active_effect_id, "suit_counters", 1),
   }
end

function M.on_score(sctx: EffectScoreContext, _deal: DealState): {ScoreReason}
   local n = sctx.active.counters["suit_counters"] or 0
   local fan = math.floor(n / 4)
   if fan <= 0 then return {} end
   local reason: ScoreReason = {
      category = "boon" as ScoreReasonCategory,
      label    = "Current (" .. tostring(n) .. " counters)",
      fan      = fan,
      is_limit = false,
   }
   return { reason }
end

return M
