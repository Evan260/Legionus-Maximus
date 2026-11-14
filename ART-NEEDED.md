# Art still needed

Prices are in USD, with the CAD amount alongside (1 USD is about 1.39 CAD).

Everything here is content that is built and tested but stays hidden in the game until its art exists, because an entry whose art keys are missing is not offered (`Content.ready()`). None of it is made yet. `python tools/art/pixellab.py balance` shows what is left on the PixelLab account.

## How to make it

Run every command from the repo root. Each one appends its real cost to `tools/art/ledger.csv`.

Characters are 48 px (chieftains and the elephants 64 px), low top-down, selective outline, 8 directions. Walking and running use PixelLab's built-in loops through `--template-action`. Where a unit is an animal or a rider the character command passes `--template dog`, `bear` or `horse`; if PixelLab rejects one of those names, drop `--template` and describe the animal in the prompt. Define these once in the shell:

```bash
PL="python tools/art/pixellab.py"; R=art_test/raw
DIRS="south south-west west north-west north north-east east south-east"
id(){ python -c "import json;print(json.load(open('$R/$1/character.json'))['character_id'])"; }
# anim NAME walking|running: animates all 8 directions of a finished character, 7 at a time
anim(){ n=0; for d in $DIRS; do $PL animate "$(id $1)" x --template-action $2 --direction $d --out-dir $R/$1/t_$2_$d & n=$((n+1)); [ $((n % 7)) -eq 0 ] && wait; done; wait; }
# prop NAME WxH "prompt": Pro Flash with the style image, so props match the rest of the game
prop(){ $PL proflash "$3, top-down game prop, selective outline, transparent background, warm afternoon light" $2 --style $R/style_ref.png --style-use "match this art style, palette, shading and pixel density" --transparent --out $R/props3/$1.png; }
# icon NAME "prompt": 32 px side-view icon straight into the game
icon(){ $PL pixen "$2, game upgrade icon, centered, warm afternoon light" 32x32 --view side --outline "selective outline" --detail "medium detail" --transparent --raw --out game/assets/icons/$1.png; }
```

Estimates come from the averages in `tools/art/ledger.csv`. A 48 px character costs about \$0.084, a 64 px one \$0.134, one animated direction about \$0.056 (so about \$0.45 for the 8 directions; the built-in loops often cost less, so treat it as a ceiling), a Pro Flash prop about \$0.117, a Pro Flash ground about \$0.111 and a pixen icon about \$0.022.

## After the art lands

1. Units: add the name to `UNITS` in `tools/art/build_atlas.py` (`"walking"` for recruits and commanders, `"running"` for enemies). Props: add `"name": "props3/name.png"` to `PROPS`. Icons need no step, they are read from `game/assets/icons/` as they are.
2. Rebuild the atlas: `python tools/art/build_atlas.py` (rewrites `game/assets/atlas.png` and `atlas.json`), then `godot --headless --path game --import`.
3. Shrink the test lists in `game/tests/run_tests.gd`: delete each recruit id from `WAITING_FOR_ART` and each arm, forged form or drill id from `NO_ICON_YET` once all its art keys exist, so the test that every implemented entry has all its art covers it from then on.
4. Run `godot --headless --path game -- --run-tests` and `-- --bench`, then look at it with `--autoplay --give=ID` or `--commander=ID`.

Ground per province needs one code change besides the art: the game draws a single `game/assets/ground.png`, and `Content.available_art()` does not yet list `ground:<province>`. When a ground is made, save it as `game/assets/ground_<province>.png`, make `available_art()` report `ground:<id>` for each file, and have `world_view.gd` load the ground of the province being played. Make each tile seamless with `tools/art/make_seamless.py` and `tools/art/remove_leaves.py` as for the Germania ground.

## Recruits

Each recruit needs a unit and an icon (icons are under Icons below). The cavalryman also unlocks the cavalry prefect, the centurion the old centurion and the standard bearer the legate.

### unit:slinger

