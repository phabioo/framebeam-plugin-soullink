# Architecture

Status: package 1 (tooling and the pure run model) and package 2 (wiring, UI, release workflow). Everything below is design against plugin API v1 as documented in `docs/guides/plugin-api.md` of the FrameBeam repository; open API items are listed at the end.

## Layout

- `src/`: Lua modules; the list is `src/modules.txt`. `src/main.lua` is the entry (package 1: loads the modules and logs).
  - `data/oras.lua`: route keys, zone table (empty), level caps, labels.
  - `app/controller.lua` (wiring to `fb`), `app/sync.lua` (set/patch of UI slots).
  - `ui/common.lua`, `panel.lua`, `hud.lua`, `tile.lua`, `screen.lua`, `corrections.lua`, `board.lua`: pure builders `ctx -> block tree`.
  - `model/util.lua`, `rules.lua`, `state.lua`, `detect.lua`, `snapshot.lua`, `events.lua`, `corrections.lua`, `view.lua`.
- `tools/bundle.lua`: generates the single `plugin/main.lua` (the sandbox has no `require`). `lua5.4 tools/bundle.lua` writes, `--check` fails when it is stale. A new module must be listed in `src/modules.txt`.
- `plugin/`: installable plugin: `manifest.json`, generated `main.lua` (committed, never edit), `i18n/en.json` (source) and `de.json`.
- `tests/`: `lua5.4 tests/run.lua` runs every `tests/test_*.lua` against synthetic data. Support: `support/fb_mock.lua` (fake `fb` with `fb.call` and `fb.run`), `support/build.lua` (record, tracker, event log builders), `support/t.lua`.
- `tools/package.py`: builds and verifies `plugin/` as `<id>-<version>.fbplugin` (deterministic zip, copied from pokemon-core).
- CI (`.github/workflows/ci.yml`): `lua5.4 tools/bundle.lua --check`, `lua5.4 tests/run.lua`, package build and verify.
- Release (`.github/workflows/release.yml`): a tag `vX.Y.Z` (or a manual run with a tag; a new tag is created at the dispatch commit on `main`) checks bundle and tests, runs `tools/package.py --tag` (fails when the tag differs from the manifest version) and attaches the `.fbplugin` to the GitHub release. The package is unsigned.

The model is pure: it never reads `fb` (only `snapshot.from_core(fb)` calls `fb.call`). Game names (species, moves, places) are never shipped; tables are keyed by internal ids and route keys.

## Data flow

```text
pokemon.core --snapshot.from_core--> snapshot --detect.diff(prev own state, cfg)--> new own state + facts
own state  -> fb.run.setState        facts -> events.from_facts -> fb.run.event (automatic)
user action -> corrections.<kind> -> fb.run.event (manual)
view.view(fb.run.current(), fb.run.states(), fb.run.events(...), cfg) -> UI / Hub board
```

## Modules

### `model.rules`

`parse(run) -> cfg`, `cfg = { mode = "nuzlocke"|"soullink", mode_set = bool, rules = {flag = bool} }`. Settings are read from `run.settings["net.framebeam.soullink"] = { mode, rules = {...} }`. Unknown keys are ignored, wrong types fall back to the defaults. Without a valid mode: `soullink` with two or more joined participants (status `joined` or missing), else `nuzlocke`. Other functions: `defaults()`, `normalize(x)` (accepts a cfg or flat flags), `to_settings(cfg)`, `joined_count(run)`, `DEFAULTS`, `ORDER`.

Defaults: `first_encounter_only` true, `dupes_clause` true, `shiny_clause` true, `hordes_count` false, `pairs_differ_primary_type` false, `only_linked_in_team` false, `nickname_required` true, `level_caps` true.

### `data.oras`

`ROUTE_KEYS` (`route-101` .. `route-134`), `STARTER = "starter"`, `ZONE_TO_ROUTE` (empty, zone id -> route key or `false` for "not a route"; filled once pokemon-core reports ORAS locations), `LEVEL_CAPS[badges]` (marked verify locally), `level_cap(badges)`, `is_key(key)`, `custom_key(text)` (`place:<text>`, whitespace cleaned, 48 characters), `order_index(key)`, `compare(a, b)`, `route_number(key)`, `label(key, tr)` (i18n `route` with `{n}`, `route_starter`; free places keep the typed text).

