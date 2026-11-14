local ADDON, ns = ...

ns.name = ADDON
ns.version = "4.0.0"

--------------------------------------------------------------------------------
-- Printing
--------------------------------------------------------------------------------

local PREFIX = "|cff00ff00Auto|cffed9121Carrot|r |cff7fbfffForever|r: "

function ns.Print(msg)
    print(PREFIX .. tostring(msg or ""))
end

function ns.Debug(msg)
    if ns.db and ns.db.debug then
        print(PREFIX .. "|cff999999" .. tostring(msg or "") .. "|r")
    end
end

--------------------------------------------------------------------------------
-- Event dispatcher
-- ns:On(event, fn) subscribes; events starting with "AC_" are internal and are
-- never registered with the client. ns:Fire(event, ...) calls subscribers.
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

local function register(event, unit)
    -- RegisterEvent errors on events this client does not know; Forever is a beta.
    local ok
    if unit then
        ok = pcall(frame.RegisterUnitEvent, frame, event, unit)
    else
        ok = pcall(frame.RegisterEvent, frame, event)
    end
    if not ok then
        ns.Debug("Event not available on this client: " .. event)
    end
end

function ns:On(event, fn, unit)
    if not handlers[event] then
        handlers[event] = {}
        if not event:match("^AC_") then
            register(event, unit)
        end
    end
    table.insert(handlers[event], fn)
end

function ns:Fire(event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    ns:Fire(event, ...)
end)

--------------------------------------------------------------------------------
-- API wrappers. Every client call that differs between versions goes through
-- here so a beta API change touches one place.
--------------------------------------------------------------------------------

local API = {}
ns.API = API

function API.FirstBag()
    return BACKPACK_CONTAINER or 0
end

function API.LastBag()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

function API.GetBagSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

-- Returns free slots and bag family (0 = normal bag that accepts any item).
function API.GetBagFreeSlots(bag)
    if C_Container and C_Container.GetContainerNumFreeSlots then
        return C_Container.GetContainerNumFreeSlots(bag)
    end
    return GetContainerNumFreeSlots(bag)
end

-- Returns a table { hyperlink, itemID, isLocked, isBound } or nil.
function API.GetBagItemInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        return C_Container.GetContainerItemInfo(bag, slot)
    end
    local _, _, locked, _, _, _, link, _, _, itemID, isBound = GetContainerItemInfo(bag, slot)
    if not link then return nil end
    return { hyperlink = link, itemID = itemID, isLocked = locked, isBound = isBound }
end

function API.PickupBagItem(bag, slot)
    if C_Container and C_Container.PickupContainerItem then
        return C_Container.PickupContainerItem(bag, slot)
    end
    return PickupContainerItem(bag, slot)
end

function API.CanEquipByName()
    return (C_Item and C_Item.EquipItemByName or EquipItemByName) ~= nil
end

function API.EquipItemByName(item, slot)
    if C_Item and C_Item.EquipItemByName then
        return C_Item.EquipItemByName(item, slot)
    end
    return EquipItemByName(item, slot)
end

function API.GetItemInfo(item)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(item)
    end
    return GetItemInfo(item)
end

-- itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID
function API.GetItemInfoInstant(item)
    if C_Item and C_Item.GetItemInfoInstant then
        return C_Item.GetItemInfoInstant(item)
    end
    return GetItemInfoInstant(item)
end

-- Bind type from item info (Enum.ItemBind): 0 = never binds (most white and
-- grey items), 1 = on pickup, 2 = on equip, 3 = on use, 4 = quest, ...
-- nil while the item is not in the client cache.
API.BIND_NONE = (Enum and Enum.ItemBind and Enum.ItemBind.None) or 0

function API.GetBindType(item)
    return (select(14, API.GetItemInfo(item)))
end

function API.GetItemSpell(item)
    if C_Item and C_Item.GetItemSpell then
        return C_Item.GetItemSpell(item)
    end
    return GetItemSpell(item)
end

function API.GetItemCount(item, includeBank)
    if C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(item, includeBank) or 0
    end
    return GetItemCount(item, includeBank) or 0
