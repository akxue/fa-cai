-- BoonContext constructor. Builds the per-listener context record that
-- exposes the engine primitive API to a boon's condition/effect functions.
-- Pure rules layer — no love/ui/scenes/app imports.

require("core.types")
require("game.deal_types")
require("effects.boon_types")

local primitives = require("effects.boon_primitives")

local M = {}

-- Constructs a BoonContext bound to (deal, active_boon, player_index).
-- The returned record carries the primitive functions as fields so boons can
-- call them via `ctx:peek_wall(2)` / `ctx:grant_token("foo", 1)` etc.
--
-- Implementation note: primitive function references are reused across calls
-- (they live at module scope on boon_primitives); only the value record is
-- allocated per context.
function M.make(deal: DealState, active: ActiveBoon, player_index: integer): BoonContext
   return {
      active                    = active,
      deal                      = deal,
      player_index              = player_index,

      get_counter               = primitives.get_counter,
      set_counter               = primitives.set_counter,
      get_flag                  = primitives.get_flag,
      set_flag                  = primitives.set_flag,

      peek_wall                 = primitives.peek_wall,
      live_counter              = primitives.live_counter,
      discard_and_redraw        = primitives.discard_and_redraw,
      swap_hand_for_wall        = primitives.swap_hand_for_wall,
      extra_draw                = primitives.extra_draw,
      reveal_opponent_last_draw = primitives.reveal_opponent_last_draw,
      take_from_discard_pile    = primitives.take_from_discard_pile,

      grant_token               = primitives.grant_token,
      spend_token               = primitives.spend_token,
      get_tokens                = primitives.get_tokens,

      prompt_player             = primitives.prompt_player,
   }
end

-- Convenience: a fresh empty ActiveBoon shell for tests and offer-pool
-- construction. Boon-specific state lives in counters / flags / tokens maps.
function M.new_active(boon_id: string, acquired_at: AcquisitionPoint): ActiveBoon
   return {
      boon_id     = boon_id,
      acquired_at = acquired_at,
      counters    = {},
      flags       = {},
      tokens      = {},
   }
end

return M
