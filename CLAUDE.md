# Legionus Maximus

A survivors-style game in pixel art where the player steers a growing Roman legion through barbarian hordes. Fourth game from Slow Sunday Games. [Plan.md](Plan.md) is the plan and [Features.md](Features.md) the full feature set; the game in `game/` is the prototype.

## Commands

Godot is `C:\Users\evand\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`. Run it with `--path game`; the flags after `--` go to the game, which reads them in `main.gd`.

- Import after adding assets: `godot --headless --path game --import`
- Tests: `godot --headless --path game -- --run-tests` (must print ALL TESTS PASSED)
- Speed: `godot --headless --path game -- --bench` (simulation time per update at the horde cap (balance max_enemies) and a 100-soldier legion; keep it under 5 ms, and run it three times after touching `_move_enemies` or the legion)
- Balance: `godot --headless --path game --script res://tests/balance_bots.gd` plays runs with five bots (standing still, marching straight, circling, facing the crowd, facing with recruits first). Put `{"modes": [...], "seeds": [...], "balance": {...}, "enemies": {...}}` in `game/tests/balance_overrides.json` to try numbers without editing the data (delete it afterwards). After the November 2026 tuning, standing still and marching straight die within about 5 minutes and facing the crowd reaches the chieftain about 4 times in 10.
- Look without playing: `godot --path game -- --autoplay`, with `--skip=SECONDS` to start later in the run and `--shot=PATH --at=SECONDS` to save a screenshot and quit
- Every other flag, all for looking or testing and none of them saved to the profile:
  - `--chieftain-at=S` brings the chieftain at that second; `--hold-choice` with `--autoplay` leaves a level-up open
  - `--hard`, `--endless`, `--decimatio` start the run in that mode
  - `--screen=camp|quartermaster|tablinum|map|commanders|settings|title|pause|summary` opens a screen with a sample profile (`--page=controls` for the key page of the settings)
  - `--lang=CODE`, `--text-size=1|2`, `--commander=ID`, `--as-demo`, `--card=ID` (an achievement card), `--give=ID,ID:RANK` (arms and drills to start with)
- Windows build: `godot --headless --path game --export-release "Windows"` writes `builds/windows/Legionus Maximus.exe` with the slim engine from Fishus. Run it with `-- --autoplay --shot=PATH --at=10` to check it.
- Boot splash: `python tools/art/make_boot_splash.py` after the logo changes, then copy the colour it prints into `boot_splash/bg_color` in `project.godot`.

## Layout

- Autoloads (`project.godot`): `Profile` (`profile.gd`, the saved profile), `Lang` (`lang.gd`, languages and fonts), `Audio` (`audio.gd`, sounds and the two music layers), `Steamworks` (`steam.gd`, achievements and rich presence).
- `game/scripts/sim.gd`: the whole run as plain data (legion, horde, missiles, coins, levels). No nodes, so tests drive it directly. `legion.gd` is the soldiers and their formation, `horde.gd` the barbarians as packed arrays, elites, chieftains, chests and supply carts.
- `game/scripts/terrain.gd`: the props on the field as plain data, seeded per run. Trees, rocks and logs are solid; `refresh()` builds a grid of the solid ones around the commander and the horde reads it directly in `_move` for speed. `clear()` empties the field for tests.
- `game/scripts/arms.gd`: the twelve weapons and six forged forms, on their timers, with burning ground, oil, caltrops and the stake ring as zones.
- `game/scripts/upgrades.gd`: the level-up choices, rerolls and banishes.
- `game/scripts/content.gd`: reads `game/data/content.json` (every recruit, arm, forged form, drill, enemy, province, commander, quartermaster upgrade and achievement, with its name, text, history and art keys). Grounds are `game/assets/grounds/<province>.png`, found by `available_art()` as `ground:<province>`, so a province turns on with no code change once its ground, props and enemies exist. An entry whose art keys are not in the atlas or the icons folder stays hidden, so content can be built before its art.
- `game/data/balance.json`: every number. `credits.json` feeds the credits.
- `game/scripts/world_view.gd`, `hud.gd`, `atlas.gd`: drawing. Every sprite is in one atlas so the horde draws in one batch.
- `game/scripts/main.gd`: input, the state machine and the command-line modes. `game.gd` says whether this is the demo.
- `game/scripts/screens/`: title, camp, quartermaster, tablinum, map, commanders, pause, settings and the run summary, all drawn through `ui.gd`. `controls.gd` has the default keys and pad buttons and the player's rebinding laid over them.
- `game/tests/run_tests.gd`: every test. `WAITING_FOR_ART` (recruits) and `NO_ICON_YET` (arms, forged forms, drills, empty since every icon exists) list entries whose art is not drawn yet; shrink them as art lands (see ART-NEEDED.md).
- `ART-NEEDED.md`: every art key still missing, the PixelLab command for each, its cost and what it unlocks.
- `game/scripts/lang.gd` (autoload `Lang`): the 14 languages, their fonts and the saved or system language. Every player-facing string goes through `tr("English words")`, and `content.json` names, texts and histories get a key such as `content.recruits.legionary.name` that `Content.localize()` lays over the English. `--lang=CODE` shows another language.
- Translations: `python tools/extract_strings.py` fills `game/translations/strings.csv` (and clears the cells of a line whose English changed), `python tools/translate_strings.py` sends the empty cells to Azure (key in `.env`), `python tools/write_presence.py` writes `tools/steam/rich_presence.vdf`; reimport the project afterwards. English, French, German, Spanish, Italian and Portuguese draw in Silkscreen, Polish, Turkish, Russian and Ukrainian in Fusion Pixel 10 px (16 px at large text), Chinese, Japanese and Korean in Fusion Pixel 8 px. Draw text through `Ui.font()` and `Ui.px`, and wrap it with `Ui.lines_of`, which breaks between letters in Chinese and Japanese.

## Art

All art is PixelLab, made with `tools/art/pixellab.py` (token in `.env`, never in code), costs in `tools/art/ledger.csv`.

- Characters are 48 px (the chieftain 64 px), low top-down, selective outline, from 8 directions. Walking and running use PixelLab's built-in `walking` and `running` motions, which loop and cost nothing.
- Ground and props are made with Pro Flash using `art_test/raw/style_ref.png` (the commander and a barbarian) as the style image, or they come out in a brighter cartoon style that does not match.
- `tools/art/batch_art.sh` makes the prototype's art, `build_atlas.py` packs it into `game/assets/atlas.png` and takes new units and props through its `UNITS` and `PROPS`; `make_seamless.py` and `remove_leaves.py` make the ground tile and `make_boot_splash.py` the boot splash.
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
