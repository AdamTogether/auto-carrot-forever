# AutoCarrot Forever

A WoW: Forever (1.60.1, interface 16001) fork of **AutoCarrot 3.01** by **kebabstorm**.

It equips movement-speed gear automatically and puts your normal gear back when you no longer need it:

- **Zone-limited speed:** The Desert Rose (+7% mount speed in Desert areas) is worn only in desert zones. Nobody knows the exact list of desert zones yet. The default is Tanaris and Silithus, and you can add more in game with `/ac zone add desert` (`/ac speed` shows whether the bonus applies where you are). Your own items can be limited to zones the same way.
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
