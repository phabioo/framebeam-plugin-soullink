-- In-game panel (design 5b): run header, location card with place picker, encounter hint,
-- own team with link partners, graveyard, footer. Pure builder: panel.build(ctx) -> block.
local common = require("ui.common")
local corr_ui = require("ui.corrections")
local oras = require("data.oras")

local M = {}

function M.empty(tr)
  return { type = "column", gap = 12, children = {
    common.empty(tr, "empty_title", "empty_panel"),
  } }
end

local function header(ctx)
  local tr, run = ctx.tr, ctx.run
  local kids = {
    { type = "text", id = "h-eyebrow", text = tr("panel_eyebrow_" .. ctx.view.mode), style = "eyebrow" },
    { type = "text", id = "h-name", text = run.name or "", style = "heading" },
    { type = "button", id = "h-open", label = tr("open_run"), action = "open_run", variant = "quiet" },
  }
  if not common.writable(run) then
    table.insert(kids, 3, { type = "badge", id = "h-ro", text = tr("run_readonly_" .. tostring(run.status)), tone = "warning" })
  end
  return { type = "column", id = "header", gap = 4, children = kids }
end

local function others_on_place(ctx, me)
  local tr, view = ctx.tr, ctx.view
  local rows = {}
  local key = me.place.key
  if not key then return rows end
  local row = common.row_of(view, key)
  for i, p in ipairs(view.players) do
    if p.id ~= me.id and p.place.key == key then
      local cell = row and row.cells[p.id] or { state = "open" }
      rows[#rows + 1] = { type = "row", id = "o-" .. i, gap = 8, align = "center", children = {
        { type = "avatar", id = "o-av" .. i, initial = common.initial(p.name), color = common.color(p, i), size = "s" },
        { type = "text", id = "o-t" .. i, text = tr("other_on_place", { player = p.name, state = common.cell_text(cell, tr) }),
          style = "meta" },
      } }
    end
  end
  return rows
end

local function location(ctx, me)
  local tr = ctx.tr
  local status = me.place.status
  local sub_key = ({ open = "loc_open", encounter = "loc_encounter", caught = "loc_caught", missed = "loc_missed",
    no_route = "loc_no_route", unknown = "loc_unknown" })[status] or "loc_unknown"
  local row = me.place.key and common.row_of(ctx.view, me.place.key)
  local cell = row and row.cells[me.id]
  local sub
  if status == "caught" and cell then
    sub = common.cell_text(cell, tr)
  else
    sub = tr(sub_key)
  end
  local kids = others_on_place(ctx, me)
  return { type = "location", id = "loc", title = common.place_label(me.place, tr), sub = sub,
    status = common.loc_status(status), children = kids }
end

