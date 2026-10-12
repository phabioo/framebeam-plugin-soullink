-- Run screen (design 5e), shown in the in-game screen slot: tabs Routes | Team & box | Graveyard |
-- Event log (Map first only when route coordinates exist: drawn default F hides it otherwise).
local common = require("ui.common")
local corr_ui = require("ui.corrections")
local oras = require("data.oras")

local M = {}

M.LOG_LIMIT = 100

function M.empty(tr)
  return { type = "column", gap = 12, children = { common.empty(tr, "empty_title", "empty_screen") } }
end

function M.has_map() return next(oras.COORDS) ~= nil end

local function header(ctx)
  local tr, view, run = ctx.tr, ctx.view, ctx.run
  local players = {}
  for i, p in ipairs(view.players) do
    players[#players + 1] = { type = "row", id = "ph" .. i, gap = 8, align = "center", children = {
      { type = "avatar", id = "ph-av" .. i, initial = common.initial(p.name), color = common.color(p, i), size = "m" },
      { type = "text", id = "ph-t" .. i, text = p.name .. " · " .. common.place_label(p.place, tr), style = "body" },
    } }
  end
  local s = view.stats
  return { type = "column", id = "head", gap = 8, children = {
    { type = "row", id = "head-row", gap = 8, align = "center", children = {
      { type = "text", id = "head-name", text = run.name or "", style = "title" },
      { type = "badge", id = "head-status", text = tr("run_status_" .. tostring(run.status)) .. " · " .. common.mode_text(view, tr),
        tone = common.writable(run) and "info" or "warning" },
    } },
    { type = "column", id = "head-players", gap = 4, children = players },
    { type = "grid", id = "head-stats", columns = 3, gap = 8, children = {
      { type = "stat", id = "st-deaths", label = tr("stat_deaths"), value = tostring(s.deaths) },
      { type = "stat", id = "st-routes", label = tr("stat_routes"), value = s.routes_done .. " / " .. s.routes_total },
      { type = "stat", id = "st-badges", label = tr("stat_badges"), value = tostring(s.badges_max) },
    } },
  } }
end

local function find_mine(ctx, route)
  local me = common.me(ctx)
  if not me then return nil end
  for _, id in ipairs(me.ids) do
    local m = me.mons[id]
    if m.route == route and m.counted then return m end
  end
  return nil
end

