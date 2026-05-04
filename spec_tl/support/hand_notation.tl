-- Compact test hand notation parser.
-- Converts notation strings into lists of Tile objects with deterministic IDs.
--
-- Suited groups:  "123t" "456w" "789b" "55t"
-- Honor groups:   "E" "S" "W" "N" "F" "H" "B"  (single tile)
--                 "3F" "2H"                      (count prefix)
-- Spaces separate groups; order within groups assigns copy suffixes a, b, c, d.
--
-- Errors if more than 4 copies of any kind are requested.

require("core.types")

local M = {}

local SUIT_MAP: {string:string} = {
   t = "tiao", w = "wan", b = "bing",
}

local HONOR_MAP: {string:string} = {
   E = "east", S = "south", W = "west", N = "north",
   F = "fa_cai", H = "hong_zhong", B = "bai_ban",
}

local COPY_SUFFIXES: {string} = {"a", "b", "c", "d"}

global record NotationResult
   ok:    boolean
   tiles: {Tile}
   error: string
end

local function make_tile(kind_id: TileKindId, counts: {string:integer}): Tile | nil, string | nil
   local k = kind_id as string
   local n = (counts[k] or 0) + 1
   if n > 4 then
      return nil, "too many copies of " .. k .. " (max 4)"
   end
   counts[k] = n
   local tile_id = (k .. "_" .. COPY_SUFFIXES[n]) as TileId
   return { tile_id = tile_id, kind_id = kind_id }, nil
end

-- Parses a notation string into a flat list of Tile objects.
-- Returns NotationResult with ok=false and error message on failure.
function M.parse(notation: string): NotationResult
   local tiles: {Tile} = {}
   local counts: {string:integer} = {}

   for token in notation:gmatch("%S+") do
      -- Honor tile(s): optional count prefix + uppercase letter
      local count_str, honor_letter = token:match("^(%d*)([ESWN FBHB])$")
      -- Try honor match: optional digits then one honor letter
      local hcount_s, hletter = token:match("^(%d*)([ESWNH FB])$")
      -- Simpler: try to match honor pattern
      local honor_count: integer = 1
      local honor_key: string = ""
      local is_honor = false

      -- Check if token is purely honor (optional digit prefix + single uppercase)
      local hpfx, hkey = token:match("^(%d*)([ESWN FHB])$")
      if hkey and HONOR_MAP[hkey] then
         is_honor = true
         honor_key = hkey
         honor_count = (hpfx ~= "" and tonumber(hpfx) or 1) as integer
      end

      if is_honor then
         local kind_id = HONOR_MAP[honor_key] as TileKindId
         for _ = 1, honor_count do
            local tile, err = make_tile(kind_id, counts)
            if err then return { ok = false, tiles = {}, error = err } end
            tiles[#tiles + 1] = tile as Tile
         end
      else
         -- Suited group: digits followed by suit letter
         local digits, suit_letter = token:match("^(%d+)([twb])$")
         if not digits or not SUIT_MAP[suit_letter] then
            return { ok = false, tiles = {}, error = "unrecognised token: " .. token }
         end
         local suit = SUIT_MAP[suit_letter]
         for i = 1, #digits do
            local rank = tonumber(digits:sub(i, i)) as integer
            if rank < 1 or rank > 9 then
               return { ok = false, tiles = {}, error = "invalid rank " .. tostring(rank) .. " in token: " .. token }
            end
            local kind_id = (suit .. "_" .. tostring(rank)) as TileKindId
            local tile, err = make_tile(kind_id, counts)
            if err then return { ok = false, tiles = {}, error = err } end
            tiles[#tiles + 1] = tile as Tile
         end
      end
   end

   return { ok = true, tiles = tiles, error = "" }
end

return M
