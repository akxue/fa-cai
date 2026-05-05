-- Vanilla AI decision module. Pure — no imports from love, ui, scenes, app.
--
-- Two entry points:
--   ai.decide_main(deal, player_index)     — when it's the AI's turn
--   ai.decide_reaction(deal, player_index) — when the AI is in a reaction window
--
-- Both return (DealAction, AiReasoning). The scene drives turn pumping by
-- calling these functions and dispatching the returned action through the
-- engine. The AI never mutates state directly. An AI seat may read its own
-- `players[seat].known_wall_tile_ids` (populated only when that seat owns an
-- info effect like Third Eye / Open Eyes); it must not read another seat's
-- list. M1 vanilla AIs own no info effects, so this read returns empty.

require("core.types")
require("game.deal_types")
local engine     = require("game.deal_engine")
local validator  = require("game.hand_validator")
local scorer_mod = require("game.scorer")
local calls_mod  = require("game.calls")
local td         = require("game.ting_distance")
local fx_runner  = require("effects.effect_runner")
local wall_mod   = require("game.wall")

global record AiReasoning
   tag:         string    -- "draw" | "zi_mo" | "discard" | "concealed_kong"
                          -- | "added_kong" | "hu_on_discard" | "peng" | "open_kong"
                          -- | "chi" | "pass_reaction"
   message:     string
   ting_before: integer   -- ting distance before this decision; -100 if N/A
   ting_after:  integer   -- ting distance after this decision; -100 if N/A
end

local M = {}

local PLAYER_COUNT <const> = 4
local NA <const> = -100

-- ── Live-tile bookkeeping ─────────────────────────────────────────────────
-- Returns a `live_counts` map of how many copies of each kind are still
-- drawable from the AI's perspective: 4 minus visible copies in (own
-- concealed, all sets across all players, all discards across all players,
-- pending discard if any). Other players' concealed tiles are intentionally
-- not subtracted — they are not visible to this AI.

local ALL_KINDS: {string} = {
   "tiao_1","tiao_2","tiao_3","tiao_4","tiao_5","tiao_6","tiao_7","tiao_8","tiao_9",
   "wan_1","wan_2","wan_3","wan_4","wan_5","wan_6","wan_7","wan_8","wan_9",
   "bing_1","bing_2","bing_3","bing_4","bing_5","bing_6","bing_7","bing_8","bing_9",
   "east","south","west","north","fa_cai","hong_zhong","bai_ban",
}

function M.compute_live_counts(deal: DealState, player_index: integer): {string:integer}
   local live: {string:integer} = {}
   for _, k in ipairs(ALL_KINDS) do live[k] = 4 end
   local function dec(k: TileKindId)
      local s = k as string
      live[s] = (live[s] or 0) - 1
   end
   for _, t in ipairs(deal.players[player_index].hand.concealed_tiles) do dec(t.kind_id) end
   for i = 1, PLAYER_COUNT do
      local p = deal.players[i]
      for _, s in ipairs(p.hand.sets) do
         for _, t in ipairs(s.tiles) do dec(t.kind_id) end
      end
      for _, t in ipairs(p.hand.discards) do dec(t.kind_id) end
   end
   if deal.has_pending_discard then dec(deal.pending_discard.tile.kind_id) end
   return live
end

-- ── Score-context builder ──────────────────────────────────────────────────
-- Mirrors deal_engine.build_score_ctx so AI Hu legality matches the engine
-- exactly. is_men_qian is derived from open-set visibility.

local function build_score_ctx(
   deal:           DealState,
   player_index:   integer,
   is_zi_mo:       boolean,
   is_gang_shang:  boolean,
   is_qiang_gang:  boolean
): ScoreContext
   local open_sets = deal.players[player_index].hand.sets
   local is_men_qian = true
   for _, s in ipairs(open_sets) do
      if (s.visibility as string) == "open" then
         is_men_qian = false
         break
      end
   end
   local is_hai_di = is_zi_mo and wall_mod.remaining(deal.wall) == 0
   return {
      incoming_tile = { tile_id = "" as TileId, kind_id = "" as TileKindId },
      has_incoming  = not is_zi_mo,
      is_zi_mo      = is_zi_mo,
      is_men_qian   = is_men_qian,
      is_hai_di     = is_hai_di,
      is_gang_shang = is_gang_shang,
      is_qiang_gang = is_qiang_gang,
      round_wind    = deal.round_wind,
      seat_wind     = deal.players[player_index].seat_wind,
   }
end

