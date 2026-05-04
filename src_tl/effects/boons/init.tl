-- Registers all Milestone 1 starter boon modules with the effect registry.
-- Call register_all() once at app startup. Tests may call it before each
-- describe block via reset_and_register_all() if isolation is needed.

require("effects.effect_types")
local registry = require("effects.effect_registry")

local current        = require("effects.boons.current")
local still_water    = require("effects.boons.still_water")
local dragons_weight = require("effects.boons.dragons_weight")
local open_eyes      = require("effects.boons.open_eyes")
local third_eye      = require("effects.boons.third_eye")
local fresh_start    = require("effects.boons.fresh_start")
local momentum       = require("effects.boons.momentum")

local M = {}

function M.register_all()
   registry.register(current)
   registry.register(still_water)
   registry.register(dragons_weight)
   registry.register(open_eyes)
   registry.register(third_eye)
   registry.register(fresh_start)
   registry.register(momentum)
end

function M.reset_and_register_all()
   registry.reset()
   M.register_all()
end

return M