### `model.state`

`new(game)`, `ensure(st)`, `size(st)`, `guard(st) -> ok, bytes`, `compact(st)`, `deaths(mon)`, `MAX_BYTES` (48 KiB soft limit, platform limit is 64 KiB). Test: 6 team + 120 box mons are about 18 KiB.

### `model.detect`

- `diff(prev, snap, cfg, opts) -> new_state, facts`. `prev` is never modified. `opts`: `family(species)` (default identity), `zones` (default `ZONE_TO_ROUTE`), `first` (`auto`|`baseline`|`starter`), `game`.
- `set_place(prev, input, name) -> new_state, fact|nil`: manual place; `input` is a route key or free text (becomes `place:<text>`), empty clears.

Rules of the diff:

- Tracking starts with the first snapshot where team and boxes are both known. Then everything present is baseline, except `first = "starter"` or `auto` with exactly one non-egg mon in the team and none in the boxes: that mon is the starter on route `starter`.
- A personality that is not in the baseline and not tracked is a catch on the current place (`place.key`).
- Egg: gift (`gift`, no route consumed). No place: recorded with route nil, fact `why = "no_place"` (the UI asks). Shiny with `shiny_clause`: `why = "shiny"`, route stays open. Dupe (`dupes_clause`, `family(species)` equals that of a tracked mon that is not dupe/extra/gone): `why = "dupe"`, route stays open. Route already used with `first_encounter_only`: kept, `why = "extra"`; with the rule off: `why = "additional"` (route entry keeps the first mon, so the additional mon is in no link group). A `missed` route whose entry species equals the caught species is upgraded to caught (the catch arrived after the battle ended).
- Evolution: same personality, other species: fact `evolve`, mon updated. Form/level/nickname are updated.
- Death: hp known before (>0) and now 0: `deaths + 1`, fact `death`. Unknown hp never produces a death. A mon missing from a snapshot with team and boxes both known is `gone` after two consecutive snapshots; with a part unknown nothing changes.
- Battle: with `battle().active` and `wild`: on the transition to active one `encounter` fact (hordes only count with `hordes_count`; shiny/dupe/used routes do not count); route entry `encounter`. On the transition to inactive remaining `encounter` entries become `missed` (fact `missed`). Without `battle`, an `encounters` list is processed as new encounters (no `missed` detection then).
- Place: `location.zone` through the zone table; an unknown zone keeps a manual place and otherwise clears the key.

Facts (`kind`): `place {key?, name?, zone?, manual, previous?}`, `catch {mon, species, form?, nickname?, level?, shiny, route?, where, counts, why?, gift?, starter?}`, `evolve {mon, from, to, route?}`, `death {mon, species, nickname?, route?, deaths}`, `moved {mon, from, to}`, `encounter {route?, species?, form?, shiny, horde, counts, why?}`, `missed {route, species?}`.

### `model.snapshot`

`collect(call) -> snap, issues`, `from_core(fb)`. Snapshot: `team` (list), `boxes` (list of lists, or flat list), `location {zone?, name?}`, `battle {active, wild, horde?, foes = {records}}`, `encounters` (list of `{species, form?, shiny?, horde?}`), `badges` (number, `{count}` or list of booleans). A part that is unsupported, not ready or raising an error stays nil and is listed in `issues`.

### Own state (`model.state`, written with `fb.run.setState`)

```text
{ v = 1, started = bool, inb = bool,
  game = { id, language },
  place = { key?, name?, zone?, manual },
  baseline = { ["<hex8 personality>"] = true },
  mons = { ["<hex8>"] = { species, form?, nickname?, nicknamed? (false only), level, shiny? (true only),
           route?, where = "team"|"box"|"gone", deaths? (absent = 0), hp?, mhp? (max hp), gift? (true only),
           why? = "extra"|"dupe"|"shiny"|"additional"|"gift", miss? } },
  routes = { [route key] = { status = "encounter"|"caught"|"missed", mon?, species?, kind? = "wild"|"horde"|"starter"|"gift" } },
  order = { "<hex8>", ... }, badges = n }
```

