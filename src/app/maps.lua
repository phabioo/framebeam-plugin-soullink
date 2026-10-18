-- Region map from the game picture: the player opens the map in the game on the 3DS bottom screen and
-- "Take map from screen" captures it with fb.video.capture (permission video.capture, Player 0.11+ with
-- the game picture API). The PNG stays in the own cache of this player (never in the run state):
--   map/<game id>.png   the captured map (empty file = removed)
--   map/current.txt     game id of the last capture (the run view in the shell has no game id)
--   map/coords.json     { map = game id, crop = { t, b, l, r }, routes = { [route key] = { x, y } } } recorded by the player;
--                       crop = percent of the captured screen cut off at top/bottom/left/right when the stored PNG was
--                       taken (the capture rect lies inside the bottom screen, so the PNG is already cropped)
-- Route positions are image pixels of the cropped map. Taking the map again with another crop RESCALES the
-- recorded positions (screen fraction kept) instead of clearing them; without a known old crop it is 0.
-- Route positions on the image are our own recorded facts (data.oras.COORDS[game id]) merged under the
-- recorded ones. Retaking or removing the map keeps the positions. Without fb.video (older Player) the
-- Map tab says so; nothing else depends on it.
local util = require("model.util")
local oras = require("data.oras")

local M = {}
M.__index = M

M.COORDS_FILE, M.CURRENT = "map/coords.json", "map/current.txt"
M.NO_GAME = "game"
M.SIDES = { "t", "b", "l", "r" }
M.MAX_CROP = 45 -- percent per side; opposite sides together stay below 90

--- Clamp a crop table { t, b, l, r } (percent) to whole numbers 0..MAX_CROP with opposite sides <= 90 together.
function M.clean_crop(c)
  local out = {}
  for _, k in ipairs(M.SIDES) do
    local v = type(c) == "table" and tonumber(c[k]) or 0
    out[k] = math.max(0, math.min(M.MAX_CROP, math.floor((v or 0) + 0.5)))
  end
  return out
end

--- Suggested crop of the game in percent (data.oras.map_crop, an estimate), or all zero.
function M.suggest_crop(game)
  local f = oras.map_crop(game)
  if not f then return M.clean_crop({}) end
  return M.clean_crop({ t = f.top * 100, b = f.bottom * 100, l = f.left * 100, r = f.right * 100 })
end

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
  self.edit = self.crop and M.clean_crop(self.crop) or M.suggest_crop(self.game)
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
  self.coords, self.crop = {}, nil
  local s = self:read(M.COORDS_FILE)
  if type(s) ~= "string" or not self.id then return end
  local id = s:match('"map"%s*:%s*"(.-)"')
  if id ~= self.id then return end
  local cs = s:match('"crop"%s*:%s*(%b{})')
  if cs then
    local c = {}
    for _, k in ipairs(M.SIDES) do c[k] = tonumber(cs:match('"' .. k .. '"%s*:%s*(%d+)')) end
    self.crop = M.clean_crop(c)
  end
  local routes = s:match('"routes"%s*:%s*(%b{})') or ""
  for key, x, y in routes:gmatch('"([^"]+)"%s*:%s*{%s*"x"%s*:%s*(-?%d+)%s*,%s*"y"%s*:%s*(-?%d+)%s*}') do
    if oras.is_route(key) then self.coords[key] = { x = tonumber(x), y = tonumber(y) } end
  end
end

function M:save_coords()
  local routes = {}
  for key, c in pairs(self.coords) do routes[key] = { x = c.x, y = c.y } end
  self:write(M.COORDS_FILE, util.encode({ map = self.id, crop = self.crop, routes = routes }))
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

--- Screen to capture: the entry "bottom", else "main" of fb.video.screens() ({ name, x, y, w, h }), else nil.
function M:target()
  local ok, list = pcall(self.fb.video.screens)
  if not ok or type(list) ~= "table" then return nil end
  local by = {}
  for _, sc in ipairs(list) do
    if type(sc) == "table" and math.type(sc.x) == "integer" and math.type(sc.y) == "integer"
        and math.type(sc.w) == "integer" and math.type(sc.h) == "integer" and sc.w > 0 and sc.h > 0 then
      by[sc.name] = sc
    end
  end
  return by.bottom or by.main or nil
end

