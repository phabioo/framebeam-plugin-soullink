-- v0.8.0: Uzume design boards 5b, 5e, 5f (panel, HUD, run tab, corrections). Synthetic data only.
local t = require("t")
local B = require("build")
local V = require("model.view")
local json = require("json")
local screen = require("ui.screen")
local hud = require("ui.hud")
local common = require("ui.common")
local corr_ui = require("ui.corrections")
local ui_validator = require("ui_validator")

local function read(path) local f = assert(io.open(path, "rb")); local s = f:read("a"); f:close(); return s end
local EN = json.decode(read("plugin/i18n/en.json"))
local DE = json.decode(read("plugin/i18n/de.json"))
local function tr(key, vars)
  local s = EN[key] or key
  return (s:gsub("{(%w+)}", function(k) return vars and vars[k] ~= nil and tostring(vars[k]) or "{" .. k .. "}" end))
end

local function setup()
  local run = B.run({ "Lena", "Jonas" })
  local cfg = B.cfg("soullink")
  local log = B.log()
  local trs = {}
  for i, n in ipairs({ "Lena", "Jonas" }) do
    trs[i] = B.tracker("u-" .. n:lower(), cfg, log)
    trs[i]:start()
  end
  for i, tk in ipairs(trs) do tk:place("route-101"); tk:catch(0x100 + i, 10 + i) end
  trs[1]:hp(0x101, 0)
  local st = {}
  for _, tk in ipairs(trs) do st[tk.uid] = tk.st end
  local view = V.view(run, st, log.events, cfg)
  return { view = view, run = run, me = "u-lena", ui = {}, tr = tr, readonly = false, events = log.events }
end

t.case("hotkey hints only name keys the manifest declares", function()
  local m = json.decode(read("plugin/manifest.json"))
  local declared = {}
  for _, h in ipairs(m.ui.hotkeys) do declared[h.id] = h.key end
  t.eq(common.HOTKEYS, declared)
end)

t.case("HUD: no own badge, status as toned badge, 'SL · place' text", function()
  local ctx = setup()
  local tree = hud.build(ctx)
  t.ok(ui_validator.validate(tree))
  t.eq(ui_validator.find(tree, "hud-sl"), nil)
  t.ok(ui_validator.find(tree, "hud-place").text:find("^SL · "))
  local b = ui_validator.find(tree, "hud-status")
  t.eq(b.type, "badge")
  t.eq(b.text, "Caught")
  t.eq(b.tone, "ok")
end)

t.case("run tab: summary line, tabs in board order, rules and game data below the tabs", function()
  local ctx = setup()
  ctx.diag = { a_b = 1 }
  local tree = screen.build(ctx)
  t.ok(ui_validator.validate(tree))
  t.eq(ui_validator.find(tree, "head-summary").text, "Deaths 2 · Routes 1 / 2 · Badges 0")
  for _, id in ipairs({ "head-name", "head-players", "head-stats" }) do t.eq(ui_validator.find(tree, id), nil, id) end
  local tabs = ui_validator.find(tree, "tabs")
  t.eq(tabs.tabs, { "Routes", "Team & box", "Graveyard", "Event log" })
  local ids = {}
  for _, c in ipairs(tree.children) do ids[#ids + 1] = c.id end
  t.eq(ids, { "head", "tabs", "foot" })
  t.ok(ui_validator.find(tree, "diag-chip") and ui_validator.find(tree, "rules-chip"))
  t.eq(ui_validator.find(tree, "diag-title"), nil, "game data stays closed")
end)

t.case("graveyard: linked deaths are grouped, with Undo… per group", function()
  local ctx = setup()
  ctx.ui.screen_tab_id = "grave"
  local tree = screen.build(ctx)
  local page = ui_validator.find(tree, "page-grave")
  local head = ui_validator.find(page, "grave-h1")
  t.eq(head.text, "Link group 1 · 2 died together")
  local undo = ui_validator.find(page, "grave-undo1")
  t.eq(undo.label, "Undo…")
  t.eq(undo.action, "undo_open")
  t.eq(#ui_validator.find(page, "grave-list").rows, 2)
  ctx.readonly = true
  t.eq(ui_validator.find(screen.build(ctx), "grave-undo1"), nil, "read only: no undo button")
end)

t.case("event log: Manual count, people select and person filter", function()
  local ctx = setup()
  ctx.ui.screen_tab_id = "log"
  local page = ui_validator.find(screen.build(ctx), "page-log")
  t.eq(ui_validator.find(page, "lf-manual").text, "Manual · 0")
  local sel = ui_validator.find(page, "lf-person")
  t.eq(#sel.options, 3)
  t.eq(sel.action, "log_person")
  local all = #ui_validator.find(page, "log-list").rows
  ctx.ui.log_person = "u-jonas"
  local only = ui_validator.find(screen.build(ctx), "log-list")
  t.ok(only == nil or #only.rows < all)
  t.eq(common.when(tr, "2026-10-22T22:41:07Z"), "10-22 22:41 UTC")
  t.eq(common.when(tr, "nonsense"), nil)
end)

t.case("corrections: action before Cancel, board titles and the who-sees-it line", function()
  local ctx = setup()
  ctx.ui.corr = { kind = "mark_missed", route = "route-105" }
  local s = corr_ui.section(ctx)
  t.eq(s.title, "Mark Route 105 as missed for you?")
  local btns = ui_validator.find(s, "corr-buttons").children
  t.eq(btns[1].id, "corr-submit"); t.eq(btns[2].id, "corr-cancel")
  t.ok(ui_validator.find(s, "c-who").text:find("Jonas", 1, true))
  local g = ctx.view.groups[1]
  ctx.ui.corr = { kind = "undo_death", group = g.route, number = g.number, members = g.members }
  t.eq(corr_ui.section(ctx).title, "Undo the death of link group 1?")
  ctx.ui.corr = { kind = "set_group", mon = "00000101", group = "none" }
  local mon = common.mon_name(ctx.view.players[1].mons["00000101"])
  t.eq(ui_validator.find(corr_ui.section(ctx), "c-text").text, "Moving " .. mon .. " also changes who dies with it.")
end)

t.case("i18n: German has every key of English and the placeholders match", function()
  for k, v in pairs(EN) do
    t.ok(DE[k], "de lacks " .. k)
    if DE[k] then
      local a, b = {}, {}
      for p in v:gmatch("{(%w+)}") do a[p] = true end
      for p in DE[k]:gmatch("{(%w+)}") do b[p] = true end
      t.eq(b, a, "placeholders of " .. k)
    end
  end
end)

t.case("map: source eyebrow and route card rows for the selected route", function()
  local ctx = setup()
  ctx.map = { state = "ready", live = false, coords = { ["route-101"] = { x = 5, y = 5 } }, src = "cache:map.png", w = 100, h = 80 }
  ctx.ui.selected_route = "route-101"
  local tree = screen.build(ctx)
  t.ok(ui_validator.validate(tree))
  t.eq(ui_validator.find(tree, "tabs").tabs[1], "Map")
  t.eq(ui_validator.find(tree, "map-source").text, "Map from your game picture")
  local pop = ui_validator.find(tree, "map").popover
  t.eq(#pop, 2)
  t.eq(pop[1].name, "Lena"); t.eq(pop[1].owner, 1)
  t.ok(type(pop[2].status) == "string" and pop[2].status ~= "")
end)
