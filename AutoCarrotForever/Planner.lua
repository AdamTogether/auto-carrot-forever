local ADDON, ns = ...

-- Pure functions (no WoW API calls) so they can be unit-tested outside the
-- game; see tests/test_planner.lua.

local Planner = {}
ns.Planner = Planner

local TRINKET = { [13] = true, [14] = true }
local MAIN_HAND, OFF_HAND = 16, 17

-- Parses an item link or item string into
-- { str, itemID, enchantID, suffixID, key }. key identifies the exact copy.
function Planner.ParseItemString(link)
    if type(link) ~= "string" then return nil end
    local str = link:match("item:[%-%d:]*")
    if not str then return nil end
    local fields = {}
    for v in (str:sub(6) .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = v
    end
    local itemID = tonumber(fields[1])
    if not itemID then return nil end
    local enchantID = tonumber(fields[2]) or 0
    local suffixID = tonumber(fields[7]) or 0
    return {
        str = str,
        itemID = itemID,
        enchantID = enchantID,
        suffixID = suffixID,
        key = itemID .. ":" .. enchantID .. ":" .. suffixID,
    }
end

function Planner.Matches(match, item)
    if not match or not item then return false end
    if match.itemID then
        return item.itemID == match.itemID
    end
    if match.enchantID then
        return match.enchantID ~= 0 and item.enchantID == match.enchantID
    end
    return false
end

function Planner.MatchKey(match)
    if match.itemID then return "i:" .. match.itemID end
    return "e:" .. tostring(match.enchantID)
end

-- A rule matches an item if its own match does, or (set rules) any piece does.
function Planner.RuleMatches(rule, item)
    if rule.pieces then
        for _, p in ipairs(rule.pieces) do
            if Planner.Matches(p.match, item) then return true end
        end
        return false
    end
    return Planner.Matches(rule.match, item)
end

-- Every match key a rule covers (one for item/enchant rules, one per piece for sets).
function Planner.RuleKeys(rule)
    if rule.pieces then
        local keys = {}
        for _, p in ipairs(rule.pieces) do keys[#keys + 1] = Planner.MatchKey(p.match) end
        return keys
    end
    return { Planner.MatchKey(rule.match) }
end

--------------------------------------------------------------------------------
-- Zones (DESIGN.md §5.5)
--------------------------------------------------------------------------------

local function normZone(name)
    if type(name) ~= "string" then return nil end
    return (name:lower():gsub("^the%s+", ""))
end
Planner.NormZone = normZone

--[[
ZoneMatches(zones, current, groups)
zones:   nil/empty = anywhere; else list of { name, mapID } or { group = key }
current: { name, mapID, names = {...}, mapIDs = {...} } - every map the player is
         inside (zone, sub-zone maps, instance), so "the Deadmines" matches
         inside the dungeon and Westfall matches in its sub-zones.
groups:  { [key] = list of { name, mapID } }
Names compare case-insensitively and ignore a leading "The ".
]]
function Planner.ZoneMatches(zones, current, groups)
    if not zones or #zones == 0 then return true end
    if not current then return false end
    local names, ids = {}, {}
    if current.name then names[normZone(current.name)] = true end
    for _, n in ipairs(current.names or {}) do names[normZone(n)] = true end
    if current.mapID then ids[current.mapID] = true end
    for _, id in ipairs(current.mapIDs or {}) do ids[id] = true end
    local function one(z)
        if z.mapID and ids[z.mapID] then return true end
        local n = normZone(z.name)
        return n ~= nil and names[n] == true
    end
    for _, z in ipairs(zones) do
        if z.group then
            for _, gz in ipairs((groups and groups[z.group]) or {}) do
                if one(gz) then return true end
            end
        elseif one(z) then
            return true
        end
    end
    return false
end

local DIRECTIONS = { eastern = true, western = true, northern = true, southern = true }

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Zone list from an item tooltip (DESIGN.md §7.2):
-- "The Barrens, Thousand Needles, and Razorfen Downs." -> three names;
-- "Eastern and Western Plaguelands" -> "Eastern Plaguelands", "Western Plaguelands".
function Planner.SplitZones(list)
    list = (list:gsub("%.%s*$", ""))
    list = (list:gsub(",%s*and%s+", ", "))
    list = (list:gsub("%s+and%s+", ", "))
    local parts = {}
    for part in list:gmatch("[^,]+") do
        part = trim(part)
        if part ~= "" then parts[#parts + 1] = part end
    end
    for i = 1, #parts - 1 do
        local nextFirst, noun = parts[i + 1]:match("^(%a+)%s+(.+)$")
        if DIRECTIONS[parts[i]:lower()] and nextFirst and DIRECTIONS[nextFirst:lower()] then
            parts[i] = parts[i] .. " " .. noun
        end
    end
    return parts
end

--------------------------------------------------------------------------------
-- Planning
--------------------------------------------------------------------------------

-- Higher priority first; on a tie custom rules beat built-ins, then list order.
function Planner.SortRules(rules)
    local sorted = {}
    for i, r in ipairs(rules) do sorted[i] = r end
    table.sort(sorted, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        if a.source ~= b.source then return a.source == "custom" end
        return (a.order or 0) < (b.order or 0)
    end)
    return sorted
end

-- Chooses among candidate slots for a multi-slot rule (DESIGN.md §6.5).
function Planner.PickSlot(rule, cands, a)
    if #cands == 0 then return nil end
    if #cands == 1 then return cands[1] end
    -- A slot already holding a speed item gets replaced anyway.
    for _, s in ipairs(cands) do
        if a.speedWorn and a.speedWorn[s] then return s end
    end
    -- The player's explicit preference.
    if a.preferredTrinket then
        for _, s in ipairs(cands) do
            if s == a.preferredTrinket then return s end
        end
    end
    -- Cheapest swap; lastSlot breaks ties; then the later slot (3.01 default).
    local last = a.lastSlot and a.lastSlot[rule.id]
    local best, bestCost
    for _, s in ipairs(cands) do
        local c = (a.cost and a.cost[s]) or 1
        if not bestCost or c < bestCost - 1e-6 then
            best, bestCost = s, c
        elseif math.abs(c - bestCost) <= 1e-6 then
            if s == last or best ~= last then best = s end
        end
    end
    return best
end

--[[
Plan(a) -> { [slot] = rule }

a.rules            active rules: { id, match, slots, priority, source, order, excludes, twoHand }
                   or set rules: { id, pieces = { { match, slots, twoHand } }, need, ... }
                   (for sets, pieces must already be limited to owned, usable ones)
a.equipped         { [slot] = parsed item }
a.speedWorn        { [slot] = true } slots whose current item matches any enabled rule
a.locked           { [slot] = true } never swap
a.forbidden        { [slot] = true } on-use trinket protected by "never swap on-use"
a.cost             { [slot] = number } swap cost (lower is cheaper)
a.preferredTrinket 13 | 14 | nil
a.lastSlot         { [ruleId] = slot }
a.trinketBudget    max trinket slots speed items may take

A two-handed rule placed in the main hand also reserves the off hand. Set
rules are placed atomically: if fewer than `need` pieces fit, none are used.
For sets, plan[slot] is a per-piece sub-rule whose id is the set's id.
]]
function Planner.Plan(a)
    local rules = Planner.SortRules(a.rules or {})
    local equipped = a.equipped or {}
    local plan, usedKeys, excluded, reserved = {}, {}, {}, {}
    local trinketsUsed = 0
    local budget = a.trinketBudget or 2

    for _, r in ipairs(rules) do
        for _, ex in ipairs(r.excludes or {}) do
            if ex ~= r.id then excluded[ex] = true end
        end
    end

    local function free(s)
        return not plan[s] and not reserved[s]
    end

    -- Places one item rule; returns the slot or nil. Records bookkeeping.
    local function place(rule)
        local key = Planner.MatchKey(rule.match)
        if usedKeys[key] then return nil end
        local function fits(s)
            if not free(s) then return false end
            if rule.twoHand and s == MAIN_HAND and (plan[OFF_HAND] or reserved[OFF_HAND]) then return false end
            return true
        end
        local chosen
        for _, s in ipairs(rule.slots or {}) do
            if fits(s) and Planner.Matches(rule.match, equipped[s]) then
                chosen = s
                break
            end
        end
        if not chosen then
            local cands = {}
            for _, s in ipairs(rule.slots or {}) do
                if fits(s)
                    and not (a.locked and a.locked[s])
                    and not (a.forbidden and a.forbidden[s]) then
                    cands[#cands + 1] = s
                end
            end
            chosen = Planner.PickSlot(rule, cands, a)
        end
        if chosen and TRINKET[chosen] and trinketsUsed >= budget then
            chosen = nil
        end
        if not chosen then return nil end
        plan[chosen] = rule
        usedKeys[key] = true
        if TRINKET[chosen] then trinketsUsed = trinketsUsed + 1 end
        if rule.twoHand and chosen == MAIN_HAND then reserved[OFF_HAND] = true end
        return chosen
    end

    local function unplace(slot)
        local rule = plan[slot]
        if not rule then return end
        plan[slot] = nil
        usedKeys[Planner.MatchKey(rule.match)] = nil
        if TRINKET[slot] then trinketsUsed = trinketsUsed - 1 end
        if rule.twoHand and slot == MAIN_HAND then reserved[OFF_HAND] = nil end
    end

    for _, rule in ipairs(rules) do
        if not excluded[rule.id] then
            if rule.pieces then
                -- Worn pieces first, so a half-worn set is completed, not reshuffled.
                local ordered = {}
                for _, p in ipairs(rule.pieces) do
                    local worn = false
                    for _, s in ipairs(p.slots or {}) do
                        if Planner.Matches(p.match, equipped[s]) then worn = true end
                    end
                    if worn then table.insert(ordered, 1, p) else ordered[#ordered + 1] = p end
                end
                local placed = {}
                for _, p in ipairs(ordered) do
                    if #placed >= (rule.need or 2) then break end
                    local sub = {
                        id = rule.id, match = p.match, slots = p.slots, twoHand = p.twoHand,
                        priority = rule.priority, source = rule.source, order = rule.order,
                        allowBind = rule.allowBind, name = rule.name, set = rule,
                    }
                    local s = place(sub)
                    if s then placed[#placed + 1] = s end
                end
                if #placed < (rule.need or 2) then
                    for _, s in ipairs(placed) do unplace(s) end
                end
            else
                place(rule)
            end
        end
    end
    return plan
end

return Planner
