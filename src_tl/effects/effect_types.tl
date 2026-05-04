-- Typed effect system shared types: metadata, queries, commands, and the
-- EffectModule interface. Pure module — no imports from love, ui, scenes, app.

require("core.types")
require("game.deal_types")

-- ── Metadata (content-side description) ───────────────────────────────────

global record EffectMetadata
   effect_id:    string
   label:        string         -- player-facing name
   description:  string         -- short description text
   source_kind:  EffectSourceKind
   source_id:    string         -- e.g. boon id (often == effect_id for boons)
   priority:     integer        -- lower runs earlier; default 100
end

-- ── Queries (read-only, no state mutation) ────────────────────────────────

global record OpeningModifiers
   extra_opening_tiles: integer  -- additional tiles dealt to dealer at opening
end

global record EffectAction
   active_effect_id: string
   label:            string
   payload_kind:     string      -- effect-specific identifier
end

-- ── Command envelope ──────────────────────────────────────────────────────
--
-- Mirrors the DealAction pattern: a public typed envelope with `command_kind`,
-- and concrete records that all carry the same field. Builders return the
-- envelope; the engine casts back to the concrete record at runtime.

global record EffectCommand
   command_kind: string
end

global record IncrementCounterCommand
   command_kind:     string   -- "increment_counter"
   active_effect_id: string
   counter_key:      string
   delta:            integer
end

global record SetCounterCommand
   command_kind:     string   -- "set_counter"
   active_effect_id: string
   counter_key:      string
   value:            integer
end

global record MarkUsedCommand
   command_kind:     string   -- "mark_used"
   active_effect_id: string
end

global record RevealWallFrontCommand
   command_kind: string       -- "reveal_wall_front"
   count:        integer
end

global record ReplaceConcealedTilesCommand
   command_kind:        string    -- "replace_concealed_tiles"
   player_index:        integer
   tile_ids_to_remove:  {TileId}
   reshuffle_wall:      boolean
end

global record AddLogCommand
   command_kind: string       -- "add_log"
   message:      string
end

-- ── Module interface ──────────────────────────────────────────────────────
--
-- Hooks are optional. Implementers fill only the functions they need; the
-- runner null-checks each hook before calling. Hooks must be pure: read deal
-- + active state, return commands or score reasons.

global record EffectScoreContext
   active:        ActiveEffectState
   ctx:           ScoreContext
   shape:         WinShape
   player_index:  integer
end

global record EffectAfterDrawContext
   active:        ActiveEffectState
   player_index:  integer
   drawn_tile:    Tile
   is_supplement: boolean
end

global record EffectAfterPengContext
   active:        ActiveEffectState
   player_index:  integer
end

global record EffectOpeningContext
   active:        ActiveEffectState
   round_index:   integer
end

global record EffectUseContext
   active:        ActiveEffectState
   player_index:  integer
   tile_ids:      {TileId}
end

global record EffectModule
   metadata:                 EffectMetadata
   on_score:                 function(EffectScoreContext, DealState): {ScoreReason}
   on_after_draw:            function(EffectAfterDrawContext, DealState): {EffectCommand}
   on_after_peng:            function(EffectAfterPengContext, DealState): {EffectCommand}
   on_opening_deal_complete: function(EffectOpeningContext, DealState): {EffectCommand}
   on_use_action:            function(EffectUseContext, DealState): {EffectCommand}
   collect_opening_modifiers: function(ActiveEffectState, integer): OpeningModifiers
   collect_available_actions: function(ActiveEffectState, DealState, integer): {EffectAction}
end

return {}
