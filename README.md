# AutoCarrot Forever

A WoW: Forever (1.60.1, interface 16001) fork of **AutoCarrot 3.01** by **kebabstorm**.

It equips movement-speed gear automatically and puts your normal gear back when you no longer need it:

- **Zone-limited speed:** The Desert Rose (+7% mount speed in Desert areas) is worn only in desert zones. Blizzard doesn't publish the list of desert zones. The default is Tanaris, Silithus and Desolace (Desolace is confirmed in game), and you can add more in game with `/ac zone add desert` (`/ac speed` shows whether the bonus applies where you are). Your own items can be limited to zones the same way.
- **Other Forever zone items, built in:**
  - Wintersaber Hide Lined Gloves (+6% while mounted, in Winterspring)
  - Agamaggan's Clutch (+3% in The Barrens, Thousand Needles and the Razorfen dungeons)
  - the **Blessing of Kalimdor** set: any 2 pieces, +5% in The Barrens and Stonetalon Mountains
  - the two-handed **Staff of Westfall**, **Forsaken Greataxe** and **Gnarled Necromancer's Staff** (+2% in their zones). These are off by default: in combat your real weapon goes back on at once, which costs a global cooldown.
- **Sets:** `/ac addset 2 <link> <link> ...` swaps set pieces together, so the bonus is active. Use it for sets like Rider of the Plaguelands once their pieces are known.
- **Mount speed:** Carrot on a Stick, plus gloves with the Riding Skill enchant (#930) and boots with the Mithril Spurs enchant (#464). Matching is by enchant, not by item name: Forever's "Riding Gloves" item gives no speed and is not used. Bonuses stack in Forever, so by default two speed trinkets are worn when you have them.
- **Swimming and underwater:** none of the 3.01 swim items exist in Forever. Add any you find as custom items with the Swimming or Underwater trigger.
- **Your own items:** add any armor, ring, trinket or cloak (or any item carrying a given enchant). Choose when it is worn (mounted, flying, swimming, underwater, resting or always) and which slot it goes in. Custom items are shared by all your characters.
- **Suggestions:** items in your bags whose tooltip mentions mount, swim or movement speed are offered as new rules.

After combat, the correct gear goes back on as soon as the game allows it.

## Install

Copy the `AutoCarrotForever` folder into `World of Warcraft\_forever_\Interface\AddOns\`. Use the folder for your Forever install if it has a different name.

## Use

- `/ac` opens the custom item editor. `/ac help` lists every command.
- **Esc → Options → AddOns → AutoCarrot Forever** has all the settings.
- The minimap button turns the addon on or off with a left-click and opens the editor with a right-click. There is also an optional on/off button you can move with Alt-drag (`/ac button 1`).

## Development

- Design: [docs/DESIGN.md](docs/DESIGN.md)
- Original addon, for reference: [AutoCarrot-3.01/](AutoCarrot-3.01/)
- Planner unit tests (plain Lua 5.1+): `lua tests/test_planner.lua`