Unlocks: recruit slinger. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Roman auxiliary slinger, light leather cap, tunic, leather sling in one hand and a pouch of stones at the belt, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/slinger
anim slinger walking
```

### unit:cavalry

Unlocks: recruit cavalry, commander cavalry_prefect. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Roman cavalryman on a brown horse, mail shirt, oval shield on his arm, red cloak, long spatha, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --template horse --out-dir $R/cavalry
anim cavalry walking
```

### unit:standard_bearer

Unlocks: recruit standard_bearer, commander legate. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Roman standard bearer, lion pelt over his helmet, mail shirt, carrying a tall legion standard topped with a gold hand and silver discs, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/standard_bearer
anim standard_bearer walking
```

### unit:medicus

Unlocks: recruit medicus. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Roman army medic, plain tunic with a red cross-belt, leather satchel of herbs and bandages, no armour, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/medicus
anim medicus walking
```

### unit:ballista

Unlocks: recruit ballista. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "two Roman artillerymen turning a wheeled wooden ballista with a heavy bolt loaded, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/ballista
anim ballista walking
```

### unit:centurion

Unlocks: recruit centurion, commander old_centurion. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Roman centurion, iron helmet with a tall transverse crest, silvered mail, greaves, vine staff in one hand, red cloak, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/centurion
anim centurion walking
```

Subtotal: \$3.19 (about \$4.44 CAD).

## War dogs (arm)

The dog pack of the War dogs weapon.

### unit:war_dog

Unlocks: arm war_dogs. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Roman war dog, large mastiff with a spiked leather collar, grey-brown coat, snarling, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --template dog --out-dir $R/war_dog
anim war_dog running
```

Subtotal: \$0.53 (about \$0.74 CAD).

## Germania enemies

The club warrior, spearman and the chieftain exist already.

### unit:axe_thrower

Unlocks: enemy axe_thrower. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Germanic warrior holding a throwing axe overhead, bare chest, trousers, long hair, small round shield on his back, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/axe_thrower
anim axe_thrower running
```

### unit:wolf

Unlocks: enemy wolf. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "grey forest wolf, shaggy fur, snarling, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --template dog --out-dir $R/wolf
anim wolf running
```

### unit:berserker

Unlocks: enemy berserker. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Germanic berserker in a wolf pelt, wild eyes, bare muscular arms, huge two-handed axe, blood-red war paint, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/berserker
anim berserker running
```

### unit:war_band_leader

Unlocks: enemy war_band_leader. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Germanic war band leader, iron helmet with horns, chainmail, large round shield and a long sword, fur cloak, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/war_band_leader
anim war_band_leader running
```

Subtotal: \$2.13 (about \$2.96 CAD).

## Britannia enemies

Ordinary enemies, two elites and the warrior queen who is the province's chieftain.

### unit:painted_warrior

Unlocks: enemy painted_warrior. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Briton warrior, body covered in blue woad spirals, trousers, round shield, short sword, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/painted_warrior
anim painted_warrior running
```

### unit:briton_slinger

Unlocks: enemy briton_slinger. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Briton slinger, woad-painted face, leather jerkin, a sling whirling in one hand, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/briton_slinger
anim briton_slinger running
```

### unit:chariot

Unlocks: enemy chariot. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "light Briton war chariot with two small ponies, a woad-painted warrior standing in the wicker car, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --template horse --out-dir $R/chariot
anim chariot running
```

### unit:druid_acolyte

Unlocks: enemy druid_acolyte. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "young druid in a hooded green-brown robe with a gnarled wooden staff and a sickle at the belt, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/druid_acolyte
anim druid_acolyte running
```

### unit:chariot_charge

Unlocks: enemy chariot_charge. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "heavy Briton war chariot with two charging ponies, scythe blades on the wheels, a woad-painted warrior with a spear, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --template horse --out-dir $R/chariot_charge
anim chariot_charge running
```

### unit:druid

