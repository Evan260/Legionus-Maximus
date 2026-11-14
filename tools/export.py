"""Build the game for Windows, macOS and Linux, each into its own folder under builds/.

  python tools/export.py                 every platform
  python tools/export.py windows linux   only those
  python tools/export.py --demo          the demo (the "demo" feature) for every platform
GODOT may name the Godot console exe; the WinGet install is used otherwise.
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = "Legionus Maximus"
GODOT = os.environ.get("GODOT", str(Path.home() / "AppData/Local/Microsoft/WinGet/Packages"
    / "GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"))
PRESETS = {
    "windows": ("Windows", f"{GAME}.exe"),
    "macos": ("macOS", f"{GAME}.zip"),
    "linux": ("Linux", f"{GAME}.x86_64"),
}
DEMO_PRESETS = {
    "windows": ("Windows demo", f"{GAME} Demo.exe"),
    "macos": ("macOS demo", f"{GAME} Demo.zip"),
    "linux": ("Linux demo", f"{GAME} Demo.x86_64"),
}


def godot(*args):
    result = subprocess.run([GODOT, "--headless", "--path", str(ROOT / "game"), *args], capture_output=True, text=True,
                            encoding="utf-8", errors="replace")
    if result.returncode != 0:
        sys.exit(f"Godot failed: {' '.join(args)}\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}")
    return result


def export(platform, folder, demo=False):
    preset, name = (DEMO_PRESETS if demo else PRESETS)[platform]
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / name
    target.unlink(missing_ok=True)
    result = godot("--export-release", preset, str(target))
    if not target.exists() or "ERROR:" in result.stdout + result.stderr:
        sys.exit(f"the {platform} export failed:\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}")
    print(f"built {platform}{' demo' if demo else ''}: {target}")
    return target


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("platforms", nargs="*", help="windows, macos or linux; every platform when none is given")
    parser.add_argument("--demo", action="store_true", help="build the free demo")
    args = parser.parse_args()
    unknown = [p for p in args.platforms if p not in PRESETS]
    if unknown:
        parser.error(f"unknown platform {', '.join(unknown)}; choose from {', '.join(PRESETS)}")
    godot("--import")
    for platform in args.platforms or PRESETS:
        export(platform, ROOT / "builds" / (f"{platform}-demo" if args.demo else platform), args.demo)


if __name__ == "__main__":
    main()
