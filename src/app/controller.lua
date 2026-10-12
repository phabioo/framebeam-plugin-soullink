-- App controller: wires the model to fb (core polling, run state and events, UI slots, actions).
-- Everything the UI shows comes from view.view(); everything the user changes goes through
-- detect.set_place / model.corrections and the run (state and events), never into the view directly.
local util = require("model.util")
local rules = require("model.rules")
local state = require("model.state")
local detect = require("model.detect")
local snapshot = require("model.snapshot")
local events = require("model.events")
local corrections = require("model.corrections")
local view_mod = require("model.view")
local oras = require("data.oras")
local common = require("ui.common")
local corr_ui = require("ui.corrections")
local panel = require("ui.panel")
local hud = require("ui.hud")
local screen = require("ui.screen")
local tile = require("ui.tile")
local board = require("ui.board")
local sync = require("app.sync")

local A = {}
A.__index = A

A.POLL_MS = 500      -- team, place, battle, badges
A.BOX_MS = 5000      -- boxes
A.RENDER_MS = 250    -- at most 4 UI refreshes per second
A.BOARD_MS = 5000    -- run board
A.HUD_MS = 3000      -- HUD stays expanded after a linked death
A.NOTICE_TRIES = 40  -- renders to wait for the state that shows a death

function A.new(fb)
  local self = setmetatable({}, A)
  self.fb = fb
  self.tr = function(key, vars) return fb.i18n.t(key, vars) end
  self.ui = { screen_tab = 1 }
  self.events, self.seen = {}, {}
  self.queue = {}          -- death events waiting for the view
  self.tiles, self.tile_slots = {}, {}
  self.sync = sync.new(fb)
  self.last_poll, self.last_box, self.last_render, self.last_board = -1e9, -1e9, -1e9, -1e9
  self.dirty = true
  self.errors = {}
  return self
end

local function warn_once(self, key, ...)
  if not self.errors[key] then
    self.errors[key] = true
    self.fb.log.warn(...)
  end
end

-- ---------------------------------------------------------------- start

function A:start()
  local fb, tr = self.fb, self.tr
  fb.ui.on_action(function(action, value, slot) self:on_action(action, value, slot) end)
  if not fb.run then
    self.sync:push("panel", panel.empty(tr))
    self.sync:push("hud", hud.empty(tr))
    self.sync:push("screen", screen.empty(tr))
    return
  end
  self.run = fb.run.current()
  self.me = self.run.me
  self.viewing = self.run.view == true -- run view of the Runs screen: shell context, read only
  -- run view: no game, so no core calls, no tracking, no notices; only the `run` slot shows the run
  if self.viewing then self.sync:push("screen", screen.empty(tr)) end
  self.st = state.ensure(util.copy(fb.run.state()))
  self.last_enc = (not self.viewing and fb.run.state()) and util.encode(self.st) or nil
  self:load_events()
  self.live = not self.viewing
  fb.run.on("event", function(ev) self:on_event(ev) end)
  fb.run.on("state", function() self.dirty = true end)
  fb.run.on("participants", function() self.dirty = true end)
  fb.run.on("status", function() self.dirty = true end)
  if not self.viewing then
    fb.events.on("fb", "tiles", function(list) self.tiles = type(list) == "table" and list or {}; self.dirty = true end)
  end
  fb.on_tick(function() self:tick() end)
  self:poll(true)
  self:render()
end

