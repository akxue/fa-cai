-- M2 engine primitives: the fixed vocabulary of state mutations available to
-- boon effects. Pure rules layer — no love/ui/scenes/app imports.
--
-- Each primitive takes a BoonContext as first arg so it can be wired as a
-- method on the context record (ctx:peek_wall(2) == primitives.peek_wall(ctx, 2)).
-- Primitives that mutate state do so in place on ctx.deal — callers receive
-- the same DealState reference and observe the change without re-binding.
--
-- See MILESTONE-2-PLAN.md §196 for the canonical primitive list and §259 for
-- token state semantics.

require("core.types")
require("game.deal_types")
require("effects.boon_types")

local wall_mod = require("game.wall")

local M = {}

-- ── 1. peek_wall ──────────────────────────────────────────────────────────
-- Returns the next n wall tiles (front) without mutating the wall.
function M.peek_wall(ctx: BoonContext, n: integer): {Tile}
   return wall_mod.peek_front(ctx.deal.wall, n)
end

-- ── 2. live_counter ───────────────────────────────────────────────────────
-- Snapshot count of tiles in the given scope that pass the filter. Scope:
--   "wall"               — remaining wall tiles
--   "opponent_discards"  — tiles in any non-owner player's discard pile
--   "all_discards"       — tiles across every player's discard pile
--
-- Plan §202 describes a CounterHandle that updates live; S00 implements the
-- equivalent semantics via per-call re-evaluation. Callers that need live
-- behavior in S00 simply re-invoke; promotion to a stored handle can land
-- when an in-deal boon needs change-notification (S04+).
function M.live_counter(ctx: BoonContext, filter: TileFilter, scope: string): integer
   local count = 0
   if scope == "wall" then
      for _, t in ipairs(ctx.deal.wall.tiles) do
         if filter(t) then count = count + 1 end
      end
   elseif scope == "opponent_discards" then
      for i, p in ipairs(ctx.deal.players) do
         if i ~= ctx.player_index then
            for _, t in ipairs(p.hand.discards) do
               if filter(t) then count = count + 1 end
            end
         end
      end
   elseif scope == "all_discards" then
      for _, p in ipairs(ctx.deal.players) do
         for _, t in ipairs(p.hand.discards) do
            if filter(t) then count = count + 1 end
         end
      end
   else
      error("live_counter: unknown scope: " .. scope)
   end
   return count
end

