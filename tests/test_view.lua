local t = require("t")
local B = require("build")
local V = require("model.view")
local C = require("model.corrections")

local function setup(names, mode, over)
  local run = B.run(names)
  local cfg = B.cfg(mode or "soullink", over)
  local log = B.log()
  local trs = {}
  for i, n in ipairs(names) do
    local tr = B.tracker("u-" .. n:lower(), cfg, log)
    tr:start()
    trs[i] = tr
  end
  local env = { run = run, cfg = cfg, log = log, trs = trs }
  function env.view()
    local st = {}
    for _, tr in ipairs(trs) do st[tr.uid] = tr.st end
    return V.view(run, st, log.events, cfg)
  end
  function env.correct(spec, user)
    return log:add(user or trs[1].uid, spec)
  end
  -- everybody catches on `route`: species = base + index
  function env.all_catch(route, base, pid_base)
    for i, tr in ipairs(trs) do
      tr:place(route)
      tr:catch(pid_base + i, base + i)
    end
  end
  return env
end

local function row(view, route)
  for _, r in ipairs(view.rows) do if r.route == route then return r end end
end

local function group(view, route)
  for _, g in ipairs(view.groups) do if g.route == route then return g end end
end

t.case("two players: linked group, numbered by completion", function()
  local e = setup({ "Lena", "Jonas" })
  local a, b = e.trs[1], e.trs[2]
  a:place("route-103"); a:catch(0x103, 30)          -- seq: A catches 103 first (pending)
  a:place("route-105"); a:catch(0x105, 50)
  b:place("route-105"); b:catch(0x205, 51)          -- 105 completes first
  b:place("route-103"); b:catch(0x203, 31)          -- 103 completes second
  local v = e.view()
  t.eq(v.mode, "soullink")
  t.eq(group(v, "route-105").state, "linked")
  t.eq(group(v, "route-105").number, 1)
  t.eq(group(v, "route-103").number, 2)
  t.eq(#group(v, "route-103").members, 2)
  t.eq(row(v, "route-105").cells["u-lena"].state, "caught")
  t.eq(row(v, "route-105").cells["u-jonas"].species, 51)
  t.eq(v.stats.routes_done, 2)
  t.eq(v.stats.groups_linked, 2)
  t.eq(v.groups[1].route, "route-105")
end)

t.case("numbering falls back to route order without catch events", function()
  local e = setup({ "Lena", "Jonas" })
  e.all_catch("route-102", 20, 0x100)
  e.all_catch("route-101", 10, 0x200)
  local st = {}
  for _, tr in ipairs(e.trs) do st[tr.uid] = tr.st end
  local v = V.view(e.run, st, {}, e.cfg)
  t.eq(group(v, "route-101").number, 1)
  t.eq(group(v, "route-102").number, 2)
end)

t.case("pending group is open, missed makes it broken", function()
  local e = setup({ "Lena", "Jonas" })
  local a, b = e.trs[1], e.trs[2]
  a:place("route-102"); a:catch(0x102, 20)
  local v = e.view()
  t.eq(group(v, "route-102").state, "open")
  t.eq(group(v, "route-102").number, nil)
  t.eq(row(v, "route-102").cells["u-jonas"].state, "open")
  b:place("route-102"); b:battle(21); b:end_battle()
  v = e.view()
  t.eq(group(v, "route-102").state, "broken")
  t.eq(row(v, "route-102").cells["u-jonas"].state, "missed")
  t.eq(row(v, "route-102").done, true)
  t.eq(v.players[2].place.status, "missed")
  t.eq(v.players[1].place.status, "caught")
end)

t.case("death propagates through a linked group", function()
  local e = setup({ "Lena", "Jonas" })
  e.all_catch("route-101", 10, 0x100)
  local a = e.trs[1]
  a:hp(0x101, 0)
  local v = e.view()
  t.eq(group(v, "route-101").state, "dead")
  t.eq(group(v, "route-101").number, 1)
  local la, jo = v.players[1].mons["00000101"], v.players[2].mons["00000102"]
  t.eq(la.dead, true); t.eq(la.cause, "own")
  t.eq(jo.dead, true); t.eq(jo.cause, "linked")
  t.eq(#v.graveyard, 2)
  t.eq(v.graveyard[1].owner, "u-lena")
  t.eq(v.graveyard[1].group_number, 1)
  t.eq(v.stats.deaths, 2)
  t.eq(v.stats.groups_dead, 1)
  t.eq(v.players[2].dead, 1); t.eq(v.players[2].alive, 0)
  t.eq(row(v, "route-101").cells["u-jonas"].state, "dead")
  t.eq(row(v, "route-101").cells["u-jonas"].cause, "linked")
end)

t.case("dead on arrival", function()
  local e = setup({ "Lena", "Jonas" })
  local a, b = e.trs[1], e.trs[2]
  a:place("route-110"); a:catch(0x110, 60)
  a:hp(0x110, 0)
  local v = e.view()
  t.eq(group(v, "route-110").state, "dead")
  t.eq(group(v, "route-110").complete, false)
  t.eq(group(v, "route-110").number, nil)
  b:place("route-110"); b:catch(0x210, 61)
  v = e.view()
  local jo = v.players[2].mons["00000210"]
  t.eq(jo.dead, true); t.eq(jo.cause, "linked"); t.eq(jo.doa, true)
  t.eq(group(v, "route-110").number, 1)
  t.eq(v.graveyard[2].doa, true)
end)

t.case("undo_death revives the whole group, revert brings the death back", function()
  local e = setup({ "Lena", "Jonas" })
  e.all_catch("route-101", 10, 0x100)
  e.trs[1]:hp(0x101, 0)
  local v = e.view()
  local undo = C.undo_death({ group = "route-101", reason = "glitch",
    undone = C.undo_entries(group(v, "route-101")) })
  t.ok(C.validate_spec(undo))
  local seq = e.correct(undo)
  v = e.view()
  t.eq(group(v, "route-101").state, "linked")
  t.eq(#v.graveyard, 0)
  t.eq(v.players[2].mons["00000102"].dead, false)
  -- fainting again after the undo: dead again
  e.trs[1]:hp(0x101, 9)
  e.trs[1]:hp(0x101, 0)
  v = e.view()
  t.eq(group(v, "route-101").state, "dead")
  t.eq(v.players[1].mons["00000101"].deaths, 2)
  -- revert the undo (the second death is also still counted -> dead either way); then undo again
  local seq2 = e.correct(C.undo_death({ group = "route-101", undone = C.undo_entries(group(v, "route-101")) }))
  v = e.view()
  t.eq(group(v, "route-101").state, "linked")
  e.correct(C.revert({ target = seq2 }))
  v = e.view()
  t.eq(group(v, "route-101").state, "dead")
  e.correct(C.revert({ target = seq + 100 })) -- unknown target: no effect
  local rr = e.correct(C.revert({ target = seq2 + 1 })) -- reverts the revert
  v = e.view()
  t.eq(group(v, "route-101").state, "linked")
  t.ok(rr > 0)
end)

t.case("set_group moves a mon, none unlinks it", function()
  local e = setup({ "Lena", "Jonas" })
  local a, b = e.trs[1], e.trs[2]
  a:place("route-120"); a:catch(0x120, 70)
  b:place("route-121"); b:catch(0x221, 71)
  local v = e.view()
  t.eq(group(v, "route-120").state, "open")
  local seq = e.correct(C.set_group({ user = "u-jonas", mon = "00000221", group = "route-120" }), "u-jonas")
  v = e.view()
  t.eq(group(v, "route-120").state, "linked")
  t.eq(group(v, "route-121"), nil)
  t.eq(row(v, "route-121").cells["u-jonas"].state, "open")
  t.eq(v.players[2].mons["00000221"].route, "route-120")
  t.eq(v.players[2].mons["00000221"].group_number, 1)
  e.correct(C.revert({ target = seq }))
  v = e.view()
  t.eq(group(v, "route-120").state, "open")
  e.correct(C.set_group({ user = "u-lena", mon = "00000120", group = "none" }))
  v = e.view()
  t.eq(group(v, "route-120").state, "nolink")
  t.eq(row(v, "route-120").cells["u-lena"].state, "caught")
end)

t.case("set_group assigns a catch that had no place", function()
  local e = setup({ "Lena", "Jonas" })
  e.trs[1]:catch(0x100, 10)
  e.trs[2]:place("route-101"); e.trs[2]:catch(0x200, 11)
  local v = e.view()
  t.eq(group(v, "route-101").state, "open")
  e.correct(C.set_group({ user = "u-lena", mon = "00000100", group = "route-101" }))
  v = e.view()
  t.eq(group(v, "route-101").state, "linked")
end)

t.case("gift: no link and no propagation", function()
  local e = setup({ "Lena", "Jonas" })
  e.all_catch("route-101", 10, 0x100)
  e.correct(C.set_gift({ user = "u-lena", mon = "00000101" }))
  e.trs[2]:hp(0x102, 0)
  local v = e.view()
  t.eq(group(v, "route-101").state, "gift")
  t.eq(v.players[1].mons["00000101"].dead, false)
  t.eq(v.players[2].mons["00000102"].dead, true)
  t.eq(#v.graveyard, 1)
  e.correct(C.set_gift({ user = "u-lena", mon = "00000101", gift = false }))
  v = e.view()
  t.eq(group(v, "route-101").state, "dead")
end)

t.case("doesnt_count frees the route and excludes the mon", function()
  local e = setup({ "Lena", "Jonas" })
  e.trs[1]:place("route-130"); e.trs[1]:catch(0x130, 80)
  local v = e.view()
  t.eq(row(v, "route-130").cells["u-lena"].state, "caught")
  local seq = e.correct(C.doesnt_count({ user = "u-lena", route = "route-130", mon = "00000130", reason = "dupe" }))
  v = e.view()
  t.eq(row(v, "route-130").cells["u-lena"].state, "open")
  t.eq(v.players[1].mons["00000130"].excluded, true)
  t.eq(v.players[1].mons["00000130"].counted, false)
  t.eq(group(v, "route-130"), nil)
  e.correct(C.revert({ target = seq }))
  t.eq(row(e.view(), "route-130").cells["u-lena"].state, "caught")
end)

t.case("doesnt_count reopens a missed route", function()
  local e = setup({ "Lena", "Jonas" })
  local a = e.trs[1]
  a:place("route-131"); a:battle(1); a:end_battle()
  t.eq(row(e.view(), "route-131").cells["u-lena"].state, "missed")
  e.correct(C.doesnt_count({ user = "u-lena", route = "route-131", reason = "wrong" }))
  t.eq(row(e.view(), "route-131").cells["u-lena"].state, "open")
end)

t.case("mark_missed breaks a group, add replaces missed", function()
  local e = setup({ "Lena", "Jonas" })
  e.trs[2]:place("route-131"); e.trs[2]:catch(0x231, 5)
  e.correct(C.mark_missed({ user = "u-lena", route = "route-131" }))
  local v = e.view()
  t.eq(row(v, "route-131").cells["u-lena"].state, "missed")
  t.eq(group(v, "route-131").state, "broken")
  e.correct(C.add({ user = "u-lena", route = "route-131", species = 9, nickname = "Hand", level = 7, state = "team" }))
  v = e.view()
  t.eq(row(v, "route-131").cells["u-lena"].state, "caught")
  t.eq(group(v, "route-131").state, "linked")
  t.eq(v.players[1].team[1].nickname, "Hand")
  t.eq(v.players[1].team[1].virtual, true)
  -- added dead: the group is dead on arrival for nobody (Jonas' mon was there first)
  local e2 = setup({ "Lena", "Jonas" })
  e2.trs[2]:place("route-131"); e2.trs[2]:catch(0x231, 5)
  e2.correct(C.add({ user = "u-lena", route = "route-131", species = 9, state = "dead" }))
  local v2 = e2.view()
  t.eq(group(v2, "route-131").state, "dead")
  t.eq(v2.players[2].mons["00000231"].cause, "linked")
  t.eq(#v2.graveyard, 2)
end)

t.case("add on a taken route is extra", function()
  local e = setup({ "Lena" })
  e.trs[1]:place("route-131"); e.trs[1]:catch(0x131, 5)
  e.correct(C.add({ user = "u-lena", route = "route-131", species = 9, state = "box" }))
  local v = e.view()
  t.eq(v.players[1].mons["add-2"] ~= nil or v.players[1].mons["add-3"] ~= nil, true)
  t.eq(v.players[1].box_count, 2)
  t.eq(v.players[1].mons["00000131"].counted, true)
end)

t.case("mark_dead", function()
  local e = setup({ "Lena", "Jonas" })
  e.all_catch("route-101", 10, 0x100)
  e.correct(C.mark_dead({ user = "u-jonas", mon = "00000102" }))
  local v = e.view()
  t.eq(group(v, "route-101").state, "dead")
  t.eq(v.players[1].mons["00000101"].cause, "linked")
  t.eq(v.players[2].mons["00000102"].cause, "own")
end)

t.case("nuzlocke mode has no groups and no propagation", function()
  local e = setup({ "Lena", "Jonas" }, "nuzlocke")
  e.all_catch("route-101", 10, 0x100)
  e.trs[1]:hp(0x101, 0)
  local v = e.view()
  t.eq(v.mode, "nuzlocke")
  t.eq(#v.groups, 0)
  t.eq(row(v, "route-101").group, nil)
  t.eq(v.players[1].mons["00000101"].dead, true)
  t.eq(v.players[2].mons["00000102"].dead, false)
  t.eq(v.stats.deaths, 1)
end)

t.case("single player nuzlocke", function()
  local e = setup({ "Solo" }, "nuzlocke")
  e.trs[1]:place("route-101"); e.trs[1]:catch(0x1, 10, { team = true })
  e.trs[1]:place("route-102"); e.trs[1]:catch(0x2, 11)
  local v = e.view()
  t.eq(#v.players, 1)
  t.eq(#v.players[1].team, 1)
  t.eq(v.players[1].box_count, 1)
  t.eq(v.stats.routes_done, 2)
  t.eq(v.players[1].place.status, "caught")
end)

t.case("four players: link, break, pending, propagation, undo", function()
  local e = setup({ "Lena", "Jonas", "Sam", "Kim" })
  e.all_catch("route-104", 10, 0x100)
  local v = e.view()
  t.eq(group(v, "route-104").state, "linked")
  t.eq(#group(v, "route-104").members, 4)
  -- 3 catch, 1 misses: broken
  for i = 1, 3 do e.trs[i]:place("route-105"); e.trs[i]:catch(0x500 + i, 20 + i) end
  e.trs[4]:place("route-105"); e.trs[4]:battle(5); e.trs[4]:end_battle()
  v = e.view()
  t.eq(group(v, "route-105").state, "broken")
  t.eq(group(v, "route-105").number, nil)
  -- 3 catch, 1 pending
  for i = 1, 3 do e.trs[i]:place("route-106"); e.trs[i]:catch(0x600 + i, 30 + i) end
  v = e.view()
  t.eq(group(v, "route-106").state, "open")
  t.eq(group(v, "route-106").count, 3)
  -- a death in 104 kills all four; 105 (broken) is not affected
  e.trs[3]:hp(0x103, 0)
  e.trs[1]:hp(0x501, 0)
  v = e.view()
  t.eq(group(v, "route-104").state, "dead")
  t.eq(v.stats.deaths, 5)
  for i = 1, 4 do t.eq(v.players[i].mons[string.format("%08x", 0x100 + i)].dead, true) end
  t.eq(v.players[2].mons["00000502"].dead, false)
  t.eq(v.players[3].mons["00000103"].cause, "own")
  t.eq(v.players[4].mons["00000104"].cause, "linked")
  t.eq(v.stats.groups_dead, 1)
  -- undo revives all four
  e.correct(C.undo_death({ group = "route-104", undone = C.undo_entries(group(v, "route-104")) }), "u-sam")
  v = e.view()
  t.eq(group(v, "route-104").state, "linked")
  for i = 1, 4 do t.eq(v.players[i].mons[string.format("%08x", 0x100 + i)].dead, false) end
  t.eq(v.stats.deaths, 1)
  t.eq(row(v, "route-105").cells["u-kim"].state, "missed")
  t.eq(row(v, "route-106").cells["u-kim"].state, "open")
end)

t.case("view is deterministic and ignores invalid corrections", function()
  local e = setup({ "Lena", "Jonas" })
  e.all_catch("route-101", 10, 0x100)
  local bad = e.correct({ type = C.TYPE, source = "manual", payload = { kind = "set_group", user = "u-lena" } })
  e.correct({ type = C.TYPE, source = "manual", payload = { kind = "nope" } })
  local v1, v2 = e.view(), e.view()
  t.eq(v1, v2)
  t.eq(#v1.invalid_corrections, 2)
  t.eq(v1.invalid_corrections[1], bad)
  t.eq(group(v1, "route-101").state, "linked")
end)

t.case("team order, box count and place status", function()
  local e = setup({ "Lena" }, "nuzlocke")
  local a = e.trs[1]
  a:place("route-101"); a:catch(0x1, 10, { team = true })
  a:place("route-102"); a:catch(0x2, 11, { team = true })
  a:place("route-103"); a:catch(0x3, 12)
  local v = e.view()
  t.eq(#v.players[1].team, 2)
  t.eq(v.players[1].team[1].id, "00000001")
  t.eq(v.players[1].team[2].id, "00000002")
  t.eq(v.players[1].box_count, 1)
  t.eq(v.players[1].place.status, "caught")
  a:place("route-120")
  t.eq(e.view().players[1].place.status, "open")
  a:battle(3)
  t.eq(e.view().players[1].place.status, "encounter")
  a:place(nil)
  t.eq(e.view().players[1].place.status, "unknown")
  a.st.place = { zone = 4, manual = false }
  t.eq(e.view().players[1].place.status, "no_route")
end)

t.case("hints: nickname, level cap, only linked in team", function()
  local e = setup({ "Lena", "Jonas" }, "soullink", { only_linked_in_team = true })
  local a, b = e.trs[1], e.trs[2]
  a:place("route-101"); a:catch(0x1, 10, { team = true, lv = 20 })
  b:place("route-101"); b:catch(0x2, 11)              -- partner stays in the box
  a:place("route-102"); a:catch(0x3, 12, { team = true })
  b:place("route-102"); b:battle(1); b:end_battle()   -- broken
  a.st.mons["00000001"].nickname = nil
  local v = e.view()
  local codes = {}
  for _, h in ipairs(v.hints) do codes[#codes + 1] = h.code .. ":" .. h.user .. ":" .. h.mon end
  t.eq(codes, {
    "nickname_missing:u-lena:00000001", "level_cap:u-lena:00000001",
    "partner_not_in_team:u-lena:00000001", "unlinked_in_team:u-lena:00000003",
  })
  t.eq(v.hints[3].partner, "u-jonas")
  -- switches off: no hints
  local off = setup({ "Lena" }, "nuzlocke", { nickname_required = false, level_caps = false })
  off.trs[1]:place("route-101"); off.trs[1]:catch(0x1, 10, { team = true, lv = 90, nick = "x" })
  off.trs[1].st.mons["00000001"].nickname = nil
  t.eq(off.view().hints, {})
end)

t.case("view without run data falls back to the states", function()
  local tr = B.tracker("u-x", B.cfg("nuzlocke")); tr:start(); tr:place("route-101"); tr:catch(0x1, 10)
  local v = V.view(nil, { ["u-x"] = tr.st }, {}, B.cfg("nuzlocke"))
  t.eq(#v.players, 1)
  t.eq(v.players[1].id, "u-x")
  local empty = V.view(nil, nil, nil, nil)
  t.eq(#empty.players, 0)
end)
