-- Own state: one object per participant, written with fb.run.setState (limit 64 KiB).
local util = require("model.util")

local S = {}

S.VERSION = 1
--- Soft limit well below the 64 KiB platform limit; guard() compacts above it.
S.MAX_BYTES = 48 * 1024

--- Fresh state. `game` = { id = ..., language = ... } (both optional).
---
--- Schema (v = 1), all keys strings, JSON-able:
---   v, started (bool: baseline taken), inb (bool: wild battle was active at the last diff)
---   game   = { id, language }
---   place  = { key?, name?, zone?, manual }   key = route key or nil (no place / not a route)
---   baseline = { ["<hex8 personality>"] = true }   mons present before tracking, ignored forever
---   mons   = { ["<hex8>"] = { species, form?, nickname?, nicknamed? (false only), level, shiny? (true only),
---              route?, where = "team"|"box"|"gone", deaths? (absent = 0), hp?, gift? (true only),
---              why? = "extra"|"dupe"|"shiny"|"additional"|"gift", miss? } }
---   routes = { [route key] = { status = "encounter"|"caught"|"missed", mon?, species?, kind? } }
---   order  = { "<hex8>", ... }   tracked mons in team order
---   badges = number
function S.new(game)
  local g = {}
  if type(game) == "table" then
    g.id = game.id
    g.language = game.language
  end
  return {
    v = S.VERSION, started = false, inb = false,
    game = g, place = { manual = false },
    baseline = {}, mons = {}, routes = {}, order = {}, badges = 0,
  }
end

--- Complete a state received from the Hub (nil or older shape) so the model can use it.
function S.ensure(st)
  if type(st) ~= "table" then return S.new() end
  st.v = st.v or S.VERSION
  st.game = st.game or {}
  st.place = st.place or { manual = false }
  st.baseline = st.baseline or {}
  st.mons = st.mons or {}
  st.routes = st.routes or {}
  st.order = st.order or {}
  st.badges = st.badges or 0
  return st
end

--- Death count of a tracked mon (absent = 0).
function S.deaths(mon) return mon and mon.deaths or 0 end

--- Size in bytes of the JSON encoding of `st`.
function S.size(st) return util.json_size(st) end

--- Drop what can be dropped safely when the state is large: mons that are gone and own no route
--- entry, then shorten nicknames. Returns the (same) state. Baseline entries are never dropped.
function S.compact(st)
  local referenced = {}
  for _, r in pairs(st.routes) do if r.mon then referenced[r.mon] = true end end
  for pid, m in pairs(st.mons) do
    if m.where == "gone" and not referenced[pid] and (m.deaths or 0) == 0 then st.mons[pid] = nil end
  end
  if S.size(st) > S.MAX_BYTES then
    for _, m in pairs(st.mons) do
      if m.nickname then m.nickname = util.clean_text(m.nickname, 12) end
    end
  end
  return st
end

--- Size guard: returns ok, bytes. Compacts when above MAX_BYTES; ok is false when it still is.
function S.guard(st)
  local n = S.size(st)
  if n <= S.MAX_BYTES then return true, n end
  S.compact(st)
  n = S.size(st)
  return n <= S.MAX_BYTES, n
end

return S
