LEGIONUS MAXIMUS: STEAM STORE PAGE FILES

Everything the Steam store page needs, ready to upload in Steamworks (partner.steamgames.com). Open the game's app,
then Edit Store Page. Steamworks shows the exact size it wants on each upload slot; if a size there differs from the
file name here, tell Claude and the picture will be remade.

The pictures are made by python tools/steam/make_store_art.py, which has the game render each scene, so they always
match the game. Run it again after the art changes. The game lays out a fresh field for every run, so look at each
picture afterwards; the script's own notes say how to keep a render that came out well and take the rest again. This
folder is the only one it writes to.


TEXT

short_description.txt       Description tab > Short description (296 of 300 characters)
about_this_game.txt         Description tab > About This Game (written in Steam's [h2], [list] and [b] formatting;
                            its "At a glance" list is the features list)
tags.txt                    Basic Info > Tags and Genres
languages.txt               Basic Info > Supported Languages
system_requirements.txt     System Requirements tab
ai_content_disclosure.txt   Content Survey > AI-generated content


STORE GRAPHICS (Graphical Assets tab, Store Assets)

header_capsule_920x430.png     Header capsule: top of the store page and in most lists
small_capsule_462x174.png      Small capsule: search results and smaller lists
main_capsule_1232x706.png      Main capsule: the front page's featured carousel
vertical_capsule_748x896.png   Vertical capsule: seasonal sales and some store pages
page_background_1438x810.png   Page background: behind the store page (optional)


LIBRARY GRAPHICS (Graphical Assets tab, Library Assets)

library_capsule_600x900.png         Library capsule: the game's cover in players' libraries
library_header_920x430.png          Library header
library_hero_3840x1240.png          Library hero: the wide picture at the top of the game's library page (no logo, on purpose)
library_logo_1280_transparent.png   Library logo: laid over the hero by Steam; place it to the bottom left


ICONS (Basic Info and the Community section)

community_icon_184x184.jpg   Community icon
app_icon.ico                 Client icon (the game's own Windows icon)


SCREENSHOTS (Screenshots tab)

screenshots/01 to 10, all 1920x1080, taken from the game as it draws. Upload them in this order; the first four show
in the store page's sidebar and in search, so they lead with a legion of a hundred in a late run in Germania, the war
elephant's trample in Parthia, Boudica's chariot in Britannia and the legion on a bridge over a ravine. Then
come the falx band's charge in Dacia, the Gaulish king and his stakes, Jupiter's storm, the fort held in Parthia,
a level-up offering cavalrymen and the campaign map of the five provinces.


ACHIEVEMENTS

The game defines its achievements in game/data/content.json. Their icons and the table to enter in Steamworks are
in store/achievements/, made by python tools/steam/make_achievement_icons.py.


TRAILER (Trailers tab)

marketing/recordings/videos/steam_trailer/steam_trailer.mp4, made by python tools/trailer/make_trailer.py (see
docs/Trailer-plan.md). It is kept out of git for its size.


BUILDS

The game itself goes to Steam with python tools/steam/publish.py once tools/steam/steam.json has the real app and
depot ids (every id is 0 for now).


DEVELOPER AND PUBLISHER (Basic Info)

Slow Sunday Games, in both the Developer and the Publisher fields.


STILL TO DECIDE BEFORE SUBMITTING

- Release date: "Coming soon", or a season and year such as "Summer 2027".
- Price in CAD, which Steamworks asks for separately and which Valve reviews.
- The system requirements are estimates; check them on an older computer and a Steam Deck before release.
- The page describes the five provinces, the eight recruits, the six commanders and the three modes now in the game.
  When more land, add them to about_this_game.txt.
