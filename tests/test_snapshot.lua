local t = require("t")
local B = require("build")
local mock = require("fb_mock")
local snapshot = require("model.snapshot")
local detect = require("model.detect")

local function core(over)
  local tbl = {
    team = function() return { B.rec({ p = 1, sp = 3, hp = 20 }) } end,
    box_count = function() return 2 end,
    box = function(n) return { B.rec({ p = 100 + n, sp = 4 }) } end,
    location = function() return nil, "unsupported" end,
    battle = function() return nil, "unsupported" end,
    encounters = function() return nil, "unsupported" end,
    badges = function() return nil, "unsupported" end,
  }
  for k, v in pairs(over or {}) do tbl[k] = v end
  return tbl
end

t.case("collect via fb.call with the fake pokemon.core", function()
  local m = mock.new()
  m.set_provider("pokemon.core", core())
  local snap, issues = snapshot.from_core(m.fb)
  t.eq(#snap.team, 1)
  t.eq(#snap.boxes, 2)
  t.eq(snap.boxes[2][1].personality, 102)
  t.eq(snap.location, nil)
  t.eq(issues.location, "unsupported")
  t.eq(issues.badges, "unsupported")
  t.eq(issues.team, nil)
end)

t.case("not_ready parts stay unknown", function()
  local m = mock.new()
  m.set_provider("pokemon.core", core({
    team = function() return nil, "not_ready" end,
    box = function(n) if n == 2 then return nil, "not_ready" end return {} end,
  }))
  local snap, issues = snapshot.from_core(m.fb)
  t.eq(snap.team, nil); t.eq(snap.boxes, nil)
  t.eq(issues.team, "not_ready"); t.eq(issues.boxes, "not_ready")
  local st = detect.diff(nil, snap, B.cfg(), {})
  t.eq(st.started, false)
end)

t.case("missing functions and errors are caught", function()
  local m = mock.new()
  m.set_provider("pokemon.core", { team = function() error("boom") end })
  local snap, issues = snapshot.from_core(m.fb)
  t.eq(snap, {})
  t.eq(issues.team, "error"); t.eq(issues.boxes, "error")
  local m2 = mock.new()
  local s2, i2 = snapshot.from_core(m2.fb) -- nobody provides the interface
  t.eq(s2, {}); t.eq(i2.team, "error")
end)

t.case("optional parts are passed through", function()
  local m = mock.new()
  m.set_provider("pokemon.core", core({
    location = function() return { zone = 5, name = "Somewhere" } end,
    battle = function() return { active = false } end,
    badges = function() return 2 end,
    box = function() return {} end,
  }))
  local snap = snapshot.from_core(m.fb)
  t.eq(snap.location.name, "Somewhere")
  t.eq(snap.badges, 2)
  local st = detect.diff(nil, snap, B.cfg(), { zones = { [5] = "route-103" } })
  t.eq(st.place.key, "route-103")
  t.eq(st.badges, 2)
  t.eq(st.started, true)
  t.eq(st.routes.starter.mon, "00000001")
end)

t.case("fb mock: run API shapes", function()
  local run = B.run({ "Lena", "Jonas" })
  local m = mock.new({ run = { current = run, states = { ["u-jonas"] = { v = 1 } } } })
  local fb = m.fb
  t.eq(fb.run.current().name, "Test")
  t.eq(fb.run.state("u-jonas"), { v = 1 })
  t.ok(fb.run.setState({ v = 1, x = 1 }))
  t.eq(fb.run.state(), { v = 1, x = 1 })
  t.eq(fb.run.states()["u-jonas"], { v = 1 })
  local seen = {}
  fb.run.on("event", function(ev) seen[#seen + 1] = ev.type end)
  local id = fb.run.event({ type = "soullink.place", payload = { user = "u-lena" } })
  t.ok(type(id) == "string")
  t.eq(seen, { "soullink.place" })
  t.eq(#fb.run.events(0, 10), 1)
  t.eq(#fb.run.events(1, 10), 0)
  t.ok(not pcall(fb.run.event, { text = "no type" }))
  t.ok(not pcall(fb.run.event, { type = "x", payload = { s = string.rep("x", 5000) } }))
  run.status = "paused"
  m.run.current.status = "paused"
  local ok, why = fb.run.setState({ v = 2 })
  t.eq(ok, nil); t.ok(why)
  local noRun = mock.new()
  t.eq(noRun.fb.run, nil)
end)