end

function API.IsEquippableItem(item)
    if C_Item and C_Item.IsEquippableItem then
        return C_Item.IsEquippableItem(item)
    end
    return IsEquippableItem(item)
end

function API.GetItemIcon(itemID)
    local _, _, _, _, icon = API.GetItemInfoInstant(itemID)
    return icon or 134400 -- question mark
end

-- Calls fn once the item is in the client cache.
function API.LoadItem(itemID, fn)
    if not itemID then return end
    if Item and Item.CreateFromItemID then
        local item = Item:CreateFromItemID(itemID)
        if item:IsItemEmpty() then return end
        item:ContinueOnItemLoad(fn)
    else
        fn()
    end
end

-- Only the required level; armor proficiency failures are caught by the
-- engine's failure back-off.
function API.MeetsLevel(itemID)
    local minLevel = select(5, API.GetItemInfo(itemID))
    if not minLevel then return true end -- not cached yet; assume yes
    return UnitLevel("player") >= minLevel
end

-- Full usability check, used by the editor for display.
function API.CanUseItem(itemID)
    if not API.MeetsLevel(itemID) then
        return false, "level"
    end
    if C_PlayerInfo and C_PlayerInfo.CanUseItem then
        local ok, can = pcall(C_PlayerInfo.CanUseItem, itemID)
        if ok and can == false then
            return false, "class"
        end
    end
    return true
end

function API.GetBagItemTooltip(bag, slot)
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        return C_TooltipInfo.GetBagItem(bag, slot)
    end
end

function API.GetInventoryItemTooltip(slot)
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
        return C_TooltipInfo.GetInventoryItem("player", slot)
    end
end

-- The player's location (DESIGN.md §5.5):
--   { mapID, name }        the zone-level map (what "Add current zone" stores)
--   { names, mapIDs }      every map from the most specific one (sub-zone,
--                          building, dungeon floor) up to the zone, plus the
--                          instance name, so "the Deadmines" matches inside it.
function API.GetCurrentZone()
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone
    local result = { names = {}, mapIDs = {} }
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    for _ = 1, 10 do
        if not mapID or not zoneType then break end
        local info = C_Map.GetMapInfo(mapID)
        if not info then break end
        if info.mapType and info.mapType < zoneType then break end -- continent or larger
        table.insert(result.names, info.name)
        table.insert(result.mapIDs, mapID)
        if info.mapType == zoneType and not result.mapID then
            result.mapID, result.name = mapID, info.name
        end
        mapID = info.parentMapID
    end
    local realZone = GetRealZoneText and GetRealZoneText()
    if realZone and realZone ~= "" then table.insert(result.names, realZone) end
    if IsInInstance() and GetInstanceInfo then
        local instanceName = GetInstanceInfo()
        if instanceName and instanceName ~= "" then table.insert(result.names, instanceName) end
    end
    -- In a dungeon there may be no zone-level map: use the most specific name.
    if not result.name then
        result.name = result.names[1]
        result.mapID = result.mapIDs[1]
    end
    if not result.name then return nil end
    return result
end

-- Movement speed as a percentage of normal run speed (7 yards/s).
function API.GetSpeedPercent()
    local base = BASE_MOVEMENT_SPEED or 7
    local function pct(v)
        if type(v) ~= "number" or API.IsSecret(v) then return 0 end
        return math.floor(v / base * 100 + 0.5)
    end
    local ok, current, run, _, swim = pcall(GetUnitSpeed, "player") -- 4th return (flight) unused: no flying in Forever
    if not ok then return 0, 0, 0 end
    return pct(current), pct(run), pct(swim)
end

