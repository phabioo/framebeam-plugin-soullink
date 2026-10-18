# Roadmap

Status: v0.5.1 (place picker with every place, Game data diagnostics, map crop; map from the game picture, compact panel, run screen opened from the game, detection from pokemon-core 0.3.1). Depends on FrameBeam plugin API v1 (0.11); see https://github.com/phabioo/framebeam `docs/roadmap.md`.

## v0.1 MVP on Omega Ruby / Alpha Sapphire

- Run rules as switches: first encounter per route, dupes and shiny clause, defeated = dead, SoulLink pairs per route, optional shared-type and team-pair rules, nickname and level-cap hints. Horde encounters do not count as first encounter by default (switchable).
- Detection via `framebeam-plugin-pokemon-core`: location, encounter (kind), catch, team, box change, death, badges.
- Manual correction of everything (encounter does not count, undo death, change pairing, add Pokémon); every change is in the event log with the user name.
- Views: in-game tab (team, location status, partner of the route, graveyard), HUD, Multiview tile overlay, run screen (routes table routes x players, map, log, graveyard), Hub run board and session view (also as OBS source).
- Design screens 5a to 5i (Claude Design handoff, accepted 2026-10-11): done, see [design/README.md](design/README.md). Open design questions are listed there.
- Playtest with the group, then feedback into platform and plugin.

## v0.4.0 panel, run screen, detection from pokemon-core 0.3

- Panel per design 5b at about 300 px (run header, location card, encounter hint, team with partners, graveyard, footer); the full run screen (5e, all corrections) opens with `fb.ui.open("screen")` (button, toast action, Ctrl+R); without that call the panel says to update FrameBeam.
- Routes are the encounter areas of the game (`areas()`, key `loc:<location id>`), names read from the game and stored short in the own run state so other players, the tile strip and the Hub show names; old `route-N` keys still render.
- Detection: `encounters()` seq (first per area, hordes, shiny and dupes clause), catch by team/box diff, death by live hp 0 or battle hp 0, badges from `badges()`, pairs-differ-primary-type via `species_info`.
- Map tab: the map is captured from the 3DS bottom screen ("Take map from screen", `fb.video.capture`, permission `video.capture`); the RomFS map candidates of pokemon-core are no longer used. Needs a Player with the game picture API; older Players show an update hint.
- Open: level caps and map positions of the areas are recorded with the real game; see `docs/architecture.md` open points.

## v0.4.1 fixes from the first playtest

- Place select and Routes list use all places of the game (`areas()` + `locations()`: towns, caves), current place preselected; no more naming places by hand.
- A finished wild battle stays pending until the mon shows up (caught) or the player moves on / the next wild battle / 60 s (missed); deaths only from the party record.
- No "No place yet" events for transient reads; species and place names are resolved at render time when they were unknown at posting time.
- Run screen: first tab selected by default and tracked by id; rules collapsed to a summary.

## Later

Follows the games supported by `framebeam-plugin-pokemon-core`: Gen 7, Gen 4/5, Gen 3, Gen 1/2.

Requires plugin API v1 (FrameBeam 0.11, planned) and `framebeam-plugin-pokemon-core`.
