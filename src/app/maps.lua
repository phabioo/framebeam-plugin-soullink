-- Region map from the game picture: the player opens the map in the game on the 3DS bottom screen and
-- "Take map from screen" captures it with fb.video.capture (permission video.capture, Player 0.11+ with
-- the game picture API). The PNG stays in the own cache of this player (never in the run state):
--   map/<game id>.png   the captured map (empty file = removed)
--   map/current.txt     game id of the last capture (the run view in the shell has no game id)
--   map/coords.json     { map = game id, routes = { [route key] = { x, y } } } recorded by the player
-- Route positions on the image are our own recorded facts (data.oras.COORDS[game id]) merged under the
-- recorded ones. Retaking or removing the map keeps the positions. Without fb.video (older Player) the
-- Map tab says so; nothing else depends on it.
local util = require("model.util")
local oras = require("data.oras")

local M = {}
M.__index = M

M.COORDS_FILE, M.CURRENT = "map/coords.json", "map/current.txt"
M.NO_GAME = "game"

--- Width and height from a PNG header, or nil.
function M.png_size(s)
  if type(s) ~= "string" or #s < 24 or s:sub(1, 8) ~= "\137PNG\r\n\26\n" or s:sub(13, 16) ~= "IHDR" then return nil end
  local w, h = string.unpack(">I4I4", s, 17)
  if w < 1 or h < 1 or w > 16384 or h > 16384 then return nil end
  return w, h
end

local function safe(id) return (tostring(id):gsub("[^%w_%-]", "_"):sub(1, 60)) end

--- `live` = false in the shell run view (no game: nothing to capture). Game id = fb.game.code.
function M.new(fb, live)
  local code = type(fb.game) == "table" and fb.game.code or nil
  local self = setmetatable({ fb = fb, state = "none", coords = {}, live = live ~= false,
                              api = type(fb.video) == "table" and type(fb.video.capture) == "function" }, M)
  self.game = (type(code) == "string" and code ~= "") and code or nil
  self:restore()
  return self
end

function M:read(name)
  local ok, v = pcall(self.fb.cache.read, name)
  return ok and v or nil
end

function M:write(name, data)
  return (pcall(self.fb.cache.write, name, data))
end

function M:file() return "map/" .. safe(self.id or M.NO_GAME) .. ".png" end

--- Restore the image and the recorded positions from the cache.
function M:restore()
  self.id = self.game
  if not self.id then
    local cur = self:read(M.CURRENT)
    self.id = (type(cur) == "string" and cur:match("^%s*(.-)%s*$") ~= "") and cur:match("^%s*(.-)%s*$") or nil
  end
  local png = self.id and self:read(self:file()) or nil
  local w, h = M.png_size(png)
  if w then self.w, self.h, self.state = w, h, "ready" end
  self:load_coords()
end

function M:load_coords()
  self.coords = {}
  local s = self:read(M.COORDS_FILE)
  if type(s) ~= "string" or not self.id then return end
  local id = s:match('"map"%s*:%s*"(.-)"')
  if id ~= self.id then return end
  local routes = s:match('"routes"%s*:%s*(%b{})') or ""
  for key, x, y in routes:gmatch('"([^"]+)"%s*:%s*{%s*"x"%s*:%s*(-?%d+)%s*,%s*"y"%s*:%s*(-?%d+)%s*}') do
    if oras.is_route(key) then self.coords[key] = { x = tonumber(x), y = tonumber(y) } end
  end
end

function M:save_coords()
  local routes = {}
  for key, c in pairs(self.coords) do routes[key] = { x = c.x, y = c.y } end
  self:write(M.COORDS_FILE, util.encode({ map = self.id, routes = routes }))
end

--- Route positions: data.oras.COORDS[map id] with the recorded ones on top.
function M:merged()
  local out = {}
  for key, c in pairs(self.id and oras.COORDS[self.id] or {}) do out[key] = c end
  for key, c in pairs(self.coords) do
    local base = out[key]
    out[key] = { x = c.x, y = c.y, area = base and base.area or nil }
  end
  return out
end

--- Record the position of a route (image pixels, clamped to the image).
function M:set_coord(route, x, y)
  if self.state ~= "ready" or not oras.is_route(route) then return false end
  x = math.max(0, math.min(self.w, math.floor(x + 0.5)))
  y = math.max(0, math.min(self.h, math.floor(y + 0.5)))
  self.coords[route] = { x = x, y = y }
  self:save_coords()
  return true
end

--- One Lua table line with all positions (data.oras.COORDS entry), written to the log. nil without positions.
function M:export_line()
  local all = self:merged()
  local keys = {}
  for key in pairs(all) do keys[#keys + 1] = key end
  if #keys == 0 or not self.id then return nil end
  table.sort(keys, function(a, b) return oras.compare(a, b, self.order) end)
  local parts = {}
  for _, key in ipairs(keys) do
    local c = all[key]
    parts[#parts + 1] = string.format("[%q] = { x = %d, y = %d%s }", key, c.x, c.y,
      c.area and string.format(", area = %q", c.area) or "")
  end
  local line = string.format("COORDS[%q] = { %s }", self.id, table.concat(parts, ", "))
  self.fb.log.info("soullink positions: " .. line)
  return line
end

--- Screen to capture: "bottom", else "main", else nil (no game / no such screen).
function M:target()
  local ok, list = pcall(self.fb.video.screens)
  if not ok or type(list) ~= "table" then return nil end
  local has = {}
  for _, sc in ipairs(list) do if type(sc) == "table" then has[sc.name] = true end end
  return (has.bottom and "bottom") or (has.main and "main") or nil
end

--- Start a capture of the game picture. Returns true when a request is pending.
function M:capture()
  self.error = nil
  if not self.api then return false end
  if not self.live or not self.game then self.error = "unsupported"; return false end
  if self.pending then self.error = "busy"; return false end
  local target = self:target()
  if not target then self.error = "no_frame"; return false end
  local ok, id = pcall(self.fb.video.capture, target)
  if not ok then
    self.fb.log.warn("soullink map capture: " .. tostring(id))
    self.error = "failed"
    return false
  end
  self.pending = id
  return true
end

--- Host event video.captured { id, ok, png, w, h, error }. Returns true when the view changed.
function M:on_captured(e)
  if type(e) ~= "table" or not self.pending or e.id ~= self.pending then return false end
  self.pending = nil
  if e.ok ~= true then
    self.error = type(e.error) == "string" and e.error or "failed"
    return true
  end
  local w, h = M.png_size(e.png)
  if not w then self.error = "failed"; return true end
  self.id = self.game
  if not (self:write(self:file(), e.png) and self:write(M.CURRENT, self.id)) then
    self.error = "failed"
    return true
  end
  self.w, self.h, self.state, self.error = w, h, "ready", nil
  self:load_coords()
  return true
end

--- Remove the map image; the recorded positions stay.
function M:remove()
  if self.state == "ready" then self:write(self:file(), "") end
  self.w, self.h, self.state, self.error = nil, nil, "none", nil
end

--- What the UI needs: { state = none|ready, api, live, pending, error?, src?, w?, h?, id?, coords }.
function M:view()
  return { state = self.state, id = self.id, w = self.w, h = self.h, api = self.api, live = self.live,
           pending = self.pending ~= nil, error = self.error,
           src = self.state == "ready" and ("cache:" .. self:file()) or nil, coords = self:merged() }
end

return M
