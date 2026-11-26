# Legionus Maximus: Steam Setup

What has to happen on Steam's side before launch. The game already does its part: it keeps achievements and its count of barbarians defeated in the save, and hands them to Steam whenever Steam is running. How builds get to Steam is in `Steam-publishing.md`, and how GitHub builds them in `Release-builds.md`.

## 1. Connect the game to Steam

GodotSteam 4.24 (the GDExtension build, with Steamworks SDK 1.65, the same libraries as Fishus Maximus's) is in `game/addons/godotsteam/`, for 64-bit Windows, macOS and Linux, with its libraries in Git LFS. Every desktop export carries them: beside the exe on Windows and Linux, and inside the app's `Contents/Frameworks` on a Mac. The Android and iOS presets leave it out.

The autoload `Steamworks` (`game/scripts/steam.gd`) starts Steam with `steamInitEx()` and keeps it only when the status is 0, a running Steam client that owns the game; any other answer leaves everything in the save, and the game plays as normal. It never calls Steam under a flag for looking or testing, headless, or in a build without GodotSteam (`Steamworks.may_start()`, which the tests check). While Steam runs it calls `run_callbacks` every frame, and opening the Steam overlay pauses a run, as losing the window's focus does.

Before the game has its own App ID, Valve's test app Spacewar (App ID 480) shows that Steam starts:

1. Start the Steam client and log in.
2. Put a file named `steam_appid.txt` holding `480` beside the exe in `builds/steam/game/windows/`, or in `game/` when running from the editor.
3. Start the game. Steam shows it as playing Spacewar, and Shift+Tab opens the overlay.

`builds/` is ignored by git, and `publish.py` empties `builds/steam/<target>/` before every build, so a file there never reaches Steam. `.gitignore` does not list `steam_appid.txt`, so delete one put in `game/` afterwards. Achievements sent under 480 land on Spacewar, so use it only to see that Steam starts. Once the real App ID exists, the file can hold that instead; a copy started by Steam itself never needs it.

## 2. The store page

Everything the store page needs is in `store/steam_page`: the four store capsules and the page background, the four library pictures, the community and client icons, ten screenshots at 1920 by 1080, and the text (the short description, About This Game, tags, languages, system requirements and the AI content disclosure). Its `README.txt` says which file goes in which Steamworks slot, and lists what is still to decide before submitting: the release date, the price in CAD, and system requirements checked on an older computer and a Steam Deck. Slow Sunday Games goes in both the Developer and the Publisher fields.

`python tools/steam/make_store_art.py` makes the pictures from the game itself: each capsule and the library hero is a run nine minutes in that the game renders through `tools/steam/store_scene.gd`, enlarged by whole steps with the logo over it (the hero has none, since Steam lays the library logo over it); the page background is the legion at the lip of a ravine, darkened; the screenshots are the game as it draws at 1920 by 1080, interface included. The game lays out a fresh field for every run, so look at each picture afterwards: `--renders=DIR` keeps the renders in DIR and uses them again, so a field that came out well can be kept while the others are redone, and naming a screenshot by its file name without `.png` (such as `07_jupiters_storm`) takes only that one again. It writes only to `store/steam_page`. The text files are written by hand.

The trailer is `marketing/recordings/videos/steam_trailer/steam_trailer.mp4`, made by `python tools/trailer/make_trailer.py` (`Trailer-plan.md`) and kept out of git for its size.

## 3. Achievements and the kills stat

There are 28 achievements, defined in `game/data/content.json` under `achievements`, each with a `kind` that `Steamworks.met()` checks: a win in each of the eight provinces, a win as the Archer captain and as the Engineer, unlocking the Cavalry prefect, the Old centurion and the Legate, forging each of the six forged arms, 1000, 10000 and 100000 barbarians defeated, legions of 25, 50 and 100, and bringing eight arms, all six forged arms or every drill to their last rank in one run.

The table to enter in Steamworks is `store/achievements/achievements.md`. `python tools/steam/make_achievement_icons.py` writes it from `content.json` together with the icons, so it is kept there and not copied here. It gives each achievement's API name, name, description and progress stat, and every field of the `kills` stat. In Steamworks, under App Admin, Stats & Achievements, in the full game's app (and the Playtest's, if it carries the achievements):

1. Make the stat `kills` first (Stats, New Stat), with the fields in that table.
2. Add each achievement with exactly its API name, and set `kills` as the progress stat of `kills_1000`, `kills_10000` and `kills_100000`, from 0 to each one's target.
3. Give each its two icons from `store/achievements`: `<API name>.jpg` once earned and `<API name>_locked.jpg`, the grey one, before. Both are 256 by 256; `sheet.png` shows them all side by side.
4. Publish from the Publish tab. Until the stat is published, Steam refuses it and the game carries on without it.

Earned achievements are kept in the open slot's save and sent to Steam (`setAchievement`, then `storeStats`) as they are earned. During a run the game checks them every second (`steam.check_every` in `balance.json`) and once more when the run ends. Every achievement in a save is sent again at start-up and whenever a game is opened from its slot (`Steamworks.sync()`), so ones earned without Steam, or in the demo, reach Steam later. Each new one also slides in on a card for five seconds (`steam.card_hold`), held back while a choice, the pause menu, the settings or the summary is open.

The stat `kills` is the Steam account's count of barbarians defeated, so the kill achievements count across every slot and every computer. The game reads it once Steam answers `requestUserStats` at start-up. Each finished run adds its kills before the save banks them (`Steamworks.bank_kills()`), counting on from the larger of the stat and the slot's `totals.kills`, so a save that counts more than Steam brings the stat up to it. The kill achievements count the larger of the two (`Steamworks.lifetime_kills()`), and without Steam the slot's own count. Steam's progress pop-up shows each time a run passes another tenth of a target (`steam.progress_steps`).

A new achievement needs an entry in `content.json` of a kind `met()` reads, its picture in the `ART` list of `make_achievement_icons.py`, a run of that script to remake the icons and the table, and the same entry in Steamworks.

## 4. Steam Cloud

Legionus Maximus does not use Steam Cloud, so leave it off in Steamworks. The privacy policy (`https://evan260.github.io/slowsunday/privacy.html`) lists Legionus with achievements, the kills stat and rich presence only, and the kills stat is what carries progress towards the kill achievements to another computer.

The game writes everything to its user folder, which the full game and the demo share: `%APPDATA%\Godot\app_userdata\Legionus Maximus` on Windows, `~/Library/Application Support/Godot/app_userdata/Legionus Maximus` on a Mac and `~/.local/share/godot/app_userdata/Legionus Maximus` on Linux. In it are the three slots `save_1.json` to `save_3.json`, each written through `save_N.json.tmp`, with rolling backups `save_N.json.bak1` to `.bak3` and any slot that cannot be read set aside as `save_N.json.unreadable-STAMP`; `settings.json` with its `.tmp` and `.bak`, shared by every slot; `profile.json.migrated`, once an early build's single save has been moved into slot 1; and `music/`, the player's own music.

To turn Steam Cloud on later, first add it to the privacy policy's Steam section and to Legionus's entry under "Each game at a glance", then use Auto-Cloud, which needs no code, with two root paths per platform:

| Platform | Root | Subdirectory | Pattern |
|---|---|---|---|
| Windows | `WinAppDataRoaming` | `Godot/app_userdata/Legionus Maximus` | `save_*.json` |
| Windows | `WinAppDataRoaming` | `Godot/app_userdata/Legionus Maximus` | `save_*.json.bak*` |
| macOS | `MacAppSupport` | `Godot/app_userdata/Legionus Maximus` | `save_*.json` |
| macOS | `MacAppSupport` | `Godot/app_userdata/Legionus Maximus` | `save_*.json.bak*` |
| Linux | `LinuxXdgDataHome` | `godot/app_userdata/Legionus Maximus` | `save_*.json` |
| Linux | `LinuxXdgDataHome` | `godot/app_userdata/Legionus Maximus` | `save_*.json.bak*` |

The patterns leave out the `.tmp` and `.unreadable` files, the settings and the music, which stay on each computer. If the save files are renamed in `game/scripts/profile.gd`, these patterns must change with them, or cloud saves quietly stop syncing.

## 5. Rich presence

Steam friends see "In the camp" while the player is in the menus, and something like "Marching through Gaul, minute 7, legion of 42" during a run. `Steamworks.presence()` sets `steam_display` to `#Status_Camp`, or to `#Status_Marching` with `province` (the province's id), `minute` and `legion` (the soldiers and the commander), and tells Steam only what has changed, at most every ten seconds (`steam.presence_every`). Without the Steam client it never calls Steam.

The words are in `tools/steam/rich_presence.vdf`, in all 14 of the game's languages, with a `#Province_<id>` token for each province, so a friend reads the province in their own language whatever the player's is. `python tools/write_presence.py` writes it from the `presence.*` rows and the province names in `game/translations/strings.csv`, after `tools/extract_strings.py` and `tools/translate_strings.py`. A test in `game/tests/run_tests.gd` (`test_presence_names_the_province_minute_and_legion`) fails until every language has every token and names every province. Upload the file once, and again whenever it changes:

1. In Steamworks, open the app's Edit Steamworks Settings, then Community, then Rich Presence.
2. Under Localization, choose the file `tools/steam/rich_presence.vdf` and upload it. Steam reads every language from the one file.
3. Publish the change from the Publish tab.

## 6. Demo

The free demo is the same project exported with the "... demo" presets in `game/export_presets.cfg` (`python tools/export.py --demo`), which carry the `demo` feature. It plays only Germania (`demo.province` in `balance.json`), lists the first three commanders (`demo.commanders`: the Tribune, the Archer captain and the Cavalry prefect) and ends each run at 11:00 (`demo.seconds`, 660). The build holds only what the demo shows: `tools/demo_stage.py` exports it from a trimmed copy of `game/` that keeps Germania with its enemies, those three commanders, every recruit, arm, forged form, drill, god and quartermaster upgrade, and the 18 achievements that name nothing it leaves out, and `tools/check_demo.py` fails the export when another province's ground, enemies, props or data got in. The Release section of CLAUDE.md has the details.

The title, and the summary of a run the time limit ended, offer Wishlist on Steam, which opens the full game's store page (`Steamworks.open_store()`), in the Steam client when it runs and in the browser otherwise. It reads the full game's App ID from `demo.store_app_id` in `game/data/balance.json` and stays hidden while that is 0, as it is now. Put the App ID there as soon as Steamworks gives it; `tools/steam/publish.py demo` and the GitHub Steam upload refuse to upload the demo until it matches `targets.game.app_id` in `tools/steam/steam.json`.

The demo saves in the same folder as the full game, so a demo game carries over on the same computer. A save made by a newer version shows in the load list but is never opened or written over, and every save keeps the fields an older build does not know (`Profile.laid_over`). The demo's app needs neither the `kills` stat nor the progress settings (`achievements.md`). Achievements earned in the demo stay in its save, and the full game sends them to Steam the first time it opens that slot with Steam running; kills banked in the demo stay in the slot's `totals.kills`, which the full game's first finished run with that slot brings the stat up to.

In Steamworks, the demo is an app of its own, linked to the main game:

1. On the main game's Steamworks page, under All Associated Packages, DLC, Demos and Tools, create a demo. Steam gives it its own App ID.
2. Set it up like the main game (steps 2 to 6 of the Steamworks setup in `Steam-publishing.md`): three depots, a `testing` branch, App Bundles Are Notarized, and these launch options:
   - `Legionus Maximus Demo.exe`, Windows
   - `Legionus Maximus.app`, macOS (Godot names the Mac app after the project, so the demo's app keeps the full game's name; it comes in `Legionus Maximus Demo.zip`)
   - `Legionus Maximus Demo.x86_64`, Linux + SteamOS
3. Upload `tools/steam/rich_presence.vdf` to the demo's Rich Presence page too (section 5), since the demo sends the same presence.
4. Put its App ID and depots into `targets.demo` in `tools/steam/steam.json`.
5. Upload it with `python tools/steam/publish.py demo`. As with the main game, the build goes live on `testing`, and you set it live on the default branch in Steamworks when the demo is ready to release.
