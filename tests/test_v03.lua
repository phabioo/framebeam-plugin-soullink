-- v0.3: panel run view, creature icons, zone-based route detection, map setup and calibration.
local t = require("t")
local B = require("build")
local mock = require("fb_mock")
local ui_validator = require("ui_validator")
local controller = require("app.controller")
local detect = require("model.detect")
local view_mod = require("model.view")
local oras = require("data.oras")
local util = require("model.util")

local SIG = "\137PNG\r\n\26\n"
local function png(w, h) return SIG .. string.pack(">I4", 13) .. "IHDR" .. string.pack(">I4I4", w, h) .. string.rep("\0", 8) end

--- core: extra functions of the fake pokemon.core; opts.cache: files to start with.
local function boot(core, opts)
  opts = opts or {}
  local run = B.run({ "Lena", "Jonas" })
  local m = mock.new({ run = { current = run }, game = { code = "000400000011C400", language = "en" } })
  for k, v in pairs(opts.cache or {}) do m.cache_files[k] = v end
  local world = { team = { B.rec({ p = 0xB1, sp = 900, hp = 30 }) }, box = {} }
  local provider = {
    team = function() return world.team end,
    box_count = function() return 1 end,
    box = function() return world.box end,
  }
  for k, v in pairs(core or {}) do provider[k] = v end
  m.set_provider("pokemon.core", provider)
  local app = controller.new(m.fb)
  app:start()
  local env = { m = m, world = world, app = app, run = run }
  function env.step(ms) m.advance(ms or 600); m.tick(1) end
  function env.act(a, v, slot) m.action(a, v, slot or "panel"); env.step(300) end
  function env.calls(fn)
    local n = 0
    for _, c in ipairs(m.calls) do if c.fn == fn then n = n + 1 end end
    return n
  end
  return env
end

t.case("panel switches to the run view and back; screen slot keeps working", function()
  local e = boot()
  e.step()
  t.ok(ui_validator.find(e.m.ui.trees.panel, "panel"), "live view first")
  e.act("open_run")
  local p = e.m.ui.trees.panel
  t.ok(ui_validator.find(p, "tabs") and ui_validator.find(p, "back"), "run view in the panel")
  t.ok(not ui_validator.find(p, "panel"))
  t.ok(ui_validator.find(e.m.ui.trees.screen, "tabs"), "screen slot as before")
  e.act("panel_back")
  t.ok(ui_validator.find(e.m.ui.trees.panel, "panel"), "back to live")
  e.act("open_run", nil, "hotkey") -- Ctrl+R in the manifest is the id open-run
  t.ok(not ui_validator.find(e.m.ui.trees.panel, "tabs"), "unknown hotkey id ignored")
  e.act("open-run", nil, "hotkey")
  t.ok(ui_validator.find(e.m.ui.trees.panel, "tabs"), "Ctrl+R opens")
  e.act("open-run", nil, "hotkey")
  t.ok(ui_validator.find(e.m.ui.trees.panel, "panel"), "Ctrl+R toggles back")
  e.act("open_run") -- toast action
  t.ok(ui_validator.find(e.m.ui.trees.panel, "tabs"))
  e.act("open_run")
  t.ok(ui_validator.find(e.m.ui.trees.panel, "tabs"), "toast action never closes")
  -- the panel tab is its own: choosing one does not move the screen's tab
  e.act("tab", 3, "panel")
  t.eq(ui_validator.find(e.m.ui.trees.panel, "tabs").selected, 3)
  t.eq(ui_validator.find(e.m.ui.trees.screen, "tabs").selected, 1)
end)

