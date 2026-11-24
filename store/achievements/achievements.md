# Steam achievements and stats

Enter these in Steamworks under App Admin, Stats & Achievements, in the full game's app (and the Playtest app if it
carries the achievements), then Publish. Each achievement's icons are the two pictures named after its API name.

## Achievements

| API name | Name | Description | Hidden | Progress stat |
|---|---|---|---|---|
| `win_germania` | Victory in Germania | Win a run in Germania. | no |  |
| `win_britannia` | Victory in Britannia | Win a run in Britannia. | no |  |
| `win_gaul` | Victory in Gaul | Win a run in Gaul. | no |  |
| `win_dacia` | Victory in Dacia | Win a run in Dacia. | no |  |
| `win_parthia` | Victory in Parthia | Win a run in Parthia. | no |  |
| `win_hispania` | Victory in Hispania | Win a run in Hispania. | no |  |
| `win_aegyptus` | Victory in Aegyptus | Win a run in Aegyptus. | no |  |
| `win_sarmatia` | Victory in Sarmatia | Win a run in Sarmatia. | no |  |
| `win_as_archer_captain` | Victory as the Archer captain | Win a run as the Archer captain. | no |  |
| `commander_cavalry_prefect` | Cavalry prefect unlocked | Unlock the Cavalry prefect. | no |  |
| `win_as_engineer` | Victory as the Engineer | Win a run as the Engineer. | no |  |
| `commander_old_centurion` | Old centurion unlocked | Unlock the Old centurion. | no |  |
| `commander_legate` | Legate unlocked | Unlock the Legate. | no |  |
| `forge_hooked_pila` | Hooked pila forged | Forge the Hooked pila. | no |  |
| `forge_greek_fire` | Greek fire forged | Forge the Greek fire. | no |  |
| `forge_siege_train` | Siege train forged | Forge the Siege train. | no |  |
| `forge_hunting_horn` | Hunting horn forged | Forge the Hunting horn. | no |  |
| `forge_burning_eagle` | Burning eagle forged | Forge the Burning eagle. | no |  |
| `forge_fortified_camp` | Fortified camp forged | Forge the Fortified camp. | no |  |
| `kills_1000` | 1000 barbarians | Defeat 1000 barbarians in total. | no | `kills`, min 0, max 1000 |
| `kills_10000` | 10000 barbarians | Defeat 10000 barbarians in total. | no | `kills`, min 0, max 10000 |
| `kills_100000` | 100000 barbarians | Defeat 100000 barbarians in total. | no | `kills`, min 0, max 100000 |
| `legion_25` | Legion of 25 | Lead 25 soldiers at once. | no |  |
| `legion_50` | Legion of 50 | Lead 50 soldiers at once. | no |  |
| `legion_100` | Legion of 100 | Lead 100 soldiers at once. | no |  |
| `arms_8` | Eight arms mastered | Bring eight arms to their highest level in one run. | no |  |
| `forge_all` | Forged in fire | Forge all six forged arms in one run. | no |  |
| `drills_all` | Master of drills | Bring every drill to its highest level in one run. | no |  |

## Stats

Make the stat first (Stats & Achievements, Stats, New Stat), then set it as the progress stat of the
achievements above. Until the changes are published, Steam refuses the stat and the game carries on without it.

| Field | Value |
|---|---|
| API name | `kills` |
| Type | INT |
| Set by | Client |
| Increment only | on |
| Max change | empty (a player's first run after release adds their whole saved count at once) |
| Min value | 0 |
| Max value | empty |
| Default value | 0 |
| Display name | Barbarians defeated |
| Aggregated | optional, the game does not use it |

The demo's app needs neither the stat nor the progress settings.