-- Runs the same validate-and-score path the engine uses for Hu approval.
-- Returns whether the player would have a valid Hu on `incoming` and the
-- best ScoreResult (after boon score modifiers).
local function evaluate_hu(
   deal:           DealState,
   player_index:   integer,
   concealed:      {Tile},
   incoming:       Tile,
   is_zi_mo:       boolean,
   is_gang_shang:  boolean,
   is_qiang_gang:  boolean
): boolean, ScoreResult
   local p      = deal.players[player_index]
   local shapes = validator.find_win_shapes(concealed, incoming, p.hand.sets)
   local ctx    = build_score_ctx(deal, player_index, is_zi_mo, is_gang_shang, is_qiang_gang)
   local output = scorer_mod.score_hand(shapes, ctx)
   if not output.has_best then
      return false, {} as ScoreResult
   end
   local final = fx_runner.apply_score_modifiers(deal, ctx, shapes[1], output.candidates[1], player_index)
   for i = 2, #output.candidates do
      local cand = fx_runner.apply_score_modifiers(deal, ctx, shapes[i], output.candidates[i], player_index)
      local best_rank = final.is_limit and 10000 or final.total_fan
      local cand_rank = cand.is_limit and 10000 or cand.total_fan
      if cand_rank > best_rank then final = cand end
   end
   return final.valid_hu, final
end

-- ── Tile-list helpers ─────────────────────────────────────────────────────

