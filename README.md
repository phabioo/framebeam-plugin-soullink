# FrameBeam Plugin: SoulLink

SoulLink/Nuzlocke runs for FrameBeam: rules, detection, team and route views, Hub run board.

Status: **v0.4.0** for Omega Ruby / Alpha Sapphire: run rules, detection through `framebeam-plugin-pokemon-core` 0.3 (places and routes from the game, encounters, catches, deaths, badges), link groups, manual corrections, a compact in-game panel, the run screen (opened from the game), HUD, tile strip, run view and Hub board. Details: [docs/architecture.md](docs/architecture.md).

Requires FrameBeam 0.11 or later (plugin API v1) and `framebeam-plugin-pokemon-core`, which the Start dialog adds to the run automatically (manifest `requires`). Part of [FrameBeam](https://github.com/phabioo/framebeam); plugin interface: `docs/architecture/12-plugins.md` there. Plan: [docs/roadmap.md](docs/roadmap.md). UI design (screens 5a to 5i): [docs/design/](docs/design/README.md).

## Releasing

1. Bump `version` in `plugin/manifest.json` and merge.
2. Release `vX.Y.Z` (must equal the manifest version), either by pushing the tag or by running "Release" in Actions on `main` with the tag as input; the latter creates the tag at that commit. The `Release` workflow runs the checks, builds the unsigned `.fbplugin` (`python3 tools/package.py`) and attaches it to the GitHub release. Re-running with an existing tag replaces the asset.
3. Run "Publish plugin" in phabioo/framebeam with this repository and the tag; it downloads, signs and indexes the package.

License: GPL-3.0-or-later, see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). Contributions under the [CLA](CLA.md).

Pokémon and Nintendo are trademarks of their owners. This project is not affiliated with them and contains no game content.
