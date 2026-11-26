# Legionus Maximus: Publishing to Steam

How builds get onto Steam and to players. Once the steps below are done, every update is one command, and everyone with the game on Steam receives it automatically the next time their Steam client updates. Prices here are in CAD.

The four games share these scripts and steps, so this follows Fishus Maximus's and Mosaicus Maximus's `docs/Steam-publishing.md`. What differs here is the names, the WSL folder `~/legionus-steam`, the demo's store App ID, and the Apple credentials, which Legionus copies from another game instead of making its own.

## What is already set up

- `tools/export.py` exports the game for Windows, macOS and Linux into `builds/<platform>/`, each with `Credits and licences.txt` beside it, and with `--demo` the demo into `builds/<platform>-demo/`; `--out DIR` builds into another folder. The macOS build is Godot's `.zip` with a universal app inside, unsigned.
- `tools/steam/publish.py` exports each platform that has a depot into `builds/steam/<target>/` through `tools/export.py`, writes the `app_build.vdf` that steamcmd reads, then hands over to WSL (the Linux that runs inside Windows), where `tools/steam/wsl_build.sh` lays the builds out in `~/legionus-steam/<target>/content`, signs and notarizes the Mac app, and uploads everything. The upload runs in WSL because a Mac app copied through Windows loses its file permissions and will not open, and the Linux game needs its "executable" permission too.
- `tools/steam/wsl_setup.sh` installs Valve's Linux steamcmd and rcodesign (the tool that signs and notarizes a Mac app without a Mac) into `~/legionus-steam` inside WSL.
- `tools/steam/macos_entitlements.plist` gives the Mac app the two permissions the Steam overlay needs; the macOS presets ask for the same two.
- `tools/steam/steam.json` holds the Steam account that uploads builds and the App ID and depots of the Playtest, the game and the demo, each made live on `testing`. The account is empty and every number is 0 until the steps below give the real ones; a depot left at 0 is skipped.
- GodotSteam is in `game/addons/godotsteam/` and goes out with every desktop build; `Steam-setup.md` says how the game uses it and how to test with Valve's App ID 480.
- `Play Legionus Maximus (everything unlocked).bat` in the project folder starts the last Steam build of the game in `builds/steam/game/windows/` with every province, mode and commander open and a million denarii (`--max-state`), without touching the real save. It is not part of any build, so nothing has to be left out of the depots.

The Windows build uses a trimmed Godot engine, `tools/engine/slim.windows.template_release.x86_64.exe`, kept in Git LFS so a fresh clone and the GitHub release builds (`Release-builds.md`) use it. It is built in Farmus Maximus with `python tools/engine/build_template.py`, and is the same file as Farmus Maximus's `tools/engine/bin/farmus.windows.template_release.x86_64.exe`; build and copy it again after every Godot update, and commit it. The macOS and Linux builds use Godot's standard export templates.

## One-time setup on this computer

Open PowerShell in the project folder and run:

```
wsl -u root -- bash tools/steam/wsl_setup.sh
```

It installs steamcmd and rcodesign in `~/legionus-steam` and prints the rcodesign version when it is done. It has not been run for Legionus yet: that folder holds only the output of dry runs, which need neither tool. An upload needs both.

## One-time setup on Steamworks

These steps need you, because they involve your Steam account, payment and tax details.

1. **Join Steamworks.** If Steamworks is already set up for another of the games, only the Steam Direct fee is new: about \$140 CAD (US\$100) per game, paid back once the game earns about \$1,400 CAD (US\$1,000). Otherwise sign up at partner.steamgames.com and fill in the tax and bank forms first; Valve checks these, which can take from a few days to a couple of weeks.
2. **Create the app.** Steamworks gives the game an **App ID**, for example 3456780. Under App Admin, SteamPipe, Depots, it also creates a **depot**, usually numbered one higher, for example 3456781. Set that depot's operating system to Windows, then add two more depots, one set to macOS and one to Linux + SteamOS.
3. **Tell Steam how to start the game.** Under Installation, General, add three launch options:
   - executable `Legionus Maximus.exe`, operating system Windows
   - executable `Legionus Maximus.app`, operating system macOS
   - executable `Legionus Maximus.x86_64`, operating system Linux + SteamOS
