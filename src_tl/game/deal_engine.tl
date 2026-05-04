-- Deal engine: deterministic state machine for one mahjong deal.
-- Implements opening deal, draw/discard flow, reaction windows, Kong flows,
-- Hu resolution, and wall exhaustion.
-- No imports from love, ui, scenes, or app.

require("core.types")
require("core.rng")
require("game.deal_types")
local wall_mod   = require("game.wall")
local tiles_mod  = require("game.tiles")
local calls_mod  = require("game.calls")
local scorer_mod = require("game.scorer")

local M = {}

local PLAYER_COUNT <const> = 4

local SEAT_WINDS: {Wind} = {
   "east" as Wind, "south" as Wind, "west" as Wind, "north" as Wind,
}

-- ── Deep copy helpers ──────────────────────────────────────────────────────

local function copy_tiles(tiles: {Tile}): {Tile}
   local out: {Tile} = {}
   for _, t in ipairs(tiles) do out[#out + 1] = t end
   return out
end

local function copy_tile_ids(ids: {TileId}): {TileId}
   local out: {TileId} = {}
   for _, id in ipairs(ids) do out[#out + 1] = id end
   return out
end

local function copy_set(s: TileSet): TileSet
   return {
      kind        = s.kind,
      visibility  = s.visibility,
      tiles       = copy_tiles(s.tiles),
      called_from = s.called_from,
   }
end

local function copy_hand(h: PlayerHand): PlayerHand
   local sets: {TileSet} = {}
   for _, s in ipairs(h.sets) do sets[#sets + 1] = copy_set(s) end
   return {
      concealed_tiles = copy_tiles(h.concealed_tiles),
      sets            = sets,
      discards        = copy_tiles(h.discards),
   }
end

local function copy_player(p: PlayerState): PlayerState
   return {
      hand         = copy_hand(p.hand),
      opening_trim = copy_tiles(p.opening_trim),
      seat_wind    = p.seat_wind,
      is_human     = p.is_human,
   }
end

local function copy_deal(d: DealState): DealState
   local players: {PlayerState} = {}
   for _, p in ipairs(d.players) do players[#players + 1] = copy_player(p) end
   local passes: {integer} = {}
   for _, pi in ipairs(d.reaction_passes) do passes[#passes + 1] = pi end
   return {
      players                  = players,
      wall                     = { tiles = copy_tiles(d.wall.tiles) },
      phase                    = d.phase,
      current_player           = d.current_player,
      dealer                   = d.dealer,
      round_wind               = d.round_wind,
      pending_discard          = d.pending_discard,
      has_pending_discard      = d.has_pending_discard,
      pending_added_kong       = d.pending_added_kong,
      has_pending_kong         = d.has_pending_kong,
      known_wall_tile_ids      = copy_tile_ids(d.known_wall_tile_ids),
      rng                      = d.rng,
      deal_result              = d.deal_result,
      has_deal_result          = d.has_deal_result,
      reaction_passes          = passes,
      last_draw_was_supplement = d.last_draw_was_supplement,
      last_drawn_tile_id       = d.last_drawn_tile_id,
      has_last_drawn           = d.has_last_drawn,
   }
end

-- ── Tile manipulation helpers ──────────────────────────────────────────────

-- Returns the tile and true if found; a dummy tile and false if not.
local function find_tile(tiles: {Tile}, tile_id: TileId): Tile, boolean
   for _, t in ipairs(tiles) do
      if (t.tile_id as string) == (tile_id as string) then return t, true end
   end
   return { tile_id = "" as TileId, kind_id = "" as TileKindId }, false
end

-- Returns list with the first occurrence of tile_id removed, and whether it was found.
local function remove_tile(tiles: {Tile}, tile_id: TileId): {Tile}, boolean
   local out: {Tile} = {}
   local found = false
   for _, t in ipairs(tiles) do
      if not found and (t.tile_id as string) == (tile_id as string) then
         found = true
      else
         out[#out + 1] = t
      end
   end
   return out, found
end

-- Removes up to `count` tiles of kind_id. Returns remaining list and removed tiles.
local function remove_by_kind(tiles: {Tile}, kind_id: TileKindId, count: integer): {Tile}, {Tile}
   local remaining: {Tile} = {}
   local removed: {Tile}   = {}
   for _, t in ipairs(tiles) do
      if #removed < count and t.kind_id == kind_id then
         removed[#removed + 1] = t
      else
         remaining[#remaining + 1] = t
      end
   end
   return remaining, removed
end

-- Returns known_wall_tile_ids with tile_id removed (if present).
local function remove_known(known: {TileId}, tile_id: TileId): {TileId}
   local out: {TileId} = {}
   local done = false
   for _, id in ipairs(known) do
      if not done and (id as string) == (tile_id as string) then done = true
      else out[#out + 1] = id end
   end
   return out
end

local function has_passed(passes: {integer}, player_index: integer): boolean
   for _, pi in ipairs(passes) do
      if pi == player_index then return true end
   end
   return false
end

-- ── Transition builders ────────────────────────────────────────────────────

local function err(deal: DealState, msg: string): DealTransition
   return { ok = false, deal = deal, events = {}, error = msg }
end

local function ok_t(deal: DealState, events: {DealEvent}): DealTransition
   return { ok = true, deal = deal, events = events, error = "" }
end

local function ev(kind: string, msg: string): DealEvent
   return { kind = kind, message = msg }
end

-- ── Empty value constructors ───────────────────────────────────────────────

local function empty_score_result(): ScoreResult
   return {
      win_shape_kind = "" as WinShapeKind,
      reasons        = {},
      total_fan      = 0,
      is_limit       = false,
      rating         = "" as Rating,
      valid_hu       = false,
   }
end

local function empty_deal_result(): DealResult
   return {
      winner_player_index = 0,
      won_by_zi_mo        = false,
      score_result        = empty_score_result(),
      has_score_result    = false,
   }
end

local function empty_pending_discard(): PendingDiscard
   return { tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }, discarder = 0 }
end

local function empty_pending_kong(): PendingAddedKong
   return { tile_id = "" as TileId, declarer = 0 }
end

-- ── Wall exhaustion ────────────────────────────────────────────────────────

local function wall_exhaustion(d: DealState): DealTransition
   d.phase = "deal_over" as DealPhase
   d.deal_result = {
      winner_player_index = -1,
      won_by_zi_mo        = false,
      score_result        = empty_score_result(),
      has_score_result    = false,
   }
   d.has_deal_result = true
   return ok_t(d, { ev("wall_exhaustion", "wall exhausted — no winner") })
end

-- ── Supplement draw ────────────────────────────────────────────────────────

-- Draws a supplement tile from the back of the wall into player_index's hand.
-- Returns updated DealState and whether the wall was already empty.
local function draw_supplement(d: DealState, player_index: integer): DealState, boolean
   if wall_mod.remaining(d.wall) == 0 then
      return d, true
   end
   local dr = wall_mod.draw_back(d.wall)
   d.wall = dr.wall
   d.players[player_index].hand.concealed_tiles[
      #d.players[player_index].hand.concealed_tiles + 1
   ] = dr.tile
   d.last_draw_was_supplement = true
   d.last_drawn_tile_id       = dr.tile.tile_id
   d.has_last_drawn           = true
   return d, false
end

-- ── Opening deal ──────────────────────────────────────────────────────────

-- Creates a new DealState with 136 tiles shuffled and 13 dealt to each player.
-- Milestone 1 defaults: dealer = player 1, round wind = east, player 1 is human.
-- S03: opening_actions phase is skipped (no effects yet).
function M.new_deal(rng: RngState): DealState
   local all_tiles = tiles_mod.make_full_tile_set()
   local wall_result = wall_mod.make_wall(all_tiles, rng)
   local w = wall_result.wall
   local cur_rng = wall_result.rng

   local players: {PlayerState} = {}
   for i = 1, PLAYER_COUNT do
      local hand_tiles: {Tile} = {}
      for _ = 1, 13 do
         local dr = wall_mod.draw_front(w)
         hand_tiles[#hand_tiles + 1] = dr.tile
         w = dr.wall
      end
      players[i] = {
         hand = { concealed_tiles = hand_tiles, sets = {}, discards = {} },
         opening_trim = {},
         seat_wind    = SEAT_WINDS[i],
         is_human     = (i == 1),
      }
   end

   return {
      players                  = players,
      wall                     = w,
      phase                    = "awaiting_draw" as DealPhase,
      current_player           = 1,
      dealer                   = 1,
      round_wind               = "east" as Wind,
      pending_discard          = empty_pending_discard(),
      has_pending_discard      = false,
      pending_added_kong       = empty_pending_kong(),
      has_pending_kong         = false,
      known_wall_tile_ids      = {},
      rng                      = cur_rng,
      deal_result              = empty_deal_result(),
      has_deal_result          = false,
      reaction_passes          = {},
      last_draw_was_supplement = false,
      last_drawn_tile_id       = "" as TileId,
      has_last_drawn           = false,
   }
end

-- ── Draw ──────────────────────────────────────────────────────────────────

local function handle_draw(deal: DealState, action: DrawAction): DealTransition
   if (deal.phase as string) ~= "awaiting_draw" then
      return err(deal, "draw requires awaiting_draw phase, got: " .. (deal.phase as string))
   end
   if action.player_index ~= deal.current_player then
      return err(deal, "draw: wrong player " .. tostring(action.player_index) .. ", expected " .. tostring(deal.current_player))
   end
   if wall_mod.remaining(deal.wall) == 0 then
      local d = copy_deal(deal)
      return wall_exhaustion(d)
   end

   local dr = wall_mod.draw_front(deal.wall)
   local d = copy_deal(deal)
   d.wall = dr.wall
   d.players[action.player_index].hand.concealed_tiles[
      #d.players[action.player_index].hand.concealed_tiles + 1
   ] = dr.tile
   d.known_wall_tile_ids    = remove_known(d.known_wall_tile_ids, dr.tile.tile_id)
   d.last_draw_was_supplement = false
   d.last_drawn_tile_id     = dr.tile.tile_id
   d.has_last_drawn         = true
   d.phase                  = "awaiting_action" as DealPhase

   return ok_t(d, { ev("draw", "player " .. tostring(action.player_index) .. " draws " .. (dr.tile.tile_id as string)) })
end

-- ── Discard ───────────────────────────────────────────────────────────────

local function handle_discard(deal: DealState, action: DiscardAction): DealTransition
   if (deal.phase as string) ~= "awaiting_action" then
      return err(deal, "discard requires awaiting_action phase")
   end
   if action.player_index ~= deal.current_player then
      return err(deal, "discard: wrong player")
   end

   local tile_obj, found = find_tile(deal.players[action.player_index].hand.concealed_tiles, action.tile_id)
   if not found then
      return err(deal, "discard: tile not in hand: " .. (action.tile_id as string))
   end

   local d = copy_deal(deal)
   local new_c, _ = remove_tile(d.players[action.player_index].hand.concealed_tiles, action.tile_id)
   d.players[action.player_index].hand.concealed_tiles = new_c
   d.pending_discard       = { tile = tile_obj, discarder = action.player_index }
   d.has_pending_discard   = true
   d.reaction_passes       = {}
   d.last_draw_was_supplement = false
   d.phase                 = "reaction_window" as DealPhase

   return ok_t(d, { ev("discard", "player " .. tostring(action.player_index) .. " discards " .. (action.tile_id as string)) })
end

-- ── Hu ────────────────────────────────────────────────────────────────────

local function build_score_ctx(deal: DealState, player_index: integer, is_zi_mo: boolean, is_gang_shang: boolean, is_qiang_gang: boolean): ScoreContext
   local open_sets = deal.players[player_index].hand.sets
   local is_men_qian = true
   for _, s in ipairs(open_sets) do
      if (s.visibility as string) == "open" then is_men_qian = false; break end
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

local function handle_hu(deal: DealState, action: DeclareHuAction): DealTransition
   local p = deal.players[action.player_index]
   local validator = require("game.hand_validator")

   -- ── Zi Mo (self-draw) ─────────────────────────────────────────────────
   if action.is_zi_mo then
      if (deal.phase as string) ~= "awaiting_action" then
         return err(deal, "zi mo requires awaiting_action phase")
      end
      if action.player_index ~= deal.current_player then
         return err(deal, "zi mo: wrong player")
      end
      if not deal.has_last_drawn then
         return err(deal, "zi mo: no drawn tile available")
      end
      local incoming, tile_ok = find_tile(p.hand.concealed_tiles, deal.last_drawn_tile_id)
      if not tile_ok then
         return err(deal, "zi mo: last drawn tile not in hand")
      end
      local rest, _ = remove_tile(p.hand.concealed_tiles, deal.last_drawn_tile_id)
      local shapes  = validator.find_win_shapes(rest, incoming, p.hand.sets)
      local ctx     = build_score_ctx(deal, action.player_index, true, deal.last_draw_was_supplement, false)
      local output  = scorer_mod.score_hand(shapes, ctx)
      if not output.has_best or not output.best.valid_hu then
         return err(deal, "zi mo: not a valid hu")
      end
      local d = copy_deal(deal)
      d.phase = "deal_over" as DealPhase
      d.deal_result = {
         winner_player_index = action.player_index,
         won_by_zi_mo        = true,
         score_result        = output.best,
         has_score_result    = true,
      }
      d.has_deal_result = true
      return ok_t(d, { ev("hu", "player " .. tostring(action.player_index) .. " wins by zi mo (" .. (output.best.rating as string) .. ")") })
   end

   -- ── Win on discard ────────────────────────────────────────────────────
   if (deal.phase as string) == "reaction_window" and deal.has_pending_discard then
      if action.player_index == deal.pending_discard.discarder then
         return err(deal, "hu on discard: discarder cannot win on own discard")
      end
      local incoming = deal.pending_discard.tile
      local ctx      = build_score_ctx(deal, action.player_index, false, false, false)
      local shapes   = validator.find_win_shapes(p.hand.concealed_tiles, incoming, p.hand.sets)
      local output   = scorer_mod.score_hand(shapes, ctx)
      if not output.has_best or not output.best.valid_hu then
         return err(deal, "hu on discard: not a valid hu")
      end
      local d = copy_deal(deal)
      d.phase = "deal_over" as DealPhase
      d.deal_result = {
         winner_player_index = action.player_index,
         won_by_zi_mo        = false,
         score_result        = output.best,
         has_score_result    = true,
      }
      d.has_deal_result   = true
      d.has_pending_discard = false
      return ok_t(d, { ev("hu", "player " .. tostring(action.player_index) .. " wins on discard (" .. (output.best.rating as string) .. ")") })
   end

   -- ── Qiang Gang (rob the kong) ─────────────────────────────────────────
   if (deal.phase as string) == "reaction_window" and deal.has_pending_kong then
      if action.player_index == deal.pending_added_kong.declarer then
         return err(deal, "qiang gang: cannot rob own kong")
      end
      local declarer   = deal.pending_added_kong.declarer
      local kong_tile, kt_ok = find_tile(deal.players[declarer].hand.concealed_tiles, deal.pending_added_kong.tile_id)
      if not kt_ok then
         return err(deal, "qiang gang: pending kong tile not found")
      end
      local ctx    = build_score_ctx(deal, action.player_index, false, false, true)
      local shapes = validator.find_win_shapes(p.hand.concealed_tiles, kong_tile, p.hand.sets)
      local output = scorer_mod.score_hand(shapes, ctx)
      if not output.has_best or not output.best.valid_hu then
         return err(deal, "qiang gang: not a valid hu")
      end
      local d = copy_deal(deal)
      d.phase = "deal_over" as DealPhase
      d.deal_result = {
         winner_player_index = action.player_index,
         won_by_zi_mo        = false,
         score_result        = output.best,
         has_score_result    = true,
      }
      d.has_deal_result = true
      d.has_pending_kong = false
      return ok_t(d, { ev("qiang_gang", "player " .. tostring(action.player_index) .. " wins by qiang gang") })
   end

   return err(deal, "declare_hu: invalid phase or state (phase=" .. (deal.phase as string) .. ")")
end

-- ── Pass reaction ──────────────────────────────────────────────────────────

local function handle_pass_reaction(deal: DealState, action: PassReactionAction): DealTransition
   if (deal.phase as string) ~= "reaction_window" then
      return err(deal, "pass_reaction requires reaction_window phase")
   end
   if has_passed(deal.reaction_passes, action.player_index) then
      return err(deal, "pass_reaction: player already passed")
   end
   -- The actor (discarder or kong declarer) cannot pass their own window.
   if deal.has_pending_discard and action.player_index == deal.pending_discard.discarder then
      return err(deal, "pass_reaction: discarder cannot pass own reaction window")
   end
   if deal.has_pending_kong and action.player_index == deal.pending_added_kong.declarer then
      return err(deal, "pass_reaction: kong declarer cannot pass own reaction window")
   end

   local d = copy_deal(deal)
   d.reaction_passes[#d.reaction_passes + 1] = action.player_index

   -- Reaction window stays open until PLAYER_COUNT - 1 non-actor players have passed.
   if #d.reaction_passes < PLAYER_COUNT - 1 then
      return ok_t(d, { ev("pass", "player " .. tostring(action.player_index) .. " passes") })
   end

   -- All non-actor players passed — resolve.
   if d.has_pending_discard then
      local discarder = d.pending_discard.discarder
      d.players[discarder].hand.discards[#d.players[discarder].hand.discards + 1] = d.pending_discard.tile
      d.pending_discard     = empty_pending_discard()
      d.has_pending_discard = false
      d.reaction_passes     = {}
      d.current_player      = (discarder % PLAYER_COUNT) + 1
      d.phase               = "awaiting_draw" as DealPhase
      d.has_last_drawn      = false
      return ok_t(d, { ev("pass_all", "all passed — discard resolved, player " .. tostring(d.current_player) .. " to draw") })

   elseif d.has_pending_kong then
      local declarer = d.pending_added_kong.declarer
      local tile_id  = d.pending_added_kong.tile_id
      -- Find the fourth tile object before removing it.
      local fourth, ft_ok = find_tile(d.players[declarer].hand.concealed_tiles, tile_id)
      if not ft_ok then
         return err(deal, "pass_all kong: fourth tile not found")
      end
      -- Remove from concealed.
      local new_c, _ = remove_tile(d.players[declarer].hand.concealed_tiles, tile_id)
      d.players[declarer].hand.concealed_tiles = new_c
      -- Convert the matching open Peng to Kong.
      local upgraded = false
      for i = 1, #d.players[declarer].hand.sets do
         local s = d.players[declarer].hand.sets[i]
         if (s.kind as string) == "peng" and (s.visibility as string) == "open"
            and #s.tiles > 0 and s.tiles[1].kind_id == fourth.kind_id
         then
            d.players[declarer].hand.sets[i].kind = "kong" as TileSetKind
            d.players[declarer].hand.sets[i].tiles[#d.players[declarer].hand.sets[i].tiles + 1] = fourth
            upgraded = true
            break
         end
      end
      if not upgraded then
         return err(deal, "pass_all kong: matching peng not found for upgrade")
      end
      d.pending_added_kong = empty_pending_kong()
      d.has_pending_kong   = false
      d.reaction_passes    = {}
      -- Draw supplement.
      local d2, was_empty = draw_supplement(d, declarer)
      if was_empty then
         return wall_exhaustion(d2)
      end
      d2.current_player = declarer
      d2.phase          = "awaiting_action" as DealPhase
      return ok_t(d2, { ev("kong_resolved", "added kong resolved — player " .. tostring(declarer) .. " draws supplement") })
   end

   return err(deal, "pass_reaction: no pending discard or kong to resolve")
end

-- ── Chi ───────────────────────────────────────────────────────────────────

local function handle_chi(deal: DealState, action: DeclareChiAction): DealTransition
   if (deal.phase as string) ~= "reaction_window" or not deal.has_pending_discard then
      return err(deal, "declare_chi requires reaction_window with pending discard")
   end
   if #action.other_tile_ids ~= 2 then
      return err(deal, "declare_chi: need exactly 2 other tile ids")
   end

   local discard_tile = deal.pending_discard.tile
   local discarder    = deal.pending_discard.discarder
   local hand_tiles   = deal.players[action.player_index].hand.concealed_tiles

   local ot1, ok1 = find_tile(hand_tiles, action.other_tile_ids[1])
   if not ok1 then return err(deal, "declare_chi: tile not in hand: " .. (action.other_tile_ids[1] as string)) end
   local ot2, ok2 = find_tile(hand_tiles, action.other_tile_ids[2])
   if not ok2 then return err(deal, "declare_chi: tile not in hand: " .. (action.other_tile_ids[2] as string)) end

   local other_pair: {Tile} = {ot1, ot2}
   if not calls_mod.can_chi(discard_tile, other_pair, discarder, action.player_index, PLAYER_COUNT) then
      return err(deal, "declare_chi: illegal chi")
   end

   local d = copy_deal(deal)
   local h = d.players[action.player_index].hand
   local c1, _ = remove_tile(h.concealed_tiles, action.other_tile_ids[1])
   local c2, _ = remove_tile(c1, action.other_tile_ids[2])
   h.concealed_tiles = c2
   h.sets[#h.sets + 1] = {
      kind        = "chi" as TileSetKind,
      visibility  = "open" as SetVisibility,
      tiles       = {discard_tile, ot1, ot2},
      called_from = discarder,
   }
   d.pending_discard       = empty_pending_discard()
   d.has_pending_discard   = false
   d.reaction_passes       = {}
   d.current_player        = action.player_index
   d.phase                 = "awaiting_action" as DealPhase
   d.last_draw_was_supplement = false
   d.has_last_drawn        = false

   return ok_t(d, { ev("chi", "player " .. tostring(action.player_index) .. " claims chi") })
end

-- ── Peng ──────────────────────────────────────────────────────────────────

local function handle_peng(deal: DealState, action: DeclarePengAction): DealTransition
   if (deal.phase as string) ~= "reaction_window" or not deal.has_pending_discard then
      return err(deal, "declare_peng requires reaction_window with pending discard")
   end

   local discard_tile = deal.pending_discard.tile
   local discarder    = deal.pending_discard.discarder
   local hand_tiles   = deal.players[action.player_index].hand.concealed_tiles

   if (action.tile_id as string) ~= (discard_tile.tile_id as string) then
      return err(deal, "declare_peng: tile_id does not match pending discard")
   end
   if not calls_mod.can_peng(discard_tile, hand_tiles, discarder, action.player_index) then
      return err(deal, "declare_peng: illegal peng")
   end

   local d = copy_deal(deal)
   local h = d.players[action.player_index].hand
   local new_c, removed = remove_by_kind(h.concealed_tiles, discard_tile.kind_id, 2)
   h.concealed_tiles = new_c
   h.sets[#h.sets + 1] = {
      kind        = "peng" as TileSetKind,
      visibility  = "open" as SetVisibility,
      tiles       = {removed[1], removed[2], discard_tile},
      called_from = discarder,
   }
   d.pending_discard       = empty_pending_discard()
   d.has_pending_discard   = false
   d.reaction_passes       = {}
   d.current_player        = action.player_index
   d.phase                 = "awaiting_action" as DealPhase
   d.last_draw_was_supplement = false
   d.has_last_drawn        = false

   return ok_t(d, { ev("peng", "player " .. tostring(action.player_index) .. " claims peng of " .. (discard_tile.kind_id as string)) })
end

-- ── Open Kong (from discard) ───────────────────────────────────────────────

local function handle_open_kong(deal: DealState, action: DeclareOpenKongAction): DealTransition
   if (deal.phase as string) ~= "reaction_window" or not deal.has_pending_discard then
      return err(deal, "declare_open_kong requires reaction_window with pending discard")
   end

   local discard_tile = deal.pending_discard.tile
   local discarder    = deal.pending_discard.discarder
   local hand_tiles   = deal.players[action.player_index].hand.concealed_tiles

   if (action.tile_id as string) ~= (discard_tile.tile_id as string) then
      return err(deal, "declare_open_kong: tile_id does not match pending discard")
   end
   if not calls_mod.can_open_kong(discard_tile, hand_tiles, discarder, action.player_index) then
      return err(deal, "declare_open_kong: illegal open kong")
   end

   local d = copy_deal(deal)
   local h = d.players[action.player_index].hand
   local new_c, removed = remove_by_kind(h.concealed_tiles, discard_tile.kind_id, 3)
   h.concealed_tiles = new_c
   h.sets[#h.sets + 1] = {
      kind        = "kong" as TileSetKind,
      visibility  = "open" as SetVisibility,
      tiles       = {removed[1], removed[2], removed[3], discard_tile},
      called_from = discarder,
   }
   d.pending_discard     = empty_pending_discard()
   d.has_pending_discard = false
   d.reaction_passes     = {}

   local d2, was_empty = draw_supplement(d, action.player_index)
   if was_empty then return wall_exhaustion(d2) end
   d2.current_player = action.player_index
   d2.phase          = "awaiting_action" as DealPhase

   return ok_t(d2, { ev("open_kong", "player " .. tostring(action.player_index) .. " claims open kong of " .. (discard_tile.kind_id as string)) })
end

-- ── Concealed Kong ────────────────────────────────────────────────────────

local function handle_concealed_kong(deal: DealState, action: DeclareConcealedKongAction): DealTransition
   if (deal.phase as string) ~= "awaiting_action" then
      return err(deal, "declare_concealed_kong requires awaiting_action phase")
   end
   if action.player_index ~= deal.current_player then
      return err(deal, "declare_concealed_kong: wrong player")
   end
   local hand_tiles = deal.players[action.player_index].hand.concealed_tiles
   if not calls_mod.can_concealed_kong(action.tile_kind_id, hand_tiles) then
      return err(deal, "declare_concealed_kong: need 4 matching tiles in hand")
   end

   local d = copy_deal(deal)
   local h = d.players[action.player_index].hand
   local new_c, removed = remove_by_kind(h.concealed_tiles, action.tile_kind_id, 4)
   h.concealed_tiles = new_c
   h.sets[#h.sets + 1] = {
      kind        = "kong" as TileSetKind,
      visibility  = "concealed" as SetVisibility,
      tiles       = {removed[1], removed[2], removed[3], removed[4]},
      called_from = -1,
   }

   local d2, was_empty = draw_supplement(d, action.player_index)
   if was_empty then return wall_exhaustion(d2) end
   d2.phase = "awaiting_action" as DealPhase

   return ok_t(d2, { ev("concealed_kong", "player " .. tostring(action.player_index) .. " declares concealed kong of " .. (action.tile_kind_id as string)) })
end

-- ── Added Kong ────────────────────────────────────────────────────────────

local function handle_added_kong(deal: DealState, action: DeclareAddedKongAction): DealTransition
   if (deal.phase as string) ~= "awaiting_action" then
      return err(deal, "declare_added_kong requires awaiting_action phase")
   end
   if action.player_index ~= deal.current_player then
      return err(deal, "declare_added_kong: wrong player")
   end
   local hand_tiles = deal.players[action.player_index].hand.concealed_tiles
   local open_sets  = deal.players[action.player_index].hand.sets
   local tile_obj, tile_ok = find_tile(hand_tiles, action.tile_id)
   if not tile_ok then
      return err(deal, "declare_added_kong: tile not in hand: " .. (action.tile_id as string))
   end
   if not calls_mod.can_added_kong(tile_obj, hand_tiles, open_sets) then
      return err(deal, "declare_added_kong: need matching open peng")
   end

   -- The fourth tile stays in concealed tiles until the Qiang Gang window resolves.
   local d = copy_deal(deal)
   d.pending_added_kong = { tile_id = action.tile_id, declarer = action.player_index }
   d.has_pending_kong   = true
   d.reaction_passes    = {}
   d.phase              = "reaction_window" as DealPhase

   return ok_t(d, { ev("added_kong", "player " .. tostring(action.player_index) .. " declares added kong — qiang gang window open") })
end

-- ── Main dispatch ──────────────────────────────────────────────────────────

-- Action parameter is typed as `any` so each concrete DealAction record (DrawAction,
-- DiscardAction, etc.) can be passed directly. All concrete actions carry `kind: string`;
-- dispatch reads kind and re-casts to the concrete type.
function M.apply_action(deal: DealState, action: any): DealTransition
   if deal.has_deal_result then
      return err(deal, "apply_action: deal is already over")
   end

   local kind = (action as DrawAction).kind as string

   if kind == "draw" then
      return handle_draw(deal, action as DrawAction)
   elseif kind == "discard" then
      return handle_discard(deal, action as DiscardAction)
   elseif kind == "declare_hu" then
      return handle_hu(deal, action as DeclareHuAction)
   elseif kind == "pass_reaction" then
      return handle_pass_reaction(deal, action as PassReactionAction)
   elseif kind == "declare_chi" then
      return handle_chi(deal, action as DeclareChiAction)
   elseif kind == "declare_peng" then
      return handle_peng(deal, action as DeclarePengAction)
   elseif kind == "declare_open_kong" then
      return handle_open_kong(deal, action as DeclareOpenKongAction)
   elseif kind == "declare_concealed_kong" then
      return handle_concealed_kong(deal, action as DeclareConcealedKongAction)
   elseif kind == "declare_added_kong" then
      return handle_added_kong(deal, action as DeclareAddedKongAction)
   else
      return err(deal, "apply_action: unknown action kind: " .. kind)
   end
end

return M