Route keys: `starter`, `route-101`..`route-134`, `place:<text>`. A mon counts when `routes[mon.route].mon` is its id.

### `model.events`

Automatic run events (spec `{type, payload, source = "automatic"}`; `text` is added by the caller with i18n and names read from the game): `soullink.catch {user, mon, species, form?, nickname?, level?, shiny?, route?, counts, why?, gift?, starter?, where}`, `soullink.death {user, mon, species, nickname?, route?, deaths}`, `soullink.encounter {user, outcome = "seen"|"missed", route?, species?, form?, shiny?, horde?, counts, why?}`, `soullink.place {user, route?, name?, manual}`. `from_fact(fact, user)`, `from_facts(facts, user)`. The event order (seq) gives the completion order of link groups.

### `model.corrections`

Event type `soullink.correction`, `source = "manual"`, payload at most 4 KiB. `payload.user` is the player the correction is about; the author is the event's `user_id`. Builders return `{type, source, payload}`, `validate(payload)` / `validate_spec(spec)` return `true` or `false, reason`.

| Kind | Payload | Effect in the view |
|---|---|---|
| `doesnt_count` | `user, route?, mon?, reason? = dupe|shiny|wrong` | mon stops counting, route reopens; without mon: reopens an `encounter`/`missed` route |
| `undo_death` | `group, undone = [{owner, mon, deaths}], reason?` | records per mon the death count that is undone (`undo_entries(group)` from a view group); revives the group |
| `set_group` | `user, mon, group = route key | "none"` | moves the mon into that route's group (also assigns a catch that had no place); `none` = no link |
| `add` | `user, route, species, form?, nickname?, level?, shiny?, state = team|box|dead` | hand-added mon (id `add-<seq>`), replaces missed/open; extra when the route is taken |
| `mark_missed` | `user, route` | route is missed for that player |
| `mark_dead` | `user, mon, reason?` | one more death |
| `set_gift` | `user, mon, gift = bool` | gift: group state `gift`, no link |
| `revert` | `target = seq, reason?` | cancels the correction event `target`; a reverted revert cancels nothing |

### `model.view`

`view(run_current, states_by_user, events_in_seq_order, cfg) -> view`. Pure and deterministic. Players are the participants with status `joined` (without participants: the keys of the states).

