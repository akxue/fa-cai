-- Core deal types: hands, sets, actions, events, scoring, and state records.
-- No imports from love, ui, scenes, or app.

require("core.types")
require("core.rng")
require("game.wall")

-- ── Tile sets ──────────────────────────────────────────────────────────────

global type TileSetKind   = string   -- "chi" | "peng" | "kong"
global type SetVisibility = string   -- "open" | "concealed"

global record TileSet
   kind:        TileSetKind
   visibility:  SetVisibility
   tiles:       {Tile}
   called_from: integer   -- seat index of the discarding player; -1 for self/concealed
end

-- ── Player hand ───────────────────────────────────────────────────────────

global record PlayerHand
   concealed_tiles: {Tile}
   sets:            {TileSet}
   discards:        {Tile}
end

-- ── Player and deal state ─────────────────────────────────────────────────

global type DealPhase = string
-- "opening_actions" | "awaiting_draw" | "awaiting_action"
-- | "reaction_window" | "deal_over"

global record PendingDiscard
   tile:          Tile
   discarder:     integer
end

global record PendingAddedKong
   tile_id:       TileId
   declarer:      integer
end

global record PlayerState
   hand:          PlayerHand
   opening_trim:  {Tile}   -- tiles trimmed during opening; not in discard pile
   seat_wind:     Wind
   is_human:      boolean
end

global record DealResult
   winner_player_index: integer   -- -1 = wall exhaustion, no winner
   won_by_zi_mo:        boolean
   score_result:        ScoreResult   -- defined below; forward ref resolved at use
   has_score_result:    boolean
end

-- A queued reaction-window claim awaiting priority resolution.
-- chi_other_tile_ids is populated only when kind == "chi".
global record PendingClaim
   player_index:       integer
   kind:               string   -- "hu" | "peng" | "chi" | "open_kong"
   chi_other_tile_ids: {TileId}
end

global record DealState
   players:              {PlayerState}
   wall:                 WallState
   phase:                DealPhase
   current_player:       integer
   dealer:               integer
   round_wind:           Wind
   pending_discard:      PendingDiscard
   has_pending_discard:  boolean
   pending_added_kong:   PendingAddedKong
   has_pending_kong:     boolean
   known_wall_tile_ids:  {TileId}
   rng:                  RngState
   deal_result:          DealResult
   has_deal_result:      boolean
   reaction_passes:      {integer}      -- player indices who passed in current window
   pending_claims:       {PendingClaim} -- queued claims awaiting priority resolution
   last_draw_was_supplement: boolean
   last_drawn_tile_id:   TileId         -- tile drawn on the most recent draw (for zi mo)
   has_last_drawn:       boolean
end

-- Placeholder — filled out in S04. Every active effect carries an id.
global record ActiveEffectState
   active_effect_id: string
end

-- ── Win shapes ────────────────────────────────────────────────────────────

global type WinShapeKind = string
-- "standard_four_sets_pair" | "seven_pairs" | "thirteen_orphans" | "nine_gates"

global record WinShape
   kind:       WinShapeKind
   sets:       {TileSet}   -- all four sets (open + decomposed concealed)
   pair_kind:  TileKindId   -- kind_id of the pair
end

-- ── Scoring ───────────────────────────────────────────────────────────────

global type ScoreReasonCategory = string
-- "hand_pattern" | "modifier" | "boon" | "limit"

global type Rating = string
-- "C" | "B" | "A" | "S" | "SS" | "Legend"

global record ScoreReason
   category: ScoreReasonCategory
   label:    string
   fan:      integer
   is_limit: boolean
end

global record ScoreResult
   win_shape_kind: WinShapeKind
   reasons:        {ScoreReason}
   total_fan:      integer
   is_limit:       boolean
   rating:         Rating
   valid_hu:       boolean
end

global record ScoreContext
   incoming_tile:    Tile
   has_incoming:     boolean   -- false for Zi Mo (tile already in hand)
   is_zi_mo:         boolean
   is_men_qian:      boolean
   is_hai_di:        boolean
   is_gang_shang:    boolean
   is_qiang_gang:    boolean
   round_wind:       Wind
   seat_wind:        Wind
end

-- ── Actions ───────────────────────────────────────────────────────────────

global record DrawAction
   kind:         string   -- "draw"
   player_index: integer
end

global record DiscardAction
   kind:         string   -- "discard"
   player_index: integer
   tile_id:      TileId
end

global record DeclareHuAction
   kind:             string   -- "declare_hu"
   player_index:     integer
   incoming_tile_id: TileId   -- empty string for Zi Mo
   is_zi_mo:         boolean
end

global record DeclareChiAction
   kind:           string   -- "declare_chi"
   player_index:   integer
   tile_id:        TileId
   other_tile_ids: {TileId}
end

global record DeclarePengAction
   kind:         string   -- "declare_peng"
   player_index: integer
   tile_id:      TileId
end

global record DeclareOpenKongAction
   kind:         string   -- "declare_open_kong"
   player_index: integer
   tile_id:      TileId
end

global record DeclareConcealedKongAction
   kind:          string   -- "declare_concealed_kong"
   player_index:  integer
   tile_kind_id:  TileKindId
end

global record DeclareAddedKongAction
   kind:         string   -- "declare_added_kong"
   player_index: integer
   tile_id:      TileId
end

global record PassReactionAction
   kind:         string   -- "pass_reaction"
   player_index: integer
end

global record UseEffectAction
   kind:             string   -- "use_effect_action"
   player_index:     integer
   active_effect_id: string
end

-- ── Events ────────────────────────────────────────────────────────────────

global record DealEvent
   kind:    string
   message: string
end

global record DealTransition
   ok:     boolean
   deal:   DealState
   events: {DealEvent}
   error:  string
end

-- Public action envelope. All concrete action records (DrawAction, DiscardAction,
-- DeclareHuAction, ...) carry the same `kind: string` field plus action-specific
-- data; DealAction is the typed boundary used by apply_action. Construct one via
-- the builder functions exported from deal_engine (engine.draw, engine.discard, …).
global record DealAction
   kind: string
end

return {}
