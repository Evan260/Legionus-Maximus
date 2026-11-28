# Legionus Maximus: Release builds

GitHub builds the game in the cloud: it runs the tests, exports Windows, macOS and Linux for the full game and the free demo, signs and notarizes the Mac apps, and for a version tag publishes a GitHub release with every build attached. The workflow is `.github/workflows/release.yml`; the scripts it runs are in `.github/scripts/`.

The repository, Evan260/Legionus-Maximus, is public, so GitHub Actions is free, Mac runners included.

## Starting a build

There are two ways.

**A version tag** builds everything and publishes a release. First set the new version in `config/version` in `game/project.godot`, which the Windows exe and the Mac app take their versions from, since their presets set none of their own, commit, then in the project folder:

```
git tag v1.0.0
git push origin v1.0.0
```

The tag must be `v` followed by `config/version`, or the tests job stops with "Version mismatch". A tag with a hyphen, such as `v1.1.0-beta1`, is published as a pre-release. `config/version` is 1.0.0 and there is no tag yet. The phone builds are not made here, and keep their own numbers: `version/code` in the "Android release" preset, and the short version and version in the "iOS" preset.

**Run workflow** builds everything without a release, to try a build. On GitHub, open the repository's **Actions** tab, choose **Release builds** on the left, press **Run workflow**, pick the branch (normally `main`) and press the green **Run workflow** button; `gh workflow run "Release builds"` does the same. The form also asks which Steam app to upload to, which matters only once Steam uploads are switched on (below). These builds are labelled `dev-` and the commit, such as `Legionus-Maximus-dev-1a2b3c4-windows.zip`.

## What the workflow does

