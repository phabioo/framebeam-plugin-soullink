# SoulLink screens

Per-screen specification of the handoff in `source/` (see [README.md](README.md) for source files, status and decisions). All names, numbers, versions and creatures are fictional mock values. Layout dimensions, tokens and blocks are the platform's: https://github.com/phabioo/uzume/tree/main/docs/design. Line ranges refer to the file named in the heading; "5a-5i" = `source/soullink-5a-5i.dc.html`, "R2" = `source/plugins-round-2.dc.html`, "5e-5g" = `source/soullink-5e-5g-run.dc.html`.

Player colors: Max blue, Lena pink, Jonas lime, Sam violet (hex in README). They mark who, never status. Status colors: cyan open / selection, green caught, grey missed / not a route / dead (with x mark), amber manual / pending / paused, red only danger actions and low HP.

## Rules shown in the UI

- Modes: **Nuzlocke** (1-4 players, no links; first encounter per route counts, fainted means dead) and **SoulLink** (2-4 players; catches from the same route form a link group; if one dies, its partners die too). Mode cannot be changed after the start (5a-1).
- Switches (5a-4, 5i; defaults on unless noted): first encounter only; dupes clause (re-roll if you already own that line); shiny clause (shinies may always be caught); hordes count as first encounter (off: hordes are skipped); linked pairs differ in primary type (off); only linked pairs in the team (a creature joins only with all partners); nickname required (reminder after each catch); level caps as hints (shows the next gym's cap, never blocks).
- Rules are the same for everyone in the run. Defaults come from Settings (5i) and apply to new runs; running runs keep theirs.
- Link group: numbered per route (Group 1..n) when every member caught there or the route is closed; "no link" or "Gift - no link" otherwise; "Broken - missed" when someone missed it. Dead is a group state: "Group dead".
- Saves: a new slot "Run - <name>" per player; the Main slot stays untouched.

## 5a Start a run

Player: 5a-5i `#5a-1`..`#5a-5`, lines 28-89 (960 x 680 dialog on a dark backdrop). Mock layout is a modal over the Library with a step list on the left.

- Purpose: create a run in five steps: Mode, Players, Games, Rules, Summary. Stepper: done = check mark, current = highlighted, rest muted.
- 5a-1 Mode: two cards (Nuzlocke, SoulLink) and run name field ("Ember & Tide"). Note: "You can't switch mode after the start."
- 5a-2 Players: "+ Invite a hub user...", rows with avatar in the player color, name, sub line, state chip (Joined green, Pending amber), action (Remove / Withdraw; none for the host). Up to 3 invited. "Invites work like Session invites. You can continue now; the run starts when everyone joined, or you start without pending players."
- 5a-3 Games: one row per player with a "3DS" chip and a game select ("Coral Saga: Ember", "Coral Saga: Tide"), note "in Library" / "twin version" / "Picks when joining" (pending). Only supported games are listed; twin versions can be mixed; each player picks their own copy.
- 5a-4 Rules: eight toggle rows (above).
- 5a-5 Summary: run, players with game, rules, saves line. Warning (amber) when a player has not joined: "Sam hasn't joined yet. Start now and Sam joins later from the invite, or wait." Button "Start run"; "Starting creates the run on hub.example.com and a save slot per player."
- Buttons per step: Back, Cancel, Next.
- Blocks: dialog, list with selection, chip, toggle rows, text field, select, platform invite (4j).

## 5ah Hub wizard

R2 `5ah-2-1`..`5ah-2-5`, lines 292-300, component `source/hub-run-wizard.dc.html`; light, 1440 x 900, Hub shell (nav: Library, Saves, Systems & Cores, Clients, Users, Plugins, Runs, Settings; Runs active). Header "New run - runs created here appear on every member's Player", a bar stepper and the same five steps as 5a. Step 2 shows invite state, step 5 the start with a pending player. Round-1 `5ah` (5a-5i 91-112) showed only step 2.

## 5b In-game panel

R2 `5b-2` (306-317, 1440 x 900, side panel 340) and `5b-1280-2` (319-329, 1280 x 800, panel 320); component `source/soullink-panel.dc.html`. Always dark. Play area draws the 3DS screen geometry (top screen wider than bottom). Header per platform (mode `session`, compact at 1280). Tab bar: Game | SoulLink (SL) | Items (IH); see platform 4e for tab fitting.

Panel content, top to bottom:

- **Run header**: "SOULLINK RUN", run name, "Open run ->".
- **Location card**: place name + state chip (below). Under it "Others on <place>": one row per other player: color dot, name, status ("caught Tidepup" with icon, "no encounter yet", "missed - fled").
- **Encounter hint** (when detected): creature icon, "Encounter detected - Wild <species> - first on this route", quiet button "Doesn't count" (Ctrl+D) -> 5f-1.
- **Your team**, "5/6 linked with": a row per creature: icon, nickname, species, level, HP bar (green / amber / red by value), then the linked partners as small icons with the partner's color dot; at 1280 only two partner icons per row, the rest in a tooltip. Empty slot drawn dashed.
- **Graveyard** (collapsed, count, dead icons grey with x mark).
- **Footer**: "Badges 4 / 8 - Next cap Lv 24", "Run screen ->".
- **Paused** (plugin error): amber banner "SoulLink & Nuzlocke was paused after an error. Your game keeps running. Encounters from now on are not tracked until the plugin restarts." Buttons "Restart plugin", "Details". The tab shows the warning marker.
- Open (B): tapping a team row only goes to the run screen; no inline 5f actions are drawn.

### Location card states

5a-5i `5b location states`, lines 142-146; also the HUD states.

| State | Text | Tone |
|---|---|---|
| No encounter yet | route name + "first encounter still open" | cyan |
| Encounter now | "wild battle running" | cyan |
| Caught | "<nickname> (<species>)" | green |
| Missed | "fled or fainted" | grey |
| Not a route | "no encounters here" (town) | grey |

## 5c HUD widget

R2 `5c-2`, 331-341 (component states on a dark frame). A HUD slot widget (platform 4e): `rgba(17,18,20,.82)`, radius 8, 12 px text, max 240 wide, max 4 per corner, 16 from the edge. Top right is reserved for Diagnostics; the corner is a setting (Bottom left default, bottom right, top left).

- **Compact**: SL mark, place, status with a dot (cyan open or encounter now, green caught, grey not a route). Ctrl+H shows or hides it.
- **Expanded** (click or controller A): place, status, and per other player: color dot, name, state (Lena caught, Jonas open, Sam missed) with creature icon.
- **Death**: a death in your link groups expands the widget for 3 s ("link group 3 died - Sprig - Mossling fainted - 3 linked partners died too"), grey x mark, no red, then back to compact. Off with Reduce motion; the notice (5h) carries the detail.
- Its menu (hide widget, Ctrl+H) opens only on hover or focus. Non-official plugins show a small "Unverified" or "Local" marker on hover or focus (platform).
- Round-1 `5c` (5a-5i 152-164) drew a red flash: reference only.

## 5d Multiview tile overlay

R2 `5d-2`, 343-358 (900 x 620). Friend's tile in Multiview (platform 4e-6-2 shows the collapsed strip).

- **Strip** (20 high, right of the key badge, one strip per tile): collapsed shows the friend's color dot, "SL Route 110 - 4 alive"; expands to max 300 x 120.
- **Tap on the remote tile -> the panel shows their run detail**: "Jonas - Coral Saga: Ember", tile caption "TILE 3 - WATCHING", last event "Jonas - Route 110 caught Voltwing - 2 min ago", their team (icon, nickname, species, level, HP bar; dead grey with x mark) and in a right column your linked partner per creature (your color dot, Max blue). Read only: "changes go through the run screen".
- Round-1 `5d` (5a-5i 166-187): reference only (DS tile).

## 5e Run screen

R2 `5e-map-2`, `5e-map-light-2`, `5e-routes-2`, `5e-log-2` (383-387); 5e-5g `5e-team`, `5e-grave` (28-36); component `source/run-screen.dc.html`, map in `source/region-map.dc.html`, icons `source/creature-icon.dc.html`. 1440 x 900, Player shell (nav Library, Runs (active, indented), Emulation, Controllers, Settings). Dark and light (light: Library, Settings, run screen, Hub). Light player colors at least 4.5:1.

Frame (all tabs): back link "<- Runs"; run name "Ember & Tide", chip "Active - SoulLink"; one player chip per player (color avatar + current place); stats "Deaths 7", "Routes 9 / 31", "Badges 4"; "Rules" (read-only list of the run's rules); tabs Map | Routes 12 | Team & box | Graveyard 7 | Event log 214 (open tab: 2 px cyan bar).

- **Map**: region image read from the player's own game file at runtime (not shipped; Marisol is a placeholder drawing). Markers per route, owners' creatures as small icons with the owner's color dot; link group number on the marker. Players are 26 px avatars; two on the same spot fan out 14 px. Below 60 % zoom, markers merge to clusters ("West - 3 routes"). Legend: player is here, caught (dot = owner), dead (grey, x mark), missed (dashed), link group. Filters: All players, Only me, Open routes (others dim to 35 %). Tap or A on a marker opens a 300 px popover 40 px above it: route, "Link group n" or "no link group yet", one row per player (dot, name, icon, "<species> - alive|dead", "missed - <species> fled", "no encounter yet"), footer "If one of these dies, the others die too." (or "A link group forms when everyone has caught here or the route is closed."). Zoom + - and fit. Controller: D-pad next marker, A open, B close, Y filters, LB/RB zoom; Tab for keyboard. Selected marker has a cyan ring; focus ring on the focused one. Empty state (no map in the game file): "Reading the map from your game file... Routes and catches are listed in the Routes tab meanwhile. The map image stays on this computer." Drawn default for games without a region map: Routes tab first, Map tab hidden.
- **Routes**: matrix routes x players. Filter chips "All 12", "Open 3", "Complete 9"; sort "Route order"; "+ Add by hand" -> 5f-4. Columns: route, one per player (icon + nickname, "open" for no encounter yet, "missed", "<species> - dead"), group, status chip (Linked green, Group dead grey, Open cyan, Gift - no link grey, Broken - missed grey). Current route row highlighted. Rows are selectable.
- **Team & box**: per player (avatar, name, game, place): team of up to 6 (sprite 68 x 56, nickname, level, HP bar), box with count.
- **Graveyard**: columns creature, owner, route, cause ("fainted to <trainer>", "linked partner died", "fainted - undone, then fainted again"), when, link group, "Undo..." -> 5f-2. Linked deaths are grouped by time (same time stamp, same group). Own-cause rows full text, linked rows muted.
- **Event log**: filter All | Automatic | Manual (6); player filter "All players"; "214 events - Export". Rows: time, player avatar, text, tag (`automatic` grey, `manual` amber) and source ("Lena's Player", "Hub", "by Sam - seen by all", "by Jonas - Lena approved"). Manual correction entries name who made them.
- Blocks: tabs, map view, table with selection, sprite, HP bar, stat row, chip.

## 5f Manual correction

Every correction states who sees it, is applied at once and logged as `manual` with the user name. Blocks: anchored popover, confirmation dialog (danger style for undo death), segments, select, text field.

| Id | Source | Trigger | Content |
|---|---|---|---|
| 5f-1 | 5a-5i 203-209, popover 400 | "Doesn't count" (5b, Ctrl+D) | "This encounter doesn't count?", wild <species> - route - detected time. Reason segments Dupe / Shiny / Wrong. "Route 104 stays open for you. Lena, Jonas and Sam see this in the log." Cancel / "Doesn't count" |
| 5f-2-2 | R2 362-369, dialog 420 | Graveyard "Undo..." | "Undo the death of link group 3?" Rows per player (color dot, name, icon, nickname + cause). "All four come back where they were (team or box). Everyone in the run sees 'Undo death of link group 3 (Sprig + 3 linked)' with your reason." Reason field (shown in the log), Cancel / "Undo death" |
| 5f-3-2 | R2 370-377, popover 420 | creature -> "Change link group" | Radio list: "Group 6 - Route 121 / Lena, Jonas, Sam - all alive" (selected), "Group 5 - Route 118 / full - 4 of 4", "No group / unlinked, dies alone". Note: moving also changes who dies with it; others see the change and can undo it. Cancel / "Move to group 6" |
| 5f-4 | 5a-5i 226-232, dialog | Routes table "+ Add by hand" | Route select, species select (icon), nickname, level, state Box / Team / Dead. "Replaces 'missed' on Route 121 and joins link group 6. Marked 'manual' for everyone." Cancel / Add |
| 5f-5 | 5a-5i 233-239, popover | Route -> "Mark as missed" | "Mark Route 112 as missed for you?" "You won't get a creature here. Lena, Jonas and Sam can still catch on Route 112, but their catches won't be linked to you." "Logged as manual - visible to all run members." Cancel / "Mark as missed" |

Round-1 `5f-2` and `5f-3` (5a-5i 211-224) are reference only (group 7, old text). Approval by another player: not required in the drawing, open (README, C). Corrections of other players' creatures are not drawn; the tile overlay is read only.

## 5g Hub run board and stream view

### 5gh Hub run board

5e-5g `5gh`, line 33 (template with `tab=map`, `shell=hub`). The run screen (5e) rendered in the Hub shell, light, as the run detail slot of the Hub Runs page (platform 4jh). Same tabs; for people without the Player open. Hub nav: Library, Saves, Systems & Cores, Clients, Users, Plugins, Runs, Settings. Hub board is read only; whether Hub users that are not run members see it: follows the Hub's run permissions (platform), not drawn here.

### 5gs Stream view

5e-5g `5gs`, 42-58 (1920 x 1080) and 60-71 (480 x 1080). For OBS as a browser source: transparent background (checkerboard in the mock), no interaction, no chrome, stream type scale 13-44 px (platform sheet "stream" size set). Game capture shows through.

- **1920 x 1080**: four player columns in a row on top (avatar in the player color, name, place, six team slots as sprites with HP bars, empty slot dashed, dead grey with x mark); at the bottom left "DEATHS 7" and "LAST EVENTS" (up to 3 lines: dot in the player's color, text, time), bottom right run name and mode ("Ember & Tide - SoulLink - 4 badges") on a dark rounded panel (`rgba(12,13,14,.86)`).
- **480 x 1080** (sidebar): header with run name and mode, players stacked (avatar, name, place, 6 smaller slots), "DEATHS 7", "LAST EVENTS".
- Access: token link, revocable in the run settings, is drawn; security decision open (README, D).

## 5h Notices

5a-5i `5h`, 189-198 (440 wide). Platform toasts (4g), source "SoulLink & Nuzlocke", close "x".

| Kind | Source line | Message (mock) | Actions |
|---|---|---|---|
| important | cyan "- important" | "Lena's Tidepup fainted. Your linked Mossling is dead too." (creature icon with x mark) | "Open run", "Undo death..." |
| info | grey | "Jonas caught Voltwing on Route 110." | - |
| hint | grey | "New route: Route 104. No encounter yet." | - |

Deaths in your link groups are always shown (5i). Max 3 toasts visible, "+1 earlier notice" (platform 4g-2). A paused plugin shows the platform warning toast "Uzume - plugin paused" with "Restart plugin", "Details". Fullscreen behavior: README, E.

## 5i Settings

5a-5i `5i`, 246-257 (1440 x 900). Player Settings -> Plugins -> SoulLink & Nuzlocke -> Settings, generated from the plugin's schema with platform `SettingsRow` only (boolean -> toggle, enum up to 3 -> segments, enum above 3 -> select). Badge "Official". Note "Rules apply to new runs; running runs keep theirs." Changed rows are marked. Groups:

- RULE DEFAULTS: Default mode (Nuzlocke | SoulLink), the rule switches of 5a-4.
- HUD: HUD widget (Off | Compact | Expanded), HUD corner (Bottom left | Bottom right | Top left; "Top right is reserved for Diagnostics").
- NOTICES: Notices while playing (select, "Important only"; "Deaths in your link groups are always shown"), Notices in the Library (toggle, when a run member's creature dies).
- Settings count "All 14 settings" is linked from platform 4b.
