local ADDON, ns = ...

local API, Planner = ns.API, ns.Planner

local Discovery = {}
ns.Discovery = Discovery

local THROTTLE = 2
local LOGIN_QUIET = 5

-- Lower-case English patterns (DESIGN.md §7.2). Other locales: add a table
-- keyed by GetLocale(); without one, discovery is off and /ac add still works.
local PATTERNS = {
    enUS = {
        { pattern = "mount.- speed", trigger = "mounted", kind = "mount speed" },
        { pattern = "riding speed", trigger = "mounted", kind = "mount speed" },
        { pattern = "swim.- speed", trigger = "swimming", kind = "swim speed" },
        { pattern = "underwater breathing", trigger = "submerged", kind = "underwater effect" },
        { pattern = "underwater", trigger = "submerged", kind = "underwater effect" },
        { pattern = "movement speed", trigger = "always", kind = "movement speed" },
        { pattern = "run speed", trigger = "always", kind = "run speed" },
        { pattern = "minor speed", trigger = "always", kind = "run speed" },
        { pattern = "increases speed", trigger = "always", kind = "speed" },
    },
}
PATTERNS.enGB = PATTERNS.enUS

local patterns = PATTERNS[GetLocale()]
local disabled = patterns == nil

Discovery.suggestions = {}   -- [key] = suggestion
local order = {}             -- keys in discovery order
local cache = {}             -- [item string] = suggestion | false
local tries = {}             -- [item string] = tooltip load attempts
local announced = {}
local quietUntil = math.huge
local scanTimer

local function prefix(globalString)
    return type(globalString) == "string" and globalString:lower() or nil
end

local PREFIX_USE = prefix(ITEM_SPELL_TRIGGER_ONUSE) or "use:"
local PREFIX_EQUIP = prefix(ITEM_SPELL_TRIGGER_ONEQUIP) or "equip:"
local PREFIX_PROC = prefix(ITEM_SPELL_TRIGGER_ONPROC) or "chance on hit:"
local PREFIX_SET = ((type(ITEM_SET_BONUS) == "string" and ITEM_SET_BONUS:lower():match("^(.-)%%s")) or "set:")