| Job | Runs on | What it does |
|---|---|---|
| Tests | Ubuntu | For a tag, checks it against `config/version`; runs `tools/extract_strings.py` and fails if the translation sheet would change; imports the project and runs `--run-tests`, failing unless it prints `ALL TESTS PASSED` and on any `SCRIPT ERROR` line |
| Export (six at once) | Ubuntu | Exports Windows, macOS and Linux for the full game and the demo with `tools/export.py` (`--demo` for the demo, which first installs Pillow, numpy and OpenCV, since `tools/demo_stage.py` cuts the demo's atlas), each with `Credits and licences.txt` |
| Sign macOS (two at once) | Mac | Signs the full game's and the demo's apps and their libraries with the Developer ID certificate, notarizes them with Apple, staples the tickets and checks them with Gatekeeper |
| GitHub release | Ubuntu | Only for a tag: creates the release "Legionus Maximus v1.0.0" with notes made from the commits and attaches every build, or replaces the files of a release that already exists |
| Steam upload | Ubuntu | Only when the repository variable `STEAM_UPLOAD` is `true` (below) |

Godot 4.7.2 and its Linux and macOS export templates are downloaded from Godot's GitHub releases, checked against the SHA-512 sums pinned in `.github/scripts/install_godot.sh`, and kept in the Actions cache, so later runs skip that download. The Windows export uses the trimmed engine `tools/engine/slim.windows.template_release.x86_64.exe` from Git LFS (`Steam-publishing.md`), so the release exe is the same small one built on this computer.

## Where the builds appear

**Every run:** open the run on the Actions tab and scroll to **Artifacts** at the bottom. Each download is a zip holding one build:

- `release-full-windows`, `release-demo-windows`: the game folder zipped
- `release-full-linux`, `release-demo-linux`: a `.tar.gz`, which keeps the Linux executable permissions that a plain zip from GitHub would lose
- `release-full-macos`, `release-demo-macos`: the signed and notarized app with the credits, zipped on the Mac, or `-macos-unsigned.zip` when the Apple secrets are not set
- `macos-export-full-macos`, `macos-export-demo-macos`: Godot's unsigned export, only used by the signing job

**A tag:** the repository's **Releases** page gets a release named after the tag with these files:

- `Legionus-Maximus-v1.0.0-windows.zip`
- `Legionus-Maximus-v1.0.0-macos.zip`
- `Legionus-Maximus-v1.0.0-linux.tar.gz`
- `Legionus-Maximus-Demo-v1.0.0-windows.zip`, `Legionus-Maximus-Demo-v1.0.0-macos.zip`, `Legionus-Maximus-Demo-v1.0.0-linux.tar.gz`

Each holds one folder, `Legionus Maximus` or `Legionus Maximus Demo`. The demo's Mac app is named `Legionus Maximus.app`, since Godot names the app after the project.

## The secrets

The Mac signing needs six secrets. They have the same names in all four game repositories, so the values made once serve Farmus Maximus, Fishus Maximus, Mosaicus Maximus and Legionus Maximus alike. How to make each one is written out in Fishus Maximus's `docs/Release-builds.md`, under "The secrets" (Farmus Maximus's and Mosaicus Maximus's say the same), so it is not repeated here. None is set on this repository yet, so the Mac builds come out unsigned and the run shows a notice saying so; if only some are set, the signing job fails and names the missing ones.

| Secret | What it holds |
|---|---|
| `MACOS_CERTIFICATE_P12` | The Developer ID Application certificate with its private key, as a base64 .p12 |
| `MACOS_CERTIFICATE_PASSWORD` | The password chosen when exporting that .p12 |
| `APPLE_API_KEY_P8` | The App Store Connect API key, the .p8 file in base64 |
| `APPLE_API_KEY_ID` | That key's Key ID |
| `APPLE_API_ISSUER_ID` | The Issuer ID shown above the keys |
| `APPLE_TEAM_ID` | The Apple Developer team ID, ten letters and digits |
| `STEAM_USERNAME` | Later, for the Steam upload: the Steam account that uploads builds |
| `STEAM_CONFIG_VDF` | Later, for the Steam upload: steamcmd's saved login in base64 |

Add each one on GitHub under the repository's **Settings**, **Secrets and variables**, **Actions**, **New repository secret**, with the name exactly as above. The GitHub command line does the same from PowerShell; it asks for each value, so nothing lands in the shell history:

```
gh secret set APPLE_TEAM_ID --repo Evan260/Legionus-Maximus
```

GitHub never shows a secret again once saved, and the workflow keeps them out of its logs. To replace one, add it again with the same name.

## The Steam upload

The Steam job is written but switched off. It uploads the builds from the same run with steamcmd and makes them live on the `testing` branch, never the default branch, which is still set live by hand in Steamworks (`Steam-publishing.md`). It refuses a target whose branch in `tools/steam/steam.json` is not `testing`, a demo whose `demo.store_app_id` does not match the game's App ID, and a Mac depot without the signed Mac build, so the Apple secrets come first. To switch it on:

1. Fill in `tools/steam/steam.json` (the account, and the App ID and depots of `playtest`, `game` and `demo`; `Steam-publishing.md`, step 8), put the game's App ID in `demo.store_app_id` in `game/data/balance.json`, and commit them.
2. Log steamcmd in once in WSL, as in `Steam-publishing.md` step 9, with the account that uploads builds. That saves the login in `~/Steam/config/config.vdf` inside WSL.
3. Copy that saved login as base64 from PowerShell:

   ```
   wsl bash -c "base64 -w0 ~/Steam/config/config.vdf" | Set-Clipboard
   ```

   Add it as the secret `STEAM_CONFIG_VDF`, and the account name as `STEAM_USERNAME`.
4. On the same Settings page, choose the **Variables** tab and add the repository variable `STEAM_UPLOAD` with the value `true`.
5. A tag then uploads to the Playtest. To upload tags to another app, add the variable `STEAM_TARGET` with `game` or `demo`. **Run workflow** has a menu to pick the app for that run.

If Steam ends the saved login, the job fails asking for a new `STEAM_CONFIG_VDF`; log in again in WSL and repeat step 3. To switch uploads off, set `STEAM_UPLOAD` to `false`.

## The iPhone build

`.github/workflows/ios.yml` builds the game for iPhone and iPad and uploads it to App Store Connect, where it reaches TestFlight once Apple has processed it, usually within half an hour. It runs for every `v*` tag, and by hand from Actions, iPhone build, Run workflow.

| Job | Runs on | What it does |
|---|---|---|
| Export the Xcode project | Ubuntu | Exports the `iOS` preset with Godot's iOS template. On Linux that makes the Xcode project, not a finished app |
| Sign and upload to TestFlight | Mac | Sets the build number to the workflow's run number, signs with the Apple Distribution certificate and the game's App Store profile, archives, and uploads with the App Store Connect API key |

Its secrets were made through the App Store Connect API on 27 November 2026, and copies of the files are kept outside the repo:

| Secret | What it holds |
|---|---|
| `IOS_DIST_P12` | The Apple Distribution certificate with its private key, as a base64 .p12 |
| `IOS_DIST_P12_PASSWORD` | That .p12's password |
| `IOS_PROFILE` | This game's App Store provisioning profile, named after the game with "App Store", in base64 |
| `ASC_API_KEY_P8` | The App Store Connect API key "Slow Sunday setup" (Admin access), the .p8 file in base64 |
| `ASC_API_KEY_ID` | That key's Key ID |
| `ASC_API_ISSUER_ID` | The Issuer ID shown above the keys |
| `APPLE_TEAM_ID` | The Apple Developer team ID, as for the Mac build |

The certificate and the profile expire on 28 November 2027. Make new ones before then and replace `IOS_DIST_P12`, `IOS_DIST_P12_PASSWORD` and `IOS_PROFILE`.

On the iPhone the full game is sold as `<bundle id>.full_game` (for this game `com.slowsunday.<game>.full_game`), because Apple wants every product id unique across all of a developer's apps; Google Play keeps `full_game`. `FullGame.apple_product()` makes the id.
