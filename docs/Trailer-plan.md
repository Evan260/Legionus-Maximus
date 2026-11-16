# Legionus Maximus trailer

The Steam trailer is 69 seconds long. It tells one story: a commander alone in Germania, a legion that grows to a hundred men around him, the hordes and their champions it fights, the gods it calls on, the ground it fights over, Gaul, the fort held to the triumph and the map of the provinces still to take. It is made the same way as the Fishus, Mosaicus and Farmus Maximus trailers: every shot is the game playing itself in movie mode, and an edit scene cuts the shots together on the beat of the game's own music.

## Cut list

One beat is 0.667 seconds of the game's own music, 90 beats a minute, and every cut lands on a beat. The harp layer plays throughout; the drum layer comes in with the first fight and drops out for the end card.

| # | Shot or card | Caption | Beats |
|---|---|---|---|
| 1 | Card: Germania, AD 9. | | 4 |
| 2 | `grow`: the commander alone on the march, fading in | One commander. | 4 |
| 3 | `grow`: men join him until the legion is a hundred strong | A hundred men. | 10 |
| 4 | Card: Against every tribe in the forest. | | 4 |
| 5 | `horde`: a packed late horde round the legion, the drums in | Hold the line. | 8 |
| 6 | `arrows`: a block of archers' burning arrows across a charging wave | | 4 |
| 7 | `whirl`: the berserker at the edge of a small legion, his whirlwind's ring on the grass, twice as large | Berserkers. | 4 |
| 8 | `charge`: the chieftain's charge marked on the ground, then through the ranks | War chiefs. | 4 |
| 9 | `god`: Jupiter's lightning over the horde | Call on the gods. | 6 |
| 10 | `vulcan`: Vulcan's rain of fire | | 4 |
| 11 | `ravine`: the legion marches up and shoves the berserker into a ravine | Shove them over. | 4 |
| 12 | `fell`: the legion marches into a forest and fells it | Fell the forest. | 4 |
| 13 | `bridge`: a bridge laid over a ravine and marched onto | Bridge the gorge. | 4 |
| 14 | `camp`: the barbarian camp burning | Burn their camps. | 4 |
| 15 | `field`: the legion in Gaul's wheat fields | March on Gaul. | 4 |
| 16 | `village`: a Gaulish village | | 4 |
| 17 | `fort`: the Roman fort ringed by the horde | Hold the fort. | 6 |
| 18 | `fort`: the horde swept away and the VICTORY triumph | | 6 |
| 19 | `map`: the painted campaign map | | 6 |
| 20 | `endcard`: the legion marching into Gaul's wheat below the logo, a dark oval behind the lettering, the scroll and the store badges | | 10 |

## How it is made

- `python tools/trailer/make_trailer.py` records every shot that is not recorded yet, then renders the trailer. `shots NAME...` records shots again, `render` renders from the recorded shots, or from a given second into a preview, and `stills DIR` saves a contact sheet of one frame from every segment of the edit and the end card at full size, to check the look before rendering.
- Each shot in `SHOTS` in `make_trailer.py` is the game's own look flags (`--autoplay`, `--go-to`, `--boss`, `--boss-act`, `--god`, `--province`, `--give`) on a fixed seed, `--seed=7`, so it comes out the same every time. `--trailer-shot=NAME` has `main.gd` add `game/tools/trailer/shots.gd`, which mutes the game's music, hides the interface but for the gods' names and the VICTORY (`trailer_hud.gd`), shows the map without its panel and key hints (`trailer_map.gd`), turns off the pursuit that hunts a marching legion, keeps the legion alive, takes level-ups out of sight, adds men with `--men=N` (or `--men=N:archer`), and stages what no flag does: the legion growing from nothing, a wave charging the archers, the chieftain's charge, the berserker waiting at a ravine's lip, the march into a forest, the horde round the fort, and the end card's field moved down so the legion stands below the logo.
- The shots are recorded at the game's own 640 by 360 and 30 frames a second into `marketing/recordings/content/trailer_shots/`, which git ignores, and the edit shows them three times larger in whole pixels.
- `game/tools/trailer/edit.gd` is the edit: the cut list, the cards and captions in the game's own pixel font at twice its size, the end card and the two music layers. Each shot's own sounds play under the music. The edit is recorded at 1920 by 1080.
- The end card is the game's logo, `game/assets/logo.png`, over the legion in the wheat, the parchment scroll reading "Wishlist now on Steam", drawn by `tools/trailer/make_scroll.py` with the logo script's scroll, and below it the "Download on the App Store" and "Get it on Google Play" badges side by side, 96 pixels tall, from `tools/trailer/badge_app_store.png` and `badge_google_play.png`.
- The finished trailer, `steam_trailer.avi` and an `.mp4` copy with its sound brought to -16 LUFS, goes to `marketing/recordings/videos/steam_trailer/`, beside its `title.txt`, `description.txt` and `thumbnail.png`, a frame of the end card. Git ignores it for its size.
