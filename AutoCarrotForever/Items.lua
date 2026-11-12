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
    [15] = "Back", [16] = "Main hand", [17] = "Off hand", [18] = "Ranged",
}

-- Weapon slots can be swapped in combat (unless disarmed); see DESIGN.md §6.9.
ns.WEAPON_SLOTS = { [16] = true, [17] = true, [18] = true }

-- Supported equip locations (DESIGN.md §5.4). Shirts and tabards are left out:
-- they have no stats worth swapping.
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
    INVTYPE_WEAPON = { 16 },          -- one-hand: main hand only (no dual-wield guessing)
    INVTYPE_2HWEAPON = { 16 },        -- also takes the off hand
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}

ns.TWO_HAND_LOCS = { INVTYPE_2HWEAPON = true }

-- Zone groups (DESIGN.md §5.5): default contents for "<x> areas" item effects.
-- The player can edit them (account-wide). Blizzard doesn't publish which
-- zones count as "Desert areas"; Desolace is confirmed in game, Tanaris and
-- Silithus are the obvious deserts.
-- Zones are matched by name (and map ID once captured in game), because map
-- IDs on the Forever client are not known yet.
ns.ZONE_GROUP_DEFAULTS = {
    desert = { { name = "Tanaris" }, { name = "Silithus" }, { name = "Desolace" } },
}

local function zones(...)
    local list = {}
    for i = 1, select("#", ...) do list[i] = { name = (select(i, ...)) } end
    return list
end

-- Built-in rules (DESIGN.md §3.4, §5.3). Mount-speed bonuses stack in Forever,
-- so no built-in excludes another.
--
-- Riding Crop, Skybreaker Whip, the swim belt and the swim helm from 3.01 do not
-- exist in Forever and are deliberately left out (DESIGN.md §12).
--
-- The two enchant rules match the ENCHANT ID only, never an item name. Forever
-- has an item called "Riding Gloves" that gives no speed; it is not the 3.01
-- riding-glove enchant and must never be matched by name.
--
-- defaultOff: weapon swaps cost a global cooldown when a fight starts (the real
-- weapon goes back on in combat), so weapon built-ins are opt-in.
ns.BUILTINS = {
    -- "Equip: Increases mount speed by 7% in Desert areas."
    { id = "desertRose", name = "The Desert Rose", match = { itemID = 274648 }, slots = { 13, 14 },
      trigger = "mounted", priority = 110, zones = { { group = "desert" } } },
    { id = "carrot", name = "Carrot on a Stick", match = { itemID = 11122 }, slots = { 13, 14 },
      trigger = "mounted", priority = 100 },
    -- "Equip: Increases movement speed while mounted by 6% in Winterspring."
    { id = "wintersaberGloves", name = "Wintersaber Hide Lined Gloves", match = { itemID = 284266 }, slots = { 10 },
      trigger = "mounted", priority = 110, zones = zones("Winterspring") },
    { id = "ridingSkill", name = "Riding Skill glove enchant (#930)", match = { enchantID = 930 }, slots = { 10 },
      trigger = "mounted", priority = 100 },
    { id = "mithrilSpurs", name = "Mithril Spurs boot enchant (#464)", match = { enchantID = 464 }, slots = { 8 },
      trigger = "mounted", priority = 100 },
    -- "Equip: Increases movement speed by 3% in The Barrens, Thousand Needles, Razorfen Kraul, and Razorfen Downs."
    { id = "agamaggansClutch", name = "Agamaggan's Clutch", match = { itemID = 6693 }, slots = { 11, 12 },
      trigger = "always", priority = 100,
      zones = zones("The Barrens", "Thousand Needles", "Razorfen Kraul", "Razorfen Downs") },
    -- "(2) Set: Increases movement speed by 5% in The Barrens and Stonetalon Mountains."
    { id = "blessingOfKalimdor", name = "Blessing of Kalimdor (2-piece set)", kind = "set", need = 2,
      pieces = { { itemID = 285330 }, { itemID = 285331 }, { itemID = 285329 } }, -- ring, neck, cloak
      trigger = "always", priority = 100, zones = zones("The Barrens", "Stonetalon Mountains") },
    -- Two-handed weapons: "Movement speed increased by 2% in ..."
    { id = "staffOfWestfall", name = "Staff of Westfall (two-hand)", match = { itemID = 2042 }, slots = { 16 },
      twoHand = true, defaultOff = true, trigger = "always", priority = 100,
      zones = zones("Elwynn Forest", "Westfall", "Redridge Mountains", "The Deadmines") },
    { id = "forsakenGreataxe", name = "Forsaken Greataxe (two-hand)", match = { itemID = 251533 }, slots = { 16 },
      twoHand = true, defaultOff = true, trigger = "always", priority = 100,
      zones = zones("Silverpine Forest", "Hillsbrad Foothills") },
    { id = "gnarledNecromancersStaff", name = "Gnarled Necromancer's Staff (two-hand)", match = { itemID = 251534 }, slots = { 16 },
      twoHand = true, defaultOff = true, trigger = "always", priority = 100,
      zones = zones("Silverpine Forest", "Hillsbrad Foothills") },
}
