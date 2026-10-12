-- Strip on a friend's Multiview tile (design 5d): "SL <place> · <n> alive" (first text row).
local common = require("ui.common")

local M = {}

--- player = view player entry of the tile's owner.
function M.build(tr, player)
  return { type = "text", id = "tile", text = tr("tile_strip", { place = common.place_label(player.place, tr), n = player.alive }),
    style = "meta" }
end

--- Match the host event `tiles` ({ id, player, user_id, game }) to view players: by `user_id` first
--- (empty string = unknown), by name (case-insensitive) as fallback. Returns { [tile id] = player }.
function M.match(tiles, view)
  local out = {}
  for _, t in ipairs(type(tiles) == "table" and tiles or {}) do
    if type(t) == "table" and type(t.id) == "string" and t.id:match("^[%w_.%-]+$") and #t.id <= 64 then
      local found
      if type(t.user_id) == "string" and t.user_id ~= "" then
        for _, p in ipairs(view.players) do
          if p.id == t.user_id then found = p; break end
        end
      end
      if not found and type(t.player) == "string" then
        for _, p in ipairs(view.players) do
          if tostring(p.name):lower() == t.player:lower() then found = p; break end
        end
      end
      out[t.id] = found
    end
  end
  return out
end

return M
