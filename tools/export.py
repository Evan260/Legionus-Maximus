"""Build the game for Windows, macOS and Linux, each into its own folder under builds/.

  python tools/export.py                 every platform
  python tools/export.py windows linux   only those
  python tools/export.py --demo          the demo (the "demo" feature) for every platform
  python tools/export.py --out DIR       into DIR/<platform> (or DIR/<platform>-demo) instead of builds/
GODOT may name the Godot console exe; the WinGet install is used otherwise.
The demo is exported from a copy of game/ holding only what the demo shows (tools/demo_stage.py) and checked
afterwards by tools/check_demo.py.
"""
import argparse
import os
import subprocess
import sys
from contextlib import nullcontext
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = "Legionus Maximus"
CREDITS_FILE = "Credits and licences.txt"
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


def godot(*args, project=None):
    result = subprocess.run([GODOT, "--headless", "--path", str(project or ROOT / "game"), *args], capture_output=True, text=True,
                            encoding="utf-8", errors="replace")
    if result.returncode != 0:
        sys.exit(f"Godot failed: {' '.join(args)}\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}")
    return result


def project_for(demo):
    """The project to export from: the demo's trimmed copy for the demo, game/ itself otherwise."""
    # Only the demo needs Pillow and numpy, which a machine that builds the full game may not have.
    import demo_stage

    return demo_stage.staged(GODOT) if demo else nullcontext(ROOT / "game")


def export(platform, folder, demo=False, project=None):
    """Exports one platform into folder, from `project` (from project_for) when given, so several share one demo copy."""
    if demo and project is None:
        with project_for(True) as staged:
            return export(platform, folder, demo, staged)
    preset, name = (DEMO_PRESETS if demo else PRESETS)[platform]
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / name
    target.unlink(missing_ok=True)
    result = godot("--export-release", preset, str(target), project=project)
    if not target.exists() or "ERROR:" in result.stdout + result.stderr:
        sys.exit(f"the {platform} export failed:\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}")
    if demo:
        import check_demo

        check_demo.check(target)
    # The licences of the sounds, the font and Godot ask for their notices to ship with the game.
    godot("--script", "res://tools/write_credits.gd", "--", f"--out={folder / CREDITS_FILE}")
    print(f"built {platform}{' demo' if demo else ''}: {target}")
    return target


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("platforms", nargs="*", help="windows, macos or linux; every platform when none is given")
    parser.add_argument("--demo", action="store_true", help="build the free demo")
    parser.add_argument("--out", type=Path, default=ROOT / "builds", help="the folder to build into (builds/ by default)")
    args = parser.parse_args()
    unknown = [p for p in args.platforms if p not in PRESETS]
    if unknown:
        parser.error(f"unknown platform {', '.join(unknown)}; choose from {', '.join(PRESETS)}")
    godot("--import")
    with project_for(args.demo) as project:
        for platform in args.platforms or PRESETS:
            export(platform, args.out.resolve() / (f"{platform}-demo" if args.demo else platform), args.demo, project)


if __name__ == "__main__":
    main()