local function startsWith(text, p)
    return p ~= nil and text:sub(1, #p) == p
end

local function SuggestionKey(match)
    return Planner.MatchKey(match)
end

-- Is this item already covered by a rule or ignored?
local function known(item)
    for _, r in ipairs(ns.Engine.state.rules) do
        if Planner.Matches(r.match, item) then return true end
    end
    local ignored = ns.gdb.ignoredSuggestions
    if ignored["i:" .. item.itemID] then return true end
    if item.enchantID ~= 0 and ignored["e:" .. item.enchantID] then return true end
    return false
end

-- Zone limits written on the item, e.g. "... in Desert areas." becomes the
-- zone group "desert"; "... while in Tanaris." becomes that zone.
local function zoneHint(text, lower)
    local area = lower:match(" in ([%a%s']-) areas?%f[^%a]")
    if area then
        local key = strtrim(area):gsub("%s+", "_")
        return { { group = key } }
    end
    local _, _, name = text:find("[Ww]hile in ([%a%s']+)")
    if name then
        return { { name = strtrim(name) } }
    end
end

-- Reads one tooltip and returns a suggestion or false.
local function analyse(item, data)
    if not data or not data.lines then return nil end -- not loaded yet: retry later
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text ~= nil and API.IsSecret(text) then
            disabled = true
            ns.Debug("Tooltip data is restricted on this client; discovery turned off.")
            return false
        end
        if type(text) == "string" and text ~= "" then
            local lower = text:lower()
            local skip = startsWith(lower, PREFIX_USE) or startsWith(lower, PREFIX_PROC)
                or startsWith(lower, PREFIX_SET) or lower:match("^%(%d+%)")
            if not skip then
                for _, p in ipairs(patterns) do
                    if lower:find(p.pattern) then
                        local strong = startsWith(lower, PREFIX_EQUIP)
                        local byEnchant = not strong and item.enchantID ~= 0
                        local match = byEnchant and { enchantID = item.enchantID } or { itemID = item.itemID }
                        local zones = zoneHint(text, lower)
                        return {
                            zones = zones,
                            key = SuggestionKey(match),
                            match = match,
                            byEnchant = byEnchant,
                            itemID = item.itemID,
                            link = item.link,
                            text = text,
                            trigger = p.trigger,
                            kind = zones and (p.kind .. " (" .. ns.Engine:ZoneLabel(zones) .. ")") or p.kind,
                        }
                    end
                end
            end
        end
    end
    return false
end

local function supported(itemID)
    local _, _, _, equipLoc = API.GetItemInfoInstant(itemID)
    return equipLoc and ns.EQUIP_LOC_SLOTS[equipLoc] ~= nil
end

local function consider(item, getTooltip)
    if not supported(item.itemID) or known(item) then return end
    local result = cache[item.str]
    if result == nil then
        result = analyse(item, getTooltip())
        if result == nil then
            -- Tooltip not ready; ask the client for the item and try again.
            tries[item.str] = (tries[item.str] or 0) + 1
            if tries[item.str] < 3 then
                API.LoadItem(item.itemID, function() Discovery:Schedule() end)
                return
            end
            result = false
        end
        cache[item.str] = result
    end
    if result and not Discovery.suggestions[result.key] then
        Discovery.suggestions[result.key] = result
        order[#order + 1] = result.key
        Discovery:Announce(result)
        return true
    end
end

function Discovery:Scan(manual)
    if disabled then
        if manual then
            ns.Print("Speed-item discovery is not available for this client language. Use /ac add instead.")
        end
        return
    end
    if not ns.gdb or not ns.Engine.state.ready then return end
    local found = 0
    for bag = API.FirstBag(), API.LastBag() do
        for slot = 1, API.GetBagSlots(bag) do
            local info = API.GetBagItemInfo(bag, slot)
            local item = info and info.hyperlink and Planner.ParseItemString(info.hyperlink)
            if item and API.IsEquippableItem(info.hyperlink) then
                item.link = info.hyperlink
                if consider(item, function() return API.GetBagItemTooltip(bag, slot) end) then
                    found = found + 1
                end
            end
        end
    end
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        local item = link and Planner.ParseItemString(link)
        if item then
            item.link = link
            if consider(item, function() return API.GetInventoryItemTooltip(slot) end) then
                found = found + 1
            end
        end
    end
    -- Drop suggestions that became rules or were ignored meanwhile.
    for i = #order, 1, -1 do
        local s = self.suggestions[order[i]]
        local ignored = ns.gdb.ignoredSuggestions[order[i]]
        if not s or ignored or self:IsCovered(s.match) then
            self.suggestions[order[i]] = nil
            table.remove(order, i)
        end
    end
    if manual then
        local total = #order
        ns.Print(total > 0 and (total .. " possible speed item(s); see the Suggestions list (/ac).")
            or "No new speed items found in your bags or gear.")
    end
    ns:Fire("AC_SUGGESTIONS")
end

function Discovery:IsCovered(match)
    for _, r in ipairs(ns.Engine.state.rules) do
        if Planner.MatchKey(r.match) == Planner.MatchKey(match) then return true end
    end
    return false
end

function Discovery:Schedule()
    if scanTimer or disabled then return end
    local delay = math.max(THROTTLE, quietUntil - GetTime())
    if delay == math.huge then return end
    scanTimer = C_Timer.NewTimer(delay, function()
        scanTimer = nil
        Discovery:Scan(false)
    end)
end

function Discovery:List()
    local list = {}
    for _, key in ipairs(order) do
        if self.suggestions[key] then list[#list + 1] = self.suggestions[key] end
    end
    return list
end

-- Called when a rule is added for this match.
function Discovery:Forget(match)
    local key = Planner.MatchKey(match)
    if self.suggestions[key] then
        self.suggestions[key] = nil
        ns:Fire("AC_SUGGESTIONS")
    end
end

function Discovery:Ignore(key)
    ns.gdb.ignoredSuggestions[key] = true
    self.suggestions[key] = nil
    ns:Fire("AC_SUGGESTIONS")
end

--------------------------------------------------------------------------------
-- Chat output with [Add] / [Ignore] links (DESIGN.md §7.3)
--------------------------------------------------------------------------------

local function addonLink(action, key, label, color)
    return "|cff" .. color .. "|Haddon:" .. ADDON .. ":" .. action .. ":" .. key .. "|h[" .. label .. "]|h|r"
end

function Discovery:Announce(s)
    if not ns.db.chatSuggestions or announced[s.key] then return end
    announced[s.key] = true
    local what = s.byEnchant and ("the enchant on " .. (s.link or "an item")) or (s.link or "An item")
    ns.Print(what .. " looks like " .. s.kind .. " gear. " ..
        addonLink("add", s.key, "Add", "40ff40") .. " " .. addonLink("ignore", s.key, "Ignore", "ff8080"))
end

local function onLink(link)
    if type(link) ~= "string" then return end
    local action, key = link:match("^addon:" .. ADDON .. ":(%a+):(.+)$")
    if not action then return end
    local s = Discovery.suggestions[key]
    if action == "add" then
        if s then
            ns.UI.OpenEditor(s)
        else
            ns.Print("That suggestion is no longer available.")
        end
    elseif action == "ignore" then
        Discovery:Ignore(key)
        ns.Print("Ignored. It won't be suggested again on any character.")
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

ns:On("AC_LOADED", function()
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", function(_, link) onLink(link) end, Discovery)
    else
        hooksecurefunc("SetItemRef", function(link) onLink(link) end)
    end
end)

ns:On("PLAYER_LOGIN", function()
    quietUntil = GetTime() + LOGIN_QUIET
    Discovery:Schedule()
end)

ns:On("BAG_UPDATE_DELAYED", function() Discovery:Schedule() end)
ns:On("PLAYER_EQUIPMENT_CHANGED", function() Discovery:Schedule() end)
ns:On("AC_RULES", function() Discovery:Schedule() end)
