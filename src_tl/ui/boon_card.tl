-- Reusable boon-card widget. Used by both the pre-deal starter pick scene
-- (M2-S03) and the in-deal fork modal (M2-S02 T05). Renders a Boon record
-- as a clickable card with a cluster-tinted header, name, description, and
-- optional hotkey indicator.
--
-- This module may import love (per AGENTS.md ui/ dependency rule). Pure
-- helpers (hit, cluster_color) are LÖVE-free and testable.

require("core.types")
require("game.deal_types")
require("effects.boon_types")

local M = {}

-- ── Public view record ────────────────────────────────────────────────────

global record BoonCardView
   x:        number
   y:        number
   w:        number
   h:        number
   boon:     Boon
   selected: boolean
   hotkey:   string    -- "1" / "2" / "3", or "" to omit
end

-- ── Cluster tints ─────────────────────────────────────────────────────────
--
-- Warm gold for Honor, cool teal for Suit, muted slate for Concealed.
-- Returned as (r, g, b) ∈ [0, 1]; alpha is the caller's choice.

local CLUSTER_TINT: {string: {number}} = {
   honor     = {0.85, 0.70, 0.30},
   suit      = {0.30, 0.70, 0.75},
   concealed = {0.55, 0.55, 0.65},
}

local FALLBACK_TINT: {number} = {0.55, 0.55, 0.55}

function M.cluster_color(cluster: Cluster): number, number, number
   local rgb = CLUSTER_TINT[cluster as string] or FALLBACK_TINT
   return rgb[1], rgb[2], rgb[3]
end

-- Player-facing cluster label. Lowercase cluster ids ("honor") get title-
-- cased ("Honor") for display.
local CLUSTER_LABEL: {string: string} = {
   honor     = "Honor",
   suit      = "Suit",
   concealed = "Concealed",
}

local function cluster_label(cluster: Cluster): string
   return CLUSTER_LABEL[cluster as string] or (cluster as string)
end

-- ── Hit detection (pure) ──────────────────────────────────────────────────

function M.hit(view: BoonCardView, mx: number, my: number): boolean
   return mx >= view.x
      and mx <= view.x + view.w
      and my >= view.y
      and my <= view.y + view.h
end

-- ── Drawing (LÖVE) ────────────────────────────────────────────────────────
--
-- Card anatomy (top to bottom, all offsets measured from y + HEADER_H):
--   • cluster header strip — HEADER_H px tall, full width, tinted band
--   • cluster label + hotkey row at LABEL_Y_OFF
--   • boon name at NAME_Y_OFF
--   • description at DESC_Y_OFF, wrapped to card interior width
--
-- Selected cards get a brighter border + slightly lighter background.

local PAD <const>          = 14
local HEADER_H <const>     = 8
local LABEL_Y_OFF <const>  = 8
local NAME_Y_OFF <const>   = 30
local DESC_Y_OFF <const>   = 56

function M.draw(view: BoonCardView)
   local cr, cg, cb = M.cluster_color(view.boon.cluster)

   -- Body background.
   if view.selected then
      love.graphics.setColor(0.22, 0.24, 0.30, 1.0)
   else
      love.graphics.setColor(0.16, 0.17, 0.22, 1.0)
   end
   love.graphics.rectangle("fill", view.x, view.y + HEADER_H, view.w, view.h - HEADER_H)

   -- Cluster header strip.
   love.graphics.setColor(cr, cg, cb, 1.0)
   love.graphics.rectangle("fill", view.x, view.y, view.w, HEADER_H)

   -- Border.
   if view.selected then
      love.graphics.setColor(cr, cg, cb, 1.0)
   else
      love.graphics.setColor(0.32, 0.32, 0.36, 1.0)
   end
   love.graphics.rectangle("line", view.x, view.y, view.w, view.h)

   -- Cluster label.
   love.graphics.setColor(cr, cg, cb, 1.0)
   love.graphics.print(cluster_label(view.boon.cluster):upper(), view.x + PAD, view.y + HEADER_H + LABEL_Y_OFF)

   -- Hotkey on the right.
   if view.hotkey ~= "" then
      love.graphics.setColor(0.65, 0.65, 0.70, 1.0)
      love.graphics.printf("[" .. view.hotkey .. "]", view.x, view.y + HEADER_H + LABEL_Y_OFF, view.w - PAD, "right")
   end

   -- Boon name.
   if view.selected then
      love.graphics.setColor(1.0, 0.95, 0.85, 1.0)
   else
      love.graphics.setColor(0.92, 0.92, 0.95, 1.0)
   end
   love.graphics.print(view.boon.name, view.x + PAD, view.y + HEADER_H + NAME_Y_OFF)

   -- Description, wrapped to card interior width.
   love.graphics.setColor(0.75, 0.75, 0.80, 1.0)
   love.graphics.printf(
      view.boon.description,
      view.x + PAD,
      view.y + HEADER_H + DESC_Y_OFF,
      view.w - PAD * 2,
      "left"
   )
end

return M
