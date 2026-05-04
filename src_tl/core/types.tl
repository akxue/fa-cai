-- Core identity types shared across the project.
-- No imports from game, content, effects, ui, scenes, app, or love.

global type TileKindId = string   -- e.g. "tiao_1", "fa_cai"
global type TileId     = string   -- e.g. "tiao_1_a", "fa_cai_b"
global type Wind       = string   -- "east" | "south" | "west" | "north"

global record Tile
   tile_id: TileId
   kind_id: TileKindId
end

global record TileKind
   kind_id:  TileKindId
   suit:     string    -- "tiao" | "wan" | "bing" | "honor"
   rank:     integer   -- 1-9 for suited; 0 for honors
   is_honor: boolean
end

return {}
