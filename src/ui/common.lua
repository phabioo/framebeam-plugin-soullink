-- Shared helpers for the UI builders. Builders are pure: they take a context
--   ctx = { view, run, me, ui, tr, readonly, now, events }
-- and return fb.ui block trees. Only tones, sizes and player numbers are used, never colors.
local oras = require("data.oras")

local C = {}

--- Display name of a mon: its nickname, else "#<species id>" until the core provides names.
function C.mon_name(m)
  if m and type(m.nickname) == "string" and m.nickname ~= "" then return m.nickname end
  return "#" .. tostring(m and m.species or "?")
end

--- `cache:` src of the creature icon (pokemon-core icon, fetched lazily by the controller), or nil.
function C.icon(ctx, species, form)
  if type(ctx.icon) ~= "function" then return nil end
  return ctx.icon(species, form)
end

--- `image` block for a mon (alive or dead state), or nil while there is no icon.
function C.icon_block(ctx, id, m, owner, size)
  local src = C.icon(ctx, m.species, m.form)
  if not src then return nil end
  return { type = "image", id = id, src = src, size = size or "s", state = m.dead and "dead" or "alive",
           owner = owner, label = C.mon_name(m) }
end

--- Player number 1..8 (identity color): participant color 0..7 + 1, else the list position.
function C.color(p, i)
  if math.type(p.color) == "integer" and p.color >= 0 and p.color <= 7 then return p.color + 1 end
  return math.min(math.max(i or 1, 1), 8)
end

function C.initial(name)
  name = tostring(name or "?")
  local n = utf8.offset(name, 2) or (#name + 1)
  local s = name:sub(1, n - 1):upper()
  return s ~= "" and s or "?"
end

function C.index_of(view, id)
  for i, p in ipairs(view.players) do if p.id == id then return i, p end end
  return nil
end

function C.player(view, id)
  local _, p = C.index_of(view, id)
  return p
end

function C.name_of(view, id)
  local p = C.player(view, id)
  return p and p.name or tostring(id)
end

function C.groups(view)
  local map = {}
  for _, g in ipairs(view.groups) do map[g.route] = g end
  return map
end

function C.row_of(view, route)
  for _, r in ipairs(view.rows) do if r.route == route then return r end end
  return nil
end

--- Place text: name read from the game if the core reported it, else the route label.
function C.place_label(place, tr)
  if place.name and place.name ~= "" then return place.name end
  if place.key then return oras.label(place.key, tr) end
  return tr("place_none")
end

local LOC_STATUS = { open = "open", encounter = "encounter", caught = "caught", missed = "missed" }
--- Status for the `location` block.
function C.loc_status(status) return LOC_STATUS[status] or "none" end

local TONE = { open = "info", encounter = "info", caught = "ok", missed = "neutral" }
function C.status_tone(status) return TONE[status] or "neutral" end

--- Short text of a cell of the routes matrix.
function C.cell_text(cell, tr)
  if cell.state == "open" then return tr("cell_open") end
  if cell.state == "encounter" then return tr("cell_encounter", { mon = "#" .. tostring(cell.species or "?") }) end
  if cell.state == "missed" then return tr("cell_missed") end
  local name = (cell.nickname and cell.nickname ~= "") and cell.nickname or ("#" .. tostring(cell.species or "?"))
  if cell.state == "dead" then return "✕ " .. name end
  return name
end

function C.group_state_text(g, tr)
  if not g then return tr("group_none") end
  return tr("group_state_" .. g.state)
end

--- Progress of HP as 0..1, or nil when unknown.
function C.hp_ratio(m)
  if type(m.hp) ~= "number" or type(m.mhp) ~= "number" or m.mhp <= 0 then return nil end
  return math.max(0, math.min(1, m.hp / m.mhp))
end

--- The own player entry of the view (or nil).
function C.me(ctx) return C.player(ctx.view, ctx.me) end

--- Whether writes are accepted: run starting/active and not the read-only run view.
function C.writable(run)
  return run and not run.view and (run.status == "starting" or run.status == "active") or false
end

function C.empty(tr, title_key, text_key)
  return { type = "empty", id = "empty", title = tr(title_key), text = tr(text_key) }
end

function C.mode_text(view, tr) return tr("mode_" .. view.mode) end

--- Number of alive mons of all players that are not gone.
function C.alive_of(p) return p.alive end

--- Short list of the other players' names in the run.
function C.others_names(view, me)
  local names = {}
  for _, p in ipairs(view.players) do if p.id ~= me then names[#names + 1] = p.name end end
  return table.concat(names, ", ")
end

return C
