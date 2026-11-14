# AutoCarrot Forever

Automatically equips Carrot on a Stick and other mount, swim and zone-speed gear when it helps, then puts your normal gear back.

A fork of **[AutoCarrot](https://www.curseforge.com/members/kebabstorm/projects) 3.01 by kebabstorm**, rebuilt for **WoW: Forever** (1.60.1, interface 16001).

## Features

- **Automatic swaps.** Speed gear goes on when you mount, swim, dive, or enter a zone where it works. Your normal gear goes back on afterwards, into the same slots.
- **Combat-aware.**
  - Armor can't be changed in combat, so swaps wait. Your normal gear returns as soon as the fight ends, even if you were knocked off your mount.
  - Weapons are swapped back the moment combat starts.
- **Speed bonuses stack in Forever.** By default the two best speed trinkets are worn together. You can limit this to one.
- **Gentle on trinket cooldowns.** It swaps out the trinket that costs you least: passive trinkets first, or on-use trinkets already on a long cooldown. You can lock slots, for example to keep a PvP trinket on.
- **Zone-aware.** Items such as The Desert Rose only work in certain zones. Zone groups (for example *Desert areas*) can be edited in game as players discover which zones count.
- **Your own items.**
  - Add any armor, ring, trinket, cloak or weapon, any item carrying a given enchant, or a whole set.
  - Choose when it's worn (mounted, swimming, underwater, resting, or **Always**, meaning whenever AutoCarrot is turned on), which slot it goes in and which zones it works in.
  - Custom items are shared by all your characters.
- **Speed-item suggestions.** Items in your bags whose tooltip mentions mount, swim or movement speed are suggested, with **[Add]** links in chat.
- **Live speed readout.** Hover the minimap or toggle button to see your current, mounted or run, and swim speed. It updates every 0.5 seconds, and only while hovered.

## Built-in items

| Item | Effect | When it's worn |
|---|---|---|
| Carrot on a Stick | +3% mount speed | Mounted |
| The Desert Rose | +7% mount speed | Mounted, in *Desert areas* |
| Wintersaber Hide Lined Gloves | +6% while mounted | Mounted, in Winterspring |
| Riding Skill glove enchant (#930), Mithril Spurs boot enchant (#464) | Mount speed | Mounted. Matched by **enchant**, so Forever's plain "Riding Gloves" item (no speed) is never used |
| Agamaggan's Clutch | +3% movement speed | Whenever AutoCarrot is on, in The Barrens, Thousand Needles, Razorfen Kraul and Razorfen Downs |
| Blessing of Kalimdor set (any 2 pieces) | +5% movement speed | Whenever AutoCarrot is on, in The Barrens and Stonetalon Mountains |
| Rider of the Plaguelands set (any 2 pieces) | +5% while mounted | Mounted, in Eastern and Western Plaguelands. The ring and cloak are preferred over the sword |
| Staff of Westfall, Forsaken Greataxe, Gnarled Necromancer's Staff | +2% movement speed | Whenever AutoCarrot is on, in their zones. **Off by default**: putting your real weapon back at the start of a fight costs a global cooldown |

**Desert areas** defaults to Tanaris, Silithus, Desolace and Westfall. Desolace and Westfall are confirmed in game. Blizzard doesn't publish the list, so add or remove zones in the options as you test them.

None of 3.01's Riding Crop, Skybreaker Whip, swim belt or swim helm exist in Forever, and Forever has no flying mounts.

## Install

- **CurseForge:** install with the CurseForge app.
- **Manually:** copy the `AutoCarrotForever` folder into `World of Warcraft\_forever_\Interface\AddOns\`. If your Forever install folder has a different name, use that one. The folder must be named `AutoCarrotForever`, matching the `.toc` file, or the game won't load it.

## Use

- **Options:** Esc → Options → AddOns → **AutoCarrot Forever**. All settings, including the zone groups, are on one page.
- **`/ac`** opens the custom item editor. `/ac help` lists every command. Useful ones:
  - `/ac speed`: your current speed, for testing zone items
  - `/ac zone`: your zone and the zone groups
  - `/ac addset 2 <link> <link> …`: add a set rule
  - `/ac debug 1`: explains every swap decision in chat
- **Minimap button:**
  - left-click turns the addon on or off
  - right-click opens the item editor
  - Shift-click opens the options
  - drag to move it around the minimap
- **Toggle button** (shown by default): the carrot button turns AutoCarrot on (green) or off (red). Turning it off puts your normal gear back, including items set to Always. Right-click opens the editor. Hold **Alt** and drag to move it; its position is remembered without Edit Mode. Hide it in the options or with `/ac button 0`.

## Development

- Addon source: [AutoCarrotForever/](AutoCarrotForever/)
- Design document: [docs/DESIGN.md](docs/DESIGN.md)
- Original addon, for reference: [AutoCarrot-3.01/](AutoCarrot-3.01/)
- Planner unit tests (plain Lua 5.1+, run from the repo root): `lua tests/test_planner.lua`
- **Release zips:** the zip must contain the `AutoCarrotForever/` folder at its top level. Bump `## Version` in the `.toc` first. `AutoCarrotForever-<version>.zip` in the repo root is the current release; `dist/` is ignored by git.

## Credits

- **Original addon:** [AutoCarrot](https://www.curseforge.com/members/kebabstorm/projects) by **kebabstorm**. AutoCarrot Forever builds on their original design and code. Please support the original author.
- **This fork:** AdamTogether, made with the help of AI (Anthropic's Claude). I designed, tested and directed the work; AI assisted with research and writing code.
- Not affiliated with Blizzard Entertainment.

## License

[MIT](LICENSE), the same license as the original AutoCarrot. The original copyright notice is kept alongside the fork's.
