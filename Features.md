# Legionus Maximus: feature set

Everything the finished game has. [Plan.md](Plan.md) has why the game exists and the order of work.

## The run

- A run is one campaign in one province: a mission with objectives and a way out. It is won by marching the legion into the Roman fort that appears late in the run, or by killing the province's chieftain, and lost when the commander falls.
- The camera follows the commander over an endless field. Trees, rocks, rivers and ruins are scattered on it.
- Trees, rocks and logs are solid for the legion and the barbarians alike. Barbarians find their way round them.
- The forest grows in long winding ridges, too thick to pass, with clearings and paths between them, so there are only certain ways to go and a legion can be cornered against the trees. Lines of rocks and logs cross the open ground.
- Barbarians arrive from beyond the edges of the screen in a steady stream that thickens over the 20 minutes, with a surge every 2 minutes.
- War bands of a dozen or more gather in a tight group every 35 seconds, either in the legion's path or closing in from behind.
- Barbarians walk slower than the legion, but club warriors sprint in short bursts faster than it and wolves always run faster, so no direction is safe for long.
- The commander's own blow is weak: the soldiers do the killing, so an enemy at his back is dangerous until the formation turns to meet it. He recovers health slowly on his own.
- Barbarians locked in melee hold the legion back: the more of them press against it, the slower it marches, down to a fifth of its speed. A small legion cannot walk through a crowd.
- Every fallen barbarian drops denarii: gold coins, large and bright with a dark edge and a glint, so they are easy to see on the grass. Any soldier who walks over them collects them for the legion. Collecting them fills the level bar. The amount needed rises with each level.
- At each level-up the game pauses and offers three choices, one of them always a recruit while the legion has room. One can be rerolled per run for free, more with a permanent upgrade.
- Now and then a stranded supply cart stands somewhere on the screen for about 45 seconds. Reaching it gives a free choice, a heal for the whole legion, or a magnet that pulls in every coin on screen.
- When the run ends, the denarii carried go to the camp for permanent upgrades, whatever the result.

## Objectives and the fort

In 9 AD the Germans destroyed three legions in the Teutoburg Forest and carried off their eagle standards. A Germania run is a mission to win them back.

- Each run places two or three objectives in clearings some way off. Arrows at the edge of the screen point to each one that is not done yet, with its distance.
- Objectives:
  - **Barbarian camp:** huts round a captured eagle standard. Defenders pour out when the legion comes near. Reaching the eagle takes it back: a free choice and a large purse of denarii at the end of the run.
  - **Stranded column:** a supply cart with a few Roman soldiers holding out against a war band. Reaching them adds the survivors to the legion and heals it.
  - **Sacred grove:** an altar among the oaks. Holding the legion in the grove for a few seconds while war bands come to defend it burns it: a free choice, and the barbarians lose heart, so the stream thins for a minute.
- Objectives are optional. Each one done raises the denarii the run banks.
- At 16 minutes a Roman fort appears some distance away, marked like the objectives. Marching the commander through its gate wins the run.
- When the fort appears the chieftain comes out with his bodyguard to stop the legion reaching it. Killing him also wins.

## Felling trees and the palisade

- Legions cut roads through forests. Soldiers pressed against a tree fell it after a few seconds, leaving a stump, so the legion can cut its own way through a ridge, slowly.
- Each felled tree gives a log of timber, counted on the screen.
- A button (E, or the west face button) spends timber to drive a line of stakes across the ground in front of the legion. The stakes are solid, so barbarians must go round them; they rot away after a while.

## Bosses

The chieftain and the elites are meant to be fought with the whole formation: facing them, closing on the ones who stand back and stepping out of their big blows.

- **The chieftain** comes with a bodyguard of spearmen who stay round him, so the front rank cannot reach him until they are broken; pila, the onager and fire reach past them. His attacks:
  - **Charge:** a red line on the ground shows his path for a second, then he charges along it and throws aside the soldiers in his way, hurting them and breaking the formation.
  - **Slam:** a red ring round him fills in, then he strikes the ground and hurts everyone inside it.
  - **War horn:** he blows his horn and a war band arrives behind the legion.
  - **Cleave:** a sweep of his axe in front of him.
