# Roadmap

Status: planned, nothing implemented. Depends on FrameBeam plugin API v1 (0.11, planned); see https://github.com/phabioo/framebeam `docs/roadmap.md`.

## v0.1 MVP on Omega Ruby / Alpha Sapphire

- Run rules as switches: first encounter per route, dupes and shiny clause, defeated = dead, SoulLink pairs per route, optional shared-type and team-pair rules, nickname and level-cap hints. Horde encounters do not count as first encounter by default (switchable).
- Detection via `framebeam-plugin-pokemon-core`: location, encounter (kind), catch, team, box change, death, badges.
- Manual correction of everything (encounter does not count, undo death, change pairing, add Pokémon); every change is in the event log with the user name.
- Views: in-game tab (team, location status, partner of the route, graveyard), HUD, Multiview tile overlay, run screen (routes table routes x players, map, log, graveyard), Hub run board and session view (also as OBS source).
- Design screens 5a to 5i come from the Claude Design handoff and are added to `docs/design/` in this repository.
- Playtest with the group, then feedback into platform and plugin.

## Later

Follows the games supported by `framebeam-plugin-pokemon-core`: Gen 7, Gen 4/5, Gen 3, Gen 1/2.

Requires plugin API v1 (FrameBeam 0.11, planned) and `framebeam-plugin-pokemon-core`.
