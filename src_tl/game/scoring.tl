-- Shared Hu-evaluation pipeline. The engine, the AI, and the player
-- prompt all need to ask the same question — "given this incoming tile
-- and shape, would the scorer (with boon modifiers applied) accept the
-- Hu?" — and they all need to get the same answer. This module is the
-- single canonical implementation; before it existed, three near-
-- identical copies lived in deal_engine.tl, ai.tl, and table_scene.tl,
-- with the player's Hu gate at risk of silently drifting from the
-- engine's threshold.

require("core.types")
require("game.deal_types")

local validator  = require("game.hand_validator")
local scorer_mod = require("game.scorer")
local wall_mod   = require("game.wall")
local fx_runner  = require("effects.effect_runner")

local M = {}

-- Sentinel rank for limit hands when comparing candidate ScoreResults
-- by total_fan. Any value above the largest realistic non-limit total
-- works; 10000 is well above the engine's ceiling.
local LIMIT_RANK <const>: integer = 10000

function M.is_men_qian(player: PlayerState): boolean
   for _, s in ipairs(player.hand.sets) do
      if (s.visibility as string) == "open" then return false end
   end
   return true
end

function M.build_score_ctx(deal: DealState, player_index: integer, is_zi_mo: boolean, is_gang_shang: boolean, is_qiang_gang: boolean): ScoreContext
   local p = deal.players[player_index]
   local is_hai_di = is_zi_mo and wall_mod.remaining(deal.wall) == 0
   return {
      incoming_tile = { tile_id = "" as TileId, kind_id = "" as TileKindId },
      has_incoming  = not is_zi_mo,
      is_zi_mo      = is_zi_mo,
      is_men_qian   = M.is_men_qian(p),
      is_hai_di     = is_hai_di,
      is_gang_shang = is_gang_shang,
      is_qiang_gang = is_qiang_gang,
      round_wind    = deal.round_wind,
      seat_wind     = p.seat_wind,
   }
end

-- Runs the effect runner over each candidate ScoreResult and picks the
-- highest-ranked (limit hands rank above non-limit; otherwise total_fan).
function M.apply_score_modifiers(deal: DealState, ctx: ScoreContext, shapes: {WinShape}, output: ScorerOutput, winner_index: integer): ScoreResult
   if not output.has_best then return output.best end

   local best = fx_runner.apply_score_modifiers(deal, ctx, shapes[1], output.candidates[1], winner_index)
   for i = 2, #output.candidates do
      local candidate = fx_runner.apply_score_modifiers(deal, ctx, shapes[i], output.candidates[i], winner_index)
      local best_rank      = best.is_limit      and LIMIT_RANK or best.total_fan
      local candidate_rank = candidate.is_limit and LIMIT_RANK or candidate.total_fan
      if candidate_rank > best_rank then best = candidate end
   end
   return best
end

-- Returns (valid_hu, best_score_result). For Zi Mo, `concealed` should
-- exclude the incoming tile; for win-on-discard / Qiang Gang, the
-- incoming is the tile being claimed and `concealed` is the player's
-- existing hand.
function M.evaluate_hu(deal: DealState, player_index: integer, concealed: {Tile}, incoming: Tile, is_zi_mo: boolean, is_gang_shang: boolean, is_qiang_gang: boolean): boolean, ScoreResult
   local p      = deal.players[player_index]
   local shapes = validator.find_win_shapes(concealed, incoming, p.hand.sets)
   if #shapes == 0 then return false, {} as ScoreResult end
   local ctx    = M.build_score_ctx(deal, player_index, is_zi_mo, is_gang_shang, is_qiang_gang)
   local output = scorer_mod.score_hand(shapes, ctx)
   if not output.has_best then return false, {} as ScoreResult end
   local final = M.apply_score_modifiers(deal, ctx, shapes, output, player_index)
   return final.valid_hu, final
end

-- Convenience wrapper for callers that have the seat's whole concealed
-- hand and want to ask "would declaring Hu on `incoming` pass the
-- engine's fan threshold?" Handles the zi_mo case where `incoming` is
-- already in concealed_tiles (the engine placed the drawn tile back
-- into the hand before phase transitions); strips one matching tile_id
-- before delegating to evaluate_hu.
function M.would_be_valid_hu(deal: DealState, player_index: integer, incoming: Tile, is_zi_mo: boolean, is_qiang_gang: boolean): boolean
   local p = deal.players[player_index]
   local concealed: {Tile}
   if is_zi_mo then
      concealed = {}
      local removed = false
      for _, t in ipairs(p.hand.concealed_tiles) do
         if not removed and t.tile_id == incoming.tile_id then
            removed = true
         else
            concealed[#concealed + 1] = t
         end
      end
   else
      concealed = p.hand.concealed_tiles
   end
   local valid, _ = M.evaluate_hu(deal, player_index, concealed, incoming, is_zi_mo, false, is_qiang_gang)
   return valid
end

return M
