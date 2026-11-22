# Legionus Maximus trailer

The Steam trailer is one minute long (58.7 seconds) and cut the way survivors-like trailers are: it opens on the busiest moment of a run with the interface showing, lands the logo over it, then tells the run from its start, a handful of men growing into a legion of a hundred, its armour turning from iron to gold, and climbs through all eight provinces to the gods, a chieftain's fall and the victory. Every word is a short caption in large letters over the play; there are no black cards. The legion is on the march in nearly every shot, as a player always is. Every shot is the game playing itself in movie mode, and an edit scene cuts the shots together on the beat of the game's own war theme.

## Music

The music is `battle_war_theme.ogg`, 103.36 beats a minute, one beat every 0.5805 seconds with the first at 0.0697 seconds. Every cut lands on a beat. The trailer plays four stretches of the track, each from a beat of the track to a beat of the trailer, so the beat never breaks:

| Trailer beats | Track | What it is |
|---|---|---|
| 0 to 63 | from the start | the track's opening, at full strength from the first second |
| 63 to 67 | beats 275 to 279 (2:40) | the last quiet bar before the track's big return |
| 67 to 87 | beat 279 on (2:42) | the return, which lands as Jupiter's lightning strikes |
| 87 to the end | beat 471 on (4:33) | the track's own last bars and final note |

A boom lands with the logo and with the drop into the quiet bar, and a horn with the end card.

## Cut list

The top bar shows a run at that point of the story (level, clock, legion and kills, counting on from there); the objective markers and the key hints are left out. The legion's armour and cloth follow the story too: iron and red at the start, bronze and white in the middle, gold and purple from the provinces on.

| # | Shot | Province | Caption | Beats |
|---|---|---|---|---|
| 1 | `hook`: a gold legion of a hundred marching through the great horde, some 370 barbarians spread a pace apart over the whole field and closing in from every side | Germania | | 7 |
| 2 | `hook` carries on, darkened, and the logo lands with a flash and a jolt | Germania | | 4 |
| 3 | `skirmish`, twice as large: the commander and six men marching into a small band | Germania | START WITH A FEW MEN | 4 |
| 4 | `levelup`, twice as large: the level-up offers a medicus, cavalry and a ballista crew, and the ballista is taken | Germania | | 4 |
| 5 | `march`: a legion of a hundred marching between a wheat field and a village | Gaul | GROW A LEGION OF 100 | 4 |
| 6 | `archers`, twice as large: archers and ballistas loosing at a band charging in | Germania | YOU MARCH. THEY FIGHT. | 4 |
| 7 | `dodge`, twice as large: the berserker's whirlwind marks its ring on the ground and the legion marches out of it | Germania | DODGE BOSS ATTACKS | 4 |
| 8 | `livery0`, `livery1`, `livery2`, twice as large: one moment of a fight cut three times, the legion in iron, bronze and gold | Germania | IRON, BRONZE, GOLD | 2, 2, 4 |
| 9 | `fell`, twice as large: the legion marches into a forest and fells it | Germania | FELL FORESTS | 4 |
| 10 | `ravine`: the legion shoves the berserker into a ravine, then wheels and marches along the lip | Germania | SHOVE THEM OFF CLIFFS | 4 |
| 11 | `p_germania` to `p_sarmatia`: one quick cut in each province, the gold legion marching through a ring of the province's own barbarians: Germania's forest, Gaul's wheat, Britannia's stone circle, Hispania's olives, Aegyptus' palms, Parthia's war elephant, Dacia's falx charge in the snow and Sarmatia's kurgans, with the province named above the caption | all eight | CONQUER 8 PROVINCES | 2 each |
| 12 | `gods`: the choice of gods over the great horde, Jupiter picked out, in the music's quiet bar | Germania | | 4 |
| 13 | `reveal`: Jupiter's lightning on the great horde, on the music's return, opening on a flash | Germania | | 8 |
| 14 | `chief`: the legion holds its line facing the war chief, who charges in with a crowd, fights its front rank and falls there | Germania | TOPPLE THEIR WARLORDS | 6 |
| 15 | `fort`: the fort on the moor ringed by a horde, swept clear for the VICTORY on the shot's third beat, and the victory screen's rays | Britannia | | 6 |
| 16 | `endcard`: the gold legion beside Gaul's wheat under the logo, the scroll and the store badges | Gaul | | 14 |

## How it is made

- `python tools/trailer/make_trailer.py` records every shot that is not recorded yet, then renders the trailer. `shots NAME...` records shots again, `render` renders from the recorded shots, or from a given second into a preview, and `stills DIR` saves a contact sheet of one frame from every segment of the edit and the end card at full size, to check the look before rendering.
- Each shot in `SHOTS` in `make_trailer.py` is the game's own look flags (`--autoplay`, `--go-to`, `--boss`, `--boss-act`, `--god`, `--province`, `--give`, `--livery`) on a fixed seed, `--seed=7`, so it comes out the same every time. `--trailer-shot=NAME` has `main.gd` add `game/tools/trailer/shots.gd`, which mutes the game's music, keeps the legion alive, takes level-ups out of sight, turns off the pursuit that hunts a marching legion, adds men with `--men=N`, keeps the legion marching with `--march=X,Y`, draws the field larger round the commander with `--zoom=Z` while the interface keeps its size, and sets the top bar's level, clock and kills with `--hud=LEVEL,SECONDS,KILLS`. It also stages what no flag does: the great horde of the opening, the gods' choice and the lightning, its barbarians laid out a pace apart over the whole field with fresh ones walking in from beyond the edges as others fall, small bands and medium crowds with the run's own stream stopped, the level-up's choice, Jupiter picked out from the gods, the legion marching out of the berserker's ring, the berserker at a ravine's lip and the legion wheeling along it once he is over, the falx band's charge, the march into a forest, the march between the wheat and a village, the war chief charging the legion's front rank and falling there, the horde round the fort and the end card's legion beside the wheat. `trailer_hud.gd` draws the interface as the trailer shows it.
- The shots are recorded at the game's own 640 by 360 and 30 frames a second into `marketing/recordings/content/trailer_shots/`, which git ignores, and the edit shows them three times larger in whole pixels.
- `game/tools/trailer/edit.gd` is the edit: the cut list, the music's four stretches and the sounds laid over them, the captions in the game's own pixel font at three times its size in the logo's gold, landing larger and settling with a small bounce over a dark band, the logo landing over the hook and the end card. Each shot's own sounds play under the music. The edit is recorded at 1920 by 1080.
- The end card is the game's logo, `game/assets/logo.png`, over the legion beside the wheat, the parchment scroll reading "Wishlist now on Steam", drawn by `tools/trailer/make_scroll.py` with the logo script's scroll, and below it the "Download on the App Store" and "Get it on Google Play" badges side by side, 96 pixels tall, from `tools/trailer/badge_app_store.png` and `badge_google_play.png`.
- The finished trailer, `steam_trailer.avi` and an `.mp4` copy with its sound brought to -16 LUFS, goes to `marketing/recordings/videos/steam_trailer/`, beside its `title.txt`, `description.txt` and `thumbnail.png`: a frame of `thumb`, the opening battle recorded again without the top bar, at full brightness with the logo four times its size over a soft dark glow, and no badges or text, so it reads at a thumbnail's size. Git ignores it for its size.
- The `.mp4` uploaded to Steam is encoded again from the `.avi` at a steady bit rate: `ffmpeg -i steam_trailer.avi -c:v libx264 -b:v 12M -maxrate 16M -bufsize 24M -preset slow -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart steam_trailer.mp4`, run in `marketing/recordings/videos/steam_trailer/`.
