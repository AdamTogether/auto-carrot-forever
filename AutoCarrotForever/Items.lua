local ADDON, ns = ...

-- Inventory slot ids
ns.SLOT = {
    HEAD = 1, NECK = 2, SHOULDER = 3, SHIRT = 4, CHEST = 5, WAIST = 6, LEGS = 7,
    FEET = 8, WRIST = 9, HANDS = 10, FINGER1 = 11, FINGER2 = 12,
    TRINKET1 = 13, TRINKET2 = 14, BACK = 15, MAINHAND = 16, OFFHAND = 17,
    RANGED = 18, TABARD = 19,
}

ns.SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist",
    [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands",
    [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2",
    [15] = "Back",
}

-- Supported equip locations (DESIGN.md §5.4). Weapons, shirts and tabards are
-- deliberately absent in v1.
ns.EQUIP_LOC_SLOTS = {
    INVTYPE_HEAD = { 1 },
    INVTYPE_NECK = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
}

-- Zone groups (DESIGN.md §5.5): default contents for "<x> areas" item effects.
-- The player can edit them (account-wide). Which zones Blizzard counts as
-- "Desert areas" is not published; Tanaris and Silithus are the safe start.
-- Zones are matched by name (and map ID once captured in game), because map
-- IDs on the Forever client are not known yet.
ns.ZONE_GROUP_DEFAULTS = {
    desert = { { name = "Tanaris" }, { name = "Silithus" } },
}

-- Built-in rules (DESIGN.md §5.3). Mount-speed bonuses stack in Forever, so no
-- built-in excludes another.
--
-- Riding Crop, Skybreaker Whip, the swim belt and the swim helm from 3.01 do not
-- exist in Forever and are deliberately left out (DESIGN.md §12).
--
-- The two enchant rules match the ENCHANT ID only, never an item name. Forever
-- has an item called "Riding Gloves" that gives no speed; it is not the 3.01
-- riding-glove enchant and must never be matched by name.
ns.BUILTINS = {
    -- Forever-only: "Equip: Increases mount speed by 7% in Desert areas."
    { id = "desertRose", name = "The Desert Rose", match = { itemID = 274648 }, slots = { 13, 14 }, trigger = "mounted", priority = 110,
      zones = { { group = "desert" } } },
    { id = "carrot", name = "Carrot on a Stick", match = { itemID = 11122 }, slots = { 13, 14 }, trigger = "mounted", priority = 100 },
    { id = "ridingSkill", name = "Riding Skill glove enchant (#930)", match = { enchantID = 930 }, slots = { 10 }, trigger = "mounted", priority = 100 },
    { id = "mithrilSpurs", name = "Mithril Spurs boot enchant (#464)", match = { enchantID = 464 }, slots = { 8 }, trigger = "mounted", priority = 100 },
}
