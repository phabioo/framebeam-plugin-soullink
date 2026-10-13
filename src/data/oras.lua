-- Route keys and small data tables for Omega Ruby / Alpha Sapphire.
-- Keyed by internal route keys only; names (routes, species, places) are never shipped here.
local util = require("model.util")

local M = {}

M.STARTER = "starter"
M.FIRST_ROUTE = 101
M.LAST_ROUTE = 134

--- Ordered route keys "route-101" .. "route-134".
M.ROUTE_KEYS = {}
for n = M.FIRST_ROUTE, M.LAST_ROUTE do
  M.ROUTE_KEYS[#M.ROUTE_KEYS + 1] = "route-" .. n
end

--- zone id (pokemon-core `location().zone`) -> route key (string) or false (known zone that is not a
--- route, e.g. a town). EMPTY on purpose: the table is unknown until recorded with the real game.
--- Meanwhile zones are learned at runtime: the answer of a player is kept in the own run state
--- (`zones`) and merged across all players (model.view.merge_zones).
M.ZONES = {}
M.ZONE_TO_ROUTE = M.ZONES -- old name

--- Route positions on the region map image, keyed by the map id that pokemon-core reports
--- (`map_candidates()` / `map_selected()`): COORDS[map id][route key] = { x, y, area? } in image
--- pixels. Our own recorded facts, EMPTY for now: positions are recorded in the Map tab
--- ("Place routes") and exported with "Export positions".
M.COORDS = {}

--- Level cap hint by number of badges owned: LEVEL_CAPS[badges] = cap of the next gym.
--- VERIFY LOCALLY against the real game before relying on it; hints only, never blocking.
M.LEVEL_CAPS = { [0] = 15, 19, 24, 29, 31, 33, 42, 43 }

--- Level cap hint for `badges` badges, or nil when unknown (for example all eight badges).
function M.level_cap(badges)
  if math.type(badges) ~= "integer" then return nil end
  return M.LEVEL_CAPS[badges]
end

--- Route number of a key "route-NNN", or nil.
function M.route_number(key)
  local n = type(key) == "string" and key:match("^route%-(%d+)$")
  n = n and tonumber(n)
  if n and n >= M.FIRST_ROUTE and n <= M.LAST_ROUTE then return n end
  return nil
end

--- True for "starter", a known route key or a free "place:<text>" key.
function M.is_key(key)
  if type(key) ~= "string" then return false end
  if key == M.STARTER or M.route_number(key) then return true end
  local text = key:match("^place:(.+)$")
  return text ~= nil and util.clean_text(text, 48) == text
end

--- Free place key for text typed by the user ("place:<text>", text kept as typed apart from
--- whitespace cleanup, at most 48 characters). nil for empty text.
function M.custom_key(text)
  local t = util.clean_text(text, 48)
  return t and ("place:" .. t) or nil
end

--- Sort index: starter first, routes in numeric order, free places after (by text).
function M.order_index(key)
  if key == M.STARTER then return 0 end
  local n = M.route_number(key)
  if n then return n - M.FIRST_ROUTE + 1 end
  return 1000
end

--- Comparison function for route keys.
function M.compare(a, b)
  local ia, ib = M.order_index(a), M.order_index(b)
  if ia ~= ib then return ia < ib end
  return tostring(a) < tostring(b)
end

--- Display text. `tr` is fb.i18n.t (key, vars); free places keep the text as typed.
function M.label(key, tr)
  if key == M.STARTER then return tr("route_starter") end
  local n = M.route_number(key)
  if n then return tr("route", { n = n }) end
  local text = type(key) == "string" and key:match("^place:(.+)$")
  return text or tostring(key)
end

return M
