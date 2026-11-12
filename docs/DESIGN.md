# AutoCarrot Forever: Design Document

| | |
|---|---|
| **Status** | Draft |
| **Target client** | WoW: Forever 1.60.1 (build 70888), TOC `## Interface: 16001` |
| **Forked from** | AutoCarrot 3.01 by kebabstorm (`AutoCarrot-3.01/`, built for Classic, TOC `11304`) |
| **Fork name** | AutoCarrot Forever (`AutoCarrotForever/`) |

---

## 1. Overview and goals

AutoCarrot puts movement-speed gear on automatically when it helps, for example the Carrot on a Stick while mounted, or a swim-speed item the player has found while swimming. It puts the normal gear back when the condition ends.

The fork does three things:

1. **Ports** the addon to the WoW: Forever client and its Mainline-style API.
2. **Adds a basic UI**: a settings panel, an editor for the custom item list, a toggle button and a minimap button.
3. **Adds user-defined rules.** Players have not found all of Forever's movement-speed gear yet, so a fixed list of item IDs is not enough. Any equippable item can be added, with its own **trigger** (mounted, swimming, and so on) and **slot**. A discovery hint helps players find candidate items.

### Non-goals

- Equipping during combat. The client blocks it, so the addon waits instead.
- Full gear-set management, which is the Equipment Manager's job.
- External libraries (Ace3, LibDBIcon, …) in v1. The addon stays standalone.

---

## 2. Analysis of the original addon (3.01)

### 2.1 How it works

