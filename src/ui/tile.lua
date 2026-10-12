-- Strip on a friend's Multiview tile (design 5d): "SL <place> · <n> alive" (first text row).
local common = require("ui.common")

local M = {}

--- player = view player entry of the tile's owner.
function M.build(tr, player)
  return { type = "text", id = "tile", text = tr("tile_strip", { place = common.place_label(player.place, tr), n = player.alive }),
    style = "meta" }
end

--- Match the host event `tiles` ({ id, player, game }) to view players by name (case-insensitive).
--- Returns { [tile id] = player }.
function M.match(tiles, view)
  local out = {}
  for _, t in ipairs(type(tiles) == "table" and tiles or {}) do
    if type(t) == "table" and type(t.id) == "string" and t.id:match("^[%w_.%-]+$") and #t.id <= 64 then
      for _, p in ipairs(view.players) do
        if type(t.player) == "string" and tostring(p.name):lower() == t.player:lower() then out[t.id] = p; break end
      end
    end
  end
  return out
end

return M
