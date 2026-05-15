-- Run state: per-run tracking of round, lives, active effects, and RNG.
-- No imports from love, ui, scenes, or app.

require("core.types")
require("core.rng")
require("game.deal_types")

local M = {}

global record RunState
   round_index:         integer
   lives:               integer
   active_effects:      {ActiveEffectState}   -- M1 effects (D005)
   active_boons:        {ActiveBoon}          -- M2 run-scoped boons (D012)
   previous_win_rating: Rating
   has_previous_win:    boolean
   rng:                 RngState
end

-- Creates a fresh RunState for a new tournament attempt.
function M.new_run(rng: RngState): RunState
   return {
      round_index         = 1,
      lives               = 3,
      active_effects      = {},
      active_boons        = {},
      previous_win_rating = "" as Rating,
      has_previous_win    = false,
      rng                 = rng,
   }
end

return M