-- The permanent enchant's name from an item link's tooltip, e.g. "Mithril
-- Spurs" from the line "Enchanted: Mithril Spurs". nil if there is none or the
-- tooltip isn't available.
function API.GetEnchantName(link)
    if type(link) ~= "string" or not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
    if not ok or not data or not data.lines then return nil end
    local enchantType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemEnchantmentPermanent
    -- "Enchanted: %s" -> "^Enchanted: (.+)$" (localized when the global exists)
    local prefix = (type(ENCHANTED_TOOLTIP_LINE) == "string" and ENCHANTED_TOOLTIP_LINE:match("^(.-)%%s")) or "Enchanted: "
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and not API.IsSecret(text) then
            if text:sub(1, #prefix) == prefix then
                return (text:sub(#prefix + 1):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
            end
            if enchantType and line.type == enchantType then return text end
        end
    end
    return nil
end

function API.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) or false
end

--------------------------------------------------------------------------------
-- SavedVariables
--------------------------------------------------------------------------------

local GLOBAL_DEFAULTS = {
    version = 4,
    nextRuleId = 1,
    custom = {},
    ignoredSuggestions = {},
    zoneGroups = {},
}

local CHAR_DEFAULTS = {
    version = 3,
    enabled = true,
    instanceTypes = { party = false, raid = false, pvp = false, arena = false, scenario = false },
    wasAutoDisabled = false,
    restoreDelay = { mounted = 0, swimming = 1.0, submerged = 1.0, resting = 0, always = 0 },
    trinketSlot = "auto",
    speedTrinketSlots = 2,
    lockedSlots = {},
    neverSwapOnUse = false,
    chatSuggestions = true,
    debug = false,
    button = { shown = true, scale = 1.0 },
    minimap = { hide = false, angle = 225 },
    builtins = {},
    saved = {},
    slotOwner = {},
    lastSlot = {},
}

-- Tables holding user lists or per-slot state: never merge defaults into them.
local OPAQUE = {
    custom = true, ignoredSuggestions = true, lockedSlots = true, zoneGroups = true,
    saved = true, slotOwner = true, lastSlot = true,
}

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

local function merge(dst, defaults)
    for k, v in pairs(defaults) do
        if dst[k] == nil then
            dst[k] = copy(v)
        elseif type(v) == "table" and type(dst[k]) == "table" and not OPAQUE[k] then
            merge(dst[k], v)
        end
    end
    return dst
end

-- Adds a zone to a saved group unless it is already there.
local function addDefaultZone(db, key, name)
    local group = db.zoneGroups and db.zoneGroups[key]
    if not group then return end
    for _, z in ipairs(group) do
        if type(z.name) == "string" and z.name:lower() == name:lower() then return end
    end
    table.insert(group, { name = name })
end

-- Account-wide DB migrations, by target version. Each runs once, so a zone
-- the player removes afterwards stays removed.
local GLOBAL_MIGRATIONS = {
    -- 2: Desolace counts as a Desert area (confirmed in game).
    [2] = function(db) addDefaultZone(db, "desert", "Desolace") end,
    -- 3: Westfall counts as a Desert area (confirmed in game).
    [3] = function(db) addDefaultZone(db, "desert", "Westfall") end,
    -- 4: the Flying trigger was removed (no flying in Forever).
    [4] = function(db)
        for _, c in ipairs(db.custom or {}) do
            if c.triggers then c.triggers.flying = nil end
        end
    end,
}

-- Per-character DB migrations, by target version.
local CHAR_MIGRATIONS = {
    -- 2: the Flying trigger was removed (no flying in Forever).
    [2] = function(db)
        if db.restoreDelay then db.restoreDelay.flying = nil end
    end,
    -- 3: the toggle button is shown by default now (it was hidden). Runs once,
    -- so hiding it again afterwards sticks.
    [3] = function(db)
        if db.button then db.button.shown = true end
    end,
}

local function migrate(db, target, migrations)
    for v = (db.version or 1) + 1, target do
        if migrations[v] then migrations[v](db) end
        db.version = v
    end
end

local function InitDB()
    AutoCarrotForeverGlobalDB = merge(AutoCarrotForeverGlobalDB or {}, GLOBAL_DEFAULTS)
    AutoCarrotForeverDB = merge(AutoCarrotForeverDB or {}, CHAR_DEFAULTS)
    migrate(AutoCarrotForeverGlobalDB, GLOBAL_DEFAULTS.version, GLOBAL_MIGRATIONS)
    migrate(AutoCarrotForeverDB, CHAR_DEFAULTS.version, CHAR_MIGRATIONS)
    ns.gdb = AutoCarrotForeverGlobalDB
    ns.db = AutoCarrotForeverDB

    local scale = tonumber(ns.db.button.scale) or 1
    ns.db.button.scale = math.min(2, math.max(0.5, scale))
    for _, b in ipairs(ns.BUILTINS) do
        if ns.db.builtins[b.id] == nil then ns.db.builtins[b.id] = not b.defaultOff end
    end
    for key, zones in pairs(ns.ZONE_GROUP_DEFAULTS) do
        if ns.gdb.zoneGroups[key] == nil then ns.gdb.zoneGroups[key] = copy(zones) end
    end
end

ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    InitDB()
    ns:Fire("AC_LOADED")
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local function onOff(v)
    return v and "1" or "0"
end

local LEGACY_BUILTINS = {
    ridinggloves = "ridingSkill",   -- 3.01 name for the enchant #930 rule
    mithrilspurs = "mithrilSpurs",
    carrot = "carrot",
}

-- 3.01 options whose items do not exist in Forever.
local REMOVED_BUILTINS = { swimbelt = "Swim belt", swimhelm = "Swim helm" }

local function parseTriggers(text)
    if not text or text == "" then return nil end
    local set = {}
    for key in text:lower():gmatch("[^,]+") do
        if not ns.TRIGGERS[key] then
            return nil, key
        end
        set[key] = true
    end
    return set
end

local function parseSlot(text)
    if not text or text == "" or text:lower() == "auto" then return "auto" end
    return tonumber(text)
end

local function printHelp()
    local db = ns.db
    ns.Print("Commands (/ac, /acf or /autocarrot):")
    ns.Print("  /ac - open the custom item editor")
    ns.Print("  /ac on | off | toggle (" .. onOff(db.enabled) .. ")")
    ns.Print("  /ac add <link|id> [trigger,trigger] [slot|auto]")
    ns.Print("  /ac addenchant <link> [trigger,trigger]")
    ns.Print("  /ac addset <pieces needed> <link> <link> [<link>...] [trigger,trigger]")
    ns.Print("  /ac remove <link|id|rule#>")
    ns.Print("  /ac list | scan | restore | options")
    ns.Print("  /ac check <link> - why an item is or isn't swapped (enchant ID, binding, rules)")
    ns.Print("  /ac lock <slot> | unlock <slot>")
    ns.Print("  /ac zone [add|remove <group>] - current zone and zone groups (e.g. desert)")
    ns.Print("  /ac speed - current movement speed, to test zone items")
    ns.Print("  /ac button 0|1|reset|scale <n>")
    ns.Print("  /ac debug 0|1 (" .. onOff(db.debug) .. ")")
    ns.Print("  Triggers: " .. table.concat(ns.TRIGGER_ORDER, ", ") .. " (always = whenever AutoCarrot is on)")
    ns.Print("  /ac speed - current movement speed (to test zone items)")
end

local function handleSlash(msg)
    msg = msg or ""
    -- Pull item links out first: links contain spaces and case-sensitive data.
    local links = {}
    while true do
        local found = msg:match("|c%x+|Hitem:.-|h.-|h|r") or msg:match("|Hitem:.-|h.-|h")
        if not found then break end
        links[#links + 1] = found
        local s, e = msg:find(found, 1, true)
        msg = msg:sub(1, s - 1) .. " " .. msg:sub(e + 1)
    end
    local link = links[1]
    local args = {}
    for word in msg:gmatch("%S+") do args[#args + 1] = word end
    local cmd = (table.remove(args, 1) or ""):lower()
    local db = ns.db

    if cmd == "" then
        ns.UI.OpenEditor()
    elseif cmd == "help" or cmd == "?" then
        printHelp()
    elseif cmd == "on" or cmd == "off" or cmd == "toggle" or cmd == "enabled" then
        local value
        if cmd == "on" then value = true
        elseif cmd == "off" then value = false
        elseif cmd == "toggle" then value = not db.enabled
        else
            local a = args[1]
            if a == "toggle" then value = not db.enabled
            elseif tonumber(a) then value = tonumber(a) == 1
            else ns.Print("'enabled' = " .. onOff(db.enabled)) return end
        end
        ns.Engine:SetEnabled(value)
        ns.Print(value and "Enabled." or "Disabled.")
    elseif cmd == "add" or cmd == "addenchant" then
        local target = link or args[1]
        local triggerText, slotText
        if link then
            triggerText, slotText = args[1], args[2]
        else
            triggerText, slotText = args[2], args[3]
        end
        if not target then
            ns.Print("Usage: /ac " .. cmd .. " <link|id> [trigger,trigger] [slot]")
            return
        end
        local triggers, bad = parseTriggers(triggerText)
        if bad then
            ns.Print("Unknown trigger '" .. bad .. "'. Use: " .. table.concat(ns.TRIGGER_ORDER, ", "))
            return
        end
        local rule, err = ns.Engine:AddCustomRule({
            input = target,
            byEnchant = cmd == "addenchant",
            triggers = triggers,
            slot = parseSlot(slotText),
        })
        if rule then
            ns.Print("Added rule #" .. rule.id .. " for " .. ns.Engine:RuleLabel(rule) .. ".")
        else
            ns.Print(err)
        end
    elseif cmd == "addset" then
        local need = tonumber(args[1])
        local pieces = {}
        for _, l in ipairs(links) do pieces[#pieces + 1] = l end
        for i = 2, #args do
            if tonumber(args[i]) then pieces[#pieces + 1] = args[i] end
        end
        local triggerText = args[#args] and not tonumber(args[#args]) and args[#args] or nil
        if not need or #pieces < 2 then
            ns.Print("Usage: /ac addset <pieces needed> <link or id> <link or id> [...] [trigger,trigger]")
            return
        end
        local triggers, bad = parseTriggers(triggerText)
        if bad then
            ns.Print("Unknown trigger '" .. bad .. "'. Use: " .. table.concat(ns.TRIGGER_ORDER, ", "))
            return
        end
        local rule, err = ns.Engine:AddSetRule({ pieces = pieces, need = need, triggers = triggers })
        ns.Print(rule and ("Added set rule #" .. rule.id .. " (" .. need .. " of " .. #pieces .. " pieces).") or err)
    elseif cmd == "remove" then
        local target = link or args[1]
        if not target then ns.Print("Usage: /ac remove <link|id|rule#>") return end
        local n = ns.Engine:RemoveCustomRulesMatching(target)
        ns.Print(n > 0 and ("Removed " .. n .. " rule(s).") or "No matching custom rule.")
    elseif cmd == "check" then
        local target = link or args[1]
        if not target then
            ns.Print("Usage: /ac check <shift-click an item>")
            return
        end
        ns.Engine:CheckItem(target)
    elseif cmd == "list" then
        ns.Engine:PrintRules()
    elseif cmd == "scan" then
        ns.Discovery:Scan(true)
    elseif cmd == "restore" then
        ns.Engine:Resync()
        ns.Print("Cleared failure and manual-change flags; re-syncing gear.")
    elseif cmd == "options" or cmd == "config" then
        ns.UI.OpenSettings()
    elseif cmd == "lock" or cmd == "unlock" then
        local slot = tonumber(args[1])
        if not slot or slot < 1 or slot > 19 then
            ns.Print("Usage: /ac " .. cmd .. " <slot number 1-19> (13/14 = trinkets)")
            return
        end
        db.lockedSlots[slot] = (cmd == "lock") or nil
        ns.Engine:OnSettingsChanged()
        ns.Print("Slot " .. slot .. (cmd == "lock" and " locked." or " unlocked."))
    elseif cmd == "zone" or cmd == "zones" then
        local E = ns.Engine
        local action, key = (args[1] or ""):lower(), (args[2] or ""):lower()
        local zone = API.GetCurrentZone()
        if (action == "add" or action == "remove") and key ~= "" then
            if not zone then ns.Print("Could not tell which zone you are in.") return end
            E:ToggleCurrentZone(E:GroupZones(key), action == "add")
            ns.Print(zone.name .. (action == "add" and " added to " or " removed from ") .. E:GroupLabel(key) .. ".")
            return
        end
        ns.Print("Current zone: " .. (zone and (zone.name .. (zone.mapID and (" (map " .. zone.mapID .. ")") or "")) or "unknown"))
        for _, k in ipairs(E:GroupKeys()) do
            local names = {}
            for _, z in ipairs(E:GroupZones(k)) do names[#names + 1] = z.name or ("map " .. tostring(z.mapID)) end
            local mark = E:IsInGroup(k, zone) and " |cff00ff00(you are here)|r" or ""
            ns.Print("  " .. E:GroupLabel(k) .. " [" .. k .. "]: " .. (#names > 0 and table.concat(names, ", ") or "none") .. mark)
        end
        ns.Print("Usage: /ac zone add <group> | /ac zone remove <group>")
    elseif cmd == "speed" then
        local current, run, swim = API.GetSpeedPercent()
        ns.Print(string.format("Speed now %d%%  (ground %d%%, swimming %d%%). Mounted standing still: ground shows mount speed.",
            current, run, swim))
    elseif cmd == "debug" then
        if tonumber(args[1]) then db.debug = tonumber(args[1]) == 1 else db.debug = not db.debug end
        ns.Print("'debug' = " .. onOff(db.debug))
    elseif cmd == "button" then
        local a = args[1]
        if tonumber(a) then
            db.button.shown = tonumber(a) == 1
            ns.UI.UpdateButtons()
            ns.Print("'button' set: " .. onOff(db.button.shown))
        elseif a == "reset" then
            ns.UI.ResetButtons()
            ns.Print("Button position/scale reset.")
        elseif a == "scale" then
            local s = tonumber(args[2])
            if s then
                db.button.scale = math.min(2, math.max(0.5, s))
                ns.UI.UpdateButtons()
                ns.Print("'buttonScale' set: " .. db.button.scale)
            else
                ns.Print("'buttonScale' = " .. tostring(db.button.scale))
                ns.Print("Usage: /ac button scale 1.0")
            end
        else
            ns.Print("'button' = " .. onOff(db.button.shown))
        end
    elseif cmd == "instance" then
        -- 3.01 alias: dungeons + raids
        if tonumber(args[1]) then
            local v = tonumber(args[1]) == 1
            db.instanceTypes.party, db.instanceTypes.raid = v, v
            ns.Engine:CheckInstance()
        end
        ns.Print("'instance' = " .. onOff(db.instanceTypes.party and db.instanceTypes.raid))
    elseif REMOVED_BUILTINS[cmd] then
        ns.Print(REMOVED_BUILTINS[cmd] .. " does not exist in WoW Forever. Add any swim item with /ac add <link> swimming.")
    elseif LEGACY_BUILTINS[cmd] then
        local id = LEGACY_BUILTINS[cmd]
        if tonumber(args[1]) then
            db.builtins[id] = tonumber(args[1]) == 1
            ns.Engine:OnSettingsChanged()
            ns.Print("'" .. id .. "' set: " .. onOff(db.builtins[id]))
        else
            ns.Print("'" .. id .. "' = " .. onOff(db.builtins[id]))
        end
    else
        printHelp()
    end
end

local function slashTaken(command)
    for key in pairs(SlashCmdList) do
        if key ~= "AUTOCARROTFOREVER" then
            local i = 1
            local value = _G["SLASH_" .. key .. i]
            while value do
                if type(value) == "string" and value:lower() == command then return true end
                i = i + 1
                value = _G["SLASH_" .. key .. i]
            end
        end
    end
    return false
end

-- Registered at login so every other addon's commands already exist.
ns:On("PLAYER_LOGIN", function()
    SLASH_AUTOCARROTFOREVER1 = "/autocarrot"
    SLASH_AUTOCARROTFOREVER2 = "/acf"
    if not slashTaken("/ac") then
        SLASH_AUTOCARROTFOREVER3 = "/ac"
    end
    SlashCmdList["AUTOCARROTFOREVER"] = handleSlash
end)
