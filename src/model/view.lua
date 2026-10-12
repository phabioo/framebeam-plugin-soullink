-- Derived run view: everything the UI shows, computed from the participants' own states and the
-- run events. Pure and deterministic: the same inputs give the same table (no clocks, no pairs()
-- order dependence). Nothing is stored; link groups, deaths and numbers are recomputed.
local util = require("model.util")
local rules = require("model.rules")
local state = require("model.state")
local corrections = require("model.corrections")
local events_mod = require("model.events")
local oras = require("data.oras")

local V = {}

local INF = math.huge

local function joined(p) return p.status == nil or p.status == "joined" end
local function mkey(owner, id) return owner .. "\0" .. id end

local function collect_events(events)
  local list = {}
  for _, ev in ipairs(events or {}) do
    if type(ev) == "table" and math.type(ev.seq) == "integer" then list[#list + 1] = ev end
  end
  table.sort(list, function(a, b) return a.seq < b.seq end)
  local catch_seq, death_seq, corr, invalid = {}, {}, {}, {}
  for _, ev in ipairs(list) do
    local p = type(ev.payload) == "table" and ev.payload or {}
    local user = ev.user_id or p.user
    if ev.type == events_mod.TYPES.catch and user and type(p.mon) == "string" then
      local k = mkey(user, p.mon)
      if not catch_seq[k] then catch_seq[k] = ev.seq end
    elseif ev.type == events_mod.TYPES.death and user and type(p.mon) == "string" then
      local k = mkey(user, p.mon)
      death_seq[k] = death_seq[k] or {}
      if not death_seq[k][p.deaths or 0] then death_seq[k][p.deaths or 0] = ev.seq end
    elseif ev.type == corrections.TYPE then
      if corrections.validate(p) then
        corr[#corr + 1] = { seq = ev.seq, author = ev.user_id, p = p }
      else
        invalid[#invalid + 1] = ev.seq
      end
    end
  end
  -- reverts: scan newest first; a reverted revert does not revert anything
  local reverted = {}
  for i = #corr, 1, -1 do
    local c = corr[i]
    if c.p.kind == "revert" and not reverted[c.seq] and c.p.target < c.seq then
      reverted[c.p.target] = true
    end
  end
  local effective = {}
  for _, c in ipairs(corr) do
    if c.p.kind ~= "revert" and not reverted[c.seq] then effective[#effective + 1] = c end
  end
  return catch_seq, death_seq, effective, invalid
end

local function new_vmon(owner, id, m)
  return {
    id = id, owner = owner, species = m.species, form = m.form, nickname = m.nickname,
    nicknamed = m.nicknamed, level = m.level, shiny = m.shiny == true, own_route = m.route,
    where = m.where or "box", hp = m.hp, mhp = m.mhp, base_gift = m.gift == true, why = m.why,
    deaths = m.deaths or 0, manual = 0, undone = 0, virtual = false,
  }
end

local function eff_deaths(vm) return vm.deaths + vm.manual end
local function own_dead(vm) return eff_deaths(vm) > vm.undone end
local function is_gift(vm)
  if vm.gift_override ~= nil then return vm.gift_override end
  return vm.base_gift or vm.entry_kind == "gift"
end

-- Build per-player working data and apply the effective corrections in seq order.
local function build_players(players, states, effective, catch_seq, death_seq)
  local pv = {}
  for _, pl in ipairs(players) do
    local st = state.ensure(util.copy(states[pl.id]))
    local w = { st = st, mons = {}, ids = {}, routes = util.copy(st.routes), reopened = {}, manual_missed = {} }
    for _, pid in ipairs(util.keys(st.mons)) do
      w.mons[pid] = new_vmon(pl.id, pid, st.mons[pid])
      w.ids[#w.ids + 1] = pid
    end
    for _, route in ipairs(util.keys(w.routes)) do
      local e = w.routes[route]
      local vm = e.status == "caught" and e.mon and w.mons[e.mon]
      if vm then vm.counted_route, vm.entry_kind = route, e.kind end
    end
    pv[pl.id] = w
  end

  for _, c in ipairs(effective) do
    local p, seq = c.p, c.seq
    local w = p.user and pv[p.user]
    local k = p.kind
    if k == "doesnt_count" and w then
      local vm = p.mon and w.mons[p.mon]
      if not vm and p.route and not p.mon then
        local e = w.routes[p.route]
        if e and e.status == "caught" and e.mon then vm = w.mons[e.mon] end
        if not vm or vm.counted_route ~= p.route then vm = nil end
        if not vm then w.reopened[p.route], w.manual_missed[p.route] = true, nil end
      end
      if vm then vm.excluded, vm.why = true, p.reason or "manual" end
    elseif k == "mark_missed" and w then
      w.reopened[p.route], w.manual_missed[p.route] = nil, true
    elseif k == "set_group" and w and w.mons[p.mon] then
      local vm = w.mons[p.mon]
      vm.group_override = p.group ~= "none" and p.group or false
      vm.slot_seq = seq
    elseif k == "add" and w then
      local id = "add-" .. seq
      local vm = new_vmon(p.user, id, { species = p.species, form = p.form, nickname = p.nickname,
        level = p.level, shiny = p.shiny, route = p.route, where = p.state == "team" and "team" or "box",
        deaths = p.state == "dead" and 1 or 0 })
      vm.virtual, vm.slot_seq, vm.add_route = true, seq, p.route
      w.mons[id] = vm
      w.ids[#w.ids + 1] = id
      w.reopened[p.route], w.manual_missed[p.route] = nil, nil
      catch_seq[mkey(p.user, id)] = seq
      if p.state == "dead" then
        death_seq[mkey(p.user, id)] = { [1] = seq }
      end
    elseif k == "mark_dead" and w and w.mons[p.mon] then
      local vm = w.mons[p.mon]
      vm.manual = vm.manual + 1
      local dk = mkey(p.user, p.mon)
      death_seq[dk] = death_seq[dk] or {}
      death_seq[dk][eff_deaths(vm)] = seq
    elseif k == "set_gift" and w and w.mons[p.mon] then
      w.mons[p.mon].gift_override = p.gift
    elseif k == "undo_death" then
      for _, e in ipairs(p.undone) do
        local ow = pv[e.owner]
        local vm = ow and ow.mons[e.mon]
        if vm and e.deaths > vm.undone then vm.undone = e.deaths end
      end
    end
  end
  return pv
end

-- Claim route slots (route x player -> mon). Counted mons first, then moved mons, then hand-added.
local function assign_slots(players, pv)
  for _, pl in ipairs(players) do
    local w = pv[pl.id]
    w.slots = {}
    local function claim(vm, route)
      if w.slots[route] then return false end
      w.slots[route], vm.slot = vm, route
      return true
    end
    for _, id in ipairs(w.ids) do
      local vm = w.mons[id]
      if not vm.virtual and not vm.excluded and vm.group_override == nil and vm.counted_route then
        claim(vm, vm.counted_route)
      end
    end
    for _, id in ipairs(w.ids) do
      local vm = w.mons[id]
      if not vm.virtual and not vm.excluded and vm.group_override ~= nil then
        if vm.group_override == false then
          if vm.counted_route and claim(vm, vm.counted_route) then vm.unlinked = true end
        elseif not claim(vm, vm.group_override) then
          vm.group_conflict = true
        end
      end
    end
    for _, id in ipairs(w.ids) do
      local vm = w.mons[id]
      if vm.virtual and not vm.excluded then
        if not claim(vm, vm.add_route) then vm.why = vm.why or "extra" end
      end
    end
  end
end

local function cell_state(w, route)
  local vm = w.slots[route]
  if vm then return "caught", vm end
  if w.manual_missed[route] then return "missed" end
  local e = w.routes[route]
  if e and not w.reopened[route] then
    if e.status == "missed" then return "missed" end
    if e.status == "encounter" then return "encounter", nil, e end
  end
  return "open"
end

--- view(run, states, events, cfg) -> table
---   run     fb.run.current() result (participants, settings)
---   states  user_id -> own state of this plugin (fb.run.states())
---   events  run events (fb.run.events), ascending by seq; other event types are ignored
---   cfg     rules.parse() result; nil = parse from `run`
--- See docs/architecture.md for the result fields.
function V.view(run, states, events, cfg)
  run, states = run or {}, states or {}
  cfg = cfg and rules.normalize(cfg) or rules.parse(run)
  local soul = cfg.mode == "soullink"

  local players = {}
  for _, p in ipairs(run.participants or {}) do
    if type(p) == "table" and p.user_id and joined(p) then
      players[#players + 1] = { id = p.user_id, name = p.name or p.user_name or p.user_id,
                                color = p.color, game_id = p.game_id }
    end
  end
  if #players == 0 then
    for _, uid in ipairs(util.keys(states)) do players[#players + 1] = { id = uid, name = uid } end
  end
  local pindex = {}
  for i, pl in ipairs(players) do pindex[pl.id] = i end

  local catch_seq, death_seq, effective, invalid = collect_events(events)
  local pv = build_players(players, states, effective, catch_seq, death_seq)
  assign_slots(players, pv)

  -- routes with any activity, plus the current places
  local route_set = {}
  for _, pl in ipairs(players) do
    local w = pv[pl.id]
    for r in pairs(w.slots) do route_set[r] = true end
    for r in pairs(w.routes) do route_set[r] = true end
    for r in pairs(w.manual_missed) do route_set[r] = true end
    if w.st.place.key then route_set[w.st.place.key] = true end
  end
  local route_keys = util.keys(route_set)
  table.sort(route_keys, oras.compare)

  -- groups
  local groups, group_of = {}, {}
  if soul then
    for _, r in ipairs(route_keys) do
      local members, missed, gift, nolink = {}, false, false, false
      for _, pl in ipairs(players) do
        local w = pv[pl.id]
        local vm = w.slots[r]
        if vm then
          members[#members + 1] = vm
          gift = gift or is_gift(vm)
          nolink = nolink or vm.unlinked == true
        elseif (cell_state(w, r)) == "missed" then
          missed = true
        end
      end
      if #members > 0 then
        local g = { route = r, members = {}, count = #members, complete = #members == #players }
        local any_dead = false
        for _, vm in ipairs(members) do if own_dead(vm) then any_dead = true end end
        if gift then g.state = "gift"
        elseif nolink then g.state = "nolink"
        elseif missed then g.state = "broken"
        elseif any_dead then g.state = "dead"
        elseif g.complete then g.state = "linked"
        else g.state = "open" end
        g.propagates = g.state == "linked" or g.state == "dead" or g.state == "open"
        g.mons = members
        groups[#groups + 1] = g
        group_of[r] = g
      end
    end
  end

  -- deaths (own and propagated), dead on arrival, completion order, numbers
  local function seq_of_catch(vm)
    local s = math.max(catch_seq[mkey(vm.owner, vm.id)] or 0, vm.slot_seq or 0)
    return s > 0 and s or nil
  end
  for _, g in ipairs(groups) do
    local died, completed, lacking = INF, 0, false
    for _, vm in ipairs(g.mons) do
      if own_dead(vm) then
        local s = (death_seq[mkey(vm.owner, vm.id)] or {})[eff_deaths(vm)]
        if s and s < died then died = s end
      end
      local s = seq_of_catch(vm)
      if s then completed = math.max(completed, s) else lacking = true end
    end
    g.died_seq = died < INF and died or nil
    g.completed_seq = (not lacking and completed > 0) and completed or nil
    for _, vm in ipairs(g.mons) do
      if g.propagates and g.state == "dead" then
        vm.dead = true
        vm.cause = own_dead(vm) and "own" or "linked"
        if vm.cause == "linked" and g.died_seq then
          local s = seq_of_catch(vm)
          vm.doa = s ~= nil and s > g.died_seq or nil
        end
      end
      vm.group_state = g.state
    end
  end
  local numbered = {}
  for _, g in ipairs(groups) do
    if g.complete and (g.state == "linked" or g.state == "dead") then numbered[#numbered + 1] = g end
  end
  table.sort(numbered, function(a, b)
    local sa, sb = a.completed_seq or INF, b.completed_seq or INF
    if sa ~= sb then return sa < sb end
    return oras.compare(a.route, b.route)
  end)
  for i, g in ipairs(numbered) do g.number = i end

  -- mon views, players
  local out_players, graveyard, hints = {}, {}, {}
  local stats = { deaths = 0, groups_dead = 0, groups_linked = 0, routes_done = 0, routes_total = 0,
                  badges_max = 0, alive = 0 }
  local function mon_view(vm)
    if not vm.dead and own_dead(vm) then vm.dead, vm.cause = true, "own" end
    local g = vm.slot and group_of[vm.slot]
    return {
      id = vm.id, owner = vm.owner, species = vm.species, form = vm.form, nickname = vm.nickname,
      nicknamed = vm.nicknamed, level = vm.level, shiny = vm.shiny, hp = vm.hp, mhp = vm.mhp,
      route = vm.slot or vm.own_route, where = vm.where, dead = vm.dead == true, cause = vm.cause,
      doa = vm.doa == true, deaths = eff_deaths(vm), gift = is_gift(vm), why = vm.why,
      excluded = vm.excluded == true, virtual = vm.virtual, counted = vm.slot ~= nil,
      group = (g and g.propagates) and g.route or nil, group_state = vm.group_state,
      group_number = (g and g.propagates) and g.number or nil,
    }
  end

  for i, pl in ipairs(players) do
    local w = pv[pl.id]
    local team, box, seen = {}, 0, {}
    local views = {}
    for _, id in ipairs(w.ids) do views[id] = mon_view(w.mons[id]) end
    local function add_team(id)
      local mv = views[id]
      if mv and mv.where == "team" and not seen[id] then seen[id] = true; team[#team + 1] = mv end
    end
    for _, id in ipairs(w.st.order) do add_team(id) end
    for _, id in ipairs(w.ids) do add_team(id) end
    local alive, dead = 0, 0
    for _, id in ipairs(w.ids) do
      local mv = views[id]
      if mv.where == "box" then box = box + 1 end
      if mv.dead then
        dead = dead + 1
        graveyard[#graveyard + 1] = {
          owner = pl.id, mon = id, species = mv.species, form = mv.form, nickname = mv.nickname,
          route = mv.route, group = mv.group, group_number = mv.group_number, cause = mv.cause,
          doa = mv.doa, deaths = mv.deaths, shiny = mv.shiny,
          seq = mv.cause == "own" and (death_seq[mkey(pl.id, id)] or {})[mv.deaths]
            or (mv.group and group_of[mv.group].died_seq) or nil,
          player_index = i,
        }
      elseif mv.where ~= "gone" then
        alive = alive + 1
      end
    end
    stats.alive = stats.alive + alive
    local place = w.st.place
    local place_view = { key = place.key, name = place.name, zone = place.zone, manual = place.manual == true }
    local badges = w.st.badges or 0
    if badges > stats.badges_max then stats.badges_max = badges end
    out_players[i] = {
      id = pl.id, name = pl.name, color = pl.color, game_id = pl.game_id, place = place_view,
      team = team, box_count = box, alive = alive, dead = dead, badges = badges,
      level_cap = cfg.rules.level_caps and oras.level_cap(badges) or nil, mons = views, ids = w.ids,
    }
  end
  stats.deaths = #graveyard
  table.sort(graveyard, function(a, b)
    local sa, sb = a.seq or INF, b.seq or INF
    if sa ~= sb then return sa < sb end
    if a.player_index ~= b.player_index then return a.player_index < b.player_index end
    return a.mon < b.mon
  end)
  for _, g in ipairs(groups) do
    if g.state == "dead" then stats.groups_dead = stats.groups_dead + 1 end
    if g.state == "linked" then stats.groups_linked = stats.groups_linked + 1 end
  end

  -- rows (route x player)
  local rows = {}
  for _, r in ipairs(route_keys) do
    local cells, done = {}, #players > 0
    for _, pl in ipairs(players) do
      local w = pv[pl.id]
      local st_, vm, e = cell_state(w, r)
      local cell = { state = st_ }
      if vm then
        local mv = out_players[pindex[pl.id]].mons[vm.id]
        cell.mon, cell.species, cell.nickname, cell.gift = vm.id, mv.species, mv.nickname, mv.gift
        if mv.dead then cell.state, cell.cause = "dead", mv.cause end
      elseif e then
        cell.species = e.species
      end
      if st_ == "open" or st_ == "encounter" then done = false end
      cells[pl.id] = cell
    end
    local g = group_of[r]
    rows[#rows + 1] = { route = r, order = oras.order_index(r), cells = cells, group = g and {
      route = g.route, state = g.state, number = g.number, complete = g.complete, count = g.count,
    } or nil, done = done }
    if done then stats.routes_done = stats.routes_done + 1 end
  end
  stats.routes_total = #oras.ROUTE_KEYS + 1
  for _, r in ipairs(route_keys) do
    if r:sub(1, 6) == "place:" then stats.routes_total = stats.routes_total + 1 end
  end

  -- place status per player (location card)
  local row_of = {}
  for _, row in ipairs(rows) do row_of[row.route] = row end
  for i, pl in ipairs(players) do
    local p = out_players[i].place
    local status
    if not p.key then
      status = (p.zone ~= nil or p.name ~= nil) and "no_route" or "unknown"
    else
      status = row_of[p.key] and row_of[p.key].cells[pl.id].state or "open"
      if status == "dead" then status = "caught" end
    end
    p.status = status
  end

  -- group views for the UI (members carry what undo_death needs)
  local group_views = {}
  for _, g in ipairs(groups) do
    local members = {}
    for _, vm in ipairs(g.mons) do
      members[#members + 1] = { owner = vm.owner, id = vm.id, species = vm.species,
        nickname = vm.nickname, deaths = eff_deaths(vm), dead = vm.dead == true, cause = vm.cause,
        doa = vm.doa == true }
    end
    local gv = { route = g.route, state = g.state, number = g.number, complete = g.complete,
                 count = g.count, members = members, died_seq = g.died_seq, completed_seq = g.completed_seq }
    group_views[#group_views + 1] = gv
    if row_of[g.route] and row_of[g.route].group then row_of[g.route].group = gv end
  end
  table.sort(group_views, function(a, b)
    local na, nb = a.number or INF, b.number or INF
    if na ~= nb then return na < nb end
    return oras.compare(a.route, b.route)
  end)

  -- hints
  local r = cfg.rules
  for i, pl in ipairs(players) do
    local op = out_players[i]
    for _, id in ipairs(op.ids) do
      local mv = op.mons[id]
      local alive = not mv.dead and mv.where ~= "gone" and not mv.excluded and not mv.virtual
      if alive and r.nickname_required and mv.counted and not mv.gift
         and (mv.nickname == nil or mv.nickname == "" or mv.nicknamed == false) then
        hints[#hints + 1] = { code = "nickname_missing", user = pl.id, mon = id, route = mv.route, player_index = i }
      end
      if alive and r.level_caps and mv.where == "team" and op.level_cap and mv.level and mv.level > op.level_cap then
        hints[#hints + 1] = { code = "level_cap", user = pl.id, mon = id, level = mv.level,
                              cap = op.level_cap, player_index = i }
      end
      if alive and soul and r.only_linked_in_team and mv.where == "team" then
        local g = mv.group and group_of[mv.group]
        if not g or (g.state ~= "linked" and g.state ~= "open") then
          hints[#hints + 1] = { code = "unlinked_in_team", user = pl.id, mon = id, route = mv.route, player_index = i }
        elseif g.state == "linked" then
          for _, pm in ipairs(g.mons) do
            if pm.owner ~= pl.id and pm.where ~= "team" then
              hints[#hints + 1] = { code = "partner_not_in_team", user = pl.id, mon = id, route = mv.route,
                                    partner = pm.owner, partner_mon = pm.id, player_index = i }
            end
          end
        end
      end
    end
  end

  return {
    mode = cfg.mode, rules = cfg.rules, players = out_players, rows = rows, groups = group_views,
    graveyard = graveyard, stats = stats, hints = hints, invalid_corrections = invalid,
  }
end

return V