-- ── 3. discard_and_redraw ─────────────────────────────────────────────────
-- Discards the just-drawn tile (the trailing concealed tile) and draws the
-- next wall tile in its place. Returns the new drawn tile. Mutates ctx.deal.
function M.discard_and_redraw(ctx: BoonContext): Tile
   local hand = ctx.deal.players[ctx.player_index].hand
   assert(#hand.concealed_tiles > 0, "discard_and_redraw: empty concealed hand")
   local trailing = hand.concealed_tiles[#hand.concealed_tiles]
   hand.concealed_tiles[#hand.concealed_tiles] = nil
   hand.discards[#hand.discards + 1] = trailing

   local draw = wall_mod.draw_front(ctx.deal.wall)
   ctx.deal.wall = draw.wall
   hand.concealed_tiles[#hand.concealed_tiles + 1] = draw.tile
   return draw.tile
end

-- ── 4. swap_hand_for_wall ─────────────────────────────────────────────────
-- Removes the given concealed-hand tile, places it in the player's discard
-- pile, draws the next wall tile and places it in the concealed hand.
-- Returns the new drawn tile. Mutates ctx.deal.
function M.swap_hand_for_wall(ctx: BoonContext, hand_tile_id: TileId): Tile
   local hand = ctx.deal.players[ctx.player_index].hand
   local idx = -1
   for i, t in ipairs(hand.concealed_tiles) do
      if t.tile_id == hand_tile_id then idx = i; break end
   end
   assert(idx > 0, "swap_hand_for_wall: tile_id not in concealed hand: " .. hand_tile_id)
   local removed = hand.concealed_tiles[idx]
   table.remove(hand.concealed_tiles, idx)
   hand.discards[#hand.discards + 1] = removed

   local draw = wall_mod.draw_front(ctx.deal.wall)
   ctx.deal.wall = draw.wall
   hand.concealed_tiles[#hand.concealed_tiles + 1] = draw.tile
   return draw.tile
end

-- ── 5. extra_draw ─────────────────────────────────────────────────────────
-- Takes an additional wall tile beyond the normal turn draw. Per P8 (plan
-- §415), the caller (or a follow-up boon listener) is responsible for the
-- corresponding extra discard before end-of-turn. The engine validates the
-- 13+kongs invariant when emission wires up in T04.
function M.extra_draw(ctx: BoonContext): Tile
   local hand = ctx.deal.players[ctx.player_index].hand
   local draw = wall_mod.draw_front(ctx.deal.wall)
   ctx.deal.wall = draw.wall
   hand.concealed_tiles[#hand.concealed_tiles + 1] = draw.tile
   return draw.tile
end

-- ── 6. reveal_opponent_last_draw ──────────────────────────────────────────
-- Returns the tile most recently drawn by the given opponent. S00 returns
-- the deal-level last_drawn_tile_id only if current_player matches the
-- requested opponent; per-opponent tracking arrives with T04 emission. Until
-- then, returns the zero-tile sentinel when no info is available.
function M.reveal_opponent_last_draw(ctx: BoonContext, opponent_index: integer): Tile
   if ctx.deal.has_last_drawn and ctx.deal.current_player == opponent_index then
      local tid = ctx.deal.last_drawn_tile_id
      for _, t in ipairs(ctx.deal.players[opponent_index].hand.concealed_tiles) do
         if t.tile_id == tid then return t end
      end
   end
   return { tile_id = "" as TileId, kind_id = "" as TileKindId }
end

-- ── 7. take_from_discard_pile ─────────────────────────────────────────────
-- Removes the named tile from pile_owner's discard pile and adds it to the
-- caller's concealed hand. Per plan §223, age restriction varies by pile
-- (own: any age; opponent: ≥5 table-wide turns). Age tracking will land
-- with the Salvage Hand boon in S04; for S00 we accept min_age_turns and
-- enforce the lookup but do not (yet) maintain a per-tile age log.
function M.take_from_discard_pile(
   ctx: BoonContext,
   pile_owner: integer,
   tile_id: TileId,
   _min_age_turns: integer
): Tile
   local pile = ctx.deal.players[pile_owner].hand.discards
   local idx = -1
   for i, t in ipairs(pile) do
      if t.tile_id == tile_id then idx = i; break end
   end
   assert(idx > 0, "take_from_discard_pile: tile_id not in pile " .. pile_owner .. ": " .. tile_id)
   local taken = pile[idx]
   table.remove(pile, idx)
   local taker_hand = ctx.deal.players[ctx.player_index].hand
   taker_hand.concealed_tiles[#taker_hand.concealed_tiles + 1] = taken
   return taken
end

-- ── Token state primitives ────────────────────────────────────────────────
-- These read/write ActiveBoon.tokens directly. Token pools are per-boon
-- instance state — not transferable across boons.

function M.grant_token(ctx: BoonContext, token_kind: string, count: integer)
   local cur = ctx.active.tokens[token_kind]
   if cur == nil then cur = 0 end
   ctx.active.tokens[token_kind] = cur + count
end

function M.spend_token(ctx: BoonContext, token_kind: string, count: integer): boolean
   local cur = ctx.active.tokens[token_kind]
   if cur == nil then cur = 0 end
   if cur < count then return false end
   ctx.active.tokens[token_kind] = cur - count
   return true
end

function M.get_tokens(ctx: BoonContext, token_kind: string): integer
   local cur = ctx.active.tokens[token_kind]
   if cur == nil then return 0 end
   return cur
end

-- ── Counter/flag state helpers (non-token per-boon state) ─────────────────

function M.get_counter(ctx: BoonContext, key: string): integer
   local cur = ctx.active.counters[key]
   if cur == nil then return 0 end
   return cur
end

function M.set_counter(ctx: BoonContext, key: string, value: integer)
   ctx.active.counters[key] = value
end

function M.get_flag(ctx: BoonContext, key: string): boolean
   local cur = ctx.active.flags[key]
   if cur == nil then return false end
   return cur
end

function M.set_flag(ctx: BoonContext, key: string, value: boolean)
   ctx.active.flags[key] = value
end

-- ── Player prompt stub ────────────────────────────────────────────────────
-- Real implementation lands with milestone-fork UI in S02. For S00, returns
-- the empty string so unit tests can exercise the surface without UI deps.
function M.prompt_player(_ctx: BoonContext, _prompt: string, _options: {string}): string
   return ""
end

return M
