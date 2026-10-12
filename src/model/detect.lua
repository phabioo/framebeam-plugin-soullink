-- Detection: diff(previous own state, core snapshot, cfg) -> new own state + facts.
-- Pure; never touches fb. Everything the core cannot report (place, battle, hp, encounters)
-- degrades to "unknown": nothing is invented, the UI/user supplies it through manual input.
local util = require("model.util")
local rules = require("model.rules")
local state = require("model.state")
local oras = require("data.oras")

local D = {}

-- Snapshot (what the caller passes; model/snapshot.lua builds it from pokemon.core):
--   team     list of generic records, or nil = unknown
--   boxes    list of boxes (each a list of records) or a flat list of records, or nil = unknown
--   location { zone = number?, name = string? }   or nil
--   battle   { active = bool, wild = bool, horde = bool?, foes = {records} }  or nil
--   encounters list of { species, form?, shiny?, horde? } newly seen encounters, or nil
--   badges   number | { count = n } | list of booleans
-- Facts (kind): place, catch, evolve, death, moved, encounter, missed. See docs/architecture.md.

local function default_family(species) return species end

local function collect(snap)
  local list, map = {}, {}
  local team_known = type(snap.team) == "table"
  local boxes_known = type(snap.boxes) == "table"
  local function add(rec, where)
    if type(rec) ~= "table" or type(rec.species) ~= "number" then return end
    local pid = util.hex8(rec.personality)
    if not pid or map[pid] then return end
    local c = { pid = pid, rec = rec, where = where }
    map[pid] = c
    list[#list + 1] = c
  end
  if team_known then for _, rec in ipairs(snap.team) do add(rec, "team") end end
  if boxes_known then
    for _, box in ipairs(snap.boxes) do
      if type(box) == "table" and box.personality ~= nil then
        add(box, "box")
      elseif type(box) == "table" then
        for _, rec in ipairs(box) do add(rec, "box") end
      end
    end
  end
  return list, map, team_known, boxes_known
end

local function badge_count(b)
  if math.type(b) == "integer" then return b end
  if type(b) ~= "table" then return nil end
  if math.type(b.count) == "integer" then return b.count end
  local n = 0
  for _, v in ipairs(b) do if v == true then n = n + 1 end end
  return n
end

local function battle_info(snap)
  local b = snap.battle
  if type(b) ~= "table" or type(b.active) ~= "boolean" then return { known = false } end
  return { known = true, active = b.active, wild = b.wild == true, horde = b.horde == true,
           foes = type(b.foes) == "table" and b.foes or (type(b.foe) == "table" and { b.foe } or {}) }
end

-- Is a line (family) already owned by a tracked mon that counts for the dupes clause?
local function owns_line(st, species, family)
  if species == nil then return false end
  local fam = family(species)
  for _, m in pairs(st.mons) do
    if m.why ~= "dupe" and m.why ~= "extra" and m.where ~= "gone" and family(m.species) == fam then
      return true
    end
  end
  return false
end

local function update_place(st, loc, facts, zones)
  if type(loc) ~= "table" or loc.zone == nil then return end
  local old = st.place or { manual = false }
  local mapped = zones[loc.zone]
  local new
  if mapped ~= nil then
    new = { key = mapped or nil, name = loc.name, zone = loc.zone, manual = false }
  elseif old.manual then
    return -- unknown zone: keep what the user set by hand
  else
    new = { name = loc.name, zone = loc.zone, manual = false }
  end
  if new.key ~= old.key or new.name ~= old.name or new.zone ~= old.zone or old.manual then
    st.place = new
    if new.key ~= old.key or new.name ~= old.name then
      facts[#facts + 1] = { kind = "place", key = new.key, name = new.name, zone = new.zone,
                            manual = false, previous = old.key }
    end
  end
end

--- Set the place by hand. `input` is a route key ("route-104", "starter", "place:<text>") or free
--- text typed by the user (becomes "place:<text>"); nil/"" clears the place. `name` is optional
--- display text. Returns the new state and a place fact (or nil when nothing changed).
function D.set_place(prev, input, name)
  local st = state.ensure(util.copy(prev))
  local old = st.place or { manual = false }
  local key
  if input ~= nil and input ~= "" then
    key = oras.is_key(input) and input or oras.custom_key(input)
  end
  st.place = { key = key, name = name, manual = true }
  if key == old.key and name == old.name and old.manual then return st, nil end
  return st, { kind = "place", key = key, name = name, manual = true, previous = old.key }
end

local function handle_encounter(st, cfg, pk, foe, horde, facts, family)
  local fact = { kind = "encounter", route = pk, species = foe.species, form = foe.form,
                 shiny = foe.shiny == true, horde = horde, counts = false }
  local r = cfg.rules
  local existing = pk and st.routes[pk]
  if horde and not r.hordes_count then
    fact.why = "horde"
  elseif pk == nil then
    fact.why = "no_place"
  elseif fact.shiny and r.shiny_clause then
    fact.why = "shiny"
  elseif r.dupes_clause and owns_line(st, foe.species, family) then
    fact.why = "dupe"
  elseif existing and r.first_encounter_only then
    fact.why = "used"
  else
    fact.counts = true
    if not existing then
      st.routes[pk] = { status = "encounter", species = foe.species, kind = horde and "horde" or "wild" }
    end
  end
  facts[#facts + 1] = fact
end

local function handle_catch(st, cfg, c, pk, starter, facts, family)
  local rec, r = c.rec, cfg.rules
  local dupe = r.dupes_clause and owns_line(st, rec.species, family) -- before the mon is added
  local mon = {
    species = rec.species, form = rec.form, nickname = util.clean_text(rec.nickname, 24),
    level = rec.level, shiny = rec.shiny == true or nil, route = pk, where = c.where,
    hp = type(rec.hp) == "number" and rec.hp or nil,
    mhp = type(rec.max_hp) == "number" and rec.max_hp or nil,
  }
  if rec.nicknamed == false then mon.nicknamed = false end
  st.mons[c.pid] = mon
  local fact = { kind = "catch", mon = c.pid, species = rec.species, form = rec.form,
                 nickname = mon.nickname, level = rec.level, shiny = rec.shiny == true,
                 route = pk, where = c.where, counts = false, starter = starter or nil }
  local existing = pk and st.routes[pk]
  if rec.egg then
    mon.gift, mon.why = true, "gift"
    fact.gift, fact.why = true, "gift"
  elseif pk == nil then
    fact.why = "no_place"
  elseif mon.shiny and r.shiny_clause then
    mon.why, fact.why = "shiny", "shiny"
  elseif dupe then
    mon.why, fact.why = "dupe", "dupe"
  else
    local entry = { status = "caught", mon = c.pid, species = rec.species,
                    kind = starter and "starter" or "wild" }
    if not existing or existing.status == "encounter" then
      st.routes[pk], fact.counts = entry, true
    elseif existing.status == "missed" and existing.species == rec.species then
      st.routes[pk], fact.counts = entry, true -- the catch arrived after the battle was closed
    elseif not r.first_encounter_only then
      mon.why, fact.why = "additional", "additional"
    else
      mon.why, fact.why = "extra", "extra"
    end
  end
  facts[#facts + 1] = fact
end

--- diff(prev, snap, cfg, opts) -> new_state, facts
---   prev  own state (nil = fresh); never modified
---   snap  see the snapshot description above
---   cfg   result of rules.parse (or flat rule flags)
---   opts  { family = function(species) -> family id (default: species itself),
---           zones = zone -> route key table (default data.oras.ZONE_TO_ROUTE),
---           first = "auto"|"baseline"|"starter" (what the first complete snapshot means),
---           game = { id, language } }
--- Tracking starts with the first snapshot where team and boxes are both known: then either
--- everything present is baseline, or (first = "starter", or "auto" with exactly one mon in the
--- team and no box mon) that mon is the starter caught on route "starter".
function D.diff(prev, snap, cfg, opts)
  opts = opts or {}
  cfg = rules.normalize(cfg)
  local st = state.ensure(util.copy(prev))
  snap = type(snap) == "table" and snap or {}
  local facts = {}
  local family = opts.family or default_family
  if type(opts.game) == "table" then
    st.game.id = st.game.id or opts.game.id
    st.game.language = st.game.language or opts.game.language
  end

  update_place(st, snap.location, facts, opts.zones or oras.ZONE_TO_ROUTE)
  local b = badge_count(snap.badges)
  if b then st.badges = b end

  local list, map, team_known, boxes_known = collect(snap)
  local bat = battle_info(snap)
  local catch_place

  if not st.started then
    if not (team_known and boxes_known) then return st, facts end
    local first = opts.first or "auto"
    local starter = first == "starter"
      or (first == "auto" and #list == 1 and list[1].where == "team" and not list[1].rec.egg)
    st.started = true
    if not starter then
      for _, c in ipairs(list) do st.baseline[c.pid] = true end
      st.inb = bat.known and bat.active or false
      return st, facts
    end
    catch_place = oras.STARTER
  end

  -- known mons: updates, moves, evolution, deaths, disappearance
  for _, pid in ipairs(util.keys(st.mons)) do
    local m, c = st.mons[pid], map[pid]
    if c then
      local rec = c.rec
      m.miss = nil
      if m.species ~= rec.species then
        facts[#facts + 1] = { kind = "evolve", mon = pid, from = m.species, to = rec.species,
                              nickname = m.nickname, route = m.route }
        m.species = rec.species
      end
      m.form = rec.form
      m.level = rec.level or m.level
      m.nickname = util.clean_text(rec.nickname, 24) or m.nickname
      if rec.nicknamed == false then m.nicknamed = false elseif rec.nicknamed == true then m.nicknamed = nil end
      if rec.shiny == true then m.shiny = true end
      if m.where ~= c.where then
        facts[#facts + 1] = { kind = "moved", mon = pid, from = m.where, to = c.where }
        m.where = c.where
      end
      if type(rec.hp) == "number" then
        if m.hp and m.hp > 0 and rec.hp <= 0 then
          m.deaths = (m.deaths or 0) + 1
          facts[#facts + 1] = { kind = "death", mon = pid, species = m.species, nickname = m.nickname,
                                route = m.route, deaths = m.deaths }
        end
        m.hp = rec.hp
      end
      if type(rec.max_hp) == "number" then m.mhp = rec.max_hp end
    elseif team_known and boxes_known and m.where ~= "gone" then
      m.miss = (m.miss or 0) + 1 -- gone only after two snapshots in a row (no transient states)
      if m.miss >= 2 then
        facts[#facts + 1] = { kind = "moved", mon = pid, from = m.where, to = "gone" }
        m.where, m.miss = "gone", nil
      end
    end
  end

  -- new mons
  for _, c in ipairs(list) do
    if not st.baseline[c.pid] and not st.mons[c.pid] then
      handle_catch(st, cfg, c, catch_place or st.place.key, catch_place ~= nil, facts, family)
    end
  end

  -- team order (tracked mons only)
  if team_known then
    st.order = {}
    for _, c in ipairs(list) do
      if c.where == "team" and st.mons[c.pid] then st.order[#st.order + 1] = c.pid end
    end
  end

  -- encounters and missed routes
  if bat.known then
    if bat.active and not st.inb and bat.wild then
      handle_encounter(st, cfg, st.place.key, bat.foes[1] or {}, bat.horde, facts, family)
    elseif not bat.active and st.inb then
      for _, key in ipairs(util.keys(st.routes)) do
        local e = st.routes[key]
        if e.status == "encounter" then
          e.status = "missed"
          facts[#facts + 1] = { kind = "missed", route = key, species = e.species }
        end
      end
    end
    st.inb = bat.active
  elseif type(snap.encounters) == "table" then
    for _, e in ipairs(snap.encounters) do
      if type(e) == "table" then
        handle_encounter(st, cfg, st.place.key, e, e.horde == true, facts, family)
      end
    end
  end

  return st, facts
end

return D