4. **Say the Mac app is notarized.** Under Installation, General (or the store page's Platforms section), tick **App Bundles Are Notarized**. Steam has required notarized Mac games since 2019, and the publish script notarizes every Mac build.
5. **Add a test branch.** Under SteamPipe, Builds, create a branch named `testing`. No password is needed.
6. **Publish the settings.** Steamworks changes only apply after you press Publish on the Publish tab.
7. **Create the Playtest.** On the game's Steamworks page, open Playtest and create one. This makes a separate app, "Legionus Maximus Playtest", with its own App ID. Repeat steps 2 to 6 for it, adding Mac and Linux depots only if Mac and Linux testers are wanted.
8. **Fill in the numbers.** Put the account name and the numbers into `tools/steam/steam.json`:
   - `account`: the Steam account that uploads builds. Valve recommends a separate Steam account that has only the permission to upload builds, so your own account is never used by a script.
   - `targets.playtest`: the Playtest's App ID and its depots (`windows`, and `macos` and `linux` if it has them).
   - `targets.game`: the main game's App ID and its three depots. The same App ID also goes in `demo.store_app_id` in `game/data/balance.json`, where the demo reads it for its Wishlist on Steam button; `publish.py demo` refuses to upload until the two match.
   - `targets.demo`: the demo's App ID and its three depots (`Steam-setup.md`, section 6).
9. **Log in to steamcmd once.** In PowerShell, run:

   ```
   wsl ~/legionus-steam/steamcmd/steamcmd.sh +login YOUR_ACCOUNT +quit
   ```

   Type the password, then the Steam Guard code from the email or the Steam phone app. steamcmd remembers the login, so the publish script never needs the password.

The achievements, the kills stat, rich presence and the store page are in `Steam-setup.md`.

## The Apple credentials

Steam needs the Mac app signed with a Developer ID and notarized by Apple. `wsl_build.sh` does both when `~/legionus-steam/apple` holds the certificate as `developer_id.p12`, its password in `p12_password` and the notarization key as `api_key.json`. Without them a dry run leaves the Mac app unsigned and says so, and an upload with a Mac depot stops.

Legionus has no `apple_setup.sh` of its own, since one Developer ID and one key serve all four games. Make them once in Fishus Maximus, as its `docs/Steam-publishing.md` describes under "Signing the Mac app" (exporting the Developer ID from the Mac's keychain, or making a new one as Farmus Maximus's describes). Fishus Maximus's WSL folder already has rcodesign, which the key step needs. Then copy them here:

```
wsl cp -r ~/fishus-steam/apple ~/legionus-steam/
```

If another game's folder holds them instead, copy from that one, such as `~/farmus-steam/apple`. None of the four holds them yet. The GitHub workflow signs with its own copies of the same certificate and key, the secrets in `Release-builds.md`.

## Giving a tester access

1. In Steamworks, open the Playtest app and request Steam keys (a handful is plenty).
2. Send one key to the tester. They redeem it in Steam under Games, Activate a Product on Steam, and the Playtest appears in their library.
3. They right-click it, choose Properties, Betas, and pick `testing`. They only do this once; from then on Steam keeps them on the newest test build.

## Sending an update

Ask Claude to "push an update to the playtest", or run:

```
python tools/steam/publish.py playtest --note "Gentler surge"
```

The script imports the project, builds the game for every platform with a depot (the demo through its trimmed copy, checked by `tools/check_demo.py`), signs and notarizes the Mac app (Apple's check usually takes a few minutes), uploads it and makes it live on the `testing` branch. Testers get it the next time Steam updates, usually within minutes when Steam is open. The date, the git commit and the note appear next to the build in Steamworks, under SteamPipe, Builds.

`--dry-run` builds every platform, signs the Mac app if the Apple credentials exist, and lays everything out in `~/legionus-steam/<target>/content` inside WSL without notarizing or uploading, to check that everything is in order. It needs neither the ids in `steam.json` nor steamcmd, so it works before Steamworks is set up; with no ids yet it builds all three platforms. Godot's exports stay in `builds/steam/<target>/` on Windows and play from there, which is where the everything-unlocked launcher finds the game.

## The default branch and release

Steam only lets a script make a build live on a branch such as `testing`. For the default branch, the one every buyer gets, go to SteamPipe, Builds in Steamworks and set the build live there yourself. This is Valve's safeguard against a script releasing a broken build to everyone. When the game launches, the same command uploads with `game` instead of `playtest`, and you set each release live on the default branch by hand. The free demo works the same way with `demo`, which builds through `tools/export.py --demo`; its Steamworks setup is in `Steam-setup.md`.
