LEGIONUS MAXIMUS: GOOGLE PLAY STORE LISTING PICTURES

The pictures the Google Play store listing needs, ready to upload in Play Console (play.google.com/console). Open the
app, then Store presence > Main store listing > Graphics.

The pictures are made by python tools/phone/make_store_art.py, which has the game render each scene with its phone
interface and touch controls (--phone) in a window of the store's size, so they always match the game. Run it again
after the art or the interface changes, then look at every picture: the game lays out a fresh field from each scene's
seed and barbarians walk about, so one can land in front of another. Naming a scene (python
tools/phone/make_store_art.py a_hundred_men) takes only that picture again, in every folder here and in
store/app_store/ that holds it. Like the Steam screenshots, they carry no captions. The battle is drawn at a whole
number of screen pixels to the game pixel in every picture (3 on the phone and the 7-inch tablet, 4 on the 10-inch
tablet), and nothing is resized with smoothing.

The phone's interface is the one a player sees: the top bar, the health bar with the commander's health written in
its middle, the testudo and the favour, the round buttons for the testudo, the gods, the palisade, the wall, the bridge
(each with the timber it costs under its picture) and pause, and large text, which a phone starts on. Where the legion marches, a thumb holds the stick. The achievement cards a skipped run earns and the tip a first run
gets at its first ravine are left out, as in the trailer, and the battles are taken with the camp, the column and the
grove already won, so their badges stand off the fighting.


APP ICON

icon_512.png   512x512, 32-bit PNG, every pixel opaque.
               The commander's crested helmet on the red tile with the gold rim: the game's own icon, game/icon.png,
               with its rounded corners filled and enlarged twice, nearest neighbour. It fills the whole square, because
               Google rounds the corners and adds the shadow itself.
               Meets: 512x512 32-bit PNG, at most 1024 KB (this one is 4 KB).


FEATURE GRAPHIC

feature_graphic_1024x500.png   1024x500, 24-bit PNG, no alpha.
               A legion in gold and purple in a sea of barbarians, the trailer's opening shot, with the game's logo over
               it. The battle is rendered at one screen pixel to the game pixel with no interface and enlarged twice,
               and the logo is enlarged by the same two, on a soft shadow so it reads over the crowd. No badges and no
               text but the logo.
               Meets: 1024x500, JPEG or 24-bit PNG without alpha.


PHONE SCREENSHOTS (phone_screenshots/, all 1920x1080 landscape, 24-bit PNG)

Upload them in this order; the first three show first on the listing.

01_a_hundred_men.png              Thirteen minutes into a run in Gaul: a legion of a hundred in gold behind its ring
                                  of stakes, burning arrows flying into the horde and boars charging in, a thumb on the
                                  stick and the gods' button lit.
02_the_war_elephant.png           Parthia's war elephant marks a lane across the desert and charges down it at the
                                  legion, with a band of horse archers riding in.
03_boudicas_chariot.png           Britannia: Boudica, the warrior queen, drives her chariot round a marked curve into
                                  the legion's ranks, her painted warriors with her.
04_the_steppe_on_fire.png         Sarmatia: the Roxolani king has set the steppe alight beside the legion, the fire
                                  running through the wagon circle while his lancers close in.
05_raise_the_testudo.png          Germania: the berserker's red ring marks his whirlwind, the game calls "Raise the
                                  testudo!", and the legion holds it, its shields gold and the testudo button lit.
06_a_bridge_over_the_ravine.png   Hispania: the legion crosses the plank bridge it has laid over a ravine, beside an
                                  olive grove, a thumb on the stick.
07_the_falx_band_charges.png      Dacia's snow: the falx band leader marks a lane through the legion and charges down
                                  it with his band.
08_the_campaign_map.png           The campaign map, the road through the eight provinces, where the next province, the
                                  difficulty and the modes are chosen.

Meets: 2 to 8 phone screenshots, JPEG or 24-bit PNG without alpha, each side 320 to 3,840 px, 16:9. A game needs at
least three 16:9 landscape screenshots of at least 1920x1080 to be shown in Google Play's game recommendations; all
eight qualify.


TABLET SCREENSHOTS

tablet_7_inch_screenshots/    1920x1080 landscape (16:9), 24-bit PNG
tablet_10_inch_screenshots/   2560x1440 landscape (16:9), 24-bit PNG

Each folder holds the phone's eight scenes, in the same order, taken with the phone interface, so every one of the
eight places Google Play allows for each tablet size is filled:

01_a_hundred_men.png
02_the_war_elephant.png
03_boudicas_chariot.png
04_the_steppe_on_fire.png
05_raise_the_testudo.png
06_a_bridge_over_the_ravine.png
07_the_falx_band_charges.png
08_the_campaign_map.png

The game's phone preview lays out every 16:9 screen as a phone, so both sizes show the same 640x360 game pixels with
the phone's buttons and large text: the 7-inch pictures are the phone's, and the 10-inch ones the same view at four
screen pixels to the game pixel.

Meets: up to 8 screenshots for each tablet size, JPEG or 24-bit PNG without alpha, each side 320 to 3,840 px, the long
side at most 2.3 times the short one. They are 16:9, as Google's large-screen guidance asks for a game to be featured
on tablets.


NOT MADE HERE

- The listing's text: app name, short description and full description are in listing.txt, beside this file.
- The answers for the App content forms (privacy policy, app access, ads, content rating, target audience, data safety
  and the rest) are in app_content_answers.txt, beside this file. The privacy policy link waits for the page to be
  published.
- A promo video, optional, given as a YouTube link. The Steam trailer
  (marketing/recordings/videos/steam_trailer/steam_trailer.mp4) can be uploaded to YouTube for it.
- Chromebook and Android XR screenshots, optional.
