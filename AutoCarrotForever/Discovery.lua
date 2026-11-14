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
        -- "movement speed while mounted" must win over plain "movement speed".
        { pattern = "while mounted", trigger = "mounted", kind = "mount speed" },
        -- Mount-speed enchants: the tooltip shows only the enchant's name
        -- ("Enchanted: Mithril Spurs"), with no speed wording. Catches them if
        -- Forever's enchant IDs differ from the built-in rules' 464 / 930.
        { pattern = "mithril spurs", trigger = "mounted", kind = "mount speed" },
        { pattern = "riding skill", trigger = "mounted", kind = "mount speed" },
        -- %f[%a] stops "amount ... speed" from matching.
        { pattern = "%f[%a]mount%a* speed", trigger = "mounted", kind = "mount speed" },
        { pattern = "riding speed", trigger = "mounted", kind = "mount speed" },
        { pattern = "%f[%a]swim%a* speed", trigger = "swimming", kind = "swim speed" },
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
-- Returns the rule covering this item, true if it was ignored, or nil.
local function known(item)
    for _, r in ipairs(ns.Engine.state.rules) do
        if Planner.RuleMatches(r, item) then return r end
    end
    local ignored = ns.gdb.ignoredSuggestions
    if ignored["i:" .. item.itemID] then return true end
    if item.enchantID ~= 0 and ignored["e:" .. item.enchantID] then return true end
    return nil
end

local covered -- during a manual scan: { [item string] = { link, rule } }

-- Zone limits written on the item (DESIGN.md §5.5, §7.2):
--   "... in Desert areas."              -> zone group "desert"
--   "... by 3% in The Barrens, ... ."   -> those zones
--   "... while in Tanaris."             -> that zone
local function zoneHint(text, lower)
    local area = lower:match(" in ([%a%s']-) areas?%f[^%a]")
    if area then
        local key = (strtrim(area):gsub("%s+", "_"))
        return { { group = key } }
    end
    local list = text:match("%d+%%%s+in%s+(.+)$") or text:match("[Ww]hile in%s+(.+)$")
    if list then
        local zones = {}
        for _, name in ipairs(Planner.SplitZones(list)) do zones[#zones + 1] = { name = name } end
        if #zones > 0 then return zones end
    end
end

-- Other pieces of an item's set, when the client can tell us (retail API).
local function setPieces(link)
    local setID = select(16, API.GetItemInfo(link))
    if not setID or setID == 0 then return nil, nil end
    if C_LootJournal and C_LootJournal.GetItemSetItems then
        local ok, list = pcall(C_LootJournal.GetItemSetItems, setID)
        if ok and type(list) == "table" and #list > 0 then
            local ids = {}
            for _, e in ipairs(list) do
                if e.itemID then ids[#ids + 1] = e.itemID end
            end
            if #ids > 1 then return setID, ids end
        end
    end
    return setID, nil
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
            local setNeed = lower:match("^%((%d+)%)")
            local isSetLine = setNeed ~= nil or startsWith(lower, PREFIX_SET)
            local skip = startsWith(lower, PREFIX_USE) or startsWith(lower, PREFIX_PROC)
            if isSetLine and not skip then
                -- Set bonus (DESIGN.md §5.6): suggest a set rule.
                for _, p in ipairs(patterns) do
                    if lower:find(p.pattern) then
                        local setID, pieces = setPieces(item.link)
                        local zones = zoneHint(text, lower)
                        local where = zones and (" (" .. ns.Engine:ZoneLabel(zones) .. ")") or ""
                        return {
                            isSet = true,
                            key = "set:" .. (setID or ("i" .. item.itemID)),
                            match = { itemID = item.itemID },
                            need = tonumber(setNeed) or 2,
                            pieces = pieces,
                            zones = zones,
                            itemID = item.itemID,
                            link = item.link,
                            text = text,
                            trigger = p.trigger,
                            kind = "set-bonus " .. p.kind .. where,
                        }
                    end
                end
            elseif not skip then
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
    if not supported(item.itemID) then return end
    local rule = known(item)
    if rule then
        if covered and type(rule) == "table" and not covered[item.str] then
            covered[item.str] = { link = item.link, rule = rule }
        end
        return
    end
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
    if result and not Discovery.suggestions[result.key] and not ns.gdb.ignoredSuggestions[result.key] then
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
    covered = manual and {} or nil
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
        -- Items a rule already handles are never suggested; say so, so it
        -- doesn't look like they were missed.
        local list = {}
        for _, c in pairs(covered) do list[#list + 1] = c end
        table.sort(list, function(a, b) return (a.link or "") < (b.link or "") end)
        if #list > 0 then
            ns.Print("Already handled by a rule (not suggested):")
            for i, c in ipairs(list) do
                if i > 8 then
                    ns.Print("  ...and " .. (#list - 8) .. " more.")
                    break
                end
                ns.Print("  " .. (c.link or "?") .. " - " .. ns.Engine:RuleLabel(c.rule))
            end
        end
        covered = nil
    end
    ns:Fire("AC_SUGGESTIONS")
end

function Discovery:IsCovered(match)
    local key = Planner.MatchKey(match)
    for _, r in ipairs(ns.Engine.state.rules) do
        for _, k in ipairs(Planner.RuleKeys(r)) do
            if k == key then return true end
        end
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
    if s.isSet and not s.pieces then
        ns.Print(what .. " is part of a set with a " .. s.kind .. ". Add the set with " ..
            "/ac addset " .. s.need .. " followed by links to the pieces you have. " ..
            addonLink("ignore", s.key, "Ignore", "ff8080"))
        return
    end
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
