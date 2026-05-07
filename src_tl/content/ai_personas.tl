-- AI persona content. Pure data; the persona doesn't influence engine
-- behaviour in M1. Hooks for per-persona strategy land later.

local M = {}

global record AIPersona
   name:      string
   archetype: string
end

-- Indexed by seat (1 East = player, 2 South / 3 West / 4 North = AI).
local PERSONAS: {AIPersona} = {
   { name = "You",      archetype = ""               },
   { name = "South AI", archetype = "Pure Suit"      },
   { name = "West AI",  archetype = "Triplet Hunter" },
   { name = "North AI", archetype = "Dragon Chaser"  },
}

function M.for_seat(seat_index: integer): AIPersona
   return PERSONAS[seat_index]
end

return M
