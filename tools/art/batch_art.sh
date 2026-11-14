#!/bin/bash
# Generates the prototype's art in waves, since PixelLab runs at most 8 jobs at once on this plan.
cd "$(dirname "$0")/../.."
PL="python tools/art/pixellab.py"
R=art_test/raw
id(){ python -c "import json;print(json.load(open('$R/$1/character.json'))['character_id'])"; }
DIRS="south south-west west north-west north north-east east south-east"

$PL character "Germanic barbarian chieftain, huge muscular warrior, wolf pelt over head and shoulders, gold arm rings, chainmail shirt, long braided red beard, large two-handed battle axe, warm afternoon light" 64x64 --view "low top-down" --outline "selective outline" --out-dir $R/chieftain > $R/job_chieftain.log 2>&1 &
$PL proflash "seamless top-down ground texture of a Germanic forest clearing: dense short grass in muted olive and moss greens, darker grass clumps and small clover patches, a very few tiny pale flowers, no leaves, no sticks, even lighting, no objects, fills the whole image" 256x256 --style $R/style_ref.png --style-use "match this art style, palette, shading and pixel density" --out $R/ground/grass_b.png > $R/job_ground.log 2>&1 &
wait

jobs=()
for u in commander legionary archer; do for d in $DIRS; do [ -d $R/$u/t_walking_$d ] || [ "$u:$d" = "commander:east" ] || jobs+=("$u walking $d"); done; done
for u in barbarian_club barbarian_spear chieftain; do for d in $DIRS; do [ -d $R/$u/t_running_$d ] || jobs+=("$u running $d"); done; done
n=0
for j in "${jobs[@]}"; do
  set -- $j
  $PL animate "$(id $1)" x --template-action $2 --direction $3 --out-dir $R/$1/t_$2_$3 > $R/job_$1_$2_$3.log 2>&1 &
  n=$((n+1)); if [ $((n % 7)) -eq 0 ]; then wait; fi
done
wait

icon(){ $PL pixen "$1, game upgrade icon, centered, warm afternoon light" 32x32 --view side --outline "selective outline" --detail "medium detail" --transparent --raw --out game/assets/icons/$2.png > $R/job_icon_$2.log 2>&1 & }
mkdir -p game/assets/icons
icon "Roman legionary iron helmet with cheek guards" legionary
icon "wooden recurve bow with an arrow" archer
icon "three crossed Roman pilum javelins" pilum
icon "flaming arrow" fire_arrows
icon "Roman gladius short sword" gladius
icon "Roman leather marching sandal" march
icon "Roman segmented iron plate armour" lorica
icon "golden Roman eagle standard" discipline
icon "leather coin purse spilling silver coins" magnet
wait
icon "rolled linen bandage and green healing herbs" medicus
icon "large red Roman scutum shield with gold eagle wings" testudo
icon "wooden scorpio bolt thrower" scorpio
wait
echo ALL DONE