--- Capture rectangle inside screen `sc` for `crop` (percent): { x, y, w, h } in the screen coordinates.
function M.crop_rect(sc, crop)
  local c = M.clean_crop(crop)
  local l, r = sc.w * c.l // 100, sc.w * c.r // 100
  local tp, bt = sc.h * c.t // 100, sc.h * c.b // 100
  return { x = sc.x + l, y = sc.y + tp, w = math.max(1, sc.w - l - r), h = math.max(1, sc.h - tp - bt) }
end

--- Change one side of the crop being edited by `delta` percent ("t", "b", "l", "r"), within the limits.
function M:adjust(side, delta)
  if not (self.edit and self.edit[side] ~= nil) or math.type(delta) ~= "integer" then return false end
  local opp = ({ t = "b", b = "t", l = "r", r = "l" })[side]
  local v = math.max(0, math.min(M.MAX_CROP, self.edit[side] + delta))
  v = math.min(v, 90 - self.edit[opp])
  self.edit[side] = math.max(0, v)
  return true
end

--- Set the crop being edited: "none" (full screen), "suggest" (data.oras estimate) or "applied" (of the stored map).
function M:preset(name)
  if name == "none" then self.edit = M.clean_crop({})
  elseif name == "suggest" then self.edit = M.suggest_crop(self.game)
  elseif name == "applied" then self.edit = self.crop and M.clean_crop(self.crop) or M.clean_crop({})
  else return false end
  return true
end

--- Start a capture of the game picture. Returns true when a request is pending.
function M:capture()
  self.error = nil
  if not self.api then return false end
  if not self.live or not self.game then self.error = "unsupported"; return false end
  if self.pending then self.error = "busy"; return false end
  local target = self:target()
  if not target then self.error = "no_frame"; return false end
  local rect = M.crop_rect(target, self.edit)
  local ok, id = pcall(self.fb.video.capture, rect)
  if not ok then
    self.fb.log.warn("soullink map capture: " .. tostring(id))
    self.error = "failed"
    return false
  end
  self.pending, self.pending_crop = id, M.clean_crop(self.edit)
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
  local old_w, old_h, old_crop = self.w, self.h, self.crop or M.clean_crop({})
  if not (self:write(self:file(), e.png) and self:write(M.CURRENT, self.id)) then
    self.error = "failed"
    return true
  end
  self.w, self.h, self.state, self.error = w, h, "ready", nil
  self:load_coords()
  self:rescale(old_w, old_h, old_crop, self.pending_crop, w, h)
  self.crop = self.pending_crop
  self:save_coords()
  self.edit = M.clean_crop(self.crop)
  return true
end

--- Positions recorded on an image of old_w x old_h cropped by `old` (percent) move to the new image
--- (new_w x new_h, crop `new`): the point on the screen stays the same. Needs an old image; otherwise nothing changes.
function M:rescale(old_w, old_h, old, new, new_w, new_h)
  if not old_w or not old_h or next(self.coords) == nil then return end
  local function frac(c) return c.l / 100, c.t / 100, 1 - (c.l + c.r) / 100, 1 - (c.t + c.b) / 100 end
  local ol, ot, ow, oh = frac(old)
  local nl, nt, nw, nh = frac(new)
  for _, c in pairs(self.coords) do
    local fx, fy = ol + c.x / old_w * ow, ot + c.y / old_h * oh
    c.x = math.max(0, math.min(new_w, math.floor((fx - nl) / nw * new_w + 0.5)))
    c.y = math.max(0, math.min(new_h, math.floor((fy - nt) / nh * new_h + 0.5)))
  end
end

--- Remove the map image; the recorded positions stay.
function M:remove()
  if self.state == "ready" then self:write(self:file(), "") end
  self.w, self.h, self.state, self.error = nil, nil, "none", nil
end

--- What the UI needs: { state = none|ready, api, live, pending, error?, src?, w?, h?, id?, coords }.
function M:view()
  return { state = self.state, id = self.id, w = self.w, h = self.h, api = self.api, live = self.live,
           pending = self.pending ~= nil, error = self.error, crop = self.crop, edit = self.edit,
           suggest = oras.map_crop(self.game) ~= nil,
           src = self.state == "ready" and ("cache:" .. self:file()) or nil, coords = self:merged() }
end

return M
