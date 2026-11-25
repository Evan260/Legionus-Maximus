LEGIONUS MAXIMUS: APP STORE PICTURES

The pictures the App Store listing needs. Screenshots are uploaded in App Store Connect (appstoreconnect.apple.com):
Apps, the game, the version being prepared, then Previews and Screenshots, with one tab per display size.

The pictures are made by python tools/phone/make_store_art.py, which has the game render each scene with its phone
interface and touch controls (--phone) in a window of the store's size, so they always match the game. Run it again
after the art or the interface changes, then look at every picture: the game lays out a fresh field from each scene's
seed and barbarians walk about, so one can land in front of another. Naming a scene (python
tools/phone/make_store_art.py a_hundred_men) takes only that picture again, here and in store/google_play/. Like the
Steam screenshots, they carry no captions, and they are taken as the Google Play ones are (see
store/google_play/README.txt): the objectives already won, no achievement cards, a thumb on the stick where the legion
marches.

The game draws 640x360 game pixels, widened to 782x360 on the iPhone's long screen and deepened to 640x480 on the
iPad's squarer one, and an iPhone or iPad blows that view up by a scale that is not a whole number. So that every game
pixel keeps the same width, each picture is the view enlarged by the next whole number, 4 on the iPhone and 5 on the
iPad, and trimmed evenly at the edges to Apple's size, nothing resized with smoothing. The interface is held in from
the trimmed edges as far as the game keeps it from a phone's rounded corners, so none of it is cut, and the battle
shows a little larger and a little less of the field round it than on the device.


APP ICON

icon_1024.png   1024x1024 PNG, no alpha channel, square corners.
                The commander's crested helmet on the red tile with the gold rim: the game's own icon, game/icon.png,
                with its rounded corners filled and enlarged four times, nearest neighbour. Apple rounds the corners
                itself.
                Meets: the App Store icon, 1024x1024, no transparency and no alpha channel, no rounded corners.
                App Store Connect takes this icon from the build rather than from an upload, so it goes into Godot's
                iOS export preset, in its Icons section (the 1024x1024 App Store icon), once the game has one.


IPHONE SCREENSHOTS (iphone_6.9_inch_screenshots/, all 2868x1320 landscape, PNG without alpha)

01_a_hundred_men.png              Thirteen minutes into a run in Gaul: a legion of a hundred in gold behind its ring
                                  of stakes, burning arrows flying into the horde and boars charging in, a thumb on the
                                  stick.
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
08_a_level_up.png                 A level-up in the large text a phone starts on: cavalrymen, a medicus or caltrops.

The campaign map is left out here: trimmed to the iPhone's size, the names along the top of the map would be cut. The
level-up takes its place.

Meets: the 6.9-inch iPhone display size, which takes 2868x1320 in landscape (or 2796x1290 or 2736x1260); 1 to 10
screenshots, PNG or JPEG without alpha. Apple scales these down for the smaller iPhones, so this one size covers them.


IPAD SCREENSHOTS (ipad_13_inch_screenshots/, all 2752x2064 landscape, PNG without alpha)

01_a_hundred_men.png              The legion of a hundred in Gaul behind its stakes, a thumb on the stick.
02_the_war_elephant.png           Parthia's war elephant charging down his marked lane at the legion.
03_boudicas_chariot.png           Boudica's chariot on its marked curve into the legion in Britannia.
04_the_steppe_on_fire.png         The Sarmatian steppe on fire beside the legion, the Roxolani king's lancers closing in.
05_raise_the_testudo.png          The berserker's red ring in Germania and the legion holding the testudo.
06_a_bridge_over_the_ravine.png   The legion on its bridge over a ravine in Hispania.
07_the_falx_band_charges.png      The falx band's charge down its marked lane in Dacia's snow.

An iPad is a tablet to the game, so its buttons are smaller and its text the normal size. The elephant is brought a
little nearer the legion than on the other screens, so the trimmed side does not cut him. The campaign map and the
level-up are left out here: trimmed to the iPad's size, the map's panel would lose its right side, and the level-up's
list of the legion's arms at the left edge would be cut.

Meets: the 13-inch iPad display size, which takes 2752x2064 in landscape (or 2732x2048); required when the game runs
on iPad; 1 to 10 screenshots, PNG or JPEG without alpha. Apple scales these down for the smaller iPads.


NOT MADE HERE

- App previews, the optional videos of 15 to 30 seconds for each display size.
- The listing's text: name (30 characters), subtitle (30), promotional text (170), description (4,000) and keywords
  (100). store/google_play/listing.txt is written to suit both stores and is a starting point.
- A support link and a privacy policy link, and the age rating questionnaire, which are forms in App Store Connect.
  store/google_play/app_content_answers.txt has the answers Google asks for, most of which Apple asks too.
