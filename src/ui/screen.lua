-- Run screen (design 5e), shown in the `screen` slot (and, read only, in the `run` slot of the Runs page):
-- frame with tabs Map | Routes | Team & box | Graveyard | Event log. All manual corrections (5f) live here.
-- The Map tab only shows an image after the player confirmed a candidate (app.maps); until then the
-- Routes tab comes first and the Map tab shows the empty state (and the candidate chooser once the
-- game files were scanned).
local common = require("ui.common")
local corr_ui = require("ui.corrections")
local oras = require("data.oras")

local M = {}

M.LOG_LIMIT = 100

function M.empty(tr)
  return { type = "column", gap = 12, children = { common.empty(tr, "empty_title", "empty_screen") } }
end

local MAP_STATES = { ready = true, choose = true, scanning = true }
function M.has_map(ctx) return ctx ~= nil and ctx.map ~= nil and MAP_STATES[ctx.map.state] == true end

local RULE_ORDER = { "first_encounter_only", "dupes_clause", "shiny_clause", "hordes_count",
  "pairs_differ_primary_type", "only_linked_in_team", "nickname_required", "level_caps" }

local function rules_list(ctx)
  local tr, view = ctx.tr, ctx.view
  local rows = { { id = "ru-mode", title = tr("rs_mode"), sub = common.mode_text(view, tr) } }
  for _, k in ipairs(RULE_ORDER) do
    rows[#rows + 1] = { id = "ru-" .. k, title = tr("rs_" .. k), sub = tr(view.rules[k] and "rule_on" or "rule_off") }
  end
  return { type = "list", id = "rules-list", rows = rows }
end

local function header(ctx)
  local tr, view, run = ctx.tr, ctx.view, ctx.run
  local players = {}
  for i, p in ipairs(view.players) do
    players[#players + 1] = { type = "row", id = "ph" .. i, gap = 8, align = "center", children = {
      { type = "avatar", id = "ph-av" .. i, initial = common.initial(p.name), color = common.color(p, i), size = "m" },
      { type = "text", id = "ph-t" .. i, text = p.name .. " · " .. common.place_label(p.place, tr, view), style = "body" },
    } }
  end
  local s = view.stats
  local rules_open = ctx.ui.rules_open == true
  local kids = {
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
    { type = "row", id = "head-rules", gap = 8, children = {
      { type = "chip", id = "rules-chip", text = tr("rules_title"), action = "rules_toggle", selected = rules_open },
    } },
  }
  if rules_open then kids[#kids + 1] = rules_list(ctx) end
  return { type = "column", id = "head", gap = 8, children = kids }
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
  local icons = {}
  for i, p in ipairs(view.players) do
    local cell = row.cells[p.id]
    local ic = cell and cell.species and common.icon_block(ctx, "rd-i" .. i, { species = cell.species, nickname = cell.nickname,
      dead = cell.state == "dead" }, common.color(p, i), "m")
    if ic then icons[#icons + 1] = ic end
  end
  if #icons > 0 then kids[#kids + 1] = { type = "row", id = "rd-icons", gap = 8, children = icons } end
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
  return { type = "section", id = "route-detail", title = common.route_label(ctx, route), children = kids }
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
      local cells = { common.route_label(ctx, r.route) }
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
      local head = { type = "text", id = "tm" .. i .. "-" .. j, text = title, style = "body" }
      local icon = common.icon_block(ctx, "tm-i" .. i .. "-" .. j, m, common.color(p, i), "s")
      if icon then head = { type = "row", id = "tm-h" .. i .. "-" .. j, gap = 8, align = "center", children = { icon, head } } end
      local c = { head }
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
        rows[#rows + 1] = { id = "b" .. id, title = (m.dead and "✕ " or "") .. common.mon_name(m), image = common.icon(ctx, m.species, m.form),
          sub = m.route and common.route_label(ctx, m.route) or nil, tone = m.dead and "neutral" or nil }
      end
    end
    kids[#kids + 1] = { type = "text", id = "box-count" .. i, text = tr("box_count", { n = p.box_count }), style = "eyebrow" }
    if #rows > 0 then kids[#kids + 1] = { type = "list", id = "box-list" .. i, rows = rows } end
    secs[#secs + 1] = { type = "section", id = "pl" .. i, title = tr("team_player", { player = p.name, place = common.place_label(p.place, tr, view) }),
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
  for i, g in ipairs(view.graveyard) do
    local cause = g.doa and tr("cause_doa") or tr("cause_" .. tostring(g.cause))
    local parts = { common.name_of(view, g.owner), g.route and common.route_label(ctx, g.route) or "—", cause }
    if g.group_number then parts[#parts + 1] = tr("group_n", { n = g.group_number }) end
    rows[#rows + 1] = { id = "g" .. i, title = "✕ " .. common.mon_name(g), sub = table.concat(parts, " · "),
      image = common.icon(ctx, g.species, g.form), tone = "neutral",
      action = g.group and "undo_open" or nil, value = g.group }
  end
  return { type = "column", id = "page-grave", gap = 12, children = {
    { type = "list", id = "grave-list", rows = rows },
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

local STEPS = { 2, 10, 40 }

local function calibration(ctx, m)
  local tr, c = ctx.tr, ctx.ui.calib
  local opts = {}
  for _, o in ipairs(common.route_options(ctx, nil, c.route)) do
    if oras.is_route(o.value) then opts[#opts + 1] = o end
  end
  local steps = {}
  for _, n in ipairs(STEPS) do steps[#steps + 1] = { value = n, label = tr("calib_px", { n = n }) } end
  local kids = {
    { type = "text", id = "calib-hint", text = tr("calib_hint"), style = "meta" },
    { type = "select", id = "calib-route", options = #opts > 0 and opts or { { value = "", label = tr("place_none") } },
      selected = c.route or "", action = "calib_route" },
    { type = "segmented", id = "calib-step", options = steps, selected = c.step or 10, action = "calib_step" },
  }
  if c.x then
    kids[#kids + 1] = { type = "text", id = "calib-pos", text = tr("calib_pos", { x = c.x, y = c.y }), style = "meta" }
    kids[#kids + 1] = { type = "row", id = "calib-arrows", gap = 8, children = {
      { type = "button", id = "calib-l", label = "←", action = "calib_move", value = "l", variant = "secondary" },
      { type = "button", id = "calib-u", label = "↑", action = "calib_move", value = "u", variant = "secondary" },
      { type = "button", id = "calib-r", label = "→", action = "calib_move", value = "r", variant = "secondary" },
      { type = "button", id = "calib-d", label = "↓", action = "calib_move", value = "d", variant = "secondary" },
    } }
    kids[#kids + 1] = { type = "button", id = "calib-set", label = tr("calib_set"), action = "calib_set", variant = "primary" }
  end
  if c.msg then kids[#kids + 1] = { type = "text", id = "calib-msg", text = tr("calib_msg_" .. c.msg), style = "meta" } end
  kids[#kids + 1] = { type = "row", id = "calib-acts", gap = 8, children = {
    { type = "button", id = "calib-export", label = tr("calib_export"), action = "calib_export", variant = "secondary" },
    { type = "button", id = "calib-done", label = tr("calib_done"), action = "calib_toggle", variant = "quiet" },
  } }
  return { type = "section", id = "calib", title = tr("calib_title"), children = kids }
end

local function candidates(ctx, m)
  local tr = ctx.tr
  local kids = { { type = "text", id = "mc-hint", text = tr("map_choose_hint"), style = "meta" } }
  if #m.candidates == 0 then
    kids[#kids + 1] = { type = "text", id = "mc-none", text = tr("map_none"), style = "meta" }
  end
  for i, c in ipairs(m.candidates) do
    local row = {}
    if c.src then row[#row + 1] = { type = "image", id = "mc-img" .. i, src = c.src, size = "l", label = tr("map_cand", { n = i }) } end
    local label = tr("map_cand_size", { n = i, w = c.w or "?", h = c.h or "?" })
    if c.suggested then label = label .. " · " .. tr("map_suggested") end
    row[#row + 1] = { type = "column", id = "mc-col" .. i, gap = 4, children = {
      { type = "text", id = "mc-t" .. i, text = label, style = "body" },
      { type = "button", id = "mc-use" .. i, label = tr("map_use"), action = "map_use", value = c.id, variant = "secondary" },
    } }
    kids[#kids + 1] = { type = "row", id = "mc-row" .. i, gap = 12, align = "center", children = row }
  end
  return kids
end

local function map_page(ctx)
  local view, m, tr = ctx.view, ctx.map, ctx.tr
  if m.state ~= "ready" then
    -- no image before the player confirmed a candidate: empty state (5e), then the chooser
    local kids = { { type = "empty", id = "map-scan", title = tr("map_scanning"), text = tr("map_empty_text") } }
    if m.state == "choose" then
      for _, b in ipairs(candidates(ctx, m)) do kids[#kids + 1] = b end
    end
    return { type = "column", id = "page-map", gap = 12, children = kids }
  end
  local players, routes, shown = {}, {}, {}
  for i, p in ipairs(view.players) do
    local c = p.place.key and m.coords[p.place.key]
    if c then
      players[#players + 1] = { id = p.id, initial = common.initial(p.name), color = common.color(p, i), x = c.x, y = c.y }
    end
  end
  local function route_marker(key)
    local c = m.coords[key]
    local r = common.row_of(view, key)
    local icons = {}
    if r then
      for i, p in ipairs(view.players) do
        local cell = r.cells[p.id]
        local src = cell and cell.species and common.icon(ctx, cell.species, nil)
        if src and #icons < 8 then icons[#icons + 1] = { src = src, owner = common.color(p, i) } end
      end
    end
    routes[#routes + 1] = { id = key, x = c.x, y = c.y, area = c.area, number = r and r.group and r.group.number or nil,
      done = r and r.done or false, icons = #icons > 0 and icons or nil }
  end
  for _, r in ipairs(view.rows) do
    if m.coords[r.route] then route_marker(r.route); shown[r.route] = true end
  end
  local extra = {}
  for key in pairs(m.coords) do if not shown[key] then extra[#extra + 1] = key end end
  table.sort(extra, function(a, b) return oras.compare(a, b, view.order) end)
  for _, key in ipairs(extra) do route_marker(key) end
  local calib = ctx.ui.calib
  if calib and calib.x then
    players[#players + 1] = { id = "cursor", initial = "+", color = 1, x = calib.x, y = calib.y }
  end
  local map = { type = "map", id = "map", players = players, routes = routes, filter = ctx.ui.map_filter or "all",
    me = ctx.me, legend = true, action = "map_select", image = m.src, image_w = m.w, image_h = m.h }
  if ctx.ui.selected_route then map.selected = ctx.ui.selected_route end
  local kids = { map, { type = "row", id = "map-acts", gap = 8, children = {
    { type = "button", id = "map-calib", label = tr("calib_open"), action = "calib_toggle",
      variant = calib and "primary" or "quiet" },
    { type = "button", id = "map-change", label = tr("map_change"), action = "map_reset", variant = "quiet",
      confirm = { title = tr("map_change_title"), text = tr("map_change_text"), confirm_label = tr("map_change") } },
  } } }
  if calib then kids[#kids + 1] = calibration(ctx, m) end
  return { type = "column", id = "page-map", gap = 12, children = kids }
end

--- Tab order for the current data: Map | Routes | Team & box | Graveyard | Event log. The Map tab
--- leads only with a confirmed image; while it is being set up it follows Routes; hidden when the
--- game has no map to offer.
function M.tab_ids(ctx)
  local ids = {}
  local ready = ctx ~= nil and ctx.map ~= nil and ctx.map.state == "ready"
  if ready then ids[#ids + 1] = "map" end
  ids[#ids + 1] = "routes"
  if M.has_map(ctx) and not ready then ids[#ids + 1] = "map" end
  for _, id in ipairs({ "team", "grave", "log" }) do ids[#ids + 1] = id end
  return ids
end

function M.build(ctx)
  local tr, view = ctx.tr, ctx.view
  local ids = M.tab_ids(ctx)
  local labels, pages = {}, {}
  local counts = { routes = #view.rows, grave = #view.graveyard, log = #(ctx.events or {}) }
  for i, id in ipairs(ids) do
    labels[i] = tr("tab_" .. id, { n = counts[id] or 0 })
    local builders = { map = map_page, routes = routes_page, team = team_page, grave = graveyard_page, log = log_page }
    pages[i] = builders[id](ctx)
  end
  local sel = math.min(math.max(ctx.ui.screen_tab or 1, 1), #ids)
  local kids = {}
  kids[#kids + 1] = header(ctx)
  local corr = corr_ui.section(ctx)
  if corr then kids[#kids + 1] = corr end
  kids[#kids + 1] = { type = "tabs", id = "tabs", tabs = labels, selected = sel, action = "tab", children = pages }
  return { type = "column", id = "screen", gap = 16, children = kids }
end

return M
