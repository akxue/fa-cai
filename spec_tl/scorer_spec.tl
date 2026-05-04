require("core.types")
require("game.deal_types")
local notation  = require("support.hand_notation")
local validator = require("game.hand_validator")
local scorer    = require("game.scorer")

local function parse(s: string): {Tile}
   local r = notation.parse(s)
   assert.is_true(r.ok)
   return r.tiles
end

local function tile(kind_id: string): Tile
   return { tile_id = (kind_id .. "_a") as TileId, kind_id = kind_id as TileKindId }
end

local function basic_ctx(): ScoreContext
   return {
      incoming_tile  = tile("tiao_1"),
      has_incoming   = true,
      is_zi_mo       = false,
      is_men_qian    = false,
      is_hai_di      = false,
      is_gang_shang  = false,
      is_qiang_gang  = false,
      round_wind     = "east" as Wind,
      seat_wind      = "east" as Wind,
   }
end

-- Builds ScorerOutput from 13 concealed tiles + 1 incoming + open sets + context.
local function score_hand(concealed_str: string, incoming_kind: string, open_sets: {TileSet}, ctx: ScoreContext): ScorerOutput
   local concealed = parse(concealed_str)
   local inc       = tile(incoming_kind)
   local shapes    = validator.find_win_shapes(concealed, inc, open_sets)
   return scorer.score_hand(shapes, ctx)
end

local function has_label(out: ScorerOutput, frag: string): boolean
   if not out.has_best then return false end
   for _, r in ipairs(out.best.reasons) do
      if r.label:find(frag, 1, true) then return true end
   end
   return false
end

