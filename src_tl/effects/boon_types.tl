-- M2 event-listener boon system: types only.
-- Pure module — no imports from love, ui, scenes, app.
-- Lives alongside M1's effect_types.tl during the M2 transition (D012).

require("core.types")
require("game.deal_types")

-- ── Identity ──────────────────────────────────────────────────────────────

global type Cluster          = string   -- "honor" | "suit" | "concealed"
global type BoonEffectKind   = string   -- "peek" | "mulligan" | "swap" | "extra_draw" | "info" | "token"
global type EventName        = string   -- see fixed vocabulary in MILESTONE-2-PLAN.md §148

-- MilestoneId, AcquisitionPoint, and ActiveBoon are declared in
-- game/deal_types.tl as domain state. See the note there.

-- AcquisitionPoint and ActiveBoon are declared in game/deal_types.tl
-- (alongside ActiveEffectState) because they are domain state stored on
-- DealState/RunState. This module references them through that declaration.

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
   source_player: integer       -- discarder seat for chi/peng/open-kong;
                                -- -1 for self-sourced (ankan, added kong)
   kong_kind:     string        -- "open" | "added" — meaningful only on on_kong;
                                -- empty string ("") for chi/peng/ankan
end

global record HuEvent
   event_name: EventName     -- "on_hu"
   fan_total:  integer
   -- HandSnapshot is intentionally deferred; scoring shape lives in DealResult.
   --
   -- M1 contract: on_hu fires only when PLAYER_OWNER_INDEX wins (zi mo, on
   -- discard, or qiang gang). on_deal_end fires regardless of winner. This
   -- asymmetry is deliberate for M1's single-seat boon ownership; M3+ may
   -- generalize per-seat routing.
end

global record SetFormedEvent
   event_name: EventName     -- "on_set_formed"
   set_index:  integer       -- 1, 2, or 3 — the milestone threshold crossed
end

-- Fires at end-of-turn (after the player's own discard) and once at deal start
-- when a 3rd matching tile is present in the player's concealed_tiles. Fires
-- exactly once per distinct kind per deal — a pung broken and later reformed
-- does NOT re-trigger (Hidden Strength contract, MILESTONE-2-PLAN.md:490).
-- Concealed pungs only "exist" implicitly in concealed_tiles; they are not
-- materialized as TileSet records, so this event is the only signal for them.
global record ConcealedPungFormedEvent
   event_name: EventName     -- "on_concealed_pung_formed"
   kind_id:    TileKindId    -- the tile kind whose 3-of-a-kind formed
   tiles:      {Tile}        -- the three tiles composing the pung
end

global record TingReachedEvent
   event_name: EventName     -- "on_ting_reached"
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
   -- Declared for forward compatibility (plan §186-187). Not emitted by the
   -- engine in S00 — wired alongside set/ting milestones in a follow-up
   -- when a boon actually depends on per-turn lifecycle events.
end

global record DealLifecycleEvent
   event_name: EventName     -- "on_deal_start" | "on_deal_end"
end

-- Fires when the player commits a SpendBoonTokenAction. The engine validates
-- phase + boon-active + token-available, then emits this event. The boon's
-- own listener is responsible for (1) re-validating params (the engine
-- treats them opaquely), (2) calling ctx:spend_token to deduct, and (3)
-- running the spend's effect via primitives. If the listener decides the
-- spend is invalid it must NOT call spend_token — the token stays.
global record TokenSpendEvent
   event_name: EventName             -- "on_token_spent"
   boon_id:    string
   token_kind: string
   params:     {string: string}
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
