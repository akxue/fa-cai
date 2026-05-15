-- M2 event-listener boon system: types only.
-- Pure module — no imports from love, ui, scenes, app.
-- Lives alongside M1's effect_types.tl during the M2 transition (D012).

require("core.types")
require("game.deal_types")

-- ── Identity ──────────────────────────────────────────────────────────────

global type Cluster          = string   -- "honor" | "suit" | "concealed"
global type MilestoneId      = string   -- "starter" | "set_1" | "set_2" | "set_3" | "ting"
global type BoonEffectKind   = string   -- "peek" | "mulligan" | "swap" | "extra_draw" | "info" | "token"
global type AcquisitionPoint = string   -- MilestoneId values plus "carried"
global type EventName        = string   -- see fixed vocabulary in MILESTONE-2-PLAN.md §148

-- Function-type aliases used in BoonContext / live_counter signatures.
-- Aliased to dodge Teal's tuple-return parsing of bare `function(X): bool, Y`.
global type TileFilter = function(Tile): boolean

-- ── Event payload envelope ────────────────────────────────────────────────
--
-- Mirrors the DealAction / EffectCommand pattern: a public typed envelope
-- whose every concrete payload record carries the same `event_name` field.
-- The dispatcher casts back to the concrete record at runtime.

global record EventData
   event_name: EventName
end

global record PlayerDrawEvent
   event_name: EventName     -- "on_player_draw"
   tile:       Tile
end

global record PlayerDiscardEvent
   event_name: EventName     -- "on_player_discard"
   tile:       Tile
end

global record CallEvent
   event_name:    EventName     -- "on_chi" | "on_peng" | "on_kong" | "on_ankan"
   tile_set:      TileSet
   source_player: integer       -- -1 for ankan (no discarder)
end

global record HuEvent
   event_name: EventName     -- "on_hu"
   fan_total:  integer
   -- HandSnapshot is intentionally deferred; scoring shape lives in DealResult
end

global record OpponentDiscardEvent
   event_name:     EventName     -- "on_opponent_discard"
   opponent_index: integer
   tile:           Tile
end

global record OpponentCallEvent
   event_name:     EventName     -- "on_opponent_call"
   opponent_index: integer
   call_kind:      string         -- "chi" | "peng" | "kong" | "ankan"
   tile_set:       TileSet
end

global record OpponentDrawEvent
   event_name:     EventName     -- "on_opponent_draw"
   opponent_index: integer
   tile:           Tile
end

-- Tile-property events derived from base draw/discard. Payload mirrors the
-- triggering base event so listeners receive the same tile reference.

global record TilePropertyEvent
   event_name: EventName     -- "on_honor_drawn" | "on_dragon_drawn" | ...
   tile:       Tile
end

global record OpponentTilePropertyEvent
   event_name:     EventName     -- "on_opponent_honor_discarded" | ...
   opponent_index: integer
   tile:           Tile
end

global record TurnEvent
   event_name: EventName     -- "on_turn_start" | "on_turn_end"
   turn_index: integer
end

global record DealLifecycleEvent
   event_name: EventName     -- "on_deal_start" | "on_deal_end"
end

-- ── Boon record (catalog entry) ───────────────────────────────────────────
--
-- A boon is a pure data record. Effects mutate state only through the
-- BoonContext API; condition functions are read-only.

global record Boon
   id:                   string
   cluster:              Cluster
   name:                 string         -- player-facing display name
   description:          string         -- player-facing text
   eligible_milestones:  {MilestoneId}
   effect_kind:          BoonEffectKind
   weight:               number         -- selection weight; default 1.0
   listens:              {EventName}
   condition:            function(BoonContext, EventData): boolean
   effect:               function(BoonContext, EventData)
end

-- ── ActiveBoon (instance state held on Run / Deal state) ──────────────────

global record ActiveBoon
   boon_id:       string
   acquired_at:   AcquisitionPoint
   counters:      {string: integer}    -- numeric per-boon state (counters, accumulators)
   flags:         {string: boolean}    -- boolean per-boon state (used_this_deal, etc.)
   tokens:        {string: integer}    -- token pools keyed by token_kind
end

-- ── BoonContext (API surface visible to condition/effect functions) ───────
--
-- A pre-resolved view of deal/run state plus mutation primitives. The engine
-- builds a fresh context for each listener invocation; the context closes
-- over the active boon, the current deal, and the dispatch site so primitives
-- can locate state without listeners passing it around.
--
-- T02/T03/T05 fill in the function bodies. T00 only declares the surface.

global record BoonContext
   active:        ActiveBoon
   deal:          DealState
   player_index:  integer            -- the boon's owner seat (player is seat 0 in M1)

   -- Per-boon state accessors (used for non-token counters/flags)
   get_counter:   function(BoonContext, string): integer
   set_counter:   function(BoonContext, string, integer)
   get_flag:      function(BoonContext, string): boolean
   set_flag:      function(BoonContext, string, boolean)

   -- The 7 engine primitives. Wired in T02.
   peek_wall:                  function(BoonContext, integer): {Tile}
   live_counter:               function(BoonContext, TileFilter, string): integer
   discard_and_redraw:         function(BoonContext): Tile
   swap_hand_for_wall:         function(BoonContext, TileId): Tile
   extra_draw:                 function(BoonContext): Tile
   reveal_opponent_last_draw:  function(BoonContext, integer): Tile
   take_from_discard_pile:     function(BoonContext, integer, TileId, integer): Tile

   -- Token state primitives. Wired in T03.
   grant_token:  function(BoonContext, string, integer)
   spend_token:  function(BoonContext, string, integer): boolean
   get_tokens:   function(BoonContext, string): integer

   -- Player prompt stub (real implementation arrives with milestone-fork UI
   -- in S02). Returns nil string in S00; callers must tolerate.
   prompt_player: function(BoonContext, string, {string}): string
end

return {}
