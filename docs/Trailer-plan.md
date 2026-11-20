# Legionus Maximus trailer

The Steam trailer is 68 seconds long. It shows what playing feels like, close in first and wider as it goes, and takes in all five provinces: the commander and a handful of men in a small fight, a level-up offering slingers, cavalry and a ballista crew and a mixed legion at work, the forest felled and a gorge bridged, the bosses read and beaten in Germania and in Dacia's snow, a crowd held round a war elephant in Parthia, Gaul, the gods called on in Dacia, the one great horde under Jupiter's lightning, the fort held in Britannia to the triumph and the map of the five provinces. It is made the same way as the Fishus, Mosaicus and Farmus Maximus trailers: every shot is the game playing itself in movie mode, and an edit scene cuts the shots together on the beat of the game's own music.

## Cut list

One beat is 0.667 seconds of the game's own music, 90 beats a minute, and every cut lands on a beat. The harp layer plays throughout; the drum layer comes in with the mixed legion and drops out for the end card. "2x" shots are shown twice as large, so the soldiers' blows and the missiles read. From the level-up on, the legion is a mixed one: `--give=` adds slingers, cavalry, ballista crews and centurions (and in the larger legions a standard bearer and a medicus) beside the legionaries and archers of `--men=`.

| # | Shot or card | Province | Caption | Beats |
|---|---|---|---|---|
| 1 | Card: Germania, AD 9. | | | 4 |
| 2 | `skirmish`, 2x: the commander and 8 men against a band of 16 | Germania | Lead the legion. | 7 |
| 3 | `levelup`: the level-up opens mid-fight offering a medicus, cavalrymen and a ballista crew, and the ballista crew is picked out and taken | Germania | Choose your men. | 6 |
| 4 | `archers`, 2x: legionaries in front, archers and two ballistas behind, loosing at a band charging in | Germania | Every man fights. | 7 |
| 5 | `fell`: the legion marches into a forest and fells it | Germania | Fell the forest. | 6 |
| 6 | `bridge`: a bridge laid over a ravine and marched across | Germania | Bridge the gorge. | 6 |
| 7 | `whirl`, 2x: the berserker's ring shows and the legion marches out of it | Germania | Step out of the ring. | 7 |
| 8 | `onrush`: in the snow the falx band leader marks a lane through the legion and charges down it with his band, and falx warriors and bears come on behind | Dacia | Read the charge. | 7 |
| 9 | `ravine`: the legion shoves the berserker into a ravine | Germania | Shove them over. | 6 |
| 10 | `hold`: a crowd of horse archers, cataphracts and camel riders round 40 men, and the war elephant tramples through | Parthia | Hold the line. | 6 |
| 11 | `field`: the legion marching along the grass between a wheat field and a village | Gaul | March on Gaul. | 6 |
| 12 | `gods`: the choice of gods over a crowd in the snow, Jupiter picked out and called | Dacia | Call on the gods. | 5 |
| 13 | `reveal`: the one great horde, struck by Jupiter's lightning | | | 6 |
| 14 | `fort`: the fort on the moor ringed by painted warriors, slingers and chariots, swept clear for the VICTORY | Britannia | Hold the fort. | 8 |
| 15 | `map`: the campaign map with Germania, Gaul, Dacia and Parthia won and the road sailing on to Britannia | | Five provinces. | 5 |
| 16 | `endcard`: the legion standing on the grass beside Gaul's wheat below the logo, a dark oval behind the lettering, the scroll and the store badges | Gaul | | 10 |

## How it is made

- `python tools/trailer/make_trailer.py` records every shot that is not recorded yet, then renders the trailer. `shots NAME...` records shots again, `render` renders from the recorded shots, or from a given second into a preview, and `stills DIR` saves a contact sheet of one frame from every segment of the edit and the end card at full size, to check the look before rendering.
- Each shot in `SHOTS` in `make_trailer.py` is the game's own look flags (`--autoplay`, `--go-to`, `--boss`, `--boss-act`, `--god`, `--province`, `--give`, which takes recruits as well as arms) on a fixed seed, `--seed=7`, so it comes out the same every time. `--trailer-shot=NAME` has `main.gd` add `game/tools/trailer/shots.gd`, which mutes the game's music, hides the interface but for the gods' names and the VICTORY (`trailer_hud.gd`), draws the level-up and gods' choices, shows the map without its panel and key hints (`trailer_map.gd`), turns off the pursuit that hunts a marching legion, keeps the legion alive, takes level-ups out of sight, adds men with `--men=N` (or `--men=N:archer`), and stages what no flag does: small bands and medium crowds with the run's own stream stopped, the level-up offering slingers, cavalry and a ballista crew with the ballista picked out and taken, Jupiter picked out from the choice of gods, the legion marching out of the berserker's ring, the falx band leader moved off to the side to mark his lane with a wave of falx warriors behind him, the map with the first four provinces won, the berserker waiting at a ravine's lip, the march into a forest, the march between the wheat and a village, the horde round the fort, the legion standing beside the wheat on the end card, and the end card's field moved down so the legion stands below the logo.
- The shots are recorded at the game's own 640 by 360 and 30 frames a second into `marketing/recordings/content/trailer_shots/`, which git ignores, and the edit shows them three times larger in whole pixels.
- `game/tools/trailer/edit.gd` is the edit: the cut list, the cards and captions in the game's own pixel font at twice its size, the end card and the two music layers. Each shot's own sounds play under the music. The edit is recorded at 1920 by 1080.
- The end card is the game's logo, `game/assets/logo.png`, over the legion beside the wheat, the parchment scroll reading "Wishlist now on Steam", drawn by `tools/trailer/make_scroll.py` with the logo script's scroll, and below it the "Download on the App Store" and "Get it on Google Play" badges side by side, 96 pixels tall, from `tools/trailer/badge_app_store.png` and `badge_google_play.png`.
- The finished trailer, `steam_trailer.avi` and an `.mp4` copy with its sound brought to -16 LUFS, goes to `marketing/recordings/videos/steam_trailer/`, beside its `title.txt`, `description.txt` and `thumbnail.png`, a frame of the end card. Git ignores it for its size.
- The `.mp4` uploaded to Steam is encoded again from the `.avi` at a steady bit rate: `ffmpeg -i steam_trailer.avi -c:v libx264 -b:v 12M -maxrate 16M -bufsize 24M -preset slow -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart steam_trailer.mp4`, run in `marketing/recordings/videos/steam_trailer/`.