- `players[i]`: `id, name, color, game_id, place {key, name, zone, manual, status}`, `team` (list of mons, team order), `box_count`, `alive`, `dead`, `badges`, `level_cap`, `mons` (id -> mon), `ids`. `place.status`: `unknown`, `no_route`, `open`, `encounter`, `caught`, `missed`.
- mon: `id, owner, species, form, nickname, nicknamed, level, shiny, hp, route, where, dead, cause ("own"|"linked"), doa, deaths, gift, why, excluded, virtual, counted, group, group_state, group_number`.
- `rows` (routes with activity, route order): `{route, order, cells = {user -> {state = open|encounter|caught|missed|dead, mon?, species?, nickname?, gift?, cause?}}, group, done}`.
- `groups` (SoulLink only), numbered first, then by route order: `{route, state, number?, complete, count, members = [{owner, id, species, nickname, deaths, dead, cause, doa}], died_seq?, completed_seq?}`. States: `linked` (all players caught, alive), `open` (pending), `dead` (some member died; also while pending), `broken` (someone missed, no link, no propagation), `gift`, `nolink`. Numbers 1..n go to complete `linked`/`dead` groups in the order of `completed_seq` (the largest catch or placement event seq of the members); without event seqs the route order decides.
- Deaths: a mon is dead when its deaths (detected + `mark_dead`) exceed the undone count. A dead member kills its group (`cause = "linked"`); a mon caught into an already dead group is dead on arrival (`doa`, needs the catch event seq).
- `graveyard`: dead mons ordered by death seq (own death event, or the group's first), then player, then id.
- `stats`: `deaths, groups_dead, groups_linked, routes_done, routes_total, badges_max, alive`.
- `hints` (never blocking): `nickname_missing`, `level_cap {level, cap}`, `unlinked_in_team`, `partner_not_in_team {partner, partner_mon}`; each with `user, mon`.
- `invalid_corrections`: seqs of correction events that failed validation (ignored).
- Nuzlocke mode: no groups, deaths stay with the owner.

## Wiring (`app.controller`)

- Without `fb.run` (game not started from Runs, or shell context without an open run): panel, HUD and screen show an empty state ("Start this game from Runs → Play run"; the screen text also points to the Runs page), no core calls, no tracking.
- Run view (`fb.run.current().view == true`, shell context, read only): the controller sets the `run` slot with the run screen builder (`screen.build` with `readonly`: routes, team & box, graveyard, event log; no correction forms or write buttons) and the screen slot shows the Runs pointer. No core calls, no polling, no notices, no board, no `tiles` subscription, no own state injected. Every write action is ignored; the platform would answer `setState`/`event`/`setBoard` with `nil, "read only outside the game"`. `common.writable` is false for a run with `view`.
- With `fb.run`: own state is continued from `fb.run.state()`. Every 500 ms: `snapshot.from_core` (team, location, battle, badges; boxes every 5 s, in between the last box read is reused), `detect.diff`, `setState` only when the encoded state changed, facts posted as automatic events (English text from i18n, species shown as `#<id>` or the nickname until the core provides names). Core calls are `pcall`ed; failures are logged once. Paused/finished/abandoned runs are read only: no polling, no writes, banner in the panel, no action buttons.
- Subscriptions: `fb.run.on` for `event`, `state`, `participants`, `status` (4 of 16), host event `tiles`, `fb.ui.on_action`. Events are cached (paged from seq 0), the view is recomputed at most every 250 ms when something changed.
- `app.sync.push(slot, tree)`: unchanged tree = nothing, same structure with changed props on blocks with an id (at most 12) = `fb.ui.patch`, else `fb.ui.set`.
- Board: `fb.run.setBoard` with the compact tree (players, routes table, graveyard, deaths), at most every 5 s and only when it changed.
- Notices (`fb.ui.notify`): deaths in the own link groups (important, actions "Open run" and "Undo death...", HUD expanded for 3 s), catches of others that count (info), new route hint for detected places (info). A death waits for the state that shows it (up to 40 renders).
- Hotkeys: `toggle-hud` does nothing (the host handles it), `doesnt-count` opens the 5f-1 form for the current route, `open-run` = `open_run`.

## UI

All strings come from `plugin/i18n/en.json` (source) and `de.json`; only tones, sizes and player numbers (participant color + 1) are used. Death is shown as a grey `✕` prefix, never red.

- Panel (5b): run header with mode, name, read-only badge and "Open run"; `location` block (place, status, others on the same place); place picker (`select` over starter and Route 101..134 plus a `textfield` "Other place..." for free places, because the core has no location); encounter hint with "Doesn't count"; correction section when a form is open; own team rows (nickname or `#id`, level, HP bar when hp and max hp are known, linked partners as avatars, "Mark as dead" with danger confirm because the core has no live HP); graveyard chip toggling a list; footer with badges (`select`, editable by hand while the core has none), next level cap and "Run screen".
- HUD (5c): one `card` (action `hud_toggle`): `SL` badge, place, status dot text. Expanded (click) or for 3 s after a linked death: other players with their state on the same place.
- Tile (5d): `tiles` host event (`{ id, player, user_id, game }`) matched to participants by `user_id` first, by name (case-insensitive) as fallback; strip text `SL <place> · <n> alive`.
- Screen (5e, shown in the screen slot): header (run, status, mode, players with place, stats), correction section, `tabs`: Routes | Team & box | Graveyard | Event log. The Map tab appears first only when `data.oras.COORDS` has coordinates (none yet; drawn default F); the map block then shows the loading state until an image is set. Routes: filter chips, table (route, one column per player, group, status), selected route with actions (mark missed, doesn't count, undo death, change link group), "+ Add by hand". Team & box: per player team rows (own: change group, gift, dead) and box list. Graveyard: table, row action undoes the group's death. Event log: filter chips, newest 100 rows, manual rows warning tone, correction rows revert.
- Corrections (5f): inline section; fields change with the actions `cf:<field>` (text fields commit on Enter), `corr_submit` validates with `corrections.validate_spec` and posts a manual `soullink.correction` event (text from i18n), `corr_cancel` closes. Danger/confirm dialogs on the buttons for undo death, mark dead, mark missed and revert. Forms: doesn't count (reason segments), undo death (reason field), set group, add by hand (species number, nickname, level, state), mark missed, mark dead, gift, revert.
- Board (5gh): `board.build`.
- Run start rules (5a-4): the manifest field `run_settings` declares `mode` (enum `nuzlocke`|`soullink`, default `soullink`) and one boolean `rules.<flag>` per flag of `model.rules` with the same defaults; the Start dialog sends them as `settings["net.framebeam.soullink"] = { mode, rules = {...} }`, `rules.parse` reads them (the two-or-more-players mode fallback only applies to runs without settings). Labels and hints are the i18n keys `rs_*` (`rs_mode`, `rs_<flag>`, `rs_<flag>_hint`, `rs_mode_<value>`). `tests/test_platform.lua` checks the manifest against the validator rules and that its keys map exactly onto `rules.parse`.
- Out of scope: Hub run wizard steps other than the platform's rules section (5ah), stream view (5gs) and plugin settings (5i): the platform has no settings schema yet.

Tests: `tests/test_app.lua` drives the controller with the fake `fb.run`, `fb.ui` and `pokemon.core`; `tests/support/ui_validator.lua` checks every tree and patch against the documented block catalog (types, props, enums, ids, limits).

## Open points

- pokemon-core: `location()`, `battle()`, `encounters()`, `badges()` and live hp are not implemented (ORAS adapter has team/box only). The shapes above are assumptions; until then the place is entered by hand, encounters and deaths are not detected, and the user marks them via corrections. Box numbering base of `box(n)` (assumed 1..`box_count()`), the zone id and a `nicknamed` flag in the record are not specified.
- Family lookup (evolution lines) for the dupes clause: only the `family` hook exists, the default compares species ids. A table keyed by species ids is needed (no names).
- `pairs_differ_primary_type` is stored but not evaluated: it needs primary types per species.
- Zone id -> route key table (`data.oras.ZONE_TO_ROUTE`) and the ORAS level caps (`LEVEL_CAPS`) are to be filled and verified locally with the real game.
- pokemon-core is a manifest `requires` (`^0.1`): the Start dialog adds it to the run automatically (newest Hub version that fits) and it needs no `run.state` permission; the Hub must offer a matching version. Version 0.2.0 of this plugin.
- Changing rules during a run is not modeled (run settings are fixed at the start).
- Tracking start (baseline vs starter) is decided from the first snapshot; the run start flow (new game vs existing save) should tell the plugin explicitly (`opts.first`).
- Participants with status other than `joined` are not players; `left` participants drop out of link groups.
- Broken groups (someone missed) do not link the remaining members at all; whether partners that caught should stay linked is a rules question for the design.
- Event `text` for automatic and manual events and the run board tree are package 2.
- No `fb.ui` function opens or focuses the screen slot (plugin API v1): "Open run", Ctrl+R and the toast action only reset the screen's tab and refresh it. Needs a host function or a toast/link target.
- Species names are not available from the core yet: creatures show as `#<species id>` or the nickname, and places as `Route <n>`.
- The map needs coordinates and the image from the game file at runtime (`data.oras.COORDS`, `MAP_SIZE`); none yet, so the Map tab is hidden. Creature icons (`image` blocks) are not used for the same reason.
- Text fields only report their value on Enter, so the correction forms say so; a form submit button cannot read unsent text.
- Approval of corrections by another player and the settings page (5i) are not built; the run start (5a) is the platform's Start dialog with the manifest rules section (the mode cards and invite steps are the platform's).
- Release: the `.fbplugin` is unsigned; signing and the Hub upload flow are open.
