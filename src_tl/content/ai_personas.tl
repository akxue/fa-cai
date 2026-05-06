-- AI persona content. Each opponent seat (2/3/4) gets a name + archetype
-- so the table reads as "you vs. three named opponents" rather than
-- "you vs. P2/P3/P4". Pure data; the persona doesn't influence engine
-- behaviour in M1 — vanilla AI plays the same regardless. Hooks for
-- per-persona AI strategy land later.

local M = {}

global record AIPersona
   name:      string   -- display name, e.g. "South AI"
   archetype: string   -- one-word strategy hint, e.g. "Pure Suit"
end

-- Engine convention: seat 1 East = player; 2 South / 3 West / 4 North
-- are AI. Persona names lean into the seat wind so the player can
-- match the badge to the seat at a glance.
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