Unlocks: enemy druid. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "old druid in a long white robe with mistletoe crown, a staff topped with a crescent, long grey beard, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/druid
anim druid running
```

### unit:warrior_queen

Unlocks: enemy warrior_queen. Estimate \$0.58 (about \$0.81 CAD).

```bash
$PL character "Briton warrior queen in a war chariot drawn by two ponies, long red hair, gold torc, spear, woad paint, warm afternoon light" 64x64 --view "low top-down" --outline "selective outline" --template horse --out-dir $R/warrior_queen
anim warrior_queen running
```

Subtotal: \$3.77 (about \$5.25 CAD).

## Gaul enemies

Ordinary enemies, two elites and the king who is the province's chieftain.

### unit:gaul_swordsman

Unlocks: enemy gaul_swordsman. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Gaulish swordsman, bronze helmet, long moustache, oval shield, long iron sword, checked trousers, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/gaul_swordsman
anim gaul_swordsman running
```

### unit:gaul_horseman

Unlocks: enemy gaul_horseman. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Gaulish horseman on a chestnut horse, mail shirt, oval shield, long lance, checked cloak, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --template horse --out-dir $R/gaul_horseman
anim gaul_horseman running
```

### unit:gaul_archer

Unlocks: enemy gaul_archer. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Gaulish archer, leather cap, tunic and checked trousers, a short bow drawn, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/gaul_archer
anim gaul_archer running
```

### unit:boar

Unlocks: enemy boar. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "wild boar with tusks, bristly brown fur, charging, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --template dog --out-dir $R/boar
anim boar running
```

### unit:champion

Unlocks: enemy champion. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Gaulish champion, gold torc, mail shirt, plumed bronze helmet, huge shield and long sword, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/champion
anim champion running
```

### unit:horn_blower

Unlocks: enemy horn_blower. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Gaulish horn blower sounding a tall bronze carnyx war horn shaped like a boar's head, checked cloak, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/horn_blower
anim horn_blower running
```

### unit:gaul_king

Unlocks: enemy gaul_king. Estimate \$0.58 (about \$0.81 CAD).

```bash
$PL character "Gaulish king, golden helmet with wings, gold torc, mail shirt, red cloak, very long sword, an armoured bodyguard half-seen behind him, warm afternoon light" 64x64 --view "low top-down" --outline "selective outline" --out-dir $R/gaul_king
anim gaul_king running
```

Subtotal: \$3.77 (about \$5.25 CAD).

## Dacia enemies

Ordinary enemies, two elites and the king behind the shield wall.

### unit:falx_warrior

Unlocks: enemy falx_warrior. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Dacian warrior swinging a two-handed curved falx blade, wool cap, tunic, trousers, no shield, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/falx_warrior
anim falx_warrior running
```

### unit:dacian_archer

Unlocks: enemy dacian_archer. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Dacian archer in a pointed felt cap, sheepskin vest, short recurve bow, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/dacian_archer
anim dacian_archer running
```

### unit:wolf_standard_bearer

Unlocks: enemy wolf_standard_bearer. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Dacian standard bearer carrying the draco, a tall pole topped with a bronze wolf head and a long cloth windsock tail, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/wolf_standard_bearer
anim wolf_standard_bearer running
```

### unit:mountain_bear

Unlocks: enemy mountain_bear. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "large brown mountain bear, heavy shoulders, snow on its back, snarling, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --template bear --out-dir $R/mountain_bear
anim mountain_bear running
```

### unit:falx_band

Unlocks: enemy falx_band. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Dacian elite falx fighter, iron helmet, scale armour, a falx in each hand, fur cloak, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/falx_band
anim falx_band running
```

### unit:priest

Unlocks: enemy priest. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Dacian priest in a long white tunic and tall pointed cap, a gold-tipped staff, long beard, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/priest
anim priest running
```

### unit:dacian_king

Unlocks: enemy dacian_king. Estimate \$0.58 (about \$0.81 CAD).

```bash
$PL character "Dacian king, scale armour, gold helmet with a wolf crest, falx, a wall of large shields carried by guards in front of him, warm afternoon light" 64x64 --view "low top-down" --outline "selective outline" --out-dir $R/dacian_king
anim dacian_king running
```

Subtotal: \$3.77 (about \$5.25 CAD).

## Parthia enemies

Ordinary enemies, two elites (the cataphract charge and the war elephant) and the shah.

### unit:horse_archer

Unlocks: enemy horse_archer. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Parthian horse archer on a lean bay horse, pointed cap, long tunic, bow drawn backward, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --template horse --out-dir $R/horse_archer
anim horse_archer running
```