local function place_picker(ctx, me)
  local tr = ctx.tr
  local opts = { { value = oras.STARTER, label = oras.label(oras.STARTER, tr) } }
  for _, k in ipairs(oras.ROUTE_KEYS) do opts[#opts + 1] = { value = k, label = oras.label(k, tr) } end
  local selected = me.place.key
  local custom = selected and selected:match("^place:")
  if custom then opts[#opts + 1] = { value = selected, label = oras.label(selected, tr) } end
  local kids = {
    { type = "select", id = "place-select", options = opts, selected = selected, action = "place_select" },
    { type = "textfield", id = "place-text", action = "place_text", placeholder = tr("place_other"), text = "" },
  }
  if ctx.readonly then return nil end
  return { type = "column", id = "place-picker", gap = 4, children = kids }
end

local function encounter_hint(ctx, me)
  local tr = ctx.tr
  if me.place.status ~= "encounter" or ctx.readonly then return nil end
  local row = common.row_of(ctx.view, me.place.key)
  local cell = row and row.cells[me.id]
  return { type = "card", id = "enc", title = tr("enc_title"), children = {
    { type = "text", id = "enc-text", text = tr("enc_text", { mon = "#" .. tostring(cell and cell.species or "?") }), style = "meta" },
    { type = "button", id = "enc-no", label = tr("doesnt_count"), action = "dc_open", variant = "quiet" },
  } }
end

local function team(ctx, me)
  local tr = ctx.tr
  local groups = common.groups(ctx.view)
  local kids = {}
  for i, m in ipairs(me.team) do
    local title = common.mon_name(m) .. (m.level and (" · " .. tr("level_short", { n = m.level })) or "")
    if m.dead then title = "✕ " .. title end
    local c = { { type = "text", id = "m-t" .. i, text = title, style = "body", tone = m.dead and "neutral" or nil } }
    local ratio = (not m.dead) and common.hp_ratio(m)
    if ratio then
      c[#c + 1] = { type = "bar", id = "m-hp" .. i, value = ratio, label = tr("hp_label", { hp = m.hp, max = m.mhp }) }
    end
    local g = m.group and groups[m.group]
    if g and g.count > 1 then
      local partners = {}
      for j, pm in ipairs(g.members) do
        if pm.owner ~= me.id then
          local idx, pl = common.index_of(ctx.view, pm.owner)
          partners[#partners + 1] = { type = "avatar", id = "m-p" .. i .. "-" .. j,
            initial = common.initial(pl and pl.name), color = common.color(pl or {}, idx), size = "s" }
          partners[#partners + 1] = { type = "text", id = "m-pt" .. i .. "-" .. j,
            text = (pm.dead and "✕ " or "") .. common.mon_name(pm), style = "meta" }
        end
      end
      c[#c + 1] = { type = "row", id = "m-pr" .. i, gap = 8, align = "center", children = partners }
    end
    if not m.dead and not ctx.readonly then
      c[#c + 1] = { type = "button", id = "m-dead" .. i, label = tr("mark_dead"), action = "mark_dead", value = m.id,
        variant = "quiet", confirm = { title = tr("c_confirm_title_mark_dead"), text = tr("c_confirm_text_mark_dead"),
          confirm_label = tr("c_submit_mark_dead"), danger = true } }
    end
    kids[#kids + 1] = { type = "column", id = "mon" .. i, gap = 4, children = c }
  end
  if #kids == 0 then kids[1] = { type = "text", id = "team-empty", text = tr("team_empty"), style = "meta" } end
  return { type = "section", id = "team", title = tr("team_title", { n = #me.team }), children = kids }
end

local function graveyard(ctx)
  local tr, view = ctx.tr, ctx.view
  local open = ctx.ui.grave_open
  local kids = { { type = "chip", id = "grave-chip", text = tr("grave_title", { n = #view.graveyard }),
    action = "grave_toggle", selected = open and true or false } }
  if open then
    local rows = {}
    for i, g in ipairs(view.graveyard) do
      rows[i] = { id = "g" .. i, title = "✕ " .. common.mon_name(g),
        sub = tr("grave_sub", { route = g.route and oras.label(g.route, tr) or "?", player = common.name_of(view, g.owner) }),
        tone = "neutral" }
    end
    if #rows > 0 then kids[#kids + 1] = { type = "list", id = "grave-list", rows = rows } end
  end
  return { type = "column", id = "grave", gap = 4, children = kids }
end

local function footer(ctx, me)
  local tr = ctx.tr
  local opts = {}
  for n = 0, 8 do opts[#opts + 1] = { value = n, label = tostring(n) } end
  local kids = { { type = "stat", id = "badges", label = tr("badges"), value = tostring(me.badges) .. " / 8" } }
  if not ctx.readonly then
    kids[#kids + 1] = { type = "select", id = "badges-select", options = opts, selected = me.badges, action = "badges_select" }
  end
  if me.level_cap then
    kids[#kids + 1] = { type = "text", id = "cap", text = tr("next_cap", { n = me.level_cap }), style = "meta" }
  end
  kids[#kids + 1] = { type = "button", id = "f-open", label = tr("run_screen"), action = "open_run", variant = "secondary" }
  return { type = "column", id = "footer", gap = 8, children = kids }
end

--- ctx.view / ctx.run required.
function M.build(ctx)
  local me = common.me(ctx)
  if not me then
    return { type = "column", gap = 12, children = { header(ctx), common.empty(ctx.tr, "no_player_title", "no_player_text") } }
  end
  local kids = { header(ctx), location(ctx, me) }
  local picker = place_picker(ctx, me)
  if picker then kids[#kids + 1] = picker end
  local hint = encounter_hint(ctx, me)
  if hint then kids[#kids + 1] = hint end
  local corr = corr_ui.section(ctx)
  if corr then kids[#kids + 1] = corr end
  kids[#kids + 1] = team(ctx, me)
  kids[#kids + 1] = graveyard(ctx)
  kids[#kids + 1] = footer(ctx, me)
  return { type = "column", id = "panel", gap = 12, children = kids }
end

return M
