-- Region map from the player's own game: pokemon-core `map_candidates()` lists large images of the
-- game files, `map_image(id)` returns one as PNG, `map_selected()` is the core's own pick. The
-- player chooses one (or the core's pick is used); the choice and the image are kept in the own cache:
--   map/choice.txt   map id of the choice ("" = none)
--   map/region.png   the chosen image
--   map/cand-<n>-<id>.png   previews of the candidates
--   map/coords.json  { map = id, routes = { [route key] = { x, y } } } recorded by the player
-- Route positions on the image are our own recorded facts (data.oras.COORDS[map id]) merged under
-- the recorded ones. Core calls are pcalled, a few per tick.
local util = require("model.util")
local oras = require("data.oras")

local M = {}
M.__index = M

M.CORE = "pokemon.core"
M.REGION, M.CHOICE, M.COORDS_FILE = "map/region.png", "map/choice.txt", "map/coords.json"
M.MAX_CANDIDATES = 24
M.PER_TICK = 2
M.RETRY_MS = 3000

--- Width and height from a PNG header, or nil.
function M.png_size(s)
  if type(s) ~= "string" or #s < 24 or s:sub(1, 8) ~= "\137PNG\r\n\26\n" or s:sub(13, 16) ~= "IHDR" then return nil end
  local w, h = string.unpack(">I4I4", s, 17)
  if w < 1 or h < 1 or w > 16384 or h > 16384 then return nil end
  return w, h
end

local function safe(id) return (tostring(id):gsub("[^%w_%-]", "_"):sub(1, 60)) end

function M.new(fb)
  local self = setmetatable({ fb = fb, state = "none", cands = {}, preview = {}, failed = {}, retry_at = {},
                              coords = {}, next_at = 0 }, M)
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

function M:call(fn, ...)
  local ok, a, b = pcall(self.fb.call, M.CORE, fn, ...)
  return ok, a, b
end

--- Restore the choice and the recorded positions from the cache.
function M:restore()
  local choice = self:read(M.CHOICE)
  choice = type(choice) == "string" and choice:match("^%s*(.-)%s*$") or ""
  local png = choice ~= "" and self:read(M.REGION) or nil
  local w, h = M.png_size(png)
  if w then
    self.id, self.w, self.h, self.state = choice, w, h, "ready"
  end
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
    if oras.is_key(key) then self.coords[key] = { x = tonumber(x), y = tonumber(y) } end
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
  if self.state ~= "ready" or not oras.route_number(route) then return false end
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
  table.sort(keys, oras.compare)
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

--- Use the image `id` as the region map. Returns true on success.
function M:adopt(id)
  local png
  local pv = self.preview[id]
  if pv then png = self:read(pv) end
  if not png then
    local ok, p = self:call("map_image", id)
    png = ok and p or nil
  end
  local w, h = M.png_size(png)
  if not w then return false end
  if not (self:write(M.REGION, png) and self:write(M.CHOICE, id)) then return false end
  self.id, self.w, self.h, self.state = id, w, h, "ready"
  self.cands, self.preview = {}, {}
  self:load_coords()
  return true
end

--- Forget the choice (the image stays in the cache); candidates are scanned again.
function M:reset()
  self:write(M.CHOICE, "")
  self.id, self.w, self.h, self.state = nil, nil, nil, "none"
  self.cands, self.preview, self.failed, self.retry_at, self.coords = {}, {}, {}, {}, {}
  self.next_at = 0
end

--- Scan / fetch previews. Returns true when the view changed.
function M:step(now)
  if self.state == "ready" or self.state == "unsupported" then return false end
  if self.state == "none" or self.state == "scanning" then
    if now < self.next_at then return false end
    local ok, sel = self:call("map_selected")
    if not ok then self.state = "unsupported"; return true end
    if type(sel) == "string" and sel ~= "" and self:adopt(sel) then return true end
    local ok2, list, why = self:call("map_candidates")
    if not ok2 then self.state = "unsupported"; return true end
    if type(list) ~= "table" then
      if why == "not_ready" then
        local changed = self.state ~= "scanning"
        self.state, self.next_at = "scanning", now + M.RETRY_MS
        return changed
      end
      self.state = "unsupported"
      return true
    end
    for _, c in ipairs(list) do
      if #self.cands >= M.MAX_CANDIDATES then break end
      if type(c) == "table" and type(c.id) == "string" and c.id ~= "" then
        self.cands[#self.cands + 1] = { id = c.id, w = c.w, h = c.h }
      end
    end
    self.state = "choose"
    return true
  end
  -- choose: previews, a few per tick
  local changed, n = false, 0
  for i, c in ipairs(self.cands) do
    if n >= M.PER_TICK then break end
    if not self.preview[c.id] and not self.failed[c.id] and now >= (self.retry_at[c.id] or 0) then
      n = n + 1
      local ok, png, why = self:call("map_image", c.id)
      local name = "map/cand-" .. i .. "-" .. safe(c.id) .. ".png"
      if ok and type(png) == "string" and M.png_size(png) and self:write(name, png) then
        self.preview[c.id], changed = name, true
      elseif ok and why == "not_ready" then
        self.retry_at[c.id] = now + M.RETRY_MS
      else
        self.failed[c.id], changed = true, true
      end
    end
  end
  return changed
end

--- What the UI needs: { state = none|scanning|choose|ready|unsupported, src?, w?, h?, id?,
--- candidates = {{id, w, h, src?, failed?}}, coords }.
function M:view()
  local cands = {}
  for _, c in ipairs(self.cands) do
    local pv = self.preview[c.id]
    cands[#cands + 1] = { id = c.id, w = c.w, h = c.h, src = pv and ("cache:" .. pv) or nil, failed = self.failed[c.id] }
  end
  return { state = self.state, id = self.id, w = self.w, h = self.h,
           src = self.state == "ready" and ("cache:" .. M.REGION) or nil,
           candidates = cands, coords = self:merged() }
end

return M
