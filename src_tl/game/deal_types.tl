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

global type EffectSourceKind = string
-- "boon" | "opponent_package" | "relic" | "class" | "boss_aura" | "challenge"

global record PendingDiscard
   tile:          Tile
   discarder:     integer
end

global record PendingAddedKong
   tile_id:       TileId
   tile:          Tile
   declarer:      integer
end

global record PlayerState
   hand:                 PlayerHand
   opening_trim:         {Tile}   -- tiles trimmed during opening; not in discard pile
   seat_wind:            Wind
   is_human:             boolean
   known_wall_tile_ids:  {TileId} -- per-seat wall visibility from info effects (Third Eye, Open Eyes)
   -- Tile kinds for which a concealed pung has fired its on_concealed_pung_formed
   -- event this deal. Permanent within a deal: a pung that is broken and later
   -- reformed does not re-trigger (per Hidden Strength rule, MILESTONE-2-PLAN.md:490).
   concealed_pung_kinds_seen: {TileKindId}
   -- Number of bonus discards owed this turn. Incremented by extra_draw
   -- (boon primitive); decremented in apply_all_pass after each player
   -- discard. Turn-scoped — reset to 0 when the player's turn begins
   -- (handle_draw and call-apply paths). Per P8 in MILESTONE-2-PLAN.md:417,
   -- every bonus wall draw must produce a matched discard before turn end.
   turn_extra_discards_owed: integer
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
   rng:                  RngState
   deal_result:          DealResult
   has_deal_result:      boolean
   reaction_passes:      {integer}      -- player indices who passed in current window
   pending_claims:       {PendingClaim} -- queued claims awaiting priority resolution
   last_draw_was_supplement: boolean
   last_drawn_tile_id:   TileId         -- tile drawn on the most recent draw (for zi mo)
   has_last_drawn:       boolean
   effect_states:        {string: ActiveEffectState}  -- M1 effects keyed by active_effect_id
   active_boons:         {ActiveBoon}                 -- M2 boons active for this deal
   set_count_high_water: integer                       -- highest set count reached this deal (M2-S01)
   reached_ting:         boolean                       -- ting milestone fired this deal (M2-S01)
   declined_boons_this_deal: {string}                  -- boon ids declined at any fork this deal (M2-S02)

   -- ── Fork-offer flow (M2-S02-T04) ──────────────────────────────────────
   --
   -- pending_forks queues milestone ids fired but not yet resolved. The
   -- head of the queue is materialized into pending_offer + the milestone
   -- field; the player must PickBoonOffer before resuming normal play.
   pending_forks:            {MilestoneId}              -- FIFO queue
   pending_offer:            {string}                   -- boon ids currently offered; empty == no offer
   pending_offer_milestone:  MilestoneId                -- "" iff pending_offer is empty (cleared together)
end

-- An active effect instance owned by a player (or the deal). Counters live here
-- and survive within a deal; persistent ownership lives on RunState.active_effects.
global record ActiveEffectState
   active_effect_id:    string
   effect_id:           string         -- canonical effect id (e.g. "current")
   source_kind:         EffectSourceKind
   source_id:           string         -- e.g. boon id; identifies the source
   owner_player_index:  integer        -- -1 = deal-owned (no specific owner)
   has_owner:           boolean
   counters:            {string: integer}
   used_this_deal:      boolean
end

-- ── M2 boon instance state (D012) ─────────────────────────────────────────
--
-- ActiveBoon, AcquisitionPoint, and MilestoneId live here (alongside
-- ActiveEffectState) because they are domain state stored on
-- DealState/RunState. The M2 boon system (effects.boon_types) extends
-- behavior on top of these records but the records themselves are part of
-- the game domain.

global type AcquisitionPoint = string
-- "starter" | "set_1" | "set_2" | "set_3" | "ting" | "carried"

global type MilestoneId = string
-- "starter" | "set_1" | "set_2" | "set_3" | "ting"

global record ActiveBoon
   boon_id:       string
   acquired_at:   AcquisitionPoint
   counters:      {string: integer}    -- numeric per-boon state
   flags:         {string: boolean}    -- boolean per-boon state
   tokens:        {string: integer}    -- token pools keyed by token_kind
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
   tile_ids:         {TileId}   -- effect-specific payload; e.g. Fresh Start tiles
end

global record DiscardOpeningSurplusAction
   kind:         string   -- "discard_opening_surplus"
   player_index: integer
   tile_id:      TileId
end

global record ConfirmOpeningAction
   kind:         string   -- "confirm_opening"
   player_index: integer
end

global record PickBoonOfferAction
   kind:         string   -- "pick_boon_offer"
   player_index: integer
   boon_id:      string   -- must be one of deal.pending_offer
end

-- Player-initiated spend of a token on one of their active boons (D012).
-- The engine validates phase + token availability, emits on_token_spent for
-- the boon's own listener to consume; the listener is responsible for
-- validating params and running the spend's effect. Tokens are deducted
-- by the listener via ctx:spend_token — engine never deducts. This keeps
-- spend semantics in the boon's effect function, consistent with the
-- event-listener architecture (no new "abilities" field on Boon).
global record SpendBoonTokenAction
   kind:         string   -- "spend_boon_token"
   player_index: integer
   boon_id:      string   -- must match an active boon for player_index
   token_kind:   string   -- e.g. "cleanse_charge", "mulligan", "peek"
   params:       {string: string}   -- boon-specific (e.g. "tile_id" for cleanse)
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
