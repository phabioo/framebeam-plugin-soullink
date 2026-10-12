-- HUD widget (design 5c): compact place + status; expanded with the other players.
local common = require("ui.common")

local M = {}

function M.empty(tr)
  return { type = "text", id = "hud-empty", text = tr("hud_empty"), style = "meta" }
end

local function dot(status) return "●" end

--- ctx.ui.hud_expanded / ctx.hud_death (text, set for ~3 s after a linked death).
function M.build(ctx)
  local tr, view = ctx.tr, ctx.view
  local me = common.me(ctx)
  if not me then return M.empty(tr) end
  local status = me.place.status
  local compact = { type = "row", id = "hud-row", gap = 8, align = "center", children = {
    { type = "badge", id = "hud-sl", text = "SL", tone = "info" },
    { type = "text", id = "hud-place", text = common.place_label(me.place, tr), style = "body" },
    { type = "text", id = "hud-status", text = dot(status) .. " " .. tr("hud_status_" .. status),
      tone = common.status_tone(status), style = "meta" },
  } }
  local kids = { compact }
  if ctx.hud_death then
    kids[#kids + 1] = { type = "text", id = "hud-death", text = ctx.hud_death, style = "meta" }
  end
  if ctx.ui.hud_expanded or ctx.hud_death then
    local key = me.place.key
    local row = key and common.row_of(view, key)
    for i, p in ipairs(view.players) do
      if p.id ~= me.id then
        local cell = row and row.cells[p.id] or { state = "open" }
        kids[#kids + 1] = { type = "row", id = "hud-p" .. i, gap = 8, align = "center", children = {
          { type = "avatar", id = "hud-av" .. i, initial = common.initial(p.name), color = common.color(p, i), size = "s" },
          { type = "text", id = "hud-pt" .. i, text = tr("hud_other", { player = p.name, state = common.cell_text(cell, tr) }),
            style = "meta" },
        } }
      end
    end
  end
  return { type = "card", id = "hud", action = "hud_toggle", children = kids }
end

return M
