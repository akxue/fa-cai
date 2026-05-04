-- Tile kind definitions and full 136-tile set generation.
-- No imports from love, ui, scenes, or app.

require("core.types")
local ids = require("core.ids")

local M = {}

local KIND_DEFS: {{string|integer|boolean}} = {
   -- Tiao (Bamboo) 1-9
   {"tiao_1","tiao",1,false}, {"tiao_2","tiao",2,false}, {"tiao_3","tiao",3,false},
   {"tiao_4","tiao",4,false}, {"tiao_5","tiao",5,false}, {"tiao_6","tiao",6,false},
   {"tiao_7","tiao",7,false}, {"tiao_8","tiao",8,false}, {"tiao_9","tiao",9,false},
   -- Wan (Characters) 1-9
   {"wan_1","wan",1,false}, {"wan_2","wan",2,false}, {"wan_3","wan",3,false},
   {"wan_4","wan",4,false}, {"wan_5","wan",5,false}, {"wan_6","wan",6,false},
   {"wan_7","wan",7,false}, {"wan_8","wan",8,false}, {"wan_9","wan",9,false},
   -- Bing (Circles) 1-9
   {"bing_1","bing",1,false}, {"bing_2","bing",2,false}, {"bing_3","bing",3,false},
   {"bing_4","bing",4,false}, {"bing_5","bing",5,false}, {"bing_6","bing",6,false},
   {"bing_7","bing",7,false}, {"bing_8","bing",8,false}, {"bing_9","bing",9,false},
   -- Winds
   {"east","honor",0,true}, {"south","honor",0,true},
   {"west","honor",0,true}, {"north","honor",0,true},
   -- Dragons
   {"fa_cai","honor",0,true}, {"hong_zhong","honor",0,true}, {"bai_ban","honor",0,true},
}

-- Returns all 34 TileKind definitions.
function M.all_kinds(): {TileKind}
   local out: {TileKind} = {}
   for _, def in ipairs(KIND_DEFS) do
      out[#out + 1] = {
         kind_id  = (def[1] as string) as TileKindId,
         suit     = def[2] as string,
         rank     = def[3] as integer,
         is_honor = def[4] as boolean,
      }
   end
   return out
end

-- Returns all 136 physical Tile objects (4 copies of each kind).
function M.make_full_tile_set(): {Tile}
   local out: {Tile} = {}
   for _, def in ipairs(KIND_DEFS) do
      local kind_id = (def[1] as string) as TileKindId
      for copy = 1, 4 do
         out[#out + 1] = {
            tile_id = ids.tile_id(kind_id, copy),
            kind_id = kind_id,
         }
      end
   end
   return out
end

return M