function A:load_events()
  local after = 0
  while true do
    local page = self.fb.run.events(after, 500)
    for _, ev in ipairs(page) do
      if not self.seen[ev.seq] then
        self.seen[ev.seq] = true
        self.events[#self.events + 1] = ev
      end
      after = math.max(after, ev.seq)
    end
    if #page < 500 then break end
  end
end

function A:writable() return common.writable(self.run) end

-- ---------------------------------------------------------------- ticking

function A:tick()
  local now = self.fb.clock()
  if self.writable_cached ~= self:writable() then
    self.writable_cached = self:writable()
    self.dirty = true
  end
  if now - self.last_poll >= A.POLL_MS then
    local full = now - self.last_box >= A.BOX_MS
    self.last_poll = now
    if full then self.last_box = now end
    local ok, err = pcall(self.poll, self, full)
    if not ok then warn_once(self, "poll", "poll failed: " .. tostring(err)) end
  end
  if self.hud_until and now >= self.hud_until then
    self.hud_until, self.hud_text = nil, nil
    self.dirty = true
  end
  if self.board_due and now - self.last_board >= A.BOARD_MS then self.dirty = true end
  if self.dirty and now - self.last_render >= A.RENDER_MS then
    local ok, err = pcall(self.render, self)
    if not ok then warn_once(self, "render", "render failed: " .. tostring(err)) end
  end
end

-- ---------------------------------------------------------------- polling and state

function A:poll(full)
  if not self:writable() then return end
  local cfg = rules.parse(self.run)
  local snap = snapshot.from_core(self.fb, { skip_boxes = (not full) and self.boxes ~= nil, boxes = self.boxes })
  if snap.boxes then self.boxes = snap.boxes end
  local game = self.fb.game or {}
  local st, facts = detect.diff(self.st, snap, cfg, { game = { id = game.code, language = game.language } })
  self:commit(st, facts)
end

--- Adopt a new own state, publish it when it changed and post the facts as automatic events.
function A:commit(st, facts)
  state.guard(st)
  self.st = st
  local enc = util.encode(st)
  if enc ~= self.last_enc then
    if self:writable() then
      local ok, why = self.fb.run.setState(st)
      if ok then self.last_enc = enc else warn_once(self, "setState", "setState refused: " .. tostring(why)) end
    end
    self.dirty = true
  end
  for _, f in ipairs(facts or {}) do self:post_fact(f) end
  if facts and #facts > 0 then self.dirty = true end
end

function A:player_name(id)
  for _, p in ipairs(self.run.participants or {}) do
    if p.user_id == id then return p.name or p.user_name or id end
  end
  return tostring(id)
end

function A:place_text(route)
  return route and oras.label(route, self.tr) or self.tr("place_none")
end

function A:fact_text(f)
  local tr = self.tr
  local player = self:player_name(self.me)
  local mon = common.mon_name({ nickname = f.nickname, species = f.species })
  local text
  if f.kind == "catch" then
    text = tr("ev_catch", { player = player, mon = mon, place = self:place_text(f.route) })
  elseif f.kind == "death" then
    text = tr("ev_death", { player = player, mon = mon })
  elseif f.kind == "encounter" then
    text = tr("ev_encounter", { player = player, mon = "#" .. tostring(f.species or "?"), place = self:place_text(f.route) })
  elseif f.kind == "missed" then
    text = tr("ev_missed", { player = player, place = self:place_text(f.route) })
  elseif f.kind == "place" then
    text = tr("ev_place", { player = player, place = f.key and self:place_text(f.key) or (f.name or tr("place_none")) })
  end
  if text and f.why then text = text .. " " .. tr("ev_why_" .. f.why) end
  return text and util.clean_text(text, 280) or nil
end

function A:post_fact(f)
  local spec = events.from_fact(f, self.me)
  if not spec or not self:writable() then return end
  spec.text = self:fact_text(f)
  local ok, err = pcall(self.fb.run.event, spec)
  if not ok then warn_once(self, "event", "event refused: " .. tostring(err)) end
  if f.kind == "place" and f.key and not f.manual then self:note_place(f.key) end
end

-- ---------------------------------------------------------------- events and notices

function A:on_event(ev)
  if type(ev) ~= "table" or self.seen[ev.seq] then return end
  self.seen[ev.seq] = true
  local n = #self.events
  self.events[n + 1] = ev
  if n > 0 and self.events[n].seq > ev.seq then
    table.sort(self.events, function(a, b) return a.seq < b.seq end)
  end
  self.dirty = true
  if not self.live then return end
  local p = type(ev.payload) == "table" and ev.payload or {}
  if ev.type == events.TYPES.death then
    self.queue[#self.queue + 1] = { ev = ev, tries = 0 }
  elseif ev.type == events.TYPES.catch and ev.user_id ~= self.me and p.counts then
    self:notify({ tone = "info", text = self.tr("note_catch", {
      player = self:player_name(ev.user_id), mon = common.mon_name({ nickname = p.nickname, species = p.species }),
      place = self:place_text(p.route) }) })
  end
end

function A:notify(n)
  n.title = n.title or self.tr("note_title")
  local ok, id = pcall(self.fb.ui.notify, n)
  if not ok then warn_once(self, "notify", "notify failed: " .. tostring(id)) end
  return ok and id or nil
end

function A:note_place(route)
  local row = self.view and common.row_of(self.view, route)
  local cell = row and row.cells[self.me]
  if cell and cell.state ~= "open" then return end
  self:notify({ tone = "info", text = self.tr("note_new_place", { place = self:place_text(route) }) })
end

-- Deaths in the own link groups: toast (important) and HUD expansion.
function A:process_queue(view)
  local keep = {}
  local groups = common.groups(view)
  for _, q in ipairs(self.queue) do
    local ev, p = q.ev, q.ev.payload or {}
    local owner = common.player(view, ev.user_id)
    local mon = owner and owner.mons[p.mon]
    local g = mon and mon.group and groups[mon.group]
    local handled = false
    if g and g.state == "dead" then
      local mine
      for _, m in ipairs(g.members) do if m.owner == self.me then mine = m end end
      if mine then
        local partners = math.max(g.count - 1, 0)
        local text
        if ev.user_id == self.me then
          text = self.tr("note_death_own", { mon = common.mon_name(mon), n = partners })
        else
          text = self.tr("note_death_linked", { player = owner.name, mon = common.mon_name(mon), mine = common.mon_name(mine) })
        end
        self:notify({ tone = "important", text = text, actions = {
          { label = self.tr("open_run"), action = "open_run" },
          { label = self.tr("undo_death"), action = "undo_open", value = g.route },
        } })
        self.hud_until = self.fb.clock() + A.HUD_MS
        self.hud_text = self.tr("hud_death", { n = g.number or 0, mon = common.mon_name(mon), count = partners })
      end
      handled = true
    elseif q.tries >= A.NOTICE_TRIES or (mon and not mon.group) then
      handled = true
    end
    if not handled then
      q.tries = q.tries + 1
      keep[#keep + 1] = q
      self.dirty = true
    end
  end
  self.queue = keep
end

-- ---------------------------------------------------------------- rendering

function A:states()
  local states = self.fb.run.states()
  if not self.viewing and self.me and states[self.me] == nil and self.st then states[self.me] = self.st end
  return states
end

function A:ctx(view)
  return { view = view, run = self.run, me = self.me, ui = self.ui, tr = self.tr, readonly = not self:writable(),
           events = self.events, hud_death = self.hud_until and self.hud_text or nil }
end

function A:render()
  local fb = self.fb
  self.dirty = false
  local now = fb.clock()
  self.last_render = now
  self.run = fb.run.current()
  local cfg = rules.parse(self.run)
  local view = view_mod.view(self.run, self:states(), self.events, cfg)
  self.view = view
  self:process_queue(view)
  local ctx = self:ctx(view)
  if self.viewing then
    -- read-only run section of the Runs screen: the run screen without correction forms or actions
    self.sync:push("run", screen.build(ctx))
    return
  end
  self.sync:push("panel", panel.build(ctx))
  self.sync:push("hud", hud.build(ctx))
  self.sync:push("screen", screen.build(ctx))

  local matched = tile.match(self.tiles, view)
  local live = {}
  for id, p in pairs(matched) do
    local slot = "tile:" .. id
    live[slot] = true
    self.sync:push(slot, tile.build(self.tr, p))
  end
  for slot in pairs(self.tile_slots) do
    if not live[slot] then self.sync:clear(slot) end
  end
  self.tile_slots = live

  if self:writable() then
    local tree = board.build(ctx)
    local enc = util.encode(tree)
    if enc == self.last_board_enc then
      self.board_due = false
    elseif now - self.last_board >= A.BOARD_MS then
      self.board_due = false
      self.last_board = now
      if fb.run.setBoard(tree) then self.last_board_enc = enc end
    else
      self.board_due = true
    end
  end
end

-- ---------------------------------------------------------------- corrections

function A:correction_text(spec)
  local p, tr = spec.payload, self.tr
  local mon
  local owner = self.view and p.user and common.player(self.view, p.user)
  if owner and p.mon and owner.mons[p.mon] then mon = common.mon_name(owner.mons[p.mon]) end
  if p.kind == "add" then mon = common.mon_name({ nickname = p.nickname, species = p.species }) end
  return util.clean_text(tr("ev_c_" .. p.kind, {
    player = self:player_name(self.me), target = p.user and self:player_name(p.user) or "",
    route = p.route and oras.label(p.route, tr) or (p.group and p.group ~= "none" and oras.label(p.group, tr)) or "",
    mon = mon or "?", seq = p.target or "", reason = p.reason or "",
  }), 280)
end

--- Post a manual correction event. Returns true when it was accepted.
function A:post_correction(spec)
  if not self:writable() then return false end
  local ok_valid = corrections.validate_spec(spec)
  if not ok_valid then return false end
  spec.text = self:correction_text(spec)
  local ok, id = pcall(self.fb.run.event, spec)
  if not ok or id == nil then return false end
  self.dirty = true
  return true
end

local function my_player(self) return self.view and common.player(self.view, self.me) end

function A:open_corr(corr)
  corr.user = corr.user or self.me
  self.ui.corr = corr
  self.dirty = true
end

local function field_value(field, value)
  if field == "species" or field == "level" then
    local n = tonumber(value)
    return n and math.tointeger(n) or nil
  elseif field == "gift" then
    return value == true
  end
  if type(value) == "string" then return util.clean_text(value, 280) or "" end
  return value
end

function A:set_place(input)
  if not self:writable() then return end
  local st, fact = detect.set_place(self.st, input)
  self:commit(st, { fact })
end

-- ---------------------------------------------------------------- actions

function A:on_action(action, value, slot)
  if slot == "hotkey" then
    if action == "toggle-hud" then return end -- the host shows or hides the widget
    if action == "open-run" then action = "open_run"
    elseif action == "doesnt-count" then action, value = "dc_open", nil
    else return end
  end
  if not self.run then return end
  local me = my_player(self)
  local writable = self:writable()

  if action == "open_run" then
    self.ui.screen_tab = 1
    self.ui.corr = self.ui.corr
    self.dirty = true
  elseif action == "grave_toggle" then self.ui.grave_open = not self.ui.grave_open; self.dirty = true
  elseif action == "hud_toggle" then self.ui.hud_expanded = not self.ui.hud_expanded; self.dirty = true
  elseif action == "tab" then
    if math.type(value) == "integer" then self.ui.screen_tab = value; self.dirty = true end
  elseif action:sub(1, 3) == "rf:" then self.ui.routes_filter = action:sub(4); self.dirty = true
  elseif action:sub(1, 3) == "lf:" then self.ui.log_filter = action:sub(4); self.dirty = true
  elseif action == "route_select" then self.ui.selected_route = value; self.dirty = true
  elseif action == "map_select" then
    if type(value) == "table" then
      if value.kind == "route" then self.ui.selected_route = value.id
      elseif value.kind == "filter" then self.ui.map_filter = value.value end
      self.dirty = true
    end
  elseif not writable then
    return
  elseif action == "place_select" then
    if type(value) == "string" then self:set_place(value) end
  elseif action == "place_text" then
    self:set_place(type(value) == "string" and value or "")
  elseif action == "badges_select" then
    if math.type(value) == "integer" and value >= 0 and value <= 8 then
      local st = util.copy(self.st)
      st.badges = value
      self:commit(st, {})
    end
  elseif action == "mark_dead" then
    if type(value) == "string" then
      self:post_correction(corrections.mark_dead({ user = self.me, mon = value }))
    end
  elseif action == "dc_open" then
    local route = value or (me and me.place.key)
    if route then
      local corr = { kind = "doesnt_count", route = route, reason = "wrong" }
      local row = common.row_of(self.view, route)
      local cell = row and row.cells[self.me]
      if cell and cell.mon then corr.mon = cell.mon end
      self:open_corr(corr)
    end
  elseif action == "missed_open" then
    if type(value) == "string" then self:open_corr({ kind = "mark_missed", route = value }) end
  elseif action == "undo_open" then
    local g = type(value) == "string" and common.groups(self.view)[value]
    if g then
      self:open_corr({ kind = "undo_death", group = g.route, number = g.number, members = g.members,
        undone = corrections.undo_entries(g) })
    end
  elseif action == "group_open" then
    local m = me and me.mons[value]
    if m then self:open_corr({ kind = "set_group", mon = m.id, group = m.group or "none" }) end
  elseif action == "gift_open" then
    if me and me.mons[value] then self:open_corr({ kind = "set_gift", mon = value, gift = true }) end
  elseif action == "dead_open" then
    if me and me.mons[value] then self:open_corr({ kind = "mark_dead", mon = value }) end
  elseif action == "add_open" then
    self:open_corr({ kind = "add", route = me and me.place.key and oras.is_key(me.place.key) and me.place.key or oras.ROUTE_KEYS[1],
      state = "box" })
  elseif action == "revert_open" then
    if math.type(value) == "integer" then self:open_corr({ kind = "revert", target = value }) end
  elseif action:sub(1, 3) == "cf:" then
    local corr = self.ui.corr
    if corr then
      local field = action:sub(4)
      corr[field] = field_value(field, value)
      corr.error = nil
      self.dirty = true
    end
  elseif action == "corr_cancel" then
    self.ui.corr = nil; self.dirty = true
  elseif action == "corr_submit" then
    local corr = self.ui.corr
    if corr then
      local spec, err = corr_ui.to_spec(corr)
      if not spec then
        corr.error = err
      elseif self:post_correction(spec) then
        self.ui.corr = nil
      else
        corr.error = "c_err_post"
      end
      self.dirty = true
    end
  end
end

return A