describe("scorer", function()

   describe("minimum fan rule", function()

      it("bare Ping Hu (1 fan) is not valid_hu", function()
         -- 123t 456t 789t 123w + pair 55b — mixed suits/no honors, all chi
         -- 13 concealed: 3+3+3+3+1 = 13 tiles; incoming = bing_5 (pair)
         local out = score_hand("123t 456t 789t 123w 5b", "bing_5", {}, basic_ctx())
         assert.is_true(out.has_best)
         assert.is_false(out.best.valid_hu)
         assert.are.equal(1, out.best.total_fan)
      end)

      it("Ping Hu + Zi Mo + Men Qian = 3 fan = valid_hu", function()
         local ctx = basic_ctx()
         ctx.is_zi_mo    = true
         ctx.is_men_qian = true
         local out = score_hand("123t 456t 789t 123w 5b", "bing_5", {}, ctx)
         assert.is_true(out.has_best)
         assert.is_true(out.best.valid_hu)
         assert.are.equal(3, out.best.total_fan)
         assert.are.equal("C" as Rating, out.best.rating)
      end)

      it("Dui Dui Hu (3 fan) alone is valid_hu", function()
         -- 111t 222w 333b 444b + pair 55b — three suits, no honors, no modifiers
         -- 13 concealed: 3+3+3+3+1 = 13; incoming = bing_5 (pair)
         local out = score_hand("111t 222w 333b 444b 5b", "bing_5", {}, basic_ctx())
         assert.is_true(out.has_best)
         assert.is_true(out.best.valid_hu)
         assert.are.equal("C" as Rating, out.best.rating)
      end)

   end)

   describe("pattern detection", function()

      it("Qing Yi Se detected (all same suit)", function()
         -- All tiao, all chi + pair: 123t 456t 789t 123t 5t + incoming 5t → pair 55t
         -- 13 concealed = 3+3+3+3+1 = 13 tiles; incoming = tiao_5 (pair)
         local out = score_hand("123t 456t 789t 123t 5t", "tiao_5", {}, basic_ctx())
         assert.is_true(out.has_best)
         assert.is_true(has_label(out, "清一色"))
         assert.is_true(out.best.total_fan >= 6)
      end)

      it("Qi Dui (seven pairs) = 4 fan base", function()
         -- 13 concealed: 11t 22w 33b 44t 55w 66b 7t = 2+2+2+2+2+2+1 = 13; incoming = tiao_7 (pair)
         local out = score_hand("11t 22w 33b 44t 55w 66b 7t", "tiao_7", {}, basic_ctx())
         assert.is_true(out.has_best)
         assert.is_true(has_label(out, "七對"))
         assert.is_true(out.best.total_fan >= 4)
      end)

      it("Da San Yuan = Limit (Legend)", function()
         -- Three dragon pengs open + 1 more set + pair from 7 concealed
         -- 7 concealed = 3 (peng) + 2 (pair) + 2 more tiles for last set
         -- E.g., 123t (3 tiles) + pair 22t (1): concealed = "123t 2t" (4 tiles)... need 7
         -- With 3 open pengs need 4-3=1 more set + pair from 7 tiles
         -- "111t" (3) + pair "22t" (1): that's 4 tiles, need 3 more...
         -- 7 concealed = last_set (3) + pair (2) + 2 extras? No: exactly set(3) + pair(2) = 5 without draw
         -- 7 concealed + incoming: 7+1=8 = 1 set (3) + pair (2) + 3 leftover? No: 3+2=5 ≠ 8
         -- Actually: 7 concealed + 1 incoming = 8 tiles = 1 set×3 + pair×2 + 3 tiles → wrong
         -- Wait: with 3 open sets, need 4-3=1 more set + pair from concealed+incoming = 8?
         -- No: total tiles = open_sets*3 + concealed + 1 incoming = 9 + concealed + 1 = 14
         -- So concealed = 14 - 9 - 1 = 4 tiles. But we need 1 set(3) + pair(2) = 5 tiles from 5 (4+1=5). ✓
         -- 4 concealed + 1 incoming = 5 = 1 set (3) + pair (2)
         local open: {TileSet} = {
            {
               kind = "peng" as TileSetKind, visibility = "open" as SetVisibility,
               tiles = { tile("fa_cai"), tile("fa_cai"), tile("fa_cai") } as {Tile},
               called_from = 1,
            },
            {
               kind = "peng" as TileSetKind, visibility = "open" as SetVisibility,
               tiles = { tile("hong_zhong"), tile("hong_zhong"), tile("hong_zhong") } as {Tile},
               called_from = 2,
            },
            {
               kind = "peng" as TileSetKind, visibility = "open" as SetVisibility,
               tiles = { tile("bai_ban"), tile("bai_ban"), tile("bai_ban") } as {Tile},
               called_from = 3,
            },
         }
         -- 4 concealed = 111t + 2t (pair candidate); incoming = tiao_2 (completes pair)
         local out = score_hand("111t 2t", "tiao_2", open, basic_ctx())
         assert.is_true(out.has_best)
         assert.is_true(out.best.is_limit)
         assert.are.equal("Legend" as Rating, out.best.rating)
         assert.is_true(out.best.valid_hu)
      end)

      it("Shi San Yao = Limit", function()
         -- 13 orphans: 1t,9t,1w,9w,1b,9b,E,S,W,N,F,H,B (13 tiles) + incoming = dup (B)
         local out = score_hand("19t 19w 19b E S W N F H B", "bai_ban", {}, basic_ctx())
         assert.is_true(out.has_best)
         assert.is_true(out.best.is_limit)
         assert.are.equal("Legend" as Rating, out.best.rating)
      end)

      it("Xiao San Yuan = 4 fan", function()
         -- Two dragon pengs open + pair of third dragon + 1 extra set from concealed
         -- 2 open sets → need 4-2=2 more sets + pair from 7 concealed tiles
         -- 7 concealed + 1 incoming = 8 = 2 sets (6) + pair (2)
         -- Sets: 111t (peng, 3) + 45t.. wait: 8 = set(3) + set(3) + pair(2)
         -- E.g., 111t (3) + 456t (3) + B (1) = 7 tiles; incoming = bai_ban (pair)
         local open: {TileSet} = {
            {
               kind = "peng" as TileSetKind, visibility = "open" as SetVisibility,
               tiles = { tile("fa_cai"), tile("fa_cai"), tile("fa_cai") } as {Tile},
               called_from = 1,
            },
            {
               kind = "peng" as TileSetKind, visibility = "open" as SetVisibility,
               tiles = { tile("hong_zhong"), tile("hong_zhong"), tile("hong_zhong") } as {Tile},
               called_from = 2,
            },
         }
         local out = score_hand("111t 456t B", "bai_ban", open, basic_ctx())
         assert.is_true(out.has_best)
         assert.is_true(has_label(out, "小三元"))
      end)

      it("Hun Yi Se = 3 fan (one suit + honors)", function()
         -- Two open pengs (tiao_7 and fa_cai), 7 concealed + incoming = 8
         -- 8 = 2 sets (6) + pair (2): e.g. 123t (3) + 4t (1... incomplete)
         -- Wait: 7 concealed + 1 incoming = 8 = 2 chi/peng (6 tiles) + pair (2 tiles)
         -- E.g., 123t (chi, 3) + 456t (chi, 3) + E (1) = 7 tiles; incoming = E (pair east)
         -- All tiao in sets + east in pair = Hun Yi Se (one suit + honor)
         local open: {TileSet} = {
            {
               kind = "peng" as TileSetKind, visibility = "open" as SetVisibility,
               tiles = { tile("tiao_7"), tile("tiao_7"), tile("tiao_7") } as {Tile},
               called_from = 1,
            },
            {
               kind = "peng" as TileSetKind, visibility = "open" as SetVisibility,
               tiles = { tile("fa_cai"), tile("fa_cai"), tile("fa_cai") } as {Tile},
               called_from = 2,
            },
         }
         local out = score_hand("123t 456t E", "east", open, basic_ctx())
         assert.is_true(out.has_best)
         assert.is_true(has_label(out, "混一色"))
      end)

      it("Xiao Si Xi = 6 fan (three wind pengs + wind pair)", function()
         -- Three wind pengs open + wind pair from concealed
         -- 3 open sets → need 4-3=1 set + pair from 4 concealed + 1 incoming = 5
         -- E.g., 111t (3) + N (1) = 4 concealed; incoming = N (pair north)
         local open: {TileSet} = {
            {
               kind = "peng" as TileSetKind, visibility = "open" as SetVisibility,
               tiles = { tile("east"), tile("east"), tile("east") } as {Tile},
               called_from = 1,
            },
            {
               kind = "peng" as TileSetKind, visibility = "open" as SetVisibility,
               tiles = { tile("south"), tile("south"), tile("south") } as {Tile},
               called_from = 2,
            },
            {
               kind = "peng" as TileSetKind, visibility = "open" as SetVisibility,
               tiles = { tile("west"), tile("west"), tile("west") } as {Tile},
               called_from = 3,
            },
         }
         local out = score_hand("111t N", "north", open, basic_ctx())
         assert.is_true(out.has_best)
         assert.is_true(has_label(out, "小四喜"))
      end)

   end)

   describe("modifiers", function()

      it("Dragon Pung adds +1 per dragon triplet", function()
         -- Dui Dui Hu (3) + Dragon Pung fa_cai (1) = 4 fan
         -- 1 open peng fa_cai + 3 concealed pengs + pair from concealed
         -- 1 open: need 3 more sets + pair from 10 concealed + incoming = 11
         -- 11 = 3 sets (9) + pair (2)
         -- 9 concealed: "111t 222w 333b 5b" (3+3+3+1=10)... need exactly 10
         -- 10 concealed: 111t 222w 333b 5b 5b = 10 tiles. incoming = bai_ban (not a set tile)
         -- Hmm, let me simplify: use concealed with exact count
         -- 1 open set → need 3 more sets + pair from 10 concealed + 1 incoming = 11
         -- 11 = set(3)+set(3)+set(3)+pair(2) = 11 ✓
         -- E.g., 111t 222w 333b + pair 5b: 9+1 = 10 concealed; incoming = bing_5 (pair)
         local open: {TileSet} = {
            {
               kind = "peng" as TileSetKind, visibility = "open" as SetVisibility,
               tiles = { tile("fa_cai"), tile("fa_cai"), tile("fa_cai") } as {Tile},
               called_from = 1,
            },
         }
         local out = score_hand("111t 222w 333b 5b", "bing_5", open, basic_ctx())
         assert.is_true(out.has_best)
         local dragon_fan = 0
         for _, r in ipairs(out.best.reasons) do
            if r.label:find("Dragon Pung", 1, true) then dragon_fan = dragon_fan + r.fan end
         end
         assert.are.equal(1, dragon_fan)
      end)

      it("Hai Di adds +1", function()
         local ctx = basic_ctx()
         ctx.is_hai_di = true
         -- 111t 222w 333b 444b + pair 5b = multi-suit Dui Dui Hu
         local out = score_hand("111t 222w 333b 444b 5b", "bing_5", {}, ctx)
         assert.is_true(out.has_best)
         assert.is_true(has_label(out, "海底"))
      end)

      it("Seat Wind Pung adds +1", function()
         local ctx = basic_ctx()
         ctx.seat_wind = "east" as Wind
         -- Open peng of east + other sets
         -- 1 open set → 10 concealed + 1 incoming = 11 = 3 sets (9) + pair (2)
         local open: {TileSet} = {
            {
               kind = "peng" as TileSetKind, visibility = "open" as SetVisibility,
               tiles = { tile("east"), tile("east"), tile("east") } as {Tile},
               called_from = 1,
            },
         }
         local out = score_hand("111t 222w 333b 5b", "bing_5", open, ctx)
         assert.is_true(out.has_best)
         assert.is_true(has_label(out, "Seat Wind"))
      end)

   end)

   describe("ratings", function()

      it("3 fan = C", function()
         local ctx = basic_ctx()
         ctx.is_zi_mo    = true
         ctx.is_men_qian = true
         local out = score_hand("123t 456t 789t 123w 5b", "bing_5", {}, ctx)
         assert.are.equal("C" as Rating, out.best.rating)
      end)

      it("4 fan = B", function()
         -- Qi Dui = 4 fan
         local out = score_hand("11t 22w 33b 44t 55w 66b 7t", "tiao_7", {}, basic_ctx())
         assert.are.equal("B" as Rating, out.best.rating)
      end)

      it("6 fan = A", function()
         -- Qing Yi Se = 6 fan (all tiao, all chi + pair)
         local out = score_hand("123t 456t 789t 123t 5t", "tiao_5", {}, basic_ctx())
         assert.is_true(out.has_best)
         assert.is_true(out.best.total_fan >= 6)
         -- A or better (Ping Hu stacks with Qing Yi Se → 7 fan → A)
         local a_or_better = out.best.rating == ("A" as Rating) or
                             out.best.rating == ("S" as Rating) or
                             out.best.rating == ("SS" as Rating)
         assert.is_true(a_or_better)
      end)

   end)

   describe("no shapes", function()

      it("returns has_best=false when no win shapes", function()
         local out = scorer.score_hand({}, basic_ctx())
         assert.is_false(out.has_best)
      end)

   end)

end)
