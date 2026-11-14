# Legionus Maximus

A survivors-style game in pixel art where the player steers a growing Roman legion through barbarian hordes. Fourth game from Slow Sunday Games. [Plan.md](Plan.md) is the plan and [Features.md](Features.md) the full feature set; the game in `game/` is the prototype.

## Commands

Godot is `C:\Users\evand\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`.

- Tests: `godot --headless --path game -- --run-tests` (must print ALL TESTS PASSED)
- Speed: `godot --headless --path game -- --bench` (simulation time per update with about 1,000 barbarians)
- Look without playing: `godot --path game -- --autoplay`, with `--skip=SECONDS` to start later in the run and `--shot=PATH --at=SECONDS` to save a screenshot and quit
- Windows build: `godot --headless --path game --export-release "Windows"` writes `builds/windows/Legionus Maximus.exe` with the slim engine from Fishus

## Layout

- `game/scripts/sim.gd`: the whole run as plain data (legion, horde, missiles, coins, levels). No nodes, so tests drive it directly.
- `game/scripts/arms.gd`: the twelve weapons and six forged forms, on their timers, with burning ground, oil, caltrops and the stake ring as zones.
- `game/scripts/upgrades.gd`: the level-up choices, rerolls and banishes.
- `game/scripts/world_view.gd`, `hud.gd`: drawing. Every sprite is in one atlas so the horde draws in one batch.
- `game/scripts/main.gd`: input, screens and the command-line modes (`--screen=settings|summary|title|pause`, `--text-size=2`).
- `game/scripts/controls.gd`: the default keys and pad buttons and the player's rebinding laid over them; `screens/`: title, camp, pause, settings and the run summary.
- `game/data/balance.json`: every number.
- `game/scripts/lang.gd` (autoload `Lang`): the 14 languages, their fonts and the saved or system language. Every player-facing string goes through `tr("English words")`, and `content.json` names, texts and histories get a key such as `content.recruits.legionary.name` that `Content.localize()` lays over the English. `--lang=CODE` shows another language.
- Translations: `python tools/extract_strings.py` fills `game/translations/strings.csv`, `python tools/translate_strings.py` sends the empty cells to Azure (key in `.env`), `python tools/write_presence.py` writes `tools/steam/rich_presence.vdf`; reimport the project afterwards. English, French, German, Spanish, Italian and Portuguese draw in Silkscreen, Polish, Turkish, Russian and Ukrainian in Fusion Pixel 10 px (16 px at large text), Chinese, Japanese and Korean in Fusion Pixel 8 px. Draw text through `Ui.font()` and `Ui.px`, and wrap it with `Ui.lines_of`, which breaks between letters in Chinese and Japanese.

## Art

All art is PixelLab, made with `tools/art/pixellab.py` (token in `.env`, never in code), costs in `tools/art/ledger.csv`.

- Characters are 48 px (the chieftain 64 px), low top-down, selective outline, from 8 directions. Walking and running use PixelLab's built-in `walking` and `running` motions, which loop and cost nothing.
- Ground and props are made with Pro Flash using `art_test/raw/style_ref.png` (the commander and a barbarian) as the style image, or they come out in a brighter cartoon style that does not match.
- `tools/art/batch_art.sh` makes the prototype's art, `build_atlas.py` packs it into `game/assets/atlas.png`, `make_seamless.py` and `remove_leaves.py` make the ground tile.
- No mirroring: every direction is drawn.

## Rules

- The horde is packed arrays with a flat grid; keep per-enemy work out of dictionaries, and check `--bench` after touching `_move_enemies`.
- Packed arrays copy when changed through another container, so change them by name.

## Release

- Pushing a tag like `v0.1.0` runs `.github/workflows/release.yml` ("Release builds"). The tag must match `config/version` in `game/project.godot` or the run stops. It can also be started by hand with `gh workflow run "Release builds"`.
- Jobs: the tests, then a full and a demo export for Windows, macOS and Linux, then macOS signing, then a GitHub release for tags. Demo builds come from the "... demo" presets, which carry the `demo` feature (`OS.has_feature("demo")`).
- Mac builds ship unsigned until the Apple secrets (`MACOS_CERTIFICATE_P12` and the rest, see `.github/scripts/sign_macos.sh`) are set on the repo.
- Steam uploads stay off until `tools/steam/steam.json` has real app and depot ids and the repo variable `STEAM_UPLOAD` is `true`. Every id is 0 for now.
- Local export: `python tools/export.py [--demo] [windows|macos|linux]`.
