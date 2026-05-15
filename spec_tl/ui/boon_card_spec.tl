-- ui.boon_card tests: hit detection (pure) and cluster_color mapping.
-- Drawing is not exercised here — it requires a LÖVE graphics context.

require("core.types")
require("game.deal_types")
require("effects.boon_types")
require("ui.boon_card")

local card = require("ui.boon_card")

local function stub_boon(cluster: string): Boon
   return {
      id          = "stub",
      cluster     = cluster as Cluster,
      name        = "Stub Boon",
      description = "stub description",
      eligible_milestones = {"starter"},
      effect_kind = "info",
      weight      = 1.0,
      listens     = {"on_deal_start"},
      condition   = function(_c: BoonContext, _e: EventData): boolean return true end,
      effect      = function(_c: BoonContext, _e: EventData) end,
   }
end

local function make_view(x: number, y: number, w: number, h: number, cluster: string): BoonCardView
   return {
      x = x, y = y, w = w, h = h,
      boon     = stub_boon(cluster),
      selected = false,
      hotkey   = "",
   }
end

describe("ui.boon_card.cluster_color", function()
   it("returns distinct tints per cluster", function()
      local hr, hg, hb = card.cluster_color("honor" as Cluster)
      local sr, sg, sb = card.cluster_color("suit" as Cluster)
      local cr, cg, cb = card.cluster_color("concealed" as Cluster)
      -- Each tint should differ from the other two on at least one channel.
      local function ne(a: number, b: number): boolean return math.abs(a - b) > 0.001 end
      assert.is_true(ne(hr, sr) or ne(hg, sg) or ne(hb, sb))
      assert.is_true(ne(hr, cr) or ne(hg, cg) or ne(hb, cb))
      assert.is_true(ne(sr, cr) or ne(sg, cg) or ne(sb, cb))
   end)

   it("returns a fallback tint for unknown clusters", function()
      local r, g, b = card.cluster_color("future_cluster" as Cluster)
      -- Fallback should be a neutral grey: all three channels equal.
      -- (Asserting equality across channels catches a typo'd FALLBACK_TINT
      -- that the [0,1] range check alone would miss.)
      assert.are.equal(r, g)
      assert.are.equal(g, b)
      assert.is_true(r > 0 and r < 1, "fallback grey must be neither pure black nor pure white")
   end)
end)

describe("ui.boon_card.hit", function()
   local view = make_view(100, 200, 240, 160, "honor")

   it("returns true inside the card bounds", function()
      assert.is_true(card.hit(view, 100, 200))   -- top-left corner
      assert.is_true(card.hit(view, 340, 360))   -- bottom-right corner
      assert.is_true(card.hit(view, 220, 280))   -- center
   end)

   it("returns false outside the card bounds", function()
      assert.is_false(card.hit(view, 99, 200))   -- left of card
      assert.is_false(card.hit(view, 341, 200))  -- right of card
      assert.is_false(card.hit(view, 220, 199))  -- above card
      assert.is_false(card.hit(view, 220, 361))  -- below card
   end)

   it("considers the boundary inclusive", function()
      -- Matches the existing ui/clickable convention (<= on both sides).
      assert.is_true(card.hit(view, 100, 200))
      assert.is_true(card.hit(view, 340, 360))
   end)
end)