- **Main loop:** an `OnUpdate` handler runs **every frame** ([AutoCarrot.lua:16-161](../AutoCarrot-3.01/AutoCarrot.lua#L16-L161)). For each managed slot it runs its own copy of the same block:
  - **condition true:** remember the current item, then equip the speed item.
  - **condition false:** if the speed item is worn, re-equip the remembered item.
- **Built-in items:**

| Item | Match | Trigger | Slot |
|---|---|---|---|
| Carrot on a Stick | item 11122 | Mounted (not on a taxi) | Trinket 13 or 14 |
| Riding Crop | item 25653 | Mounted | Trinket 13 or 14 |
| Skybreaker Whip (name to verify) | item 32863 | Mounted | Trinket 13 or 14 |
| Riding Skill glove enchant | enchant 930 | Mounted | Hands (10) |
| Mithril spurs | enchant 464 | Mounted | Feet (8) |
| Swim belt | item 7052 | `IsSwimming()` | Waist (6) |
| Swim helm | item 10506 | `IsSubmerged()` | Head (1) |

> **In Forever** (confirmed in game): Riding Crop, Skybreaker Whip, the swim belt and the swim helm **do not exist**, so the fork keeps only the Carrot and the two enchant rules as built-ins (§3.4). Forever has an item named **"Riding Gloves"** that gives **no** speed. It is not the 3.01 riding-glove *enchant*, and rules never match items by name.

- **Remembered gear:** `AutoCarrotDB.trinketId`, `handsLink`, `bootsLink`, `beltId` and `headId`.
- **Finding the items:** a bag scan in the event handler ([AutoCarrot.lua:162-232](../AutoCarrot-3.01/AutoCarrot.lua#L162-L232)) runs on `PLAYER_ENTERING_WORLD`, `BAG_UPDATE` and `PLAYER_EQUIPMENT_CHANGED`. It finds which carrot or crop is available and which bag items have the riding-glove or spur enchant. If item 25653 or 32863 is present, the glove and spur enchants are ignored because the speed bonuses did not stack in that client. **In Forever, mount-speed bonuses from different items do stack** (confirmed in game), so the fork drops this exclusion (§5.3).
- **Restore on disable:** `AutoCarrot_EquipNormalSet` ([AutoCarrot.lua:234-252](../AutoCarrot-3.01/AutoCarrot.lua#L234-L252)).
- **Turn off in instances:** an option that clicks the toggle button on `PLAYER_ENTERING_WORLD` inside an instance ([AutoCarrot.lua:171-182](../AutoCarrot-3.01/AutoCarrot.lua#L171-L182)).
- **Slash commands:** `/autocarrot` and `/ac` ([AutoCarrot.lua:275-376](../AutoCarrot-3.01/AutoCarrot.lua#L275-L376)).
- **Toggle button:** built on `ActionButtonTemplate`. Alt-drag moves it, and the overlay is green when on and red when off ([AutoCarrot.lua:378-398](../AutoCarrot-3.01/AutoCarrot.lua#L378-L398)).

### 2.2 Problems to fix in the fork

| Problem | Where | Fix |
|---|---|---|
| Logic runs every frame | `OnUpdate`, line 16 | Event-driven, plus a slow ticker for swimming (§6.4) |
| The same block is copied for each slot | lines 19-160 | One rule engine over rules stored as data (§6) |
| `itemLink` leaks into the global namespace | lines 35, 52, 80, 93 | Use `local`, and the addon namespace |
| Hard-coded `UnitLevel("player") <= 70` | line 18 | Remove it. Each rule has its own on/off switch |
| `StaticPopup1:IsShown()` used to avoid the bind-on-equip popup | throughout | Check `C_Item.IsBound` before equipping (§6.6) |
| `AutoCarrotDB` defaults set at file load, before SavedVariables are loaded | lines 1-3 | Initialise on `ADDON_LOADED` with a deep-merge of defaults |
| Bag loop starts at slot 0 (slots start at 1) | line 210 | `for slot = 1, C_Container.GetContainerNumSlots(bag)` |
| `buttonScale` stored as a string | line 344 | `tonumber()` and clamp |
| `"…"..AutoCarrotDB.buttonScale or "1.0"` binds the wrong way | line 348 | Add parentheses |
| Whole slash message lower-cased, which breaks item links | line 370 | Lower-case only the keyword (§8.5) |
| An empty slot is not restored: the speed item stays on | lines 28-33, 116-120, 143-147 | Record empty slots as `saved[slot] = false` (§5.1) |
| `EquipItemByName` called every frame until it works, which can spam errors | throughout | One equip in flight at a time, failure back-off (§6.1, §6.6) |
| Instance check only on `PLAYER_ENTERING_WORLD`, and it calls `AutoCarrotButton:Click()` | lines 171-182 | Call `Engine:SetEnabled` directly. Settings per instance type (§6.8) |

---

## 3. Target platform

### 3.1 Client facts

- WoW: Forever runs on the **Mainline (retail) UI architecture**. The **Midnight addon restrictions** ("secret values") also apply ([Patch 1.60.1 API change notes](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes)). The secret-value rules mostly cover combat data (units, auras, nameplates). Equipment, bag and tooltip APIs on our own items should not be affected, but the API wrappers (§9) protect against that risk.
- The game type is named **Forever**, which is also accepted as an alias for **Camelot** in TOC suffixes and folder lookup.
- The client is in **beta**, so the API can change between builds.

### 3.2 TOC

```toc
## Interface: 16001
## Title: AutoCarrot Forever
## Notes: Automatically equips movement-speed gear (mount, swim, and custom items)
## Author: kebabstorm (original), AdamTogether (Forever fork)
## Version: 4.0.0
## SavedVariables: AutoCarrotForeverGlobalDB
## SavedVariablesPerCharacter: AutoCarrotForeverDB
## IconTexture: 134010
## AddonCompartmentFunc: AutoCarrotForever_OnCompartmentClick

Core.lua
Items.lua
Engine.lua
Discovery.lua
UI\Settings.lua
UI\ItemList.lua
UI\Buttons.lua
```

If Classic Era or other versions are supported later, use per-version TOC files (`AutoCarrotForever_Forever.toc`, …).

### 3.3 API migration

| 3.01 call | Forever call | Notes |
|---|---|---|
| `EquipItemByName(item, slot)` | `C_Container.PickupContainerItem` + `EquipCursorItem(slot)` (§6.2); `C_Item.EquipItemByName` only as a fallback | Exact copy chosen, and enchant rules are possible |
| `GetContainerNumSlots` / `GetContainerItemLink` | `C_Container.GetContainerNumSlots` / `GetContainerItemLink` / `GetContainerItemInfo` | Remove the global fallbacks |
| `NUM_BAG_SLOTS` loop | `for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS` | Also covers the reagent bag if present |
| Polling `IsMounted()` | `PLAYER_MOUNT_DISPLAY_CHANGED` + `IsMounted()` | |
| `StaticPopup1:IsShown()` | `C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(bag, slot))` | |
| Hidden `GameTooltip` scanning | `C_TooltipInfo.GetBagItem(bag, slot)` / `GetInventoryItem("player", slot)` | Structured `lines[].leftText` |
| `InterfaceOptions_AddCategory` | `Settings.RegisterVerticalLayoutCategory` / `RegisterCanvasLayoutSubcategory` / `RegisterAddOnCategory` | |
| `GetItemInfo` | `C_Item.GetItemInfo` + `Item:CreateFromItemID():ContinueOnItemLoad` | Handles an empty item cache |
| `GetItemCooldown` | `C_Container.GetItemCooldown` | Used by the trinket-slot choice |

### 3.4 Data to check in game

Results so far:

| 3.01 built-in | In Forever? | Fork |
|---|---|---|
| Riding Crop (25653), Skybreaker Whip (32863) | **No** (confirmed) | Removed |
| Swim belt (7052), swim helm (10506) | **No** (confirmed) | Removed. The swimming and underwater triggers stay for custom items |
| Carrot on a Stick (11122) | Assumed yes | Built-in |
| **Wintersaber Hide Lined Gloves (284266)**, hands, level 54: "Increases movement speed while mounted by 6% in Winterspring." | Yes (item databases) | Built-in: mounted + Winterspring, priority 110 (beats the 2% glove enchant) |
| **Agamaggan's Clutch (6693)**, ring, level 30: "Increases movement speed by 3% in The Barrens, Thousand Needles, Razorfen Kraul, and Razorfen Downs." | Yes (item databases) | Built-in: always + those zones |
| **Blessing of Kalimdor** set (285330 ring, 285331 neck, 285329 cloak): (2) +5% movement speed in The Barrens and Stonetalon Mountains | Yes (item databases) | Built-in **set rule** (§5.6): always + those zones |
| **Staff of Westfall (2042)**, two-hand: +2% movement speed in Elwynn Forest, Westfall, Redridge Mountains, the Deadmines | Yes (item databases) | Built-in weapon rule, **off by default** (§6.9) |
| **Forsaken Greataxe (251533)**, **Gnarled Necromancer's Staff (251534)**, two-hand: +2% movement speed in Silverpine Forest and Hillsbrad Foothills | Yes (item databases) | Built-in weapon rules, **off by default** |
| **Enchant Boots - Speed (289559)**: "+8% movement speed", and **Enchant Boots - Minor Speed (273530)**: "+4% movement speed" | Listed in item databases (Speed possibly PTR-only) | Not built in: the *enchant* IDs they apply are unknown. Discovery suggests them once they are on boots ("movement speed", "minor speed" patterns) |
| **Rider of the Plaguelands** set: Signet of the Soulless Rider (284102, ring), Horseman's Unyielding Shroud (284100, cloak), Blade of Senseless Slaughter (284101, one-hand sword). (2) "Increases movement speed while mounted by 5% in Eastern and Western Plaguelands." | Set and pieces in item databases. Drop source not yet reported | Built-in **set rule**: mounted, those zones. The pieces are listed ring, cloak, sword, so the two armor pieces are preferred and no weapon swap is needed |
| Not equipment, so out of scope: **Gift of Galloping** (271871, +10% mounted speed buff for 15 days), **Swim Speed Potion** (6372), **Transformative Cocoon** (276895, proc-based speed). Druid PvP sets with +15% speed in forms are not mounted speed and are worn permanently anyway | — | Not handled |
| **The Desert Rose (274648)**, Forever-only: unique trinket, "Equip: Increases mount speed by 7% in Desert areas." | **Yes** (confirmed) | Built-in, mounted **and** in the *Desert areas* zone group (§5.5), priority 110 |
| Riding Skill glove enchant (930), Mithril Spurs boot enchant (464) | Not yet checked | Built-in, matched by **enchant ID only** |

**Do not match by name.** Forever has an item named "Riding Gloves" with no speed effect. The glove rule matches enchant 930 on any glove, never an item called "Riding Gloves". In general, built-in and custom rules match item or enchant IDs, never names.

---

## 4. Architecture

```
AutoCarrotForever/
  AutoCarrotForever.toc
  Core.lua         namespace, event dispatcher, API wrappers, SavedVariables init/migration, slash commands
  Items.lua        built-in rule definitions (data only)
  Planner.lua      pure slot-planning functions (no WoW API; unit-tested in tests/)
  Engine.lua       trigger evaluation, equip/restore state machine
  Discovery.lua    bag scan + tooltip heuristics for candidate speed items
  UI/Widgets.lua   shared UI helpers (menus with MenuUtil or UIDropDownMenu fallback, tooltips)
  UI/Settings.lua  Settings panel
  UI/ZoneGroups.lua zone-groups section of the options page (collapsible group/zone lists)
  UI/ItemList.lua  custom item editor + suggestions list
  UI/Buttons.lua   toggle button + minimap button
```

- Every file starts with `local ADDON, ns = ...`. Modules attach to `ns` (`ns.Engine`, `ns.UI`, …).
- **Globals:** only `AutoCarrotForeverDB`, `SLASH_AUTOCARROTFOREVER*` and the named frames the UI needs (`AutoCarrotForeverButton`, `AutoCarrotForeverMinimapButton`).
- **Event flow:** `Core` owns one event frame and forwards events with `ns:Fire(event, ...)`. Modules subscribe with `ns:On(event, fn)`.
- **Engine and UI stay separate:** UI code never calls the equip APIs directly. It changes `ns.db` and calls `ns.Engine:Refresh()`.

```
 game events ──► Core (dispatcher) ──► Engine:Refresh() ──► per-slot plan ──► EquipItem wrapper
                      │                      ▲
                      ├──► Discovery ────────┤ (suggestions)
                      ▼                      │
                    UI  ── edits db ─────────┘
```

---

## 5. Data model

### 5.1 SavedVariables

There are two tables:
- **`AutoCarrotForeverGlobalDB`** (`## SavedVariables`, account-wide) holds the custom rules and the ignored suggestions. A speed item one character discovers is then known on every alt.
- **`AutoCarrotForeverDB`** (`## SavedVariablesPerCharacter`) holds the on/off settings, the UI layout and the gear to restore. Only this character can use these.

```lua
AutoCarrotForeverGlobalDB = {
  version = 1,
  nextRuleId = 3,                                      -- unique ids; one item may have several rules
  custom = {                                           -- user rules, in list order
    {
      id       = 1,
      match    = { itemID = 12345 },  -- or { enchantID = 2939 }: any item carrying that enchant
      slot     = "auto",              -- "auto" | INVSLOT_* number (see §5.4 for allowed slots)
      triggers = { mounted = true },  -- any of these active => rule active (§6.3)
      priority = 50,                  -- higher wins
      enabled  = true,
      allowBind = false,              -- user agreed to soulbind a BoE item
      noInstance = false,             -- optional: never active inside instances
      zones = { { group = "desert" } }, -- optional (§5.5): nil = any zone
    },
  },
  ignoredSuggestions = { [67890] = true },             -- itemID or "e:<enchantID>"
  zoneGroups = {                                       -- §5.5; editable, shared by all rules/characters
    desert = { { name = "Tanaris" }, { name = "Silithus", mapID = 81 }, { name = "Desolace" }, { name = "Westfall" } },
  },
}

AutoCarrotForeverDB = {
  version = 1,

  enabled = true,
  instanceTypes = { party = false, raid = false, pvp = false, arena = false, scenario = false }, -- true = auto-disable there
  wasAutoDisabled = false,
  restoreDelay = { mounted = 0, swimming = 1.0, submerged = 1.0 }, -- seconds; see §6.7
  trinketSlot = "auto",                                -- "auto" | 13 | 14: preferred slot for trinket rules
  speedTrinketSlots = 2,                               -- 2 | 1: max trinket slots speed items may take (§6.5)
  lockedSlots = { },                                   -- [invSlot] = true: never swap this slot (e.g. PvP trinket)
  chatSuggestions = true,
  debug = false,

  button  = { shown = false, scale = 1.0 },           -- position is saved by SetUserPlaced
  minimap = { hide = false, angle = 225 },             -- degrees around the minimap

  builtins = {                                         -- on/off per built-in rule, keyed by Items.lua id
    carrot = true, ridingSkill = true, mithrilSpurs = true,
  },

  saved = {                                            -- normal gear to restore, per slot
    [13] = "item:12345::::::::70:::::",                -- item string of the normal item
    [6]  = false,                                      -- false = slot was EMPTY; restore = unequip to bags
  },
  slotOwner = { [13] = "carrot" },                     -- which rule put the current speed item on
  lastSlot  = { carrot = 14 },                         -- §6.5 step 6
}
```

Some state is kept only in memory and is never saved: `dirty`, `pending[slot]`, `suppressed[slot]`, `failures[ruleId]`, `lastEquipAt[slot]` and the inventory cache.

**`saved` stores item strings, not IDs.** Two copies of an item can differ in enchant or suffix, so the ID alone cannot tell them apart. Stored strings can go stale after a client patch changes the link format, so the lookup that finds the saved item in the bags matches on **itemID + enchantID + suffix**, not on the whole string.

**An empty slot is recorded as `false`.** If the slot was empty when a speed item went on, restoring means taking the speed item off into the bags. 3.01 did not handle this and left the speed item equipped.

**Never save a speed item as normal gear.** Before writing `saved[slot]`, check whether the current item matches any rule. If it does, keep the existing `saved[slot]` (or `false`). This stops a crash, a `/reload` mid-swap or a rule change from recording the Carrot as the normal trinket. 3.01 had the same guard (`itemId ~= 25653 and …`).

### 5.2 Initialisation and migration

- On `ADDON_LOADED` for our addon, deep-merge both tables with their defaults (`ns.db`, `ns.gdb`). The merge fills in missing keys and never overwrites saved ones. It must not merge *into* list tables such as `custom`, or default entries would be added to the user's list.
- `version` controls step-by-step migrations (`MIGRATIONS[n](db)`).
- Old `AutoCarrotDB` settings cannot be read, because SavedVariables belong to each addon. The fork starts with fresh settings, which is acceptable because there were only seven booleans.

### 5.3 Rule shape (in memory)

Built-in and custom rules are turned into the same shape, so a single engine handles both:

```lua
{
  id       = "carrot" | "custom:7",   -- custom ids come from nextRuleId, NOT the itemID
  match    = { itemID = 11122 }  -- or { enchantID = 930 }
  slots    = { 13, 14 },          -- candidate slots; one entry for fixed slots
  triggers = { mounted = true },  -- OR-combined
  priority = 100,
  excludes = { "otherRuleId" },  -- optional: rules this one cancels. No built-in uses it (bonuses stack in Forever)
  source   = "builtin" | "custom",
}
```

Example `Items.lua` entries:

```lua
ns.BUILTINS = {
  { id = "carrot",        match = { itemID = 11122 }, slots = { 13, 14 }, trigger = "mounted", priority = 100 },
  { id = "ridingSkill",   match = { enchantID = 930 }, slots = { 10 },   trigger = "mounted", priority = 100 },
  { id = "mithrilSpurs",  match = { enchantID = 464 }, slots = { 8 },    trigger = "mounted", priority = 100 },
}
```

**Stacking:** mount-speed bonuses from different items stack in Forever (confirmed). The trinket, gloves, spurs and any custom mount items are therefore **all** worn together, and the built-ins have no `excludes`. The field stays in the rule shape so a future non-stacking item can use it. Because the trinkets also stack, **two** mount-speed trinkets could both be worn, taking both trinket slots. How many trinket slots speed items may use is a setting (§6.5).

(The `Items.lua` entries are written with a single `trigger` for readability. The loader turns it into `triggers = { [trigger] = true }`.)

**Overlap with built-ins:** if a custom rule matches the same item or enchant as a built-in, the custom rule wins and the built-in is ignored for that item. This lets the user change a built-in's slot, trigger or priority without needing a separate override feature.

**Matching a worn item:** a rule is satisfied when its item is worn in **any** of its candidate slots. If the Carrot is already in slot 13, a rule that would put it in 14 does nothing.

### 5.4 Equip location → slots

For `slot = "auto"`, the slots come from the item's `itemEquipLoc`, using an explicit table:

| `itemEquipLoc` | Slots |
|---|---|
| `INVTYPE_HEAD` | 1 |
| `INVTYPE_NECK` | 2 |
| `INVTYPE_SHOULDER` | 3 |
| `INVTYPE_CHEST`, `INVTYPE_ROBE` | 5 |
| `INVTYPE_WAIST` | 6 |
| `INVTYPE_LEGS` | 7 |
| `INVTYPE_FEET` | 8 |
| `INVTYPE_WRIST` | 9 |
| `INVTYPE_HAND` | 10 |
| `INVTYPE_FINGER` | 11, 12 |
| `INVTYPE_TRINKET` | 13, 14 |
| `INVTYPE_CLOAK` | 15 |
| `INVTYPE_WEAPON`, `INVTYPE_WEAPONMAINHAND` | 16 (main hand only; no dual-wield guessing) |
| `INVTYPE_2HWEAPON` | 16, and it **also takes the off hand** (§6.9) |
| `INVTYPE_WEAPONOFFHAND`, `INVTYPE_SHIELD`, `INVTYPE_HOLDABLE` | 17 |
| `INVTYPE_RANGED`, `INVTYPE_RANGEDRIGHT`, `INVTYPE_THROWN`, `INVTYPE_RELIC` | 18 |

**Shirts and tabards (slots 4, 19)** are not supported, because they have no stats worth swapping. The editor rejects them with a message.

**Weapons are supported** because Forever's zone-speed weapons need it: the Staff of Westfall, Forsaken Greataxe and Gnarled Necromancer's Staff are all two-handers. Weapons follow different combat rules from armor. §6.9 covers that.

**Can the character use it?** Before accepting a rule, the editor checks that this character can wear the item (`C_PlayerInfo.CanUseItem`, or failing that the item's required level and armor type). Unusable items are still accepted, for alts, but are shown greyed out. The engine skips them.

---

### 5.5 Zone conditions

Forever adds items that only work in certain zones. The first known one is **The Desert Rose**: "Equip: Increases mount speed by 7% in Desert areas." Wearing it anywhere else costs a trinket slot for nothing, so a rule can carry a **zone condition**:

- `rule.zones = nil` (or empty): the rule works anywhere.
- Otherwise `zones` is a list. The rule is active only if its trigger is on **and** the player's current zone matches **any** entry:
  - `{ name = "Tanaris", mapID = 71 }`: one zone.
  - `{ group = "desert" }`: a **zone group**. These are named sets in `AutoCarrotForeverGlobalDB.zoneGroups`, shared by every rule and character, so fixing the desert list once fixes it everywhere.
- **Current zone:** `C_Map.GetBestMapForUnit("player")`, walked up through parent maps to the zone-level map. That way a sub-zone, building or cave floor counts as its zone. If that fails, `GetRealZoneText()` is used.
- **Matching:** by map ID when both sides have one, otherwise by zone name (case-insensitive). The defaults are names only, because Forever's map IDs are unknown. Adding the current zone in game stores both, and an existing name-only entry learns its map ID.
- **Which zones are "Desert areas"?** Blizzard does not list them. The default group is **Tanaris, Silithus, Desolace and Westfall**. Desolace and Westfall were confirmed in game; Tanaris and Silithus are the obvious deserts. Both confirmed zones were added after the first build, so one-time migrations (global DB version 2 for Desolace, 3 for Westfall) add them to desert groups that were already saved, without restoring zones the player removed later. The player adds or removes zones while standing in them: in the editor's *Where* menu, with the settings buttons, or with `/ac zone add desert`. `/ac speed` shows the current mount speed, so you can see whether the Rose's 7% applies in a zone.
- **Discovery** reads the zone from the tooltip (§7.2): "… in Desert areas" becomes `{ group = "desert" }`, and "… while in Tanaris" becomes that zone. An unknown kind of area, such as "in Snowy areas", creates an empty group named after it. The editor then asks the player to add zones to it.
- **Leaving the zone** works like any trigger turning off. The normal restore and restore delay apply, and the zone events below trigger a `Refresh()`.

### 5.6 Set rules

Some Forever speed bonuses are **set bonuses**. Wearing one piece does nothing; wearing two does:

- **Blessing of Kalimdor** (Barrens rares): Signet of the Zhevra (285330, ring), Mark of the Pack Leader (285331, neck), Raptor Hide Cloak (285329, cloak). Its 2-piece bonus is "Increases movement speed by 5% in The Barrens and Stonetalon Mountains."
- **Rider of the Plaguelands**: 3 pieces, names and sources still unknown. Its 2-piece bonus is "+5% mount speed in Eastern and Western Plaguelands."

A **set rule** swaps several items together:

```lua
{ id = 9, kind = "set", need = 2,
  pieces = { { itemID = 285330 }, { itemID = 285331 }, { itemID = 285329 } },
  triggers = { always = true }, zones = { { name = "The Barrens" }, { name = "Stonetalon Mountains" } },
  priority = 100, enabled = true, allowBind = false, noInstance = false }
```

- **Active** when its trigger and zone condition are true **and** this character owns and can use at least `need` pieces.
- **Planning is all or nothing.** The planner places up to `need` pieces, worn pieces first, so a half-worn set is completed rather than reshuffled. Each piece goes in its own slot, with the usual slot choice for rings and trinkets. If fewer than `need` pieces fit, because other rules or locked slots took their slots, **none** are placed. Half a set gives no bonus and would only cost stats.
- **Owner and restore:** every slot a set fills is owned by the set rule's id. Restoring works slot by slot, as usual.
- **Creating sets:** use `/ac addset <need> <link> <link> [...] [trigger]`, or accept a set suggestion (§7.2). Set rules show in the editor as "Set 2 of: A, B, C". Slot is fixed per piece; trigger, zones and priority can be edited like any other rule.

---

## 6. Equip engine (`Engine.lua`)

### 6.1 Core loop

`Engine:Refresh()` is the only entry point. It is idempotent and cheap, so it can be called often.

```
Refresh():
  if not CanSwapNow(): dirty = true; return            -- §6.6 guards
  inventory = Inventory()                               -- cached; rebuilt on BAG_UPDATE_DELAYED / PLAYER_EQUIPMENT_CHANGED
  active    = rules where enabled and not failed and AnyTrigger(rule) and inventory:Has(rule.match)
                    and CanUse(rule) and ZoneMatches(rule.zones, CurrentZone())
                    and not (rule.noInstance and IsInInstance())
  active    = drop rules named in another active rule's `excludes`
  plan      = AssignSlots(active)                       -- slot -> rule, highest priority first (§6.5)
  for each managed slot, skipping lockedSlots, suppressed[slot] and pending[slot]:
    wanted = plan[slot]
    if wanted and not IsWornAnywhere(wanted):
        if slotOwner[slot] == nil and not MatchesAnyRule(CurrentItem(slot)):
            saved[slot] = CurrentItemString(slot) or false
        EquipFromBags(wanted, slot); slotOwner[slot] = wanted.id; lastSlot[wanted.id] = slot
    elseif not wanted and slotOwner[slot]:
        ScheduleRestore(slot)                           -- honours restoreDelay (§6.7)
    elseif wanted and slotOwner[slot] and slotOwner[slot] ~= wanted.id:
        slotOwner[slot] = wanted.id                     -- hand-over between rules; saved[slot] is NOT touched
```

A slot counts as **managed** if any rule targets it, or if `slotOwner[slot]` is set.

**Hand-over between rules:** say a custom swim trinket and the Carrot both use trinket slot 14, and you ride into water. Slot 14 goes Carrot → swim trinket → normal trinket. `saved[14]` keeps the *normal* trinket throughout. A speed item is never recorded as the item to restore (§5.1).

**One equip at a time.** Equipping is asynchronous: the item is locked until `PLAYER_EQUIPMENT_CHANGED` / `ITEM_LOCK_CHANGED` fires. So each `Refresh()` starts **at most one** equip or restore. The equipment-change event then triggers the next `Refresh()`, which handles the next slot. This avoids "Item is locked" errors and races between two slots that want the same bag space.

### 6.2 Equipping

The engine first finds the exact bag item: the right copy for an item rule, or any item carrying the enchant for an enchant rule. Then `Engine:SendEquip(item, slot)` does one of two things:

- **Primary:** `C_Item.EquipItemByName(item.link, slot)`, using the item's **full link**. This picks that exact copy, enchant and suffix included. It shows the client's own bind confirmation for unbound items, and it never touches the cursor. This changed in the v4.0 review: Forever addon developers reported cursor calls such as `PickupInventoryItem` raising `ADDON_ACTION_FORBIDDEN` in some contexts. `EquipItemByName` is also the documented Mainline API, moved to `C_Item` in 10.2.6.
- **Fallback:** `C_Container.PickupContainerItem` followed by `EquipCursorItem(slot)`. It is used only if the client blocks `EquipItemByName`. It needs an empty cursor, which is a §6.6 guard. If the swap is refused, the item is dropped back with `ClearCursor()` when the flight times out.
- **Restoring to an empty slot** (`saved[slot] == false`): `PickupInventoryItem(slot)` followed by `PickupContainerItem` into a free slot in a normal bag. The reagent bag is never used, because gear can't go there.
- **Blocked actions:** `ADDON_ACTION_FORBIDDEN` and `ADDON_ACTION_BLOCKED` for this addon are watched (`Engine:OnActionBlocked`).
  - If `EquipItemByName` is blocked, the engine switches to the cursor path.
  - If both paths are blocked, automatic swaps stop for the session (blocker `restricted`) with one chat message, so the game doesn't show repeated "blocked" popups.
  - If `PickupInventoryItem` is blocked, speed items that went into an empty slot are left on, with a message.

### 6.3 Triggers

| Key | Condition | Polled? | Notes |
|---|---|---|---|
| `mounted` | `IsMounted() and not UnitOnTaxi("player")` | no | Same as 3.01. Druid travel/flight forms and Ghost Wolf are **not** mounts: `IsMounted()` is false, and the Carrot does not affect them anyway. |
| `swimming` | `IsSwimming()` | **yes** | Also true in Aquatic Form and on swimming mounts |
| `submerged` | `IsSubmerged()` | **yes** | Same as 3.01 |
| `resting` | `IsResting()` | no | Speed gear in cities and inns |
| `always` | always true | no | Run-speed items. **The item stays on through combat**, because armor cannot be swapped in combat (§6.6). The editor warns about this when the trigger is chosen. Use `noInstance` to keep it out of dungeons. |

There is deliberately no `outOfCombat` trigger. The name would suggest the item would come off for combat, which the game does not allow: a swap can only start once combat has *already* begun, and then it is too late.

A rule's `triggers` is a set. The rule is active if **any** of them is active, for example a trinket that helps both mounted and swimming.

Triggers live in a table, `ns.TRIGGERS[key] = { test = fn, polled = bool, label = L["..."] }`. The UI dropdown is built from the same table.

### 6.4 When it runs

| Source | Why |
|---|---|
| `PLAYER_MOUNT_DISPLAY_CHANGED` | Mount and dismount |
| `PLAYER_CONTROL_LOST` / `PLAYER_CONTROL_GAINED` | Taxi start and end (`UNIT_FLAGS` is not a reliable taxi signal) |
| `PLAYER_REGEN_ENABLED` | Combat ended: finish deferred swaps at once, ignoring `restoreDelay` (§6.6) |
| `PLAYER_ALIVE`, `PLAYER_UNGHOST` | Resurrected: finish swaps deferred while dead |
| `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA` | Loading screens, instance check (see "login" below) |
| `BAG_UPDATE_DELAYED`, `PLAYER_EQUIPMENT_CHANGED`, `ITEM_LOCK_CHANGED` | Rebuild the inventory cache. Continue a chain of single equips (§6.1) |
| `PLAYER_UPDATE_RESTING` | Resting changes |
| `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS` | Zone conditions (§5.5) |
| `TRADE_CLOSED`, `MAIL_CLOSED`, `MERCHANT_CLOSED`, `LOOT_CLOSED`, `BANKFRAME_CLOSED` | Finish swaps deferred while those windows were open |
| `UNIT_SPELLCAST_STOP` / `_CHANNEL_STOP` (player) | Finish swaps deferred during a cast |
| `C_Timer.NewTicker(0.25)` | Checks the **polled** triggers (swimming, submerged), which have no events. It calls `Refresh()` only when a polled state changes. It runs only while at least one enabled rule uses a polled trigger. |

There is no `OnUpdate`. Several triggers in the same frame are merged into one `Refresh()` with `C_Timer.After(0, …)`.

**Login and loading screens:** right after `PLAYER_ENTERING_WORLD`, bag and item data may be incomplete. Wait for the first `BAG_UPDATE_DELAYED`, or 2 s, whichever comes first, before the first `Refresh()`. That first `Refresh()` also cleans up after a crash, a `/reload` or a logout while speed gear was on: if a `slotOwner` is set but its trigger is now off, it restores normally.

### 6.5 Choosing a slot for dual slots (trinkets, rings)

**How many trinket slots speed items may use:** `db.speedTrinketSlots` = 2 or 1, **default 2**. Since the bonuses stack, the two best speed trinkets go on together for maximum speed (the Carrot plus any custom mount-speed trinket, ordered by priority). The cost is that **both** normal trinkets come back with a 30-second cooldown after every dismount (§6.7). With 1, only the best mount trinket goes on, and the other slot keeps its normal trinket, as in 3.01. When only one speed trinket is available, both settings behave the same: §6.5 step 5 picks the cheaper slot. A locked slot (`lockedSlots`) is never used for speed items, so the limit is also capped by the number of unlocked trinket slots. Locking slot 13 with setting 2 behaves the same as setting 1.

When a rule has more than one candidate slot, choose in this order:
1. Leave it alone if the item is already worn in any candidate slot (§5.3).
2. Skip any slot in `lockedSlots`.
3. A slot that already holds a speed item from the same or a lower-priority rule.
4. The user's preferred slot (`db.trinketSlot`), if set.
5. The slot where swapping costs the least, scored like this (§6.7):
   1. the current item has **no on-use effect** (`C_Item.GetItemSpell` returns nil);
   2. or its on-use **cooldown has more than 30 s left** (`GetInventoryItemCooldown`). The re-equip cooldown is then hidden inside the real cooldown, so the swap costs nothing;
   3. or its on-use cooldown has the **least** time left. This is the most expensive case.
6. On a cost tie, the slot that rule used last time (`db.lastSlot[ruleId]`), so swaps are predictable. Cost comes first because `lastSlot` is nearly always set, and it would otherwise override the 30-second cooldown protection.
7. Otherwise the second slot (14 or 12), which matches 3.01's "trinket slot 2" default.

**Unique-equipped:** never pick a slot when the other slot already holds the same item ID.

**Two speed items, two slots:** if two active trinket rules have different items (Carrot and a custom swim trinket while riding a swimming mount), give each a slot in priority order. That can leave **no** normal trinket equipped, which is the expected result. Both slots then have a `saved` entry and are restored separately.

### 6.6 Guards and safety

`CanSwapNow()` is false, and the swap is deferred, while any of these is true:

| Guard | Check | Retried on |
|---|---|---|
| Disabled | `not db.enabled` | — |
| Combat | `InCombatLockdown() or UnitAffectingCombat("player")` | `PLAYER_REGEN_ENABLED` |
| Dead or ghost | `UnitIsDeadOrGhost("player")` | `PLAYER_ALIVE`, `PLAYER_UNGHOST` |
| Casting or channeling | `UnitCastingInfo("player") or UnitChannelInfo("player")` | `UNIT_SPELLCAST_STOP` / `_CHANNEL_STOP`. This avoids breaking a hearthstone, fishing or a profession cast |
| Cursor busy | `GetCursorInfo() ~= nil` | Next `Refresh()` source |
| Blocked UI | trade, mail, merchant, bank, guild bank or loot window **visible** (`IsVisible`, not `IsShown`: the retail `BankPanel` child stays "shown" while the bank is closed, which once blocked every swap) | Matching `*_CLOSED` event |
| Item locked | `C_Item.IsLocked(location)` on the source or target | `ITEM_LOCK_CHANGED` |

Other safety rules:

- **Dismounted into combat: the gear goes back when combat ends.** If you are knocked off your mount (daze, dismount by a mob), or dismount and are attacked straight away, the game blocks armor and trinket swaps. You fight with the speed gear on, as in 3.01. The addon **must** still put the correct gear back as soon as combat ends:
  1. **Nothing is lost when the restore is blocked.** `saved[slot]` and `slotOwner[slot]` stay as they are, and `dirty = true` is set. A restore that was already scheduled (`restoreDelay`) is cancelled, not dropped: the slot stays owned, so the next `Refresh()` restores it.
  2. **On `PLAYER_REGEN_ENABLED`, `Refresh()` runs at once**, with no `restoreDelay`. The delay is only there to absorb quick dismount/remount cycles, and you could not remount during combat anyway. If the guards in §6.6 still block (dead, casting, cursor busy, looting a corpse), each retry event listed there runs `Refresh()` again until the restore goes through.
  3. **Triggers are checked again, not replayed.** The restore is not "undo the speed gear" but "work out what should be worn *now*". If combat ended while you were swimming, the swim rules apply and only the mount-only slots are restored. If you remounted the moment combat ended, the speed gear stays on and no needless 30-second trinket cooldown is started.
  4. **Every slot is restored, one equip at a time** (§6.1): both trinkets (`speedTrinketSlots = 2`), gloves and boots. If combat starts again partway through, the slots not yet restored stay pending and the next `PLAYER_REGEN_ENABLED` finishes them.
  5. **Restored to the right copy and slot**, using the saved item strings (§5.1). Each trinket goes back into the slot it came from. An empty slot is emptied again.
  6. **Dying in that combat:** the restore waits for `PLAYER_ALIVE` / `PLAYER_UNGHOST`, then runs the same way.
  7. **`/reload` or logout before combat ends:** the saved state is in SavedVariables, so the cleanup at the next login (§6.4) restores the gear.
  8. **Feedback:** while a restore is waiting, the toggle button turns yellow and its tooltip says "Restore pending (combat)". With `debug` on, a chat line confirms when the gear is back.
- **Bind on equip:** before equipping from the bags, check `C_Item.IsBound(location)`. If the item is unbound and `rule.allowBind` is false, skip it and print one chat message per item per session: "*X* would become soulbound. Enable it in the item list to allow." This replaces 3.01's `StaticPopup1` check. If the client shows a bind confirmation anyway, the addon never accepts it on the player's behalf.
- **Failure detection and back-off:** after an equip call, expect `PLAYER_EQUIPMENT_CHANGED` for that slot within 1.5 s. If it does not arrive, or `UI_ERROR_MESSAGE` reports a failure (wrong level, wrong armor type, "can't do that right now"), increase `failures[ruleId]`. After **3** failures the rule is marked failed until `/reload` or until the user edits it, with one chat message. This stops endless retry loops and red-error spam.
- **Debounce:** at most one equip per slot every 0.5 s.
- **Bags full:** a restore needs a free bag slot for the speed item. If none is free, print a warning once per session and leave the speed item on. Retry on `BAG_UPDATE_DELAYED`.
- **Saved item not in the bags:**
  - **In the bank** (`C_Item.GetItemCount(id, true)` is higher than the count in the bags): keep `saved`, warn once, and retry on `BANKFRAME_CLOSED` / `BAG_UPDATE_DELAYED`.
  - **Gone** (sold, deleted, mailed): clear `saved[slot]`, leave the speed item on, and warn once.
- **Saved item worn in another slot:** if the player moved the normal trinket from 14 to 13 by hand, restoring it into 14 would pull it out of 13. In that case clear `saved[14]` and take the speed item off to the bags instead.
- **Manual change:** if the player, or another gear addon such as the Equipment Manager, ItemRack or Outfitter, puts a non-speed item into a managed slot while a speed item should be there, treat it as the new normal item:
  - update `saved[slot]`
  - set `suppressed[slot]` until the trigger turns off
  
  The addon will not fight the player or the other addon. A change counts as "manual" when `PLAYER_EQUIPMENT_CHANGED` arrives for a slot that has no swap of ours in flight.
- **Equipment Manager sets:** `C_EquipmentSet.UseEquipmentSet` counts as a manual change. If the player's set has the speed slot marked "ignore", nothing conflicts.
- **Protected frames:** none of the equip calls are protected today. If a future Forever build requires a hardware event for equipping (§9), the engine falls back to a **"Swap now" prompt**: a `SecureActionButtonTemplate` button with `type = "macro"` and `/equipslot 14 item:11122`. It glows on the toggle button and works on click or a key binding.

### 6.7 Restore delay and hysteresis

Swapping in and out over and over is annoying, and it is also **costly**: **in Forever, equipping an on-use trinket starts a 30-second cooldown** (confirmed). Each time you dismount, the restored on-use trinket cannot be used for 30 s, and a fight often starts right after a dismount. §6.5 step 5 keeps this cost low, and the fixes below avoid needless swaps. Common cases:
- **Gathering:** herbs and ore dismount you. Dismount, gather, remount gives two swaps per node.
- **Surface bobbing:** `IsSwimming()` turns off for a moment when you jump out of water or touch a shallow shore.
- **Mounting into a vendor or flight master stop.**

Fixes:
- `restoreDelay[trigger]` (seconds, set per trigger in the settings panel): when a trigger turns off, the restore is scheduled after this delay. If the trigger turns back on before then, the restore is **cancelled**. Defaults: mounted **0 s** (3.01 behaviour; restoring fast matters if you dismount into a fight), swimming and submerged **1 s**.
- An option **"Never swap out on-use trinkets"** (default off). When on, a trinket with an on-use effect is never removed, even when §6.5 step 5 would pick it. If both trinkets are on-use, the trinket rule is skipped, which means no Carrot. That is why the option is off by default.
- **Settings tooltip text:** "Swapping a trinket back on puts it on a 30-second cooldown." The player then knows why to lock their PvP or burst trinket.
- `lockedSlots` lets the player protect one trinket slot outright, such as a PvP trinket.

### 6.8 Enable, disable and instances

- `Engine:SetEnabled(false)` restores every slot that has a `slotOwner`, the same as `AutoCarrot_EquipNormalSet`. If the restore is blocked (combat), it stays pending and runs when the guard clears, even though the addon is now "off".
- **Instances:** `instanceTypes` lets the player choose where the addon turns itself off, by `select(2, IsInInstance())`: dungeons, raids, battlegrounds, arenas and scenarios. The single 3.01 `instance` flag maps to `party` + `raid`. Battlegrounds are listed separately because the Carrot is popular there. On entering a chosen instance type, the addon turns off and sets `wasAutoDisabled`. On leaving, it turns back on only if it was turned off automatically (same logic as 3.01).
- If the player turns the addon back on inside an instance, `wasAutoDisabled` is cleared. The choice holds until the next loading screen.

### 6.9 Weapons and combat

Weapons follow different rules from armor. **In Forever, weapons can be swapped in combat, unless the player is disarmed.** Armor and trinkets cannot. A 2% speed staff is a bad weapon to fight with, so:

1. **Out of combat**, weapon rules work like any other rule.
2. **When combat starts** (`PLAYER_REGEN_DISABLED`), `Refresh()` runs a **weapon-only pass** (`CombatWeaponPass`). It immediately restores every owned weapon slot, main hand (16) first, then off hand (17), then ranged (18), one swap at a time. Armor stays as it is until combat ends (§6.6).
3. The pass waits while the player is **disarmed** (`C_LossOfControl`, `locType == "DISARM"`), retrying every second and on `LOSS_OF_CONTROL_*` events. It also waits while casting, dead or holding something on the cursor.
4. **After combat** the speed weapon goes back on if its trigger and zone still apply. Each fight therefore costs one weapon swap at the start, and that swap triggers a **global cooldown**. For this reason the weapon built-ins are **off by default**, and the editor and settings tooltips say so.

**Two-handers:**

- **Equipping a two-hander** in the main hand makes the client put the off-hand item into the bags. The engine saves the off hand too (`saved[17]`, `slotOwner[17] = rule`). It needs a free bag slot first; if there is none, it warns once and skips.
- **Equipping an off-hand speed item** while a two-hander is in the main hand works the same way in reverse: the two-hander is saved as `saved[16]`.
- **Restoring the other hand would undo the speed weapon.** While the two-hander is still wanted, restoring the off hand is blocked (`CompanionBlocked`). Restoring a saved two-hander is likewise blocked while the off-hand speed item is still wanted. The planner also reserves the off hand while a two-handed rule holds the main hand, so no other rule can claim it.
- **Restore order:** main hand first, then off hand, because slots are processed in ascending order.
- **Our own side effects are not manual changes.** The equipment-change events for the displaced hand are expected for 3 seconds (`expectChange[slot]`), so they are not mistaken for the player changing gear by hand (§6.6).

---

## 7. Discovery hints (`Discovery.lua`)

**Purpose:** help players find unknown speed gear, including unknown speed **enchants**, without anyone maintaining an item database.

### 7.1 What is scanned and when

- **When:** on `BAG_UPDATE_DELAYED` and `PLAYER_EQUIPMENT_CHANGED`, throttled to one scan every 2 s, plus `/ac scan`. Discovery is off for 5 s after login so it does not compete with the first `Refresh()`.
- **What:** every **equippable** item (`C_Item.IsEquippableItem`) in the bags **and in the equipment slots**. Gear that is already worn is included: a player may already wear unrecognised speed boots and want to make a rule for them.
- **Cache:** results are kept per item string for the session, so an item is parsed once, not on every bag update. Tooltips that are still loading (`C_TooltipInfo` returns no lines, or the item is not cached) are retried after `ContinueOnItemLoad`.
- **Skipped:** items already covered by a rule, items in `ignoredSuggestions`, and slot types not supported in v1 (§5.4).

### 7.2 Matching tooltip lines

Read `C_TooltipInfo.GetBagItem(bag, slot)` / `GetInventoryItem("player", slot)` and look at each `lines[i].leftText` (lower-cased).

1. **Only passive effects count.** Lines that start with the localized **Use:** prefix (`ITEM_SPELL_TRIGGER_ONUSE`) or **Chance on hit:** prefix (`ITEM_SPELL_TRIGGER_ONPROC`) are **ignored**. A trinket whose *on-use* effect gives movement speed, such as Nifty Stopwatch or Insignia-style items, gains nothing from being swapped on automatically. Lines with the **Equip:** prefix (`ITEM_SPELL_TRIGGER_ONEQUIP`) are strong matches. Unprefixed green lines (enchant lines such as "Minor Speed" or "Mithril Spurs") are weak matches.
2. **Set-bonus lines** ("(2) Set: …") become **set suggestions** (§5.6). `n` is the number of pieces needed. The pieces come from the item's set ID (`GetItemInfo` return 16 with `C_LootJournal.GetItemSetItems`) when the client provides them. Otherwise the suggestion asks the player to add the set with `/ac addset`.
2b. **Zone lists** are read from the text after the percentage: "…by 3% in The Barrens, Thousand Needles, Razorfen Kraul, and Razorfen Downs." becomes four zones. "Eastern and Western Plaguelands" becomes "Eastern Plaguelands" and "Western Plaguelands" (`Planner.SplitZones`). "…in Desert areas" becomes a zone group (§5.5). Zone names are compared case-insensitively and ignore a leading "The", and instance names count, so "the Deadmines" matches inside the dungeon.
3. Patterns:

```lua
ns.SPEED_PATTERNS = {
  { pattern = "while mounted",          trigger = "mounted"   }, -- "movement speed while mounted" must not become "always"
  { pattern = "mount.- speed",          trigger = "mounted"   },
  { pattern = "riding speed",           trigger = "mounted"   },
  { pattern = "swim.- speed",           trigger = "swimming"  },
  { pattern = "underwater",             trigger = "submerged" }, -- also catches water-breathing; see note
  { pattern = "movement speed",         trigger = "always"    },
  { pattern = "run speed",              trigger = "always"    },
  { pattern = "minor speed",            trigger = "always"    },
  { pattern = "increases speed",        trigger = "always"    },
}
```

  - **Water breathing** ("allows underwater breathing") is a useful submerged item even though it does not increase speed. Keep the match, but label the suggestion "Underwater effect" rather than "speed".
  - The patterns are lower-case English. Other locales get a table indexed by `GetLocale()`. If a locale is missing, discovery is turned off and `/ac add` still works.
4. **Enchant or item?** If the matching line is an enchant line, and the item link has a non-zero enchantID, suggest an **enchant rule** (`match = { enchantID = … }`). Otherwise suggest an item rule. A speed enchant applied to a new pair of boots is then recognised without the player doing anything.

### 7.3 Output

- **Chat:** one line per new candidate per session, only if `db.chatSuggestions` is on.
  - Text: `AutoCarrot: [Item] looks like mount-speed gear. [Add] [Ignore]`
  - [Add] and [Ignore] are addon hyperlinks, `|Haddon:AutoCarrotForever:add:<itemID or e:enchantID>|h[Add]|h`, handled with `EventRegistry:RegisterCallback("SetItemRef", …)` or a `hooksecurefunc("SetItemRef", …)` fallback. They are **not** made-up link types, which the client drops.
  - [Add] opens the editor with the rule filled in. It never adds the rule without the user seeing it.
- **Editor:** an entry in the **Suggestions** section (§8.2), with the suggested trigger and any zone condition (§5.5) already filled in.
- **Ignore:** stored in the global `ignoredSuggestions`, so it applies to every character.

---

## 8. UI

### 8.1 Settings panel (`UI/Settings.lua`)

Location: **Esc → Options → AddOns → AutoCarrot Forever**. A single **canvas page** (`Settings.RegisterCanvasLayoutCategory`) built from plain widgets, with no Settings list rows and no sub-pages, because:
- the Settings list (vertical layout) cannot hold the collapsible zone-group lists;
- its button rows showed empty hover boxes on Forever;
- switching to another settings page from a button threw an error during combat.

Everything lives on this one scrolling page:

| Control | Setting |
|---|---|
| Checkbox | Enabled |
| Checkboxes | Turn off inside: Dungeons / Raids / Battlegrounds / Arenas / Scenarios |
| Section header | Built-in items |
| Checkbox per built-in | Every entry in `ns.BUILTINS`. The weapon ones are off by default |
| Section header | Behaviour |
| Choice (menu) | Trinket slots for speed items: Two (default) / One (§6.5) |
| Choice (menu) | Preferred trinket slot: Auto / Top (13) / Bottom (14) |
| Checkboxes | Lock trinket 1 / trinket 2 / ring 1 / ring 2 (`lockedSlots`) |
| Checkbox | Never swap out on-use trinkets (§6.7) |
| Stepper `< 1.0 s >` (0–5 s, step 0.5) | Restore delay: mounted / swimming / underwater |
| Section header | Interface |
| Checkbox | Show toggle button |
| Stepper (0.5–2.0, step 0.1) | Toggle button scale |
| Checkbox | Show minimap button |
| Checkbox | Show speed-item suggestions in chat |
| Button | Button positions: Reset |
| Button | Custom items: Open item editor (§8.2) |
| Checkbox | Debug messages |
| Section header | **Zone groups** (inline, last because its height changes) |

Steppers replace sliders, because slider templates differ between client versions. Every change calls `ns.Engine:OnSettingsChanged()`, which refreshes the engine and the buttons. The page re-reads all values when shown and on `AC_STATUS`, so slash-command changes show up. **Using the page in combat is safe:** nothing on it switches settings pages or touches protected frames. Changes are saved at once and take effect when the engine's guards allow (§6.6). `UI.OpenSettings` (minimap Shift-click, `/ac options`) refuses politely in combat instead of calling `Settings.OpenToCategory`.

**Zone groups section** (`UI/ZoneGroups.lua`, `UI.CreateZoneGroupsSection`, embedded at the bottom of the page):

- The top line shows the player's current zone and which groups it belongs to.
- Each group is a **collapsible row**: +/- or a click on its name opens it. The row shows the zone count and "you are here", and its tooltip lists the zones and the rules that use the group. Each row has two buttons:
  - **Add current zone** or **Remove current zone**
  - **Defaults** (built-in groups: adds back removed default zones) or **Delete** (custom groups no rule uses)
- An open group lists its zones, each with its map ID once known, a "you are here" marker and an **X** to remove it.
- Below the list, **New group** creates "<name> areas" groups (for example "Snowy" becomes *Snowy areas*), to pick under *Where* in the item editor.
- The section reports its height back to the page whenever groups open or close, so the page scrolls correctly. It refreshes on zone changes and on any rule or group change.

### 8.2 Custom item editor (`UI/ItemList.lua`)

A movable window (`BasicFrameTemplateWithInset`, strata `DIALOG` so it sits above the options panel). It opens with `/ac`, a right-click on the minimap or toggle button, or the options page's *Open item editor* button. It closes with Esc (`tinsert(UISpecialFrames, …)`).

```
┌ Custom Items (account-wide) ──────────────────────────────────────────────────┐
│ ┌──────────────┐  Item: [ link or ID ______________ ]  Match: (•) Item ( ) Enchant [Add] │
│ │  Drop item   │                                                               │
│ │    here      │                                                               │
│ └──────────────┘                                                               │
│ ─ Rules ─────────────────────────────────────────────────────────────────────── │
│ [x] [icon] Some Swift Boots    Slot:[Auto ▾] When:[Always ▾] ⚠  Pri:[50] [✕]   │
│ [x] [icon] Aquatic Trinket     Slot:[Auto ▾] When:[Swimming, Mounted ▾] Pri:[50] [✕] │
│ [x] [ench] "Mount Speed" enchant  Slot: Feet  When:[Mounted ▾]   Pri:[60] [✕]   │
│ ─ Suggestions ───────────────────────────────────────────────────────────────── │
│ [icon] Odd Spurs   "Equip: +3% mount speed"   [Add as Mounted] [Ignore]        │
└────────────────────────────────────────────────────────────────────────────────┘
```

- **Adding items:**
  - Drag an item from the bags onto the drop zone (`OnReceiveDrag` + `GetCursorInfo()`, then `ClearCursor()` so the item goes back to its bag).
  - Shift-click an item link into the edit box (hook `ChatEdit_InsertLink` while the box has focus).
  - Type an item ID.
- **Item or enchant:** if the item that was dropped or linked has an enchant, the **Match** choice appears. "Enchant" makes a rule that matches any item with that enchant, and its slot is fixed to the item's slot.
- **Checks when adding:**
  - Unsupported slots (shirts, tabards): rejected with a message (§5.4). Weapon rows get a tooltip warning about the swap at the start of each fight (§6.9).
  - Not equippable: rejected.
  - Same match already has a rule: allowed, because one item may have several rules with different triggers, but an "also used by rule N" note is shown.
  - Same item as a built-in: the note says "overrides built-in X" (§5.3).
  - The character cannot use the item: shown greyed out with the reason (§5.4).
- **Rows:** `ScrollBox` + `DataProvider` (`CreateScrollBoxListLinearView`). Each row has:
  - an enable checkbox
  - the icon and name, with a hover tooltip (`GameTooltip:SetHyperlink`)
  - a slot dropdown: **Auto** plus the slots valid for the item's equip location
  - a trigger multi-select dropdown built from `ns.TRIGGERS`. Choosing **Always** shows a ⚠ with the "stays on in combat" tooltip (§6.3)
  - a **Where** menu (§5.5) with these choices:
    - Any zone
    - tick zone groups (each shows its zones)
    - remove single zones
    - add the current zone to the rule
    - add the current zone to, or remove it from, each group the rule uses
  - a priority box (whole numbers 0–200, checked on focus loss)
  - an "Outside instances only" toggle
  - a remove button with a confirmation
  - a status icon: active now / waiting (combat) / failed (§6.6), with the reason in the tooltip
- **Unloaded items:** the row shows a placeholder until `ContinueOnItemLoad` fires.
- **Unbound BoE items** show a warning icon, and an **Allow binding** checkbox sets `allowBind`.
- **Order:** the list order is only the tie-breaker when priorities are equal (§9). Up and down arrows are enough for v1. Drag-to-reorder is not needed.

### 8.3 Toggle button (`UI/Buttons.lua`)

Keeps the 3.01 behaviour, with these changes:
- A plain `Button` with the carrot icon (134010). It deliberately does **not** use `ActionButtonTemplate`: on Forever that template's scripts swallowed Alt-drag.
- **Alt + left mouse button moves it.** This is handled in `OnMouseDown`/`OnMouseUp`, not drag events, and the mouse-up that ends a move does not toggle the addon. The position is saved in `AutoCarrotForeverDB.button.pos`, not the client layout cache (`SetUserPlaced(false)`), so Forever's Edit Mode never resets it and the player never needs Edit Mode for it.
- Green overlay when on, red when off, **yellow when a swap is pending** (combat, cast, bags full).
- Left-click turns the addon on or off. Right-click opens the editor.
- Its tooltip lists the active rules, what each slot has swapped in, and any pending or failed state with the reason.
- If the "Swap now" fallback is ever needed (§6.6), this button becomes a secure button. Its attributes can only be changed out of combat.

**Hover tooltip** (toggle button, minimap button and addon-compartment entry share it):
- It shows the status lines, then a **live speed readout**: current speed, mounted or run speed, and swim speed while swimming. These are the same numbers as `/ac speed`, from `GetUnitSpeed` and secret-safe, so a zone item can be checked just by hovering.
- **Polling only while hovered:** `OnEnter` starts a `C_Timer.NewTicker(0.5)` that rebuilds the tooltip. `OnLeave` cancels it, and so does the ticker itself if `GameTooltip` stops being shown or gets a different owner (for example the button was hidden mid-hover). Nothing runs while the mouse is elsewhere.

### 8.4 Minimap button

Hand-rolled, with no LibDBIcon:
- A round 31×31 button on `Minimap`, positioned by `db.minimap.angle`.
- Dragging updates the angle with `math.atan2`. Square minimaps are supported through `GetMinimapShape()` when another addon defines it.
- Left-click turns the addon on or off. Right-click opens the editor. Shift-click opens the settings panel.
- The icon is desaturated when the addon is off.
- Forever reskinned the minimap header in Beta 5, so the button anchors to `Minimap` itself, never to header child frames.
- If `AddonCompartmentFrame` exists, the addon also registers there (TOC `AddonCompartmentFunc`). A player who hides the minimap button can still reach the addon that way.

### 8.5 Slash commands

| Command | Action |
|---|---|
| `/ac` | Open the custom item editor |
| `/ac on` \| `off` \| `toggle` | Turn the addon on or off |
| `/ac add <link\|id> [trigger[,trigger]] [slot]` | Add a custom rule |
| `/ac addenchant <link> [trigger]` | Add an enchant rule using the enchant on the linked item |
| `/ac addset <need> <link> <link> [...] [trigger]` | Add a set rule (§5.6), e.g. `/ac addset 2 [Signet] [Cloak] always` |
| `/ac remove <link\|id\|rule#>` | Remove a custom rule |
| `/ac list` | Print all rules, their state, and the reason for any failure |
| `/ac scan` | Run discovery now |
| `/ac restore` | Clear the failed, manual-change and warning flags, then re-sync gear at once (no restore delay). Speed gear whose trigger is still on stays on |
| `/ac lock <slot>` / `unlock <slot>` | Lock or unlock a slot |
| `/ac zone` | Show the current zone (name and map ID) and every zone group, marking the ones you are in |
| `/ac zone add\|remove <group>` | Add or remove the current zone in a group, e.g. `/ac zone add desert` |
| `/ac speed` | Print current, ground and swimming speed in %, to test zone items. The same readout is in the button tooltips (§8.3) |
| `/ac options` | Open the settings panel |
| `/ac debug 0\|1` | Log decisions (rule chosen, guard that blocked a swap) to chat |
| `/ac button 0\|1\|reset\|scale <n>` | Same as 3.01 |
| `/ac ridinggloves 0\|1`, `mithrilspurs`, `instance`, `enabled` | Old 3.01 keys, kept as aliases. `swimbelt` and `swimhelm` only print that those items don't exist in Forever |

- Registered as `/autocarrot`, `/acf` and `/ac`. If another addon has already taken `/ac`, drop it and keep the other two.
- **Do not lower-case the whole message.** 3.01 did ([AutoCarrot.lua:370](../AutoCarrot-3.01/AutoCarrot.lua#L370)), and that breaks item links, which contain case-sensitive data. Only the command keyword is lower-cased.
- Links contain spaces, so they are pulled out with a pattern (`|c.-|H(item:[^|]+)|h.-|h|r`) **before** the message is split on spaces.

---

## 9. Edge cases and risks

| Case | Handling |
|---|---|
| Mount or swim starts in combat | Deferred until `PLAYER_REGEN_ENABLED` (§6.6) |
| Dismounted into combat, speed gear still on | Kept on during combat (the game requires it). Correct gear restored as soon as combat ends, slot by slot, after checking the triggers again (§6.6) |
| Gathering or vendor stops (fast dismount/remount) | `restoreDelay`, on-use protection, locked slots (§6.7) |
| Bobbing at the water surface | 1 s swim restore delay (§6.7) |
| Two rules want the same slot | Higher priority wins. On a tie, custom rules win, then built-ins, then list order |
| Mounted on a swimming mount | Both `mounted` and `swimming` rules apply. They are given separate slots (§6.5) |
| Same item in both trinket slots | Unique-equipped check (§6.5) |
| Slot was empty before the swap | `saved[slot] = false`, so restoring takes the speed item off (§5.1) |
| Speed item recorded as normal gear (crash, `/reload` mid-swap) | Never-save-a-speed-item guard (§5.1) and the cleanup on login (§6.4) |
| Normal item moved to the other slot by hand | Detected. The speed item goes to the bags instead (§6.6) |
| Restore with full bags | Warn once, leave the speed item on, retry on bag update |
| Saved item in the bank | Keep it and retry later. Sold or deleted: clear it (§6.6) |
| Item on the cursor | Swap deferred (§6.2) |
| Item locked, or several slots changing at once | One equip in flight at a time (§6.1) |
| Character cannot use the item (level, armor type) | Skipped before trying. Real failures are backed off after 3 (§6.6) |
| Other gear addons (Equipment Manager, ItemRack, Outfitter) | Treated as manual changes. The addon does not fight them (§6.6) |
| Casting (hearthstone, fishing, professions) | Swap deferred until the cast ends (§6.6) |
| Taxi | `UnitOnTaxi` plus control-lost and control-gained events (§6.4) |
| Druid forms, Ghost Wolf | Not mounts. Swim rules still apply in Aquatic Form (§6.3) |
| Item info not cached | `Item:CreateFromItemID(id):ContinueOnItemLoad` before evaluating or showing it |
| Item string format changes after a patch | Bag lookup by itemID + enchant + suffix (§5.1) |
| On-use effect gives speed, not a passive equip effect | Not suggested by discovery (§7.2) |
| API changes between beta builds | Every client API call goes through small wrappers in `Core.lua` (`ns.API.*`), so a fix touches one place |
| Equipping becomes restricted to hardware events | Secure "Swap now" fallback button (§6.6) |
| Secret-value restrictions reach item APIs | If tooltip data comes back secret, discovery turns itself off. The rest of the addon does not depend on it |
| Speed weapon equipped when a fight starts | Real weapon put back at once (weapon-only combat pass). Waits while disarmed (§6.9) |
| Two-hander pushes the off hand into the bags | Off hand saved and owned. Its restore is blocked while the two-hander is wanted. Needs a free bag slot (§6.9) |
| Set bonus needs 2 pieces | Set rule, placed all or nothing (§5.6) |
| "Movement speed while mounted" read as run speed | "while mounted" pattern checked first (§7.2) |
| Zone-limited items (The Desert Rose) | Zone condition. Only worn in matching zones. Leaving the zone restores normal gear (§5.5) |
| Zone group list wrong or incomplete | Editable in game. Matched by name until the map ID is learned (§5.5) |
| Mount-speed items stack in Forever | All mount rules are worn together. The trinket count is capped by `speedTrinketSlots` (§5.3, §6.5) |
| Restored on-use trinket comes back with a 30 s cooldown | Cheapest-slot scoring, restore delay, locks, "never swap on-use" option (§6.5, §6.7) |
| Two characters share custom rules, but only one can use an item | Rules are account-wide. Usability is checked for each character (§5.4) |

---

## 10. Testing

There is no automated test harness for WoW addons in this repo, so testing is manual in game. Run `/console scriptErrors 1`, use BugSack/BugGrabber if installed, and turn on `/ac debug 1`.

The rule-choice logic (`AssignSlots`, excludes, priority, the never-save-a-speed-item guard) has no WoW API calls if the inputs are passed in. It **should be written as pure functions** so it can be unit-tested outside the game with plain Lua 5.1 and a few stubs, and a small `tests/` folder is planned for that.

| # | Scenario | Expected |
|---|---|---|
| 1 | Carrot in the bags, mount, then dismount | Trinket 14 becomes the Carrot, then goes back to the original |
| 2 | Original trinket in slot 13, Carrot already in slot 14 | No swap fights. Restoring puts the right item back |
| 3 | Custom swim item (trigger Swimming) and custom underwater item (trigger Underwater). Enter water, swim, dive, leave | Swim item swaps while swimming. Underwater item swaps only while submerged. Both restore |
| 4 | Add a custom item with trigger "swimming" | Swaps while swimming |
| 5 | Add a custom BoE item | Not equipped. Warning printed. Equipped after enabling Allow binding |
| 6 | Mount while in combat | No swap until combat ends, then it swaps |
| 7 | Turn off with the speed gear on | All normal gear restored |
| 8 | Enter a dungeon with "turn off in dungeons" | Addon turns off and gear is restored. On leaving, it turns back on |
| 9 | Speed item in the bags with a matching tooltip | Suggestion appears in chat and in the editor. Ignore persists |
| 10 | `/reload` and relog | Settings, custom rules, button positions and saved gear persist |
| 11 | Taxi flight | No swap |
| 12 | Full bags, then dismount | One warning, no Lua error. Restores after a slot is freed |
| 13 | Empty trinket slot, mount, dismount | Carrot goes on, then back to the bags. The slot is empty again |
| 14 | `/reload` while mounted with the Carrot on, then dismount | The original trinket comes back (saved state survives). The Carrot is never recorded as normal |
| 15 | Gather a herb while mounted, with mounted restore delay 2 s | No swap if you remount within 2 s |
| 16 | Jump in and out of shallow water with a custom swim item | No flapping (1 s delay) |
| 17 | Hold an item on the cursor, then mount | No swap until the cursor is cleared. No item lost |
| 18 | Equip a different trinket by hand while mounted | It stays on. The addon does not swap it back until after dismount |
| 19 | Custom item too high-level for the character | Greyed out in the editor. No equip attempts or error spam |
| 20 | Swimming mount: mounted + swimming rules on different trinkets | Both slots swapped. Both restored afterwards |
| 21 | Hearthstone cast while dismounting | The cast is not interrupted. The swap happens after the cast |
| 22 | Enchant rule: put a known speed enchant on new boots | Recognised without editing the rule |
| 23 | Custom rule added on character A, then log in on character B | The rule shows up on B |
| 24 | `/ac add` with a shift-clicked link (mixed case) | Rule created for the right item |
| 25 | Lock trinket slot 13, mount with the Carrot | The Carrot only ever goes into 14 |
| 26 | Carrot + a custom mount-speed trinket in the bags, glove and boot items carrying enchants 930 and 464, default settings (`speedTrinketSlots = 2`) | Both trinkets in the trinket slots, plus the enchanted gloves and boots, because the bonuses stack. All four normal items restored on dismount |
| 27 | Same as #26 with `speedTrinketSlots = 1` | Only the higher-priority trinket goes on, plus gloves and boots. The other trinket stays in the bags |
| 28 | Normal trinkets: one passive, one on-use and ready. Mount with the Carrot | The passive trinket is swapped out. The on-use trinket is untouched, so no 30 s cooldown |
| 29 | Normal trinkets: both on-use, one with 90 s of cooldown left. Mount | The trinket already on cooldown is swapped out, which costs nothing |
| 30 | Weapons swapped by hand in combat, with no speed weapon owned | Ignored by the addon. Only owned weapon slots are restored in combat (§6.9) |
| 31 | Mounted with two speed trinkets, gloves and spurs. Knocked off by a mob, fight, combat ends | Speed gear stays on during the fight. When combat ends, both original trinkets, gloves and boots go back into their original slots, with no delay |
| 32 | Same as #31, plus a custom swim item, but combat ends while swimming | Mount gear restored. The swim item goes on instead of being skipped |
| 33 | Same as #31, but a second pull starts after one trinket is restored | Remaining slots restored after the second combat ends |
| 34 | Same as #31, but `/reload` during combat | Gear restored after the reload, once out of combat |
| 35 | The Desert Rose and the Carrot in the bags. Mount in Tanaris, then ride into a non-desert zone | Both trinkets in Tanaris. On leaving the desert the Rose comes off and the normal trinket goes back. The Carrot stays |
| 36 | The Desert Rose, `speedTrinketSlots = 1`. Mount in Tanaris, then outside the desert | The Rose in Tanaris (priority 110). The Carrot outside |
| 37 | Stand in a zone not in the group, `/ac zone add desert`, mount | The Rose is equipped. `/ac zone` lists the zone with its map ID |
| 38 | A bag item with "… in Snowy areas" | Suggestion shows "(Snowy areas)". After Add, the editor says the group has no zones yet |
| 39 | Staff of Westfall enabled, in Westfall, a one-hander and shield equipped | Staff equipped, shield goes to the bags. Leaving Westfall restores the main hand first, then the shield |
| 40 | Same as #39, then pull a mob | The real weapon and shield go back on immediately in combat. The staff returns after combat |
| 41 | Same as #40 while disarmed | No swap while disarmed. The swap happens as soon as the disarm ends |
| 42 | Same as #39 with full bags | One warning. The staff is not equipped |
| 43 | Two Blessing of Kalimdor pieces in the bags, in the Barrens | Both pieces equipped together. Leaving the Barrens restores both slots |
| 44 | Only one Blessing of Kalimdor piece | Nothing equipped |
| 45 | Wintersaber gloves and a Riding Skill-enchanted pair, mounted in Winterspring | Wintersaber gloves (priority 110). Outside Winterspring: the enchanted pair |
| 46 | Tooltip "(2) Set: Increases mount speed by 5% in Eastern and Western Plaguelands." | Set suggestion with zones Eastern Plaguelands and Western Plaguelands |

---

## 11. Milestones

1. **Port.** New TOC (`16001`), `Core.lua` with API wrappers and safe DB init, built-in rules running as in 3.01. *Exit:* tests 1, 3, 7 and 11 pass.
2. **Rule engine.** `Items.lua` data, the single engine loop, events instead of `OnUpdate`, equipping by bag location, slot choice, guards, restore delay, crash cleanup. Pure-Lua unit tests for `AssignSlots`. *Exit:* tests 1–3, 6–8, 11–18, 20, 21, 25–29, 31–37, 39–45 pass.
3. **Custom rules and slash commands.** The global DB, item and enchant rules, the usability check, failure back-off, `/ac add/addenchant/remove/list/restore`. *Exit:* tests 4, 5, 19, 22–24 pass.
4. **Settings panel and buttons.** *Exit:* every setting works from the UI. Test 10 passes.
5. **Item editor.** Drag-and-drop, rows, multi-trigger dropdown, status icons.
6. **Discovery hints.** *Exit:* test 9 passes. No suggestions for on-use or set-bonus speed effects.
7. **Release.** README with credit to kebabstorm, CurseForge packaging (`.pkgmeta`), a check against the latest Forever beta build.

---

## 12. Open questions

1. **Built-in items in Forever:** do the Carrot (11122) and enchants 930 and 464 exist and still give mount speed? Riding Crop, Skybreaker Whip, the swim belt and the swim helm are confirmed missing (§3.4).
2. **Level cap:** 3.01 stopped the mount swaps above level 70 because the Carrot stops working at higher levels. What is Forever's cap, and do the items have a level limit? The fork removes the hard-coded check. If a limit exists, it becomes a `maxLevel` field on the rule, read from the tooltip where possible.
3. ~~**Flying:**~~ Answered: Forever has no flying mounts. There is no flying trigger (§6.3).
4. **Weapon swap cost:** does a weapon swap in combat trigger a global cooldown in Forever, and does it reset the swing timer? This decides whether the weapon built-ins should stay off by default (§6.9).
5. **Distribution:** publish as "AutoCarrot Forever" on CurseForge or Wago? Check the license and permission with the original author, kebabstorm.
6. **Sharing rules:** add an export/import string for custom rules later, so players can share newly found items?

7. **Desert areas:** which zones count? The default is Tanaris, Silithus, **Desolace and Westfall (both confirmed in game)**. Check with `/ac speed` while mounted in other dry zones (Badlands, Thousand Needles, Durotar, the Barrens) and fix the group with `/ac zone add|remove desert`.
8. **Rider of the Plaguelands drop source:** the pieces are now known and built in (§3.4), but nobody has reported where they drop. Plaguelands rares are the likely source.
9. **Enchant Boots - Speed:** which enchant ID does it put on boots? With that ID it can become a built-in like Mithril Spurs. Is it live or PTR-only?
10. **`C_LootJournal.GetItemSetItems`:** does it return the pieces of Forever's new sets? If not, set suggestions fall back to `/ac addset` (§7.2).

### Answered in game (2026-11-11)

- **Equip cooldown:** equipping an on-use trinket starts a 30-second cooldown. → Slot cost scoring in §6.5 step 5, plus §6.7.
- **Combat swaps:** armor and trinkets cannot be swapped in combat. Weapons can, unless the player is disarmed. → The combat model in §6.6 is correct. Weapons stay out of v1 (§5.4).
- **Stacking:** mount-speed bonuses from different items stack. → `excludes` removed from the built-ins. The `speedTrinketSlots` setting was added (§5.3, §6.5).

---

## 13. Implementation notes (v4.0.0)

Where the first build differs from the sections above, and why:

- **No inventory cache.** `Refresh()` scans bags and equipment every time it runs. It only runs on events and on changes to polled triggers, never every frame, so the cost is small and stale-cache bugs are impossible.
- **Rule lists use a plain `ScrollFrame`** with rows created as needed, not `ScrollBox`/`DataProvider`. The custom list is short, and `UIPanelScrollFrameTemplate` exists on every client version.
- **The editor is its own window.** It opens from a button on the options page; there are no settings sub-pages (§8.1).
- **Built-in items that are not soulbound** are never equipped automatically. The player is asked once to equip the item by hand to bind it. Custom rules use the per-rule *Allow binding* box (§6.6).
- **Unbound items with permission** are equipped through `EquipItemByName`, so the client shows its own bind confirmation. Everything else uses the bag-location path (§6.2).
- **Usability in the engine is checked by required level only.** Class and armor-type problems are caught by the failure back-off (§6.6). The editor uses the full check (`C_PlayerInfo.CanUseItem`) to grey out rows.
- **With `/ac debug 1`**, every change in what the engine is waiting for is logged, e.g. "Waiting: window (BankPanel)" or "No longer waiting". This makes a stuck guard easy to spot.
- **Errors inside `Refresh()`** are reported once per distinct message (`xpcall`), not on every event. Forever pauses all Lua error reporting after 100 errors, which would hide every other addon's errors too.
- **One-handed weapons** are only placed in the main hand. Offering the off hand would need a dual-wield check.
- **Hiding unverified built-ins (§3.4)** is not done yet, because nobody has checked which ones exist in Forever. Every built-in is listed.
- **Missing 3.01 items:** Riding Crop, Skybreaker Whip, the swim belt and the swim helm are not in Forever. → Removed from the built-ins (§3.4). An item named "Riding Gloves" exists but gives no speed, so rules match enchant and item IDs only, never names.
- **Zone-limited items:** The Desert Rose (274648) gives +7% mount speed in Desert areas. → Built-in with a zone condition. Zone groups added (§5.5).
- **More Forever speed gear** (research, 2026-11-11): Wintersaber Hide Lined Gloves, Agamaggan's Clutch, the Blessing of Kalimdor set and three two-handed weapons. → New built-ins (§3.4). Weapon support (§6.9) and set rules (§5.6) added.
- **Desert areas:** Desolace counts (tested in game). → Added to the default desert group, with a migration for existing settings (§5.5).
- **v4.0 review (2026-11-11):**
  - Forever developer notes report cursor calls being forbidden in some contexts. → Equipping now goes through `C_Item.EquipItemByName`, with blocked-action detection and fallbacks (§6.2).
  - Cooldowns and unit values can be secret. → Cooldown and speed reads are made secret-safe.
  - Forever has no flying mounts. → The Flying trigger was removed entirely. Global DB migration 4 strips it from saved custom rules, and character DB migration 2 removes its restore delay.
  - The Rider of the Plaguelands pieces were found. → Added as a built-in set.
- **Desert areas:** Westfall counts (tested in game). → Added to the default desert group, with a migration for existing settings (§5.5).
