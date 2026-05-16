require("core.types")
require("game.deal_types")
local notation  = require("support.hand_notation")
local validator = require("game.hand_validator")

local function parse(s: string): {Tile}
   local r = notation.parse(s)
   assert.is_true(r.ok)
   return r.tiles
end

-- Build a dummy Tile for an incoming tile given a kind_id string.
local function tile(kind_id: string): Tile
   return { tile_id = (kind_id .. "_a") as TileId, kind_id = kind_id as TileKindId }
end

describe("hand_validator", function()

   describe("standard four-sets-pair", function()

      it("recognises a valid all-chi hand", function()
         -- 123t 456t 789t 123w + pair 55b
         local concealed = parse("123t 456t 789t 123w 5b")
         local incoming  = tile("bing_5")
         local shapes = validator.find_win_shapes(concealed, incoming, {})
         assert.is_true(#shapes > 0)
         local found = false
         for _, s in ipairs(shapes) do
            if s.kind == ("standard_four_sets_pair" as WinShapeKind) then
               found = true
            end
         end
         assert.is_true(found)
      end)

      it("recognises a valid all-peng hand", function()
         -- 111t 222t 333t 444t + pair EE
         local concealed = parse("111t 222t 333t 444t E")
         local incoming  = tile("east")
         local shapes = validator.find_win_shapes(concealed, incoming, {})
         local found = false
         for _, s in ipairs(shapes) do
            if s.kind == ("standard_four_sets_pair" as WinShapeKind) then found = true end
         end
         assert.is_true(found)
      end)

      it("returns empty for an invalid hand", function()
         -- 13 same-suit tiles, no valid decomposition
         local concealed = parse("1357t 1357w 135b 1b")
         local incoming  = tile("bing_3")
         local shapes = validator.find_win_shapes(concealed, incoming, {})
         assert.are.equal(0, #shapes)
      end)

      it("handles mixed chi and peng", function()
         -- 123t 456t [peng 7t via set] 789w + pair FF
         local concealed = parse("123t 456t 789w F")
         local incoming  = tile("fa_cai")
         local open: {TileSet} = {
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = { tile("tiao_7"), tile("tiao_7"), tile("tiao_7") } as {Tile},
               called_from = 2,
            }
         }
         local shapes = validator.find_win_shapes(concealed, incoming, open)
         assert.is_true(#shapes > 0)
      end)

   end)

   describe("seven pairs", function()

      it("recognises a valid seven-pairs hand", function()
         local concealed = parse("11t 22w 33b 44t 55w 66b 7t")
         local incoming  = tile("tiao_7")
         local shapes = validator.find_win_shapes(concealed, incoming, {})
         local found = false
         for _, s in ipairs(shapes) do
            if s.kind == ("seven_pairs" as WinShapeKind) then found = true end
         end
         assert.is_true(found)
      end)

      it("rejects seven pairs if any kind has 4 copies (two identical pairs)", function()
         -- 1111t 22w 33b 44t 55w 66b = not valid seven pairs (two copies of same pair)
         local concealed = parse("111t 22w 33b 44t 55w 66b 1t")
         local incoming  = tile("tiao_1")
         -- After adding incoming, 1t appears 4 times; not seven distinct kinds.
         local shapes = validator.find_win_shapes(concealed, incoming, {})
         local found = false
         for _, s in ipairs(shapes) do
            if s.kind == ("seven_pairs" as WinShapeKind) then found = true end
         end
         assert.is_false(found)
      end)

      it("rejects seven pairs if a kind has 3 copies", function()
         -- 111t 22w 33b 44t 55w 66b 7t
         local concealed = parse("111t 22w 33b 44t 55w 66b 7t")
         local incoming  = tile("wan_7")
         local shapes = validator.find_win_shapes(concealed, incoming, {})
         local found = false
         for _, s in ipairs(shapes) do
            if s.kind == ("seven_pairs" as WinShapeKind) then found = true end
         end
         assert.is_false(found)
      end)

   end)

   describe("thirteen orphans", function()

      it("recognises a valid thirteen orphans hand", function()
         local concealed = parse("19t 19w 19b E S W N F H B E")
         local incoming  = tile("east")
         local shapes = validator.find_win_shapes(concealed, incoming, {})
         -- incoming adds second E; so concealed has 1E and incoming = E
         -- Actually let's build it more carefully:
         -- Need: 1t,9t,1w,9w,1b,9b,E,S,W,N,F,H,B + one duplicate
         -- Let's use incoming = second B (bai_ban)
         local concealed2 = parse("19t 19w 19b E S W N F H B")
         local incoming2  = tile("bai_ban")
         local shapes2 = validator.find_win_shapes(concealed2, incoming2, {})
         local found = false
         for _, s in ipairs(shapes2) do
            if s.kind == ("thirteen_orphans" as WinShapeKind) then found = true end
         end
         assert.is_true(found)
      end)

      it("rejects thirteen orphans when a non-orphan tile is present", function()
         -- Replace E with tiao_2 (non-orphan)
         local concealed = parse("19t 19w 19b S W N F H B 2t")
         local incoming  = tile("bai_ban")
         local shapes = validator.find_win_shapes(concealed, incoming, {})
         local found = false
         for _, s in ipairs(shapes) do
            if s.kind == ("thirteen_orphans" as WinShapeKind) then found = true end
         end
         assert.is_false(found)
      end)

   end)

   describe("nine gates", function()

      it("recognises a valid nine gates hand (tiao)", function()
         -- 1112345678999t + one extra (e.g. 5t)
         local concealed = parse("111t 23456789t 99t")   -- = 1112345678999t, 14 tiles
         local incoming  = tile("tiao_5")
         -- build as 13 concealed + incoming
         local concealed13 = parse("111t 2345678t 999t")
         local shapes = validator.find_win_shapes(concealed13, incoming, {})
         local found = false
         for _, s in ipairs(shapes) do
            if s.kind == ("nine_gates" as WinShapeKind) then found = true end
         end
         assert.is_true(found)
      end)

      it("rejects nine gates if mixed suits", function()
         local concealed = parse("111t 234567t 999t 1w")
         local incoming  = tile("wan_2")
         local shapes = validator.find_win_shapes(concealed, incoming, {})
         local found = false
         for _, s in ipairs(shapes) do
            if s.kind == ("nine_gates" as WinShapeKind) then found = true end
         end
         assert.is_false(found)
      end)

      it("rejects nine gates with honor tiles", function()
         local concealed = parse("111t 234567t 999t E")
         local incoming  = tile("tiao_5")
         local shapes = validator.find_win_shapes(concealed, incoming, {})
         local found = false
         for _, s in ipairs(shapes) do
            if s.kind == ("nine_gates" as WinShapeKind) then found = true end
         end
         assert.is_false(found)
      end)

   end)

   describe("helpers", function()

      it("is_honor returns true for winds and dragons", function()
         assert.is_true(validator.is_honor("east" as TileKindId))
         assert.is_true(validator.is_honor("fa_cai" as TileKindId))
         assert.is_false(validator.is_honor("tiao_1" as TileKindId))
      end)

      it("is_dragon returns true only for dragons", function()
         assert.is_true(validator.is_dragon("fa_cai" as TileKindId))
         assert.is_true(validator.is_dragon("hong_zhong" as TileKindId))
         assert.is_true(validator.is_dragon("bai_ban" as TileKindId))
         assert.is_false(validator.is_dragon("east" as TileKindId))
         assert.is_false(validator.is_dragon("tiao_1" as TileKindId))
      end)

      it("is_terminal_or_honor returns true for all 13 orphan kinds", function()
         local orphans = {"tiao_1","tiao_9","wan_1","wan_9","bing_1","bing_9",
                          "east","south","west","north","fa_cai","hong_zhong","bai_ban"}
         for _, k in ipairs(orphans) do
            assert.is_true(validator.is_terminal_or_honor(k as TileKindId))
         end
         assert.is_false(validator.is_terminal_or_honor("tiao_5" as TileKindId))
      end)

   end)

   -- ── Wait-shape query (compute_waits / compute_wait_shapes) ─────────────
   --
   -- Drives the brute-force probe against representative 13-tile hands.
   -- Coverage spans single-tile wait, multi-completion wait, special shapes
   -- (seven pairs, thirteen orphans), pair-is-honors detection (Sacred Eye),
   -- pure-suit wait (Suit Sentry), and the empty-result negative path.

   describe("compute_waits", function()

      local function contains(out: {TileKindId}, kind: string): boolean
         for _, k in ipairs(out) do
            if (k as string) == kind then return true end
         end
         return false
      end

      it("returns a single completing kind for a tight standard wait", function()
         -- 123t 456t 789t 11w + pair on south, waiting on south OR pair-wait
         -- on wan_1. Build a hand cleanly waiting on bing_5 only:
         -- 123t 456t 789t 111w + bing_5 — three sets + triplet + 1 floating,
         -- wait on bing_5 to pair. Concealed = 13 tiles.
         local concealed = parse("123t 456t 789t 111w 5b")
         local waits = validator.compute_waits(concealed, {})
         assert.is_true(contains(waits, "bing_5"))
         assert.are.equal(1, #waits)
      end)

      it("returns both ends of a two-sided run wait", function()
         -- Hand has a floating 4-5 in tiao that can extend either way:
         --   45t (open) + 123t (chi) + 678t (chi) + 111w (pung) + 22b (pair)
         -- = 13 tiles. Wait completes the 4-5 into a chi via tiao_3 (→345)
         -- or tiao_6 (→456). The 678 chi is consumed by tiao_3's path; the
         -- 123 chi is consumed by tiao_6's path — both decompositions exist.
         local concealed = parse("45t 123t 678t 111w 22b")
         local waits = validator.compute_waits(concealed, {})
         assert.is_true(contains(waits, "tiao_3"))
         assert.is_true(contains(waits, "tiao_6"))
      end)

      it("returns shanpon-equivalent wait (two pairs, completes either to pung)", function()
         -- 3 chi + 2 pairs (east, south) → 13 tiles. Wait on east promotes
         -- to pung-EEE with SS as eye; wait on south is symmetric.
         local concealed = parse("123t 456t 789t 2E 2S")
         local waits = validator.compute_waits(concealed, {})
         assert.is_true(contains(waits, "east"))
         assert.is_true(contains(waits, "south"))
         assert.are.equal(2, #waits)
      end)

      it("detects a seven-pairs wait", function()
         -- Six pairs + single floating tile → single-tile wait on the floater.
         -- 11t 22t 33t 44t 55t 66t + 7t → wait on tiao_7.
         local concealed = parse("11t 22t 33t 44t 55t 66t 7t")
         local waits = validator.compute_waits(concealed, {})
         assert.is_true(contains(waits, "tiao_7"))
      end)

      it("detects a thirteen-orphans wait", function()
         -- 12 distinct terminal/honor + duplicate of one of them = 13-tile
         -- ting on the missing 13th. Missing kind here: bai_ban.
         local concealed = parse("1t 9t 1w 9w 1b 9b E S W N F H E")
         local waits = validator.compute_waits(concealed, {})
         assert.is_true(contains(waits, "bai_ban"))
      end)

      it("returns empty for a hand not at ting", function()
         -- Scattered hand with no near-completion shape.
         local concealed = parse("1357t 1357w 135b 1b")
         local waits = validator.compute_waits(concealed, {})
         assert.are.equal(0, #waits)
      end)

      it("respects open_sets — concealed material decomposes into 4 - #open sets + pair", function()
         -- One open peng of bing_5; concealed = 10 tiles. Waiting concealed
         -- portion must form (4 - 1) = 3 sets + 1 pair = 11 tiles with the
         -- incoming. Shanpon shape: 123t + 234t + 11w pair + 22b pair, wait
         -- on wan_1 (→ 111w pung, 22b eye) or bing_2 (→ 222b pung, 11w eye).
         local concealed = parse("123t 234t 11w 22b")
         local open: {TileSet} = {
            {
               kind        = "peng" as TileSetKind,
               visibility  = "open" as SetVisibility,
               tiles       = {
                  { tile_id = "bing_5_a" as TileId, kind_id = "bing_5" as TileKindId },
                  { tile_id = "bing_5_b" as TileId, kind_id = "bing_5" as TileKindId },
                  { tile_id = "bing_5_c" as TileId, kind_id = "bing_5" as TileKindId },
               },
               called_from = 2,
            },
         }
         local waits = validator.compute_waits(concealed, open)
         assert.is_true(contains(waits, "wan_1"))
         assert.is_true(contains(waits, "bing_2"))
      end)
   end)

   describe("compute_wait_shapes", function()
      it("reports pair_kind for sacred-eye-style pair-is-honors detection", function()
         -- Ting hand where the winning shape pairs on an honor (south).
         -- 123t 456t 789t 111w + south → 13 tiles, waiting on south (pair).
         local concealed = parse("123t 456t 789t 111w S")
         local shapes = validator.compute_wait_shapes(concealed, {})
         assert.is_true(#shapes > 0)
         local any_honor_pair = false
         for _, ws in ipairs(shapes) do
            local pair = ws.win_shape.pair_kind as string
            if pair == "south" or pair == "east" or pair == "west" or pair == "north"
               or pair == "fa_cai" or pair == "hong_zhong" or pair == "bai_ban" then
               any_honor_pair = true
            end
         end
         assert.is_true(any_honor_pair)
      end)

      it("supports suit-sentry-style pure-dominant-suit-wait detection", function()
         -- Hand waiting only on tiao kinds. Build a chi-heavy tiao hand
         -- with one wan pair: 123t 456t 789t + wan_5 wan_5 + 12t → 13 tiles,
         -- waiting on tiao_3 (chi 123) — wait set is purely in tiao.
         local concealed = parse("123t 456t 789t 55w 12t")
         local waits = validator.compute_waits(concealed, {})
         assert.is_true(#waits > 0)
         local all_tiao = true
         for _, k in ipairs(waits) do
            -- TileKindId starts with the suit prefix for non-honor kinds.
            local s = k as string
            if s:sub(1, 5) ~= "tiao_" then all_tiao = false end
         end
         assert.is_true(all_tiao, "all wait kinds should be tiao")
      end)
   end)

end)
