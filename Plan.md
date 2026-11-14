# Legionus Maximus: high level plan

Prices are in CAD.

A survivors-style action game in pixel art. You lead a Roman legion through waves of barbarians. You only steer: every soldier attacks on his own, and each level-up adds a soldier, a weapon or a drill. A run starts with one legionary and ends with a hundred men in formation holding off a screen full of enemies.

Fourth game from Slow Sunday Games, after Farmus, Fishus and Mosaicus Maximus.

## Why this game

Survivors games are the most reliable small-team hit on Steam: [Vampire Survivors](https://store.steampowered.com/app/1794680/) (252,930 reviews), [Brotato](https://store.steampowered.com/app/1942280/) (113,795) and [Megabonk](https://store.steampowered.com/app/3405340/) (101,720), as of 13 November 2026. None is Roman, and none has you leading a growing army instead of one hero. Late runs, with the screen packed with soldiers and barbarians, make clips that sell themselves.

It is 2D, single player and needs no online code. The art is characters, items and ground tiles, which is what PixelLab draws best.

## The run

1. Pick a commander and a province. The run starts with the commander alone.
2. Barbarians come from the edges of the screen, slowly at first and then in floods, with an elite every few minutes and a chieftain at the end.
3. You steer the legion with WASD or a stick. Soldiers attack whatever is in reach on their own.
4. Fallen enemies drop denarii. Picking them up fills the level bar.
5. Each level-up pauses the game and offers three choices, from three kinds:
   - **Recruits:** a new soldier joins the formation (legionary, archer, slinger, cavalryman, standard bearer, medic, ballista crew).
   - **Arms:** a weapon or an upgrade to one (pilum volleys, burning arrows, scorpio bolts, onager stones).
   - **Drills:** an upgrade to the whole legion (faster march, tighter ranks, more armour, wider pickup).
6. The run ends at 20 minutes with the chieftain's defeat, or earlier when the commander falls.
7. Gold carried home buys permanent upgrades and unlocks new commanders, recruits and provinces.

## The legion

The legion follows the commander in formation, so its shape matters:

- Shields in the front rank take hits for the men behind.
- Archers and slingers fire from the back over the front rank.
- Cavalry ride out to the flanks and come back.
- A soldier who loses all his health falls out of the formation. The medic can bring him back.
- **Testudo:** one button locks the shields. The legion moves slowly but arrows bounce off. It refills on a timer. This is the only control besides moving.

Enemies come from every side, so where you steer the legion and when you form the testudo is the whole skill of the game.

## Content

| | Count |
|---|---|
| Commanders, each with a starting bonus | 6 |
| Recruit types, each upgradeable 5 times | 8 |
| Weapons, each upgradeable 5 times, plus a combined form when two are maxed | 12 |
| Drills | 15 |
| Provinces, each with its own ground, enemies and chieftain | 5: Germania, Britannia, Gaul, Dacia, Parthia |
| Enemy types | 4 per province plus 2 elites and a chieftain |
| Permanent upgrades | about 20 |

Steam achievements, Rich Presence, a run timer for speedrunners, and the 14 languages the other games use.

## Look and sound

Top-down pixel art at the same scale as the other games, every sprite made with PixelLab:

- each recruit and enemy drawn from 8 directions, with walking, attacking and falling animations
- weapons, projectiles, pickups and hit effects
- ground tiles and scattered props (trees, rocks, ruins, rivers) for each province
- menus and icons in the gold lettering of the studio logo

The art passes the same outline and palette checks as Fishus. The first step agrees the look on one screen before any rules are built.

Sound: free recorded effects as in the other games (sword hits, shield thumps, horns, crowd of feet). Music from the same harp and drum style as Farmus, with drums rising as the run gets harder.

## Technical

Godot 4.7, GDScript, the same project layout, tests and release workflow as the other three games.

Hundreds of enemies and soldiers on screen at once need a different approach from the other games: all units are plain data in arrays, drawn in one batch per sprite sheet, with a grid for finding what is in reach and no physics bodies. The test for this is 1,000 enemies and 100 soldiers at a steady 60 fps on the Steam Deck.

Reused from the other games: GodotSteam, achievements and Rich Presence, translations and the font setup, the demo edition, the boot splash, the slim engine build, the Windows, Mac and Linux release workflow with Mac signing, and the Steam upload.

## Order of work

1. **Art test.** One screen: the commander and two barbarian types walking and fighting on Germanian grass, made with PixelLab. Agree the look before anything else.
2. **Horde test.** The commander walks while a thousand barbarians chase him, at 60 fps. Real art throughout.
3. **The legion.** Recruits join and follow in formation, attack on their own and fall. Testudo.
4. **Level-ups.** The three-choice screen, the first weapons and drills.
5. **One full province.** Germania from start to chieftain, its enemies and elites, timed waves. This is the point where a run is played start to finish and judged for fun.
6. **Home.** Gold, permanent upgrades and unlocks between runs.
7. **The other four provinces**, the remaining commanders, recruits and weapons.
8. **Finish.** Title and settings, sound and music, achievements, translations, controller and Steam Deck checks, the demo.
9. **Store.** Steam page, trailer and shorts, the same as the other games.

The demo is Germania with three commanders and a 15-minute cap.

Price: \$9.99, the usual price for the genre.
