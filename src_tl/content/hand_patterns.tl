-- Static hand pattern metadata. Pure content — no game logic.
-- May import core types only.

require("core.types")
require("game.deal_types")

local M = {}

global record HandPatternDef
   id:       string
   label:    string
   fan:      integer
   is_limit: boolean
end

local PATTERNS: {HandPatternDef} = {
   { id = "ping_hu",       label = "Ping Hu (平胡)",       fan = 1, is_limit = false },
   { id = "dui_dui_hu",    label = "Dui Dui Hu (對對胡)",  fan = 3, is_limit = false },
   { id = "qi_dui",        label = "Qi Dui (七對)",        fan = 4, is_limit = false },
   { id = "xiao_san_yuan", label = "Xiao San Yuan (小三元)", fan = 4, is_limit = false },
   { id = "hun_yi_se",     label = "Hun Yi Se (混一色)",    fan = 3, is_limit = false },
   { id = "qing_yi_se",    label = "Qing Yi Se (清一色)",   fan = 6, is_limit = false },
   { id = "xiao_si_xi",    label = "Xiao Si Xi (小四喜)",   fan = 6, is_limit = false },
   -- Limit hands
   { id = "zi_yi_se",         label = "Zi Yi Se (字一色)",           fan = 0, is_limit = true },
   { id = "da_san_yuan",      label = "Da San Yuan (大三元)",        fan = 0, is_limit = true },
   { id = "da_si_xi",         label = "Da Si Xi (大四喜)",           fan = 0, is_limit = true },
   { id = "jiu_lian_bao_deng",label = "Jiu Lian Bao Deng (九蓮寶燈)", fan = 0, is_limit = true },
   { id = "shi_san_yao",      label = "Shi San Yao (十三么)",        fan = 0, is_limit = true },
   { id = "si_gang",          label = "Si Gang (四槓)",              fan = 0, is_limit = true },
}

-- Returns the full list of pattern definitions.
function M.all(): {HandPatternDef}
   return PATTERNS
end

-- Returns the pattern definition for the given id, or nil.
function M.find(id: string): HandPatternDef | nil
   for _, p in ipairs(PATTERNS) do
      if p.id == id then return p end
   end
   return nil
end

return M