t.case("icons: lazy fetch, cache, image blocks, no spam on failure", function()
  local seen = {}
  local e = boot({
    info = function() return { features = { icons = true } } end,
    icon = function(sp, form) seen[#seen + 1] = sp .. "/" .. tostring(form); return png(24, 24) end,
  })
  e.step(); e.step(); e.step()
  t.ok(e.m.cache_files["icons/900-0.png"], "written to the own cache")
  local img = ui_validator.find(e.m.ui.trees.panel, "m-i1")
  t.eq(img.src, "cache:icons/900-0.png")
  local n = #seen
  for _ = 1, 10 do e.step() end
  t.eq(#seen, n, "fetched once")

  -- not_ready is retried later, not on every tick
  local tries = 0
  local e2 = boot({ icon = function() tries = tries + 1; if tries < 3 then return nil, "not_ready" end; return png(8, 8) end })
  for _ = 1, 5 do e2.step(100) end
  t.eq(tries, 1, "waits before the retry")
  for _ = 1, 30 do e2.step(6000) end
  t.eq(tries, 3)
  t.ok(ui_validator.find(e2.m.ui.trees.panel, "m-i1"))

  -- unsupported: remembered, bounded number of calls
  local calls = 0
  local e3 = boot({ icon = function() calls = calls + 1; return nil, "unsupported" end })
  for _ = 1, 40 do e3.step(2000) end
  t.ok(calls <= 2, "one call per creature at most: " .. calls)
  t.ok(not ui_validator.find(e3.m.ui.trees.panel, "m-i1"))
  t.ok(ui_validator.find(e3.m.ui.trees.panel, "m-t1"), "text fallback")

  -- features.icons = false: no icon calls at all
  local c4 = 0
  local e4 = boot({ info = function() return { features = { icons = false } } end,
    icon = function() c4 = c4 + 1; return png(8, 8) end })
  for _ = 1, 20 do e4.step(2000) end
  t.eq(c4, 0)
end)

t.case("detect: manual place wins until the zone changes", function()
  local zones = { [7] = "route-104", [8] = "route-105" }
  local st = detect.diff(nil, { location = { zone = 7 } }, B.cfg(), { zones = zones })
  t.eq(st.place.key, "route-104")
  st = detect.set_place(st, "route-110", nil, 7)
  st = detect.diff(st, { location = { zone = 7 } }, B.cfg(), { zones = zones })
  t.eq(st.place.key, "route-110"); t.ok(st.place.manual)
  st = detect.diff(st, { location = { zone = 8 } }, B.cfg(), { zones = zones })
  t.eq(st.place.key, "route-105"); t.ok(not st.place.manual)
  -- unmapped zone after a manual place: the place is open, not kept
  st = detect.set_place(st, "route-110", nil, 8)
  st = detect.diff(st, { location = { zone = 99 } }, B.cfg(), { zones = zones })
  t.eq(st.place.key, nil); t.eq(st.place.zone, 99)
end)

t.case("zones: unmapped prompt, learned mapping, shared across players, auto catch", function()
  local loc = { zone = 7 }
  local e = boot({ location = function() return loc end })
  e.step(); e.step()
  t.ok(ui_validator.find(e.m.ui.trees.panel, "zone-new"), "asks which route this is")
  e.act("place_select", "route-104")
  t.eq(e.m.run.states["u-lena"].zones["7"], "route-104")
  t.ok(not ui_validator.find(e.m.ui.trees.panel, "zone-new"))
  -- not a route
  loc.zone = 8
  e.step(); e.step()
  t.ok(ui_validator.find(e.m.ui.trees.panel, "zone-new"))
  e.act("zone_none")
  t.eq(e.m.run.states["u-lena"].zones["8"], false)
  t.ok(not ui_validator.find(e.m.ui.trees.panel, "zone-new"))
  -- Jonas' answer for zone 9 is used for Lena without asking
  e.m.run.set_state_for("u-jonas", { v = 1, zones = { ["9"] = "route-102" } })
  t.eq(view_mod.merge_zones(e.run, e.m.run.states)[9], "route-102")
  loc.zone = 9
  e.step(); e.step()
  local st = e.m.run.states["u-lena"]
  t.eq(st.place.key, "route-102"); t.ok(not st.place.manual)
  t.ok(not ui_validator.find(e.m.ui.trees.panel, "zone-new"))
  -- the first catch lands on the route without any manual choice (box 1 -> new mon)
  e.world.box[1] = B.rec({ p = 0x77, sp = 12, nick = "Zippy", hp = 30 })
  for _ = 1, 3 do e.step(6000) end
  st = e.m.run.states["u-lena"]
  t.eq(st.mons["00000077"].route, "route-102")
  t.eq(st.routes["route-102"].status, "caught")
  -- the own mapping wins over another player's; static table wins over both
  e.m.run.set_state_for("u-jonas", { v = 1, zones = { ["7"] = "route-120" } })
  t.eq(view_mod.merge_zones(e.run, e.m.run.states)[7], "route-104")
  oras.ZONES[7] = "route-111"
  t.eq(view_mod.merge_zones(e.run, e.m.run.states)[7], "route-111")
  oras.ZONES[7] = nil
end)

t.case("location unsupported: manual picker, no repeated calls", function()
  local n = 0
  local e = boot({ location = function() n = n + 1; return nil, "unsupported" end })
  for _ = 1, 20 do e.step(600) end
  t.eq(n, 1)
  local p = e.m.ui.trees.panel
  t.ok(ui_validator.find(p, "place-picker") and not ui_validator.find(p, "zone-new"))
end)

t.case("map: scan, candidates with previews, choice, region image", function()
  local state = "not_ready"
  local fetched = 0
  local e = boot({
    map_candidates = function()
      if state == "not_ready" then return nil, "not_ready" end
      return { { id = "a/one", w = 512, h = 256 }, { id = "b two", w = 400, h = 240 }, { id = "c", w = 300, h = 300 } }
    end,
    map_image = function(id) fetched = fetched + 1; return png(id == "b two" and 400 or 512, 240) end,
    map_selected = function() return nil end,
  })
  e.act("open_run")
  e.step(); e.step(3100)
  local p = e.m.ui.trees.panel
  t.ok(ui_validator.find(p, "map-scan"), "scanning state")
  t.eq(ui_validator.find(p, "map-scan").title, "Reading the map from your game file…")
  state = "ready"
  e.step(3100)
  for _ = 1, 4 do e.step(100) end
  p = e.m.ui.trees.panel
  t.eq(ui_validator.find(p, "tabs").tabs[1], "Map")
  t.ok(ui_validator.find(p, "mc-use1") and ui_validator.find(p, "mc-use3"))
  t.eq(fetched, 3, "previews fetched once each")
  t.eq(ui_validator.find(p, "mc-img2").src, "cache:map/cand-2-b_two.png")
  t.ok(e.m.cache_files["map/cand-1-a_one.png"])
  e.act("map_use", "b two")
  t.eq(e.m.cache_files["map/choice.txt"], "b two")
  t.eq(e.m.cache_files["map/region.png"], png(400, 240))
  p = e.m.ui.trees.panel
  local map = ui_validator.find(p, "map")
  t.eq(map.image, "cache:map/region.png"); t.eq(map.image_w, 400); t.eq(map.image_h, 240)
  t.eq(#map.routes, 0, "markers only for routes with positions")
  local before = fetched
  for _ = 1, 5 do e.step(3100) end
  t.eq(fetched, before, "no more core calls once chosen")

  -- calibration
  e.act("calib_toggle")
  t.ok(ui_validator.find(e.m.ui.trees.panel, "calib"))
  e.act("calib_route", "route-101")
  t.ok(ui_validator.find(e.m.ui.trees.panel, "map").players[1].id == "cursor", "cursor marker")
  t.eq(e.app.ui.calib.x, 200); t.eq(e.app.ui.calib.y, 120)
  e.act("calib_move", "r"); e.act("calib_move", "d")
  e.act("calib_step", 40); e.act("calib_move", "r")
  e.act("calib_step", 2); e.act("calib_move", "u")
  t.eq(e.app.ui.calib.x, 250); t.eq(e.app.ui.calib.y, 128)
  e.act("calib_step", 7) -- not one of 2/10/40
  t.eq(e.app.ui.calib.step, 2)
  e.act("calib_set")
  t.eq(e.m.cache_files["map/coords.json"], '{"map":"b two","routes":{"route-101":{"x":250,"y":128}}}')
  map = ui_validator.find(e.m.ui.trees.panel, "map")
  t.eq(#map.routes, 1); t.eq(map.routes[1].id, "route-101"); t.eq(map.routes[1].x, 250)
  -- clamped to the image
  for _ = 1, 20 do e.act("calib_step", 40); e.act("calib_move", "l") end
  t.eq(e.app.ui.calib.x, 0)
  -- export: one Lua table line in the log
  e.act("calib_route", "route-102"); e.act("calib_set")
  e.act("calib_export")
  local line
  for _, l in ipairs(e.m.logs) do if l.text:find("soullink positions:", 1, true) then line = l.text end end
  t.eq(line, 'soullink positions: COORDS["b two"] = { ["route-101"] = { x = 250, y = 128 }, ["route-102"] = { x = 200, y = 120 } }')

  -- a restart keeps choice and positions without asking the core again
  local cache = util.copy(e.m.cache_files)
  local e2 = boot({ map_candidates = function() error("no scan expected") end }, { cache = cache })
  e2.act("open_run")
  local m2 = ui_validator.find(e2.m.ui.trees.panel, "map")
  t.eq(m2.image, "cache:map/region.png")
  t.eq(#m2.routes, 2)
  -- baked-in COORDS are merged under the recorded ones
  oras.COORDS["b two"] = { ["route-103"] = { x = 5, y = 6, area = "w" }, ["route-101"] = { x = 1, y = 1 } }
  e2.act("calib_toggle"); e2.act("calib_toggle")
  m2 = ui_validator.find(e2.m.ui.trees.panel, "map")
  t.eq(#m2.routes, 3)
  oras.COORDS["b two"] = nil
  -- change map
  e2.act("map_reset")
  t.eq(e2.m.cache_files["map/choice.txt"], "")
end)

t.case("map: core's own selection is used; unsupported hides the tab", function()
  local e = boot({ map_selected = function() return "x" end, map_image = function() return png(100, 80) end })
  e.step(); e.step(3100)
  e.act("open_run")
  t.eq(ui_validator.find(e.m.ui.trees.panel, "map").image_w, 100)
  local e2 = boot({ map_candidates = function() return nil, "unsupported" end, map_selected = function() return nil end })
  e2.step(); e2.step(3100)
  e2.act("open_run")
  t.ok(ui_validator.find(e2.m.ui.trees.panel, "tabs").tabs[1]:find("^Routes"))
  local e3 = boot() -- core 0.1: functions missing
  e3.step(); e3.step(3100)
  e3.act("open_run")
  t.ok(ui_validator.find(e3.m.ui.trees.panel, "tabs").tabs[1]:find("^Routes"))
end)

t.case("map icons and route markers", function()
  oras.COORDS["m1"] = { ["route-101"] = { x = 10, y = 20 } }
  local ok, err = pcall(function()
    local e = boot({
      map_selected = function() return "m1" end, map_image = function() return png(100, 80) end,
      icon = function() return png(8, 8) end,
    })
    e.act("place_select", "route-101")
    e.step(3100)
    e.world.box[1] = B.rec({ p = 0x77, sp = 12, nick = "Zippy", hp = 30 })
    for _ = 1, 4 do e.step(6000) end
    e.act("open_run")
    local map = ui_validator.find(e.m.ui.trees.panel, "map")
    t.eq(map.routes[1].id, "route-101")
    t.eq(map.routes[1].icons[1].src, "cache:icons/12-0.png")
    t.eq(map.players[1].x, 10)
  end)
  oras.COORDS["m1"] = nil
  if not ok then error(err, 0) end
end)
