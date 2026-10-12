-- Synthetic data builders for the model tests (no real game data).
local util = require("model.util")
local detect = require("model.detect")
local rules = require("model.rules")
local events = require("model.events")

local B = {}

--- Generic pokemon.core record. o: p (personality), sp, lv, hp, nick, shiny, egg, form
function B.rec(o)
  return {
    personality = o.p, species = o.sp or 1, form = o.form or 0, nickname = o.nick,
    level = o.lv or 5, hp = o.hp, max_hp = o.hp and 30 or nil, shiny = o.shiny or false,
    egg = o.egg or false,
  }
end

--- cfg with overrides: B.cfg("soullink", { dupes_clause = false })
function B.cfg(mode, over)
  local cfg = { mode = mode or "nuzlocke", rules = rules.defaults() }
  for k, v in pairs(over or {}) do cfg.rules[k] = v end
  return cfg
end

--- Participants list with joined status and color 0..n-1.
function B.run(names, settings)
  local ps = {}
  for i, n in ipairs(names) do
    ps[i] = { user_id = "u-" .. n:lower(), name = n, color = i - 1, status = "joined", game_id = "g" .. i }
  end
  return { id = "run-1", name = "Test", status = "active", me = ps[1].user_id,
           settings = settings or {}, participants = ps }
end

--- Event log with increasing seq.
function B.log()
  local log = { events = {}, seq = 0 }
  function log:add(user, spec)
    self.seq = self.seq + 1
    self.events[#self.events + 1] = { seq = self.seq, user_id = user, type = spec.type,
      source = spec.source or "automatic", payload = util.copy(spec.payload) }
    return self.seq
  end
  function log:facts(user, facts)
    for _, s in ipairs(events.from_facts(facts, user)) do self:add(user, s) end
  end
  return log
end

--- Simulated player: keeps mon records, runs detect.diff, optionally posts events to a log.
function B.tracker(uid, cfg, log, opts)
  local t = { uid = uid, cfg = cfg, log = log, opts = opts or {}, recs = {}, team = {}, box = {},
              st = nil, last_facts = {}, snap_extra = {} }
  function t:snapshot()
    local team, box = {}, {}
    for _, p in ipairs(self.team) do team[#team + 1] = util.copy(self.recs[p]) end
    for _, p in ipairs(self.box) do box[#box + 1] = util.copy(self.recs[p]) end
    local s = { team = team, boxes = { box } }
    for k, v in pairs(self.snap_extra) do s[k] = v end
    return s
  end
  function t:step()
    local facts
    self.st, facts = detect.diff(self.st, self:snapshot(), self.cfg, self.opts)
    self.last_facts = facts
    if self.log then self.log:facts(self.uid, facts) end
    return facts
  end
  --- Put pre-existing mons (baseline) into the team and take the first snapshot.
  function t:start(base)
    for _, p in ipairs(base or { 0xB001, 0xB002 }) do
      self.recs[p] = B.rec({ p = p, sp = 900 + p % 100, hp = 30 })
      self.team[#self.team + 1] = p
    end
    return self:step()
  end
  function t:place(key, name)
    local fact
    self.st, fact = detect.set_place(self.st, key, name)
    if fact and self.log then self.log:facts(self.uid, { fact }) end
  end
  --- New mon (box by default, team with o.team).
  function t:catch(p, sp, o)
    o = o or {}
    self.recs[p] = B.rec({ p = p, sp = sp, nick = o.nick or ("n" .. p), lv = o.lv or 5,
      hp = o.hp or 30, shiny = o.shiny, egg = o.egg })
    local list = o.team and self.team or self.box
    list[#list + 1] = p
    return self:step()
  end
  function t:hp(p, hp) self.recs[p].hp = hp; return self:step() end
  --- Wild battle against species `sp` (active until t:end_battle()).
  function t:battle(sp, o)
    o = o or {}
    self.snap_extra.battle = { active = true, wild = true, horde = o.horde or false,
      foes = { B.rec({ p = 0xF00D, sp = sp, shiny = o.shiny }) } }
    return self:step()
  end
  function t:end_battle()
    self.snap_extra.battle = { active = false, wild = false, foes = {} }
    return self:step()
  end
  return t
end

--- states_by_user from trackers.
function B.states(...)
  local out = {}
  for _, t in ipairs({ ... }) do out[t.uid] = t.st end
  return out
end

--- Find the first fact of a kind.
function B.fact(facts, kind)
  for _, f in ipairs(facts) do if f.kind == kind then return f end end
  return nil
end

function B.count(facts, kind)
  local n = 0
  for _, f in ipairs(facts) do if f.kind == kind then n = n + 1 end end
  return n
end

return B