- **Berserker:** runs round the legion to attack its rear, where the archers are, and charges every few seconds. The legion has to keep turning to keep him in front.
- **War band leader:** rallies the barbarians round him, who move faster for a few seconds.
- **War priest:** stands back and throws burning pots at the thickest ranks, each landing in a red ring that shows a second before.

## Controls

- Move: WASD, arrow keys or the left stick.
- Testudo: Space or the south face button.
- Pause: Escape or Start.
- Build a palisade: E or the west face button.
- Everything else, including every attack, happens on its own.
- Mouse is used only in menus and choices, which also work fully from keyboard and pad.

## The legion

- The commander is the only unit the player moves. Every soldier keeps a place in a formation around him and follows it.
- The formation faces the way the commander walks: shields in front, missile troops behind, cavalry on the flanks. It turns as he turns, so soldiers swing round through the ranks.
- Each soldier has his own health. A soldier at zero falls out and the formation closes the gap.
- The commander has his own health bar. The run ends when it empties.
- Soldiers in the front rank take hits meant for the men behind them, so a deep formation protects its archers.
- The legion is capped at 100 soldiers.

### Testudo

- Pressing the button locks the shields for 4 seconds.
- During it the legion moves at half speed and takes 80% less damage. Arrows and thrown spears bounce off.
- It recharges over 15 seconds. Drills shorten that and lengthen the hold.

## Recruits

Each is chosen at a level-up and adds soldiers to the formation. Choosing one again adds more, and the 5th pick of a type also promotes all of them.

| Recruit | Place | What he does | Promotion |
|---|---|---|---|
| Legionary | front ranks | stabs the nearest enemy in reach with his gladius | veterans: double damage and health |
| Archer | rear | shoots the nearest enemy in range | arrows pierce one enemy |
| Slinger | rear | throws stones in a wide arc that knock enemies back | stones bounce once |
| Cavalryman | flanks | rides out at enemies near the flanks and back | tramples everything in his path |
| Standard bearer | middle | raises the attack speed of every soldier near him | his aura covers the whole legion |
| Medicus | middle | heals the most wounded soldier near him | revives one fallen soldier a minute |
| Ballista crew | rear | fires a heavy bolt down a line every few seconds | bolts explode at the end |
| Centurion | front | stronger legionary whose shout stuns enemies around him | his shout doubles in size |

## Arms

Legion-wide weapons that fire on their own. Each is upgraded 5 times. When two are both at level 5, a level-up can offer the forged form in their place.

| Weapon | What it does |
|---|---|
| Pilum volley | every legionary throws a pilum at the nearest enemy |
| Burning arrows | archers' arrows set enemies alight |
| Scorpio | a bolt thrower that fires at the strongest enemy on screen |
| Onager | stones land in the thickest crowd and scatter it |
| Caltrops | spikes left behind as the legion marches |
| Ditch and stakes | a ring of stakes around the legion, which hurts enemies who cross it |
| Fire pots | jars thrown ahead that leave burning ground |
| War dogs | hounds that run down enemies who break away |
| Trumpets | a blast every few seconds that pushes enemies back |
| Eagle | the aquila flashes and strikes every enemy around the commander |
| Oil jars | slick ground that slows enemies |
| Torches | fire that circles the formation |

Forged forms: pilum and caltrops make hooked pila that pin enemies in place; burning arrows and fire pots make Greek fire; scorpio and onager make the siege train; dogs and trumpets make the hunting horn; eagle and torches make the burning eagle; stakes and oil make the fortified camp.

## Drills

Small upgrades to the whole legion, each takeable several times.

- Forced march: move speed.
- Lorica: soldier health.
- Shield wall: damage taken by the front rank.
- Discipline: attack speed.
- Sharpened gladii: melee damage.
- Better bows: missile range.
- Long reach: pickup radius.
- Rations: health regeneration.
- Close order: soldiers keep their places faster when the formation turns.
- Testudo practice: shorter testudo recharge, longer hold.
- Plunder: more denarii per kill.
- Veterans: soldiers gain health with every kill.
- Reserves: a fallen soldier is replaced after 20 seconds.
- Fortune: a fourth choice at every level-up.
- Glory: more experience per coin.

## Enemies

Every province has four ordinary enemies, two elites that arrive with the surges, and a chieftain at the 20-minute mark.

