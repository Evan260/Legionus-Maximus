# Legionus Maximus

A survivors-style action game in pixel art about leading a Roman legion through the barbarian hordes of Germania, made for Steam (Windows, Mac, Linux and Steam Deck), in 14 languages. Fourth game from Slow Sunday Games, after Farmus, Fishus and Mosaicus Maximus.

You only steer. Every soldier fights on his own, and each level-up adds a recruit, a weapon or a drill, so a run that starts with the commander alone ends with a hundred men in formation holding off a screen full of enemies. Forest ridges and ravines leave only certain ways through, so the legion fells trees for timber to cut new roads, drive palisades and bridge the gorges. Elites with their own abilities come every minute, and the gods of Rome can be called on to clear the field. A run is won by retaking the eagles, burning the sacred grove and marching into the Roman fort that appears at 16 minutes, past the chieftain who comes out to stop you.

## Playing it

The game is made with Godot 4.7. With `GODOT` standing for the Godot executable:

```
GODOT --path game
```

Add `-- --autoplay` to watch the legion play itself, with `--skip=SECONDS` to start later in the run. Every other flag for looking at a screen, a boss or a god is listed in [CLAUDE.md](CLAUDE.md). None of them is saved.

Move with WASD, the arrow keys or the left stick. Space or the south face button forms the testudo, E or the west face button drives a palisade, C or the right shoulder button lays a bridge, and F or the north face button calls the gods once their favour is full.

## The project

| Folder | What is in it |
|---|---|
| `game/` | The Godot project: scenes, GDScript, art, sound and the data files |
| `game/data/` | Every number in `balance.json`, and every recruit, weapon, enemy, province and achievement in `content.json` |
| `game/tests/` | Automated checks and the balance bots |
| `tools/` | Scripts for art, sound, translations, exporting and Steam |
| `art_test/` | The raw PixelLab art before it is packed into the atlas |
| `docs/` | The build plans |
| `builds/` | Exported builds (not kept in git) |

## Checking changes

```
GODOT --headless --path game -- --run-tests
```

It has to print `ALL TESTS PASSED`. After adding or changing any picture or sound, run `GODOT --headless --path game --import`, or the game keeps using the old file.

`GODOT --headless --path game -- --bench` times the simulation with a full horde and a large legion, and `GODOT --headless --path game --script res://tests/balance_bots.gd` plays runs with bots that stand still, march straight, circle or fight, to check how long each one lasts.

## Builds

`python tools/export.py` exports Windows, Mac and Linux into `builds/`, and `--demo` exports the demo.

Pushing a version tag such as `v0.1.0` makes GitHub test the game, build the full game and the demo for Windows, Mac and Linux, sign the Mac app and attach every build to a release. The tag must match `config/version` in `game/project.godot`.

## Art and sound

Everything is pixel art drawn with PixelLab (what each picture cost is in `tools/art/ledger.csv`) and packed into one atlas by `tools/art/build_atlas.py`, so the whole horde draws in one batch. Every sound is a CC0 recording, cut by the scripts in `tools/audio/`, and the music is built from harp and drum recordings by `tools/audio/make_music.py`. Everything shipped with the game is credited in [CREDITS.md](CREDITS.md).