local function tiles_without_id(tiles: {Tile}, tile_id: TileId): {Tile}
   local out: {Tile} = {}
   for _, t in ipairs(tiles) do
      if t.tile_id ~= tile_id then out[#out + 1] = t end
   end
   return out
end

local function tiles_without_kind(tiles: {Tile}, kind_id: TileKindId, max_remove: integer): {Tile}
   local out: {Tile} = {}
   local removed = 0
   for _, t in ipairs(tiles) do
      if removed < max_remove and t.kind_id == kind_id then
         removed = removed + 1
      else
         out[#out + 1] = t
      end
   end
   return out
end

local function tiles_remove_id_pair(tiles: {Tile}, id_a: TileId, id_b: TileId): {Tile}
   local out: {Tile} = {}
   for _, t in ipairs(tiles) do
      if t.tile_id ~= id_a and t.tile_id ~= id_b then
         out[#out + 1] = t
      end
   end
   return out
end

-- ── Discard heuristic ─────────────────────────────────────────────────────
-- For each candidate concealed tile, simulate removal and compute the
-- resulting LIVE ting distance over all shapes. Live ting prunes paths
-- whose required tiles are no longer drawable (already in some discard pile,
-- open set, or the AI's own hand) — this avoids the AI committing to a
-- "ting" hand that will never complete because all winning tiles are dead.

local function pick_best_discard(deal: DealState, player_index: integer): TileId, integer, integer
   local p = deal.players[player_index]
   local concealed = p.hand.concealed_tiles
   local live = M.compute_live_counts(deal, player_index)
   local before = td.ting_distance_live(concealed, p.hand.sets, live)

   local best_id: TileId = concealed[1].tile_id
   local best_after = 1000
   for _, t in ipairs(concealed) do
      local rest = tiles_without_id(concealed, t.tile_id)
      -- After this hypothetical discard, the tile sits in the discard pile —
      -- still not drawable, so the live count is unchanged from `live`.
      local after = td.ting_distance_live(rest, p.hand.sets, live)
      if after < best_after or (after == best_after and (t.tile_id as string) < (best_id as string)) then
         best_id = t.tile_id
         best_after = after
      end
   end
   return best_id, before, best_after
end

-- ── Concealed/added Kong evaluation ───────────────────────────────────────

-- Find a kind held 4 times in concealed tiles, if any.
local function find_concealed_quad_kind(concealed: {Tile}): TileKindId, boolean
   local counts: {string:integer} = {}
   for _, t in ipairs(concealed) do
      local k = t.kind_id as string
      counts[k] = (counts[k] or 0) + 1
   end
   for k, n in pairs(counts) do
      if n >= 4 then return k as TileKindId, true end
   end
   return "" as TileKindId, false
end

-- Find a tile in concealed whose kind matches an existing open Peng. Returns
-- the tile_id and true on hit.
local function find_added_kong_target(concealed: {Tile}, sets: {TileSet}): TileId, boolean
   for _, s in ipairs(sets) do
      if (s.kind as string) == "peng" and #s.tiles > 0 then
         local pk = s.tiles[1].kind_id
         for _, t in ipairs(concealed) do
            if t.kind_id == pk then return t.tile_id, true end
         end
      end
   end
   return "" as TileId, false
end

-- ── Public entry: main turn decision ──────────────────────────────────────

-- Returns the AI's chosen action for its own turn.
-- Phase contract:
--   awaiting_draw  → returns a DrawAction.
--   awaiting_action → considers Zi Mo, then concealed/added Kong, then discard.
-- Other phases return a discard placeholder; callers should not poll AI in
-- non-AI phases.
function M.decide_main(deal: DealState, player_index: integer): DealAction, AiReasoning
   local phase = deal.phase as string

   if phase == "awaiting_draw" then
      local p = deal.players[player_index]
      local live = M.compute_live_counts(deal, player_index)
      local before = td.ting_distance_live(p.hand.concealed_tiles, p.hand.sets, live)
      return engine.draw(player_index), {
         tag         = "draw",
         message     = "draw (ting=" .. tostring(before) .. ")",
         ting_before = before,
         ting_after  = NA,
      }
   end

   if phase == "awaiting_action" then
      local p        = deal.players[player_index]
      local concealed = p.hand.concealed_tiles

      -- Zi Mo: split off last drawn tile and check Hu.
      if deal.has_last_drawn then
         local drawn_id = deal.last_drawn_tile_id
         local drawn_tile: Tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }
         for _, t in ipairs(concealed) do
            if t.tile_id == drawn_id then drawn_tile = t; break end
         end
         if (drawn_tile.tile_id as string) ~= "" then
            local rest = tiles_without_id(concealed, drawn_id)
            local ok, _final = evaluate_hu(deal, player_index, rest, drawn_tile, true, deal.last_draw_was_supplement, false)
            if ok then
               return engine.declare_hu(player_index, "" as TileId, true), {
                  tag         = "zi_mo",
                  message     = "zi mo on " .. (drawn_tile.kind_id as string),
                  ting_before = NA,
                  ting_after  = NA,
               }
            end
         end
      end

      -- Added Kong: prefer it because it preserves an existing committed shape.
      local ak_id, ak_ok = find_added_kong_target(concealed, p.hand.sets)
      if ak_ok then
         return engine.declare_added_kong(player_index, ak_id), {
            tag         = "added_kong",
            message     = "added kong",
            ting_before = NA,
            ting_after  = NA,
         }
      end

      -- Concealed Kong: only declare if removing the four tiles does not
      -- worsen ting distance (it shouldn't, since the four become a set).
      local quad_kind, has_quad = find_concealed_quad_kind(concealed)
      if has_quad then
         local live = M.compute_live_counts(deal, player_index)
         local before = td.ting_distance_live(concealed, p.hand.sets, live)
         local rest   = tiles_without_kind(concealed, quad_kind, 4)
         local fake_set: TileSet = {
            kind        = "kong" as TileSetKind,
            visibility  = "concealed" as SetVisibility,
            tiles       = {},
            called_from = -1,
         }
         local sets_after: {TileSet} = {}
         for _, s in ipairs(p.hand.sets) do sets_after[#sets_after + 1] = s end
         sets_after[#sets_after + 1] = fake_set
         local after = td.ting_distance_live(rest, sets_after, live)
         if after <= before then
            return engine.declare_concealed_kong(player_index, quad_kind), {
               tag         = "concealed_kong",
               message     = "concealed kong " .. (quad_kind as string),
               ting_before = before,
               ting_after  = after,
            }
         end
      end

      -- Default: pick best discard.
      local tid, before, after = pick_best_discard(deal, player_index)
      return engine.discard(player_index, tid), {
         tag         = "discard",
         message     = "discard " .. (tid as string),
         ting_before = before,
         ting_after  = after,
      }
   end

   -- Unknown phase: defensive — return a draw with NA reasoning. Callers should
   -- not invoke decide_main outside the AI's turn.
   return engine.draw(player_index), {
      tag         = "draw",
      message     = "unexpected phase: " .. phase,
      ting_before = NA,
      ting_after  = NA,
   }
end

-- ── Public entry: reaction-window decision ────────────────────────────────

-- Picks the AI's response to a pending discard or pending added kong. Order
-- of consideration: Hu > open_kong > Peng > Chi > pass. A call is only made
-- if it does not regress ting distance compared to the no-call state. Hu is
-- evaluated through the engine's same scoring path, so the 3-fan minimum
-- and boon modifiers apply.
function M.decide_reaction(deal: DealState, player_index: integer): DealAction, AiReasoning
   if (deal.phase as string) ~= "reaction_window" then
      return engine.pass_reaction(player_index), {
         tag         = "pass_reaction",
         message     = "not in reaction window",
         ting_before = NA,
         ting_after  = NA,
      }
   end

   local p = deal.players[player_index]
   local concealed = p.hand.concealed_tiles

   -- Hu on discard (or qiang gang on pending added kong).
   if deal.has_pending_discard then
      if player_index ~= deal.pending_discard.discarder then
         local incoming = deal.pending_discard.tile
         local ok, _final = evaluate_hu(deal, player_index, concealed, incoming, false, false, false)
         if ok then
            return engine.declare_hu(player_index, incoming.tile_id, false), {
               tag         = "hu_on_discard",
               message     = "hu on " .. (incoming.kind_id as string),
               ting_before = NA,
               ting_after  = NA,
            }
         end
      end
   elseif deal.has_pending_kong then
      if player_index ~= deal.pending_added_kong.declarer then
         local kong_tile = deal.pending_added_kong.tile
         local ok, _final = evaluate_hu(deal, player_index, concealed, kong_tile, false, false, true)
         if ok then
            return engine.declare_hu(player_index, deal.pending_added_kong.tile_id, false), {
               tag         = "hu_on_discard",
               message     = "qiang gang on " .. (kong_tile.kind_id as string),
               ting_before = NA,
               ting_after  = NA,
            }
         end
      end
      -- No legal Peng/Chi/Open Kong on a pending added kong.
      return engine.pass_reaction(player_index), {
         tag         = "pass_reaction",
         message     = "pass on added kong",
         ting_before = NA,
         ting_after  = NA,
      }
   end

   -- Discard-driven calls: open_kong → peng → chi.
   if deal.has_pending_discard then
      if player_index == deal.pending_discard.discarder then
         return engine.pass_reaction(player_index), {
            tag         = "pass_reaction",
            message     = "discarder passes own window",
            ting_before = NA,
            ting_after  = NA,
         }
      end
      local discarded = deal.pending_discard.tile
      local discarder = deal.pending_discard.discarder
      local live   = M.compute_live_counts(deal, player_index)
      local before = td.ting_distance_live(concealed, p.hand.sets, live)

      -- Open Kong: 3 in hand + 1 from discard. Set absorbs all 3 matching tiles.
      if calls_mod.can_open_kong(discarded, concealed, discarder, player_index) then
         local rest = tiles_without_kind(concealed, discarded.kind_id, 3)
         local sets_after = {} as {TileSet}
         for _, s in ipairs(p.hand.sets) do sets_after[#sets_after + 1] = s end
         sets_after[#sets_after + 1] = {
            kind        = "kong" as TileSetKind,
            visibility  = "open" as SetVisibility,
            tiles       = {},
            called_from = discarder,
         }
         local after = td.ting_distance_live(rest, sets_after, live)
         if after <= before then
            return engine.declare_open_kong(player_index, discarded.tile_id), {
               tag         = "open_kong",
               message     = "open kong " .. (discarded.kind_id as string),
               ting_before = before,
               ting_after  = after,
            }
         end
      end

      -- Peng: 2 in hand + 1 from discard.
      if calls_mod.can_peng(discarded, concealed, discarder, player_index) then
         local rest = tiles_without_kind(concealed, discarded.kind_id, 2)
         local sets_after = {} as {TileSet}
         for _, s in ipairs(p.hand.sets) do sets_after[#sets_after + 1] = s end
         sets_after[#sets_after + 1] = {
            kind        = "peng" as TileSetKind,
            visibility  = "open" as SetVisibility,
            tiles       = {},
            called_from = discarder,
         }
         local after = td.ting_distance_live(rest, sets_after, live)
         if after <= before then
            return engine.declare_peng(player_index, discarded.tile_id), {
               tag         = "peng",
               message     = "peng " .. (discarded.kind_id as string),
               ting_before = before,
               ting_after  = after,
            }
         end
      end

      -- Chi: only the next player can chi. Take the first combination that
      -- does not regress ting distance, deterministic by combo order.
      if calls_mod.is_next_player(discarder, player_index, PLAYER_COUNT) then
         local combos = calls_mod.chi_combinations(discarded, concealed)
         for _, pair in ipairs(combos) do
            local rest = tiles_remove_id_pair(concealed, pair[1], pair[2])
            local sets_after = {} as {TileSet}
            for _, s in ipairs(p.hand.sets) do sets_after[#sets_after + 1] = s end
            sets_after[#sets_after + 1] = {
               kind        = "chi" as TileSetKind,
               visibility  = "open" as SetVisibility,
               tiles       = {},
               called_from = discarder,
            }
            local after = td.ting_distance_live(rest, sets_after, live)
            if after <= before then
               return engine.declare_chi(player_index, discarded.tile_id, pair), {
                  tag         = "chi",
                  message     = "chi " .. (discarded.kind_id as string),
                  ting_before = before,
                  ting_after  = after,
               }
            end
         end
      end
   end

   return engine.pass_reaction(player_index), {
      tag         = "pass_reaction",
      message     = "pass",
      ting_before = NA,
      ting_after  = NA,
   }
end

return M
