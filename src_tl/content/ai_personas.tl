-- AI persona content. Pure data; the persona doesn't influence engine
-- behaviour in M1. Hooks for per-persona strategy land later.

local M = {}

global record AIPersona
   archetype: string
end

-- Indexed by seat (1 East = player, 2 South / 3 West / 4 North = AI).
local PERSONAS: {AIPersona} = {
   { archetype = ""               },
   { archetype = "Pure Suit"      },
   { archetype = "Triplet Hunter" },
   { archetype = "Dragon Chaser"  },
}

function M.for_seat(seat_index: integer): AIPersona
   return PERSONAS[seat_index]
end

return M
