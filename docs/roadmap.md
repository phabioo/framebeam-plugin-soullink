# Roadmap

Status: v0.6.2 (map from the game files or the game picture, full-screen default crop, Game data block with every key; place picker with every place, compact panel, run screen opened from the game, detection from pokemon-core 0.3.1). Depends on FrameBeam plugin API v1 (0.11); see https://github.com/phabioo/framebeam `docs/roadmap.md`.

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
- Map tab: the map is captured from the 3DS bottom screen ("Take map from screen", `fb.video.capture`, permission `video.capture`). Needs a Player with the game picture API; older Players show an update hint. (0.6.0 adds the second source, see below.)
- Open: level caps and map positions of the areas are recorded with the real game; see `docs/architecture.md` open points.

## v0.4.1 fixes from the first playtest

- Place select and Routes list use all places of the game (`areas()` + `locations()`: towns, caves), current place preselected; no more naming places by hand.
- A finished wild battle stays pending until the mon shows up (caught) or the player moves on / the next wild battle / 60 s (missed); deaths only from the party record.
- No "No place yet" events for transient reads; species and place names are resolved at render time when they were unknown at posting time.
- Run screen: first tab selected by default and tracked by id; rules collapsed to a summary.

## v0.6.0 map from the game files

- Map tab source choice: "Take map from screen" (default crop is the full screen, the estimated ORAS crop was wrong and is gone) or "From game files": browse the images pokemon-core found in the player's own RomFS (`map_candidates()`, preview from `map_image(id)`, "Image n of N", previous / next, "Use this map", "still searching" while the core scans). The chosen id is stored per game with the map; positions are rescaled when the source or crop changes. Hidden for a core without these functions.
- Game data block: every diagnostics key, grouped by prefix (one wrapped line per group); closed by default in 0.6.1, chip "Show game data" / "Hide game data", state kept across refreshes.

## v0.6.1 Game data closed by default

- The "Game data" block is closed by default again; the chip "Show game data" opens it and the choice is kept across refreshes. Grouping by key prefix and the no-cap behaviour are unchanged.

## v0.6.2 corrections and detection agree, icon check

- Fix (found in a real Omega Ruby run): "Doesn't count" on a route only changed the view; detection kept the first encounter (missed / encounter) and rejected the next encounter as "used" and the catch as "extra". Now the effective corrections (`doesnt_count`, `mark_missed`, `add`, with reverts) are passed to detection as route overrides, so a later encounter on a reopened route is the first one and its catch counts; the view and detection use the same function (`corrections.route_overrides`). Entries created after a correction carry the correction seq (`rs`), older stored states load unchanged. The dupes clause ignores mons that "don't count".
- Game data block: "Icon check" with the 4 variants from pokemon-core `icon_variants(species, form?)` (>= 0.3.4) for the first team creature, asked once per opening; hidden with an older core.

## Later

Follows the games supported by `framebeam-plugin-pokemon-core`: Gen 7, Gen 4/5, Gen 3, Gen 1/2.

Requires plugin API v1 (FrameBeam 0.11, planned) and `framebeam-plugin-pokemon-core`.
