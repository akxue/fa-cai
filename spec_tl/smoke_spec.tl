-- S00 smoke test: verifies the busted pipeline compiles and runs.
-- No game logic yet.

describe("smoke", function()
   it("true is true", function()
      assert.is_true(true)
   end)

   it("1 + 1 = 2", function()
      assert.are.equal(2, 1 + 1)
   end)
end)