### unit:cataphract

Unlocks: enemy cataphract. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Parthian cataphract, rider and horse both covered in scale armour, long lance, conical helmet, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --template horse --out-dir $R/cataphract
anim cataphract running
```

### unit:camel_rider

Unlocks: enemy camel_rider. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Parthian camel rider on a tan camel, turban, curved sword, round shield, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/camel_rider
anim camel_rider running
```

### unit:parthian_slinger

Unlocks: enemy parthian_slinger. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Parthian slinger, light tunic, turban, sling whirling, desert sandals, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --out-dir $R/parthian_slinger
anim parthian_slinger running
```

### unit:cataphract_charge

Unlocks: enemy cataphract_charge. Estimate \$0.53 (about \$0.74 CAD).

```bash
$PL character "Parthian heavy cataphract with a long lance lowered, horse in full scale barding, red banner on the lance, warm afternoon light" 48x48 --view "low top-down" --outline "selective outline" --template horse --out-dir $R/cataphract_charge
anim cataphract_charge running
```

### unit:war_elephant

Unlocks: enemy war_elephant. Estimate \$0.58 (about \$0.81 CAD).

```bash
$PL character "armoured Parthian war elephant with a wooden tower on its back, two archers in the tower, red cloth, tusks tipped with iron, warm afternoon light" 64x64 --view "low top-down" --outline "selective outline" --out-dir $R/war_elephant
anim war_elephant running
```

### unit:shah

Unlocks: enemy shah. Estimate \$0.58 (about \$0.81 CAD).

```bash
$PL character "Parthian shah riding a large armoured war elephant, gold crown, jewelled robes, a servant holding a sunshade, elephant in red and gold cloth, warm afternoon light" 64x64 --view "low top-down" --outline "selective outline" --out-dir $R/shah
anim shah running
```

Subtotal: \$3.82 (about \$5.32 CAD).

## Props, pickups and weapon effects

Pro Flash with `--style art_test/raw/style_ref.png`, saved in `art_test/raw/props3/` (create it first). The chest and supply cart are in no `art` list: the game skips them until a `chest` or `supply_cart` prop is in the atlas, and the tests count them as drawn.

### prop:stake

Unlocks: arm stakes (Ditch and stakes). Estimate \$0.12 (about \$0.16 CAD).

```bash
prop stake 32x32 "a sharpened wooden stake driven into the ground, pointing up"
```

### prop:caltrops

Unlocks: arm caltrops. Estimate \$0.12 (about \$0.16 CAD).

```bash
prop caltrops 24x24 "a small scatter of iron caltrop spikes on the ground"
```

### prop:fire_pot

Unlocks: arm fire_pots. Estimate \$0.12 (about \$0.16 CAD).

```bash
prop fire_pot 32x32 "a clay pot with a burning rag, flames rising"
```

### prop:onager_stone

Unlocks: arm onager. Estimate \$0.12 (about \$0.16 CAD).

```bash
prop onager_stone 24x24 "a large round grey stone, as thrown by a Roman onager"
```

### prop:pine

Unlocks: province dacia. Estimate \$0.12 (about \$0.16 CAD).

```bash
prop pine 64x96 "a tall snow-dusted pine tree"
```

### prop:frozen_stream

Unlocks: province dacia. Estimate \$0.12 (about \$0.16 CAD).

```bash
prop frozen_stream 96x32 "a short stretch of frozen stream, pale blue ice with cracks and snowy banks"
```

### prop:heather

Unlocks: province britannia. Estimate \$0.12 (about \$0.16 CAD).

```bash
prop heather 32x32 "a clump of purple heather on moorland"
```

### prop:bog

Unlocks: province britannia. Estimate \$0.12 (about \$0.16 CAD).

```bash
prop bog 64x32 "a dark boggy pool with reeds and moss"
```

### prop:wheat

Unlocks: province gaul. Estimate \$0.12 (about \$0.16 CAD).

```bash
prop wheat 32x32 "a patch of ripe golden wheat"
```

### prop:hedge

Unlocks: province gaul. Estimate \$0.12 (about \$0.16 CAD).

```bash
prop hedge 64x32 "a thick green hedgerow"
```

### prop:dune

Unlocks: province parthia. Estimate \$0.12 (about \$0.16 CAD).

```bash
prop dune 96x32 "a low sand dune with wind ripples, warm sand"
```

### prop:palm

Unlocks: province parthia. Estimate \$0.12 (about \$0.16 CAD).

```bash
prop palm 64x96 "a date palm tree with a curved trunk"
```

### prop:chest

Unlocks: every elite, which drops a chest with a free choice (hidden until drawn). Estimate \$0.12 (about \$0.16 CAD).

```bash
prop chest 32x32 "a small iron-bound wooden chest with a gold lock, lid shut"
```

### prop:supply_cart

Unlocks: the supply carts (hidden until drawn). Estimate \$0.12 (about \$0.16 CAD).

```bash
prop supply_cart 64x48 "a Roman supply cart, two wooden wheels, loaded with sacks and barrels, no horse"
```

Subtotal: \$1.64 (about \$2.28 CAD).

## Grounds

One seamless 256x256 tile per province, Pro Flash with the style image, then `tools/art/make_seamless.py` (see the code note under After the art lands). Germania's ground exists.

### ground:britannia

Unlocks: province britannia. Estimate \$0.11 (about \$0.15 CAD).

```bash
$PL proflash "seamless top-down ground texture of wet moorland: tussocky grass in dull green and brown, patches of dark peat, a few tiny purple heather sprigs, no leaves, no sticks, even lighting, no objects, fills the whole image" 256x256 --style $R/style_ref.png --style-use "match this art style, palette, shading and pixel density" --out $R/ground/britannia.png
python tools/art/make_seamless.py $R/ground/britannia.png --out $R/ground/britannia_tile.png
```

### ground:gaul

Unlocks: province gaul. Estimate \$0.11 (about \$0.15 CAD).

```bash
$PL proflash "seamless top-down ground texture of farmland: short green meadow grass with a few bare earth patches and tiny yellow wildflowers, no leaves, no sticks, even lighting, no objects, fills the whole image" 256x256 --style $R/style_ref.png --style-use "match this art style, palette, shading and pixel density" --out $R/ground/gaul.png
python tools/art/make_seamless.py $R/ground/gaul.png --out $R/ground/gaul_tile.png
```

### ground:dacia

Unlocks: province dacia. Estimate \$0.11 (about \$0.15 CAD).

```bash
$PL proflash "seamless top-down ground texture of snowy mountain ground: white snow with grey rock patches, frozen dirt and a few sparse dead grass tufts, no leaves, no sticks, even lighting, no objects, fills the whole image" 256x256 --style $R/style_ref.png --style-use "match this art style, palette, shading and pixel density" --out $R/ground/dacia.png
python tools/art/make_seamless.py $R/ground/dacia.png --out $R/ground/dacia_tile.png
```

### ground:parthia

Unlocks: province parthia. Estimate \$0.11 (about \$0.15 CAD).

```bash
$PL proflash "seamless top-down ground texture of desert: warm tan sand with small pebbles and faint wind ripples, a few dry scrub tufts, no leaves, no sticks, even lighting, no objects, fills the whole image" 256x256 --style $R/style_ref.png --style-use "match this art style, palette, shading and pixel density" --out $R/ground/parthia.png
python tools/art/make_seamless.py $R/ground/parthia.png --out $R/ground/parthia_tile.png
```

Subtotal: \$0.44 (about \$0.62 CAD).

## Icons

Pixen, 32 px, side view, saved straight into `game/assets/icons/`.

```bash
icon slinger "Roman sling with a round stone"
icon cavalry "Roman cavalry helmet with a horsehair plume and a horse head"
icon standard_bearer "Roman legion standard pole with gold hand and silver discs"
icon ballista "Roman ballista bolt thrower with a heavy bolt"
icon centurion "Roman centurion helmet with a tall transverse crest and a vine staff"
icon onager "Roman onager catapult with its arm raised"
icon caltrops "iron caltrop spikes"
icon stakes "ring of sharpened wooden stakes"
icon fire_pots "clay pot with flames"
icon war_dogs "snarling war dog head with a spiked collar"
icon trumpets "curved Roman cornu horn trumpet"
icon eagle "Roman aquila eagle with spread wings and lightning bolts"
icon oil_jars "clay amphora spilling dark oil"
icon torches "two burning torches"
icon hooked_pila "Roman pilum with a barbed hook head"
icon greek_fire "clay pot with green-white flames"
icon siege_train "Roman onager and scorpio side by side"
icon hunting_horn "curved horn trumpet with a hound's head"
icon burning_eagle "golden Roman eagle wreathed in flames"
icon fortified_camp "Roman palisade fort with a gate and a banner"
icon shield_wall "Roman shields locked in a row"
icon better_bows "long composite bow with a fine arrow"
icon close_order "three Roman helmets packed close together"
icon plunder "overflowing sack of coins"
icon veterans "Roman helmet with three chevron service stripes"
icon reserves "two Roman helmets behind a gate"
icon fortune "golden four-leaf clover with a coin"
icon glory "golden laurel wreath with a star"
```

| Icon | Unlocks |
|---|---|
| slinger | recruit slinger |
| cavalry | recruit cavalry |
| standard_bearer | recruit standard_bearer |
| ballista | recruit ballista |
| centurion | recruit centurion |
| onager | arm onager |
| caltrops | arm caltrops |
| stakes | arm stakes |
| fire_pots | arm fire_pots |
| war_dogs | arm war_dogs |
| trumpets | arm trumpets |
| eagle | arm eagle |
| oil_jars | arm oil_jars |
| torches | arm torches |
| hooked_pila | forged form hooked_pila |
| greek_fire | forged form greek_fire |
| siege_train | forged form siege_train |
| hunting_horn | forged form hunting_horn |
| burning_eagle | forged form burning_eagle |
| fortified_camp | forged form fortified_camp |
| shield_wall | drill shield_wall |
| better_bows | drill better_bows |
| close_order | drill close_order |
| plunder | drill plunder |
| veterans | drill veterans |
| reserves | drill reserves |
| fortune | drill fortune |
| glory | drill glory |

28 icons at \$0.02 (about \$0.03 CAD) each. Subtotal: \$0.62 (about \$0.86 CAD).

## Optional: the camp scene

The camp screens draw on a plain backdrop today. If the Roman marching camp from Features.md is wanted as a picture, it is one Pro Flash image (not counted in the total below), saved as `game/assets/camp.png`, which the camp screen would need code to draw.

```bash
$PL proflash "Roman marching camp seen from above at golden hour: rows of leather tents, a wooden palisade, a central standard with a gold eagle, campfires, a banner, no people" 256x144 --style $R/style_ref.png --style-use "match this art style, palette, shading and pixel density" --out game/assets/camp.png
```

Estimate \$0.15 (about \$0.21 CAD).

## Total

| Group | Estimate |
|---|---|
| Recruits | \$3.19 (about \$4.44 CAD) |
| War dogs (arm) | \$0.53 (about \$0.74 CAD) |
| Germania enemies | \$2.13 (about \$2.96 CAD) |
| Britannia enemies | \$3.77 (about \$5.25 CAD) |
| Gaul enemies | \$3.77 (about \$5.25 CAD) |
| Dacia enemies | \$3.77 (about \$5.25 CAD) |
| Parthia enemies | \$3.82 (about \$5.32 CAD) |
| Props | \$1.64 (about \$2.28 CAD) |
| Grounds | \$0.44 (about \$0.62 CAD) |
| Icons | \$0.62 (about \$0.86 CAD) |
| **Everything above, camp scene left out** | **\$23.70 (about \$32.94 CAD)** |