| Province | Ordinary | Elites | Chieftain |
|---|---|---|---|
| Germania | club warrior, spearman, axe thrower, wolf | berserker, war band leader, war priest | Arminius-style war chief with an axe |
| Britannia | painted warrior, slinger, chariot, druid acolyte | chariot charge, druid | warrior queen in a chariot |
| Gaul | swordsman, horseman, archer, boar | champion, horn blower | king with a long sword and bodyguard |
| Dacia | falx warrior, archer, wolf-standard bearer, mountain bear | falx band, priest | king behind a moving shield wall |
| Parthia | horse archer, cataphract, camel rider, slinger | cataphract charge, war elephant | shah on an elephant |

- Ranged enemies stop at a distance and fire at the nearest Roman, which is what the testudo answers. After three throws they close in to fight hand to hand.
- Some enemies join the stream later in the run: in Germania, wolves from 1:30 and axe throwers from 3:00.
- Elites have far more health, a name over their heads and drop a chest with one free choice. Each has a tactic:
  - the berserker charges the legion every few seconds and hits hard when he arrives;
  - the war band leader rallies the barbarians around him, who move faster for a few seconds;
  - the war priest stands back and throws burning pots at the thickest ranks. A red ring marks where each will land a second before it does, so the legion can step out or raise the testudo.
- A chieftain has a health bar across the top of the screen and three attacks of his own.

## Provinces

Five, unlocked in order by beating the one before.

| Province | Ground | Scattered on it |
|---|---|---|
| Germania | forest clearings | oaks, firs, logs, standing stones |
| Britannia | wet moorland | heather, bogs, stone circles |
| Gaul | farmland | wheat fields, hedges, villages |
| Dacia | snowy mountains | pines, rocks, frozen streams |
| Parthia | desert | dunes, palms, ruined walls |

## Commanders

Six. The first is free and the others are unlocked by playing.

| Commander | Starts with | Unlocked by |
|---|---|---|
| Tribune | two legionaries | free |
| Archer captain | three archers | winning in Germania |
| Cavalry prefect | two cavalrymen, faster march | killing 5,000 barbarians in total |
| Engineer | the scorpio | winning in Gaul |
| Old centurion | a centurion, more health, slower | surviving 20 minutes with no more than 10 soldiers |
| Legate | a standard bearer and a free reroll | winning in all five provinces |

## The camp

The screen between runs, a Roman marching camp drawn like the other games' title scenes.

- **Quartermaster:** about 20 permanent upgrades bought with denarii, each with several ranks: starting health, starting soldiers, move speed, damage, pickup radius, rerolls, banishes (removing a choice from the run's pool), testudo charge, experience, more denarii.
- **Tablinum:** the record of every recruit, weapon, enemy and forged form found, with a line of history for each. Empty entries show as silhouettes.
- **Map:** the five provinces with their best time and best result.
- **Commanders:** pick one and see how to unlock the rest.

## After a province is beaten

- **Hard mode** for each province: enemies have more health and arrive faster, and denarii pay more.
- **Endless:** the run keeps going after the chieftain, with stronger waves every minute, for a high score.
- **Decimatio:** a run modifier that starts the legion at full size and takes one soldier in ten away every 2 minutes.

## Screens and options

- Title, camp, run, level-up, pause, run summary (time, kills, denarii, damage by weapon, legion size over time) and settings.
- Settings: master, music and effects volume; full screen and window; screen shake; damage numbers on or off; text size; key and button rebinding; language.
- The screen scales up in whole steps so the pixel art stays sharp at every resolution, and fits the Steam Deck.

## Steam

- Achievements for winning each province, each commander, each forged form, kill counts, and legion size.
- Rich Presence showing the province, the minute and the legion size.
- Steam Cloud saves, full controller support and Steam Deck verified.
- A demo with Germania, three commanders and a 15-minute cap.
- 14 languages, the same as the other games.

## In the prototype

The prototype is one run in Germania, built with the art test's characters, to judge whether the game is fun:

- the commander, legionaries and archers in formation, facing the way they march
- club warriors and spearmen in a stream that thickens, surges every 2 minutes, and the chieftain at 10 minutes
- denarii, levels and the three-choice screen
- recruits: legionary and archer; arms: pilum volley, burning arrows and scorpio; drills: forced march, lorica, discipline, sharpened gladii, long reach, rations and testudo practice
- the testudo
- a summary at the end and a restart