local function route_detail(ctx)
  local tr, view = ctx.tr, ctx.view
  local route = ctx.ui.selected_route
  local row = route and common.row_of(view, route)
  if not row then return nil end
  local g = row.group
  local kids = { { type = "text", id = "rd-status", text = common.group_state_text(g, tr) .. (g and g.number and (" · " .. tr("group_n", { n = g.number })) or ""),
    style = "meta" } }
  if not ctx.readonly then
    local acts = {
      { type = "button", id = "rd-missed", label = tr("mark_missed"), action = "missed_open", value = route, variant = "quiet" },
      { type = "button", id = "rd-dc", label = tr("doesnt_count"), action = "dc_open", value = route, variant = "quiet" },
    }
    if g and g.state == "dead" then
      acts[#acts + 1] = { type = "button", id = "rd-undo", label = tr("undo_death"), action = "undo_open", value = route, variant = "quiet" }
    end
    local mine = find_mine(ctx, route)
    if mine then
      acts[#acts + 1] = { type = "button", id = "rd-group", label = tr("change_group"), action = "group_open", value = mine.id, variant = "quiet" }
    end
    kids[#kids + 1] = { type = "row", id = "rd-acts", gap = 8, children = acts }
  end
  return { type = "section", id = "route-detail", title = oras.label(route, tr), children = kids }
end

local function routes_page(ctx)
  local tr, view = ctx.tr, ctx.view
  local filter = ctx.ui.routes_filter or "all"
  local n_open, n_done = 0, 0
  for _, r in ipairs(view.rows) do if r.done then n_done = n_done + 1 else n_open = n_open + 1 end end
  local columns = { tr("col_route") }
  for _, p in ipairs(view.players) do columns[#columns + 1] = p.name end
  columns[#columns + 1] = tr("col_group")
  columns[#columns + 1] = tr("col_status")
  local rows = {}
  for _, r in ipairs(view.rows) do
    if filter == "all" or (filter == "open" and not r.done) or (filter == "done" and r.done) then
      local cells = { oras.label(r.route, tr) }
      for _, p in ipairs(view.players) do cells[#cells + 1] = common.cell_text(r.cells[p.id], tr) end
      cells[#cells + 1] = (r.group and r.group.number) and tr("group_n", { n = r.group.number }) or "—"
      cells[#cells + 1] = common.group_state_text(r.group, tr)
      rows[#rows + 1] = { cells = cells, action = "route_select", value = r.route }
    end
  end
  local kids = {
    { type = "row", id = "rf", gap = 8, align = "center", children = {
      { type = "chip", id = "rf-all", text = tr("filter_all", { n = #view.rows }), action = "rf:all", selected = filter == "all" },
      { type = "chip", id = "rf-open", text = tr("filter_open", { n = n_open }), action = "rf:open", selected = filter == "open" },
      { type = "chip", id = "rf-done", text = tr("filter_done", { n = n_done }), action = "rf:done", selected = filter == "done" },
    } },
  }
  if not ctx.readonly then
    kids[#kids + 1] = { type = "button", id = "add-open", label = tr("add_by_hand"), action = "add_open", variant = "secondary" }
  end
  if #rows > 0 then
    kids[#kids + 1] = { type = "table", id = "routes-table", columns = columns, rows = rows }
  else
    kids[#kids + 1] = { type = "text", id = "routes-empty", text = tr("routes_empty"), style = "meta" }
  end
  local d = route_detail(ctx)
  if d then kids[#kids + 1] = d end
  return { type = "column", id = "page-routes", gap = 12, children = kids }
end

local function team_page(ctx)
  local tr, view = ctx.tr, ctx.view
  local secs = {}
  for i, p in ipairs(view.players) do
    local kids = {}
    for j, m in ipairs(p.team) do
      local title = (m.dead and "✕ " or "") .. common.mon_name(m) .. (m.level and (" · " .. tr("level_short", { n = m.level })) or "")
      local c = { { type = "text", id = "tm" .. i .. "-" .. j, text = title, style = "body" } }
      local ratio = (not m.dead) and common.hp_ratio(m)
      if ratio then c[#c + 1] = { type = "bar", id = "tm-hp" .. i .. "-" .. j, value = ratio, label = tr("hp_label", { hp = m.hp, max = m.mhp }) } end
      if p.id == ctx.me and not ctx.readonly then
        c[#c + 1] = { type = "row", id = "tm-a" .. j, gap = 8, children = {
          { type = "button", id = "tm-g" .. j, label = tr("change_group"), action = "group_open", value = m.id, variant = "quiet" },
          { type = "button", id = "tm-gift" .. j, label = tr("mark_gift"), action = "gift_open", value = m.id, variant = "quiet" },
          (not m.dead) and { type = "button", id = "tm-d" .. j, label = tr("mark_dead"), action = "dead_open", value = m.id, variant = "quiet" } or nil,
        } }
      end
      kids[#kids + 1] = { type = "column", id = "tmc" .. i .. "-" .. j, gap = 4, children = c }
    end
    if #p.team == 0 then kids[1] = { type = "text", id = "tm-empty" .. i, text = tr("team_empty"), style = "meta" } end
    local rows = {}
    for _, id in ipairs(p.ids) do
      local m = p.mons[id]
      if m.where == "box" then
        rows[#rows + 1] = { id = "b" .. id, title = (m.dead and "✕ " or "") .. common.mon_name(m),
          sub = m.route and oras.label(m.route, tr) or nil, tone = m.dead and "neutral" or nil }
      end
    end
    kids[#kids + 1] = { type = "text", id = "box-count" .. i, text = tr("box_count", { n = p.box_count }), style = "eyebrow" }
    if #rows > 0 then kids[#kids + 1] = { type = "list", id = "box-list" .. i, rows = rows } end
    secs[#secs + 1] = { type = "section", id = "pl" .. i, title = tr("team_player", { player = p.name, place = common.place_label(p.place, tr) }),
      children = kids }
  end
  return { type = "column", id = "page-team", gap = 12, children = secs }
end

local function graveyard_page(ctx)
  local tr, view = ctx.tr, ctx.view
  if #view.graveyard == 0 then
    return { type = "column", id = "page-grave", gap = 12, children = { { type = "text", id = "grave-empty", text = tr("grave_empty"), style = "meta" } } }
  end
  local rows = {}
  for _, g in ipairs(view.graveyard) do
    local cause = g.doa and tr("cause_doa") or tr("cause_" .. tostring(g.cause))
    rows[#rows + 1] = { cells = { common.mon_name(g), common.name_of(view, g.owner), g.route and oras.label(g.route, tr) or "—",
      cause, g.group_number and tr("group_n", { n = g.group_number }) or "—" },
      action = g.group and "undo_open" or nil, value = g.group }
  end
  return { type = "column", id = "page-grave", gap = 12, children = {
    { type = "table", id = "grave-table", columns = { tr("col_creature"), tr("col_owner"), tr("col_route"), tr("col_cause"), tr("col_group") }, rows = rows },
    { type = "text", id = "grave-hint", text = tr("grave_hint"), style = "meta" },
  } }
end

local function event_text(ctx, ev)
  if type(ev.text) == "string" and ev.text ~= "" then return ev.text end
  return ctx.tr("log_type_" .. tostring(ev.type):gsub("[^%w]", "_"))
end

local function log_page(ctx)
  local tr, view = ctx.tr, ctx.view
  local filter = ctx.ui.log_filter or "all"
  local rows = {}
  local evs = ctx.events or {}
  for i = #evs, 1, -1 do
    local ev = evs[i]
    if ev.source ~= "hub" and (filter == "all" or ev.source == filter) and #rows < M.LOG_LIMIT then
      rows[#rows + 1] = {
        id = "e" .. ev.seq, title = event_text(ctx, ev),
        sub = tr("log_sub", { player = common.name_of(view, ev.user_id), source = tr("source_" .. tostring(ev.source)) }),
        meta = "#" .. ev.seq, tone = ev.source == "manual" and "warning" or nil,
        action = (ev.type == "soullink.correction" and not ctx.readonly) and "revert_open" or nil,
        value = ev.seq,
      }
    end
  end
  local kids = { { type = "row", id = "lf", gap = 8, children = {
    { type = "chip", id = "lf-all", text = tr("log_all"), action = "lf:all", selected = filter == "all" },
    { type = "chip", id = "lf-auto", text = tr("log_automatic"), action = "lf:automatic", selected = filter == "automatic" },
    { type = "chip", id = "lf-manual", text = tr("log_manual"), action = "lf:manual", selected = filter == "manual" },
  } } }
  if #rows > 0 then kids[#kids + 1] = { type = "list", id = "log-list", rows = rows }
  else kids[#kids + 1] = { type = "text", id = "log-empty", text = tr("log_empty"), style = "meta" } end
  return { type = "column", id = "page-log", gap = 12, children = kids }
end

local function map_page(ctx)
  local view = ctx.view
  local players, routes = {}, {}
  for i, p in ipairs(view.players) do
    local c = p.place.key and oras.COORDS[p.place.key]
    if c then
      players[#players + 1] = { id = p.id, initial = common.initial(p.name), color = common.color(p, i), x = c.x, y = c.y }
    end
  end
  for _, r in ipairs(view.rows) do
    local c = oras.COORDS[r.route]
    if c then
      routes[#routes + 1] = { id = r.route, x = c.x, y = c.y, area = c.area, number = r.group and r.group.number or nil, done = r.done }
    end
  end
  local map = { type = "map", id = "map", players = players, routes = routes, filter = ctx.ui.map_filter or "all",
    me = ctx.me, legend = true, action = "map_select" }
  if ctx.ui.map_src and oras.MAP_SIZE then
    map.image, map.image_w, map.image_h = ctx.ui.map_src, oras.MAP_SIZE.w, oras.MAP_SIZE.h
  end
  if ctx.ui.selected_route then map.selected = ctx.ui.selected_route end
  return { type = "column", id = "page-map", gap = 12, children = { map } }
end

--- Tab order for the current data: { "map"? , "routes", "team", "grave", "log" }.
function M.tab_ids()
  local ids = {}
  if M.has_map() then ids[#ids + 1] = "map" end
  for _, id in ipairs({ "routes", "team", "grave", "log" }) do ids[#ids + 1] = id end
  return ids
end

function M.build(ctx)
  local tr, view = ctx.tr, ctx.view
  local ids = M.tab_ids()
  local labels, pages = {}, {}
  local counts = { routes = #view.rows, grave = #view.graveyard, log = #(ctx.events or {}) }
  for i, id in ipairs(ids) do
    labels[i] = tr("tab_" .. id, { n = counts[id] or 0 })
    local builders = { map = map_page, routes = routes_page, team = team_page, grave = graveyard_page, log = log_page }
    pages[i] = builders[id](ctx)
  end
  local sel = math.min(math.max(ctx.ui.screen_tab or 1, 1), #ids)
  local kids = { header(ctx) }
  local corr = corr_ui.section(ctx)
  if corr then kids[#kids + 1] = corr end
  kids[#kids + 1] = { type = "tabs", id = "tabs", tabs = labels, selected = sel, action = "tab", children = pages }
  return { type = "column", id = "screen", gap = 16, children = kids }
end

return M
