# Hunter Pet Collector

A transmog-style journal of every tameable hunter pet look for **WoW: Forever** and **Mists of Pandaria Classic**.

This project builds on [Hunter Pet Collector on CurseForge](https://www.curseforge.com/wow/addons/hunter-pet-collector), originally credited to Ben in the addon metadata. This repository contains further changes to the interface and localization. The original project's included README and `LICENSE` identify GPLv3.

## Features

- **Every pet look**: 1,553 looks in MoP Classic (44 families, exotics included) and 468 in WoW: Forever (17 families). Each look is one unique model and colour. Every creature that wears it is listed as a source.
- **3D previews**: The grid shows a live model on every tile. Pick a tile to open the big viewer: drag to rotate, right-drag to move, mouse wheel to zoom. There are Idle, Walk, Run, Attack and Roar animations and a turntable spin.
- **Combat roles**: Every look shows how good its family is at DPS, tanking and support (heals, battle res, Bloodlust, party buffs), with a rating out of 100 and what the family brings. Click the **DPS**, **Tank** or **Support** tab and every pet is ranked from best to worst. The family list turns into a numbered ranking (#1, #2, #3…) with each family's score, so the best pet for the job is at the top. The Sort button also offers **Rarest first** and **Level**.
  - In MoP Classic any pet can be set to Ferocity, Tenacity or Cunning, so ratings reflect each family's buffs and abilities (Core Hound's Bloodlust, Spirit Beast's heal, Turtle's Shell Shield and so on).
  - In WoW: Forever, ratings follow Blizzard's Offensive / Balanced / Defensive family types and each family's unique ability.
  - The ratings are a judgement based on guides (Icy Veins, Warcraft Tavern, Blizzard's Forever notes), not simulated numbers. Forever is in beta, so they may change.
- **Spawn pins on your maps**: Right-click a tile, or press **Show on map**, to pin every known spawn of that look. Pins show on the world map (including zoomed-out continent views) and on the minimap. They stay until you remove them.
  - Click a creature in the "Where to tame" list to pin it and open the map at its zone.
  - Shift-click a creature to set a waypoint to its nearest spawn. TomTom is used too if you have it.
  - Right-click a pin to remove it. **Clear pins** removes them all.
- **Tracking arrow**: Press **Track** on a look, or Ctrl-click one of its pins. An on-screen arrow then points to the nearest spawn and shows the distance. It turns green when you're facing the right way.
  - When you reach a spawn, it says "look around". After a few seconds it moves on to the next closest spawn you haven't checked, so you can sweep every spawn point of a rare.
  - Ctrl-click the arrow to skip a spawn, or right-click it to stop. Shift-drag moves it.
  - Tracking stops automatically once you collect the look.
- **Hunt mode**: Press **Hunt all** in the collection window header (or `/hpc hunt`). Every look you haven't collected shows on your world map and minimap. The arrow leads you to the nearest one, and the rare tracker alerts you when one is nearby. Each look drops off the moment you collect it, so you keep hunting until everything is collected.
  - In Options you can limit the hunt to Uncommon+, Rare+ or Epic+, and to beasts you can tame at your level (on by default).
  - Zoomed out to a continent, the map shows one pin per beast per zone to keep it readable. A specific look you **Track** takes priority over the hunt.
- **Rare tracker**: The addon watches nameplates, your mouseover, your target and rare markers on the minimap. When a wanted beast is nearby, it shows a popup with the beast's 3D model, plays the raid warning sound and flashes the game icon. The popup has a **Target** button, and a **Track** button that points the arrow at the beast's exact spot.
  - You choose what counts as wanted in Options: your tracked look, any uncollected rare (the default), or any uncollected look.
- **Paw pins on the minimap**: Pinned and tracked spawns show as a paw symbol in a rarity-coloured ring. Spawns of the tracked look glow.
- **Pets you already own count**: Visit a stable master once and every pet in your stable and Call Pet slots is collected automatically, in both MoP Classic and Forever. Your active pet is also picked up whenever you log in or summon it.
- **Your collection is safe**: Your collection isn't stored in the addon folder. The game keeps it in its WTF folder, so installing a new version never touches it. Every collected look is also backed up account-wide, so it comes back if the character's own file fails to load. After a **realm transfer or rename**, the addon offers to bring your collection over the first time you log in (`/hpc restore` does the same). Collected looks are never removed: there's no way to reset a collection, and the backup only ever grows.
- **Backup codes**: `/hpc export` gives you a short code holding your whole collection. Keep it anywhere outside the game. If your WTF folder is lost, the game is reinstalled or you change PC, `/hpc import` restores it. A code only works for the character it was made for. The addon reminds you to make a fresh code after every 15 new looks.
- **Collection is earned, not ticked**: Looks are only collected when you tame a beast, summon a pet, or the game shows it in your stable. There's no manual marking. The collection is signed to your character, so hand-edited saved files are detected and their scores aren't shared.
- **Points by rarity**:

  | Rarity | When it applies | Points |
  | --- | --- | --- |
  | Common | 2+ normal creatures share the look | 5 |
  | Uncommon | Only one normal creature, or elites only | 10 |
  | Rare | Rare spawns only (or exotic Uncommon) | 25 |
  | Epic | Rare elite or boss only (or exotic Rare) | 50 |
  | Legendary | Spirit Beasts | 100 |

- **Server leaderboard**: In MoP Classic the board only shows hunters on your server (and its connected realms). WoW: Forever is one big mega-server, so its board shows every hunter playing Forever. The two game versions keep separate boards, and Battle.net is never used. Scores are shared through your guild, your party or raid, and friends on your server. Anyone who has sent you their score once (for example while grouped) keeps getting yours by hidden whisper after that, so you stay up to date without grouping again. Sharing is kept light: your score goes out when you log in, when you collect a new look and every 20 minutes. Other players' scores are only asked for when you press Ask for scores (at most once a minute). Whispers never go to more than 15 players at a time, and offline players are left alone. To reach players anywhere on your server, the addon posts one short coded line in its own hidden chat channel whenever you open its window (at most every 20 minutes) or press **Ask for scores**. Every Pet Collector user on the server picks it up, adds you to their board and sends their score back. The line is hidden from chat, and it can only be sent when you click or type something, because the game doesn't let addons post in chat channels on their own. Opening the board asks everyone for fresh scores. Type `/hpc comm` to check the connection.
- **Pet XP Bar**: A movable, scalable XP bar with your pet animated in 3D beside it. Hunters see their own pet with its real level and experience (on MoP Classic, where pets don't level, the bar stays hidden). Other classes get a pretend wolf that earns the experience you earn, a little per kill at max level, and can't pass your level, just for fun. Right-click the bar, shift-click the minimap button, or type `/hpc xp` or `/petxp` for its options: size, colours and presets, text style, and the pet's size, position and animation. Ctrl+mouse wheel scales it. Its settings are saved separately from your collection.
- **Easy pet feeding** (WoW: Forever and other versions where pets get hungry): A Feed button sits next to the XP bar. One click feeds your pet the best food in your bags that it will eat, saving your better food where it can and skipping food it would refuse. A coloured dot shows its mood (green happy, yellow content, red unhappy), and you get a warning when it drops, since unhappy pets do less damage. Hover the button to see what it will use and what your pet eats. Shift-drag to move it. It does nothing on MoP Classic, where pets don't eat.
- **Options menu**: Open the settings page in the collection window using the gear icon or `/hpc options`.

## Commands

| Command | Action |
| --- | --- |
| `/hpc` | Open or close the collection window |
| `/hpc board` | Open the leaderboard |
| `/hpc options` | Open the settings |
| `/hpc clear` | Remove all map pins |
| `/hpc hunt` | Start or stop hunting every uncollected look |
| `/hpc next` | Point the arrow at the next spawn |
| `/hpc stop` | Stop tracking |
| `/hpc comm` | Check how score sharing is connected |
| `/hpc scan` | Check your current pet and say which look it is |
| `/hpc log` | Show what the addon has collected recently |
| `/hpc export` | Get a backup code for your collection |
| `/hpc import` | Restore your collection from a backup code |
| `/hpc restore` | Bring your collection over after a realm transfer |
| `/hpc xp` | Pet XP Bar options (also `/petxp`) |
| `/hpc feed` | Say which food the Feed button will use |
| `/hpc logo` | Open the logo tuner to adjust the bear and night elf |

## Install

Copy the `HunterPetCollector` folder into your AddOns folder.

**Upgrading from a version with the old `HunterPetCodex` folder:** the game names your saved collection after the addon's folder, so rename the saved files once, with WoW closed. In PowerShell, run this for each game folder you use:

```powershell
Get-ChildItem "C:\Program Files (x86)\World of Warcraft\_classic_\WTF" -Recurse -Filter "HunterPetCodex.lua*" | Rename-Item -NewName { $_.Name -replace 'HunterPetCodex','HunterPetCollector' }
```

Then delete the old `HunterPetCodex` addon folder. The folder name won't change again.

- MoP Classic: `World of Warcraft\_classic_\Interface\AddOns\`
- WoW: Forever: `World of Warcraft\_classic_beta_\Interface\AddOns\`

## Notes and limits

- **Board coverage**: The board fills up as your client hears from other Pet Collector users on your server. Scores from other realms are ignored on purpose.
- **Cheat protection has limits**: An addon can't be fully tamper-proof. The signature stops casual edits and copied files, but someone determined could still forge data.
- **Updating from 1.0**: Any looks you marked manually in 1.0 are removed. Summon your pets to collect them again.
- **Rare tracker limits**: Alerts depend on what the game shows. Turn on enemy nameplates for the best range. The Target button can't be created during combat, so it's missing from alerts that pop up mid-fight.
- **Spawn pins coverage**: 1,189 of the 1,553 MoP looks and 409 of the 468 Forever looks have pins. The rest have no recorded spawns (mostly unused or event-only creatures) or are in Forever's new zones.
- **Data sources**: The beast list comes from Wowhead. Spawn coordinates come from Wowhead and from [QuestieDB](https://github.com/Questie/QuestieDB) by the Questie team. All data was downloaded 27 Oct 2026. Forever is still in beta, so spawns may move.

## Licence and credits

The included `LICENSE` is GNU GPL v3. The spawn data in `Data/Spawns_*.lua` and NPC translations in `Locale/NPC_zh*.lua` are derived from QuestieDB, which the Questie team allows to be reused under GPLv3. Thanks to the Questie team and contributors. This addon is not affiliated with Questie. The pet food list in `Data/PetFoods.lua` is taken from the [CMaNGOS classic database](https://github.com/cmangos/classic-db) (GPLv3).

## Development and localization

Develop directly in the addon folder and use `/reload` in game after changes. Test both supported client versions when possible. Automated checks require Python and the test dependency:

```sh
python -m pip install -r tests/requirements.txt
python -m unittest discover -s tests -v
```

English is the default. `Locale/zhCN.lua` and `Locale/zhTW.lua` supply Simplified and Traditional Chinese translations; untranslated strings currently fall back to English. Add translations using the exact English key, preserving format placeholders and WoW color codes. Some interface text and creature data remain untranslated. `Locale/NPC_ForeverExtra.lua` contains community translations for additional Forever creatures; these names may differ from the official game localization. When browsing the collection, the addon requests NPC names from the game tooltip one at a time and caches successful results per game flavor and client language. Names observed on a target or mouseover creature are also cached. If the client cannot resolve an NPC, the included translations or English remain available. This tooltip lookup approach is also used by [LibNPCInfo](https://github.com/wind-addons/LibNPCInfo). NPC translations were extracted from QuestieDB v1.0.14; `scripts/extract_questiedb_locales.py` documents how to regenerate them from a baked QuestieDB TOC (requires `cbor2`).
