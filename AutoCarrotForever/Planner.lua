local ADDON, ns = ...

-- Pure functions (no WoW API calls) so they can be unit-tested outside the
-- game; see tests/test_planner.lua.

local Planner = {}
ns.Planner = Planner

local TRINKET = { [13] = true, [14] = true }

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

-- Zone condition (DESIGN.md §5.5). zones: nil/empty = anywhere; otherwise a
-- list of { name, mapID } or { group = key }. current: { name, mapID }.
-- groups: { [key] = list of { name, mapID } }.
function Planner.ZoneMatches(zones, current, groups)
    if not zones or #zones == 0 then return true end
    if not current then return false end
    local currentName = type(current.name) == "string" and current.name:lower() or nil
    local function one(z)
        if z.mapID and current.mapID and z.mapID == current.mapID then return true end
        return type(z.name) == "string" and currentName ~= nil and z.name:lower() == currentName
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

--[[
Plan(a) -> { [slot] = rule }

a.rules            active rules: { id, match, slots, priority, source, order, excludes }
a.equipped         { [slot] = parsed item }
a.speedWorn        { [slot] = true } slots whose current item matches any enabled rule
a.locked           { [slot] = true } never swap
a.forbidden        { [slot] = true } on-use trinket protected by "never swap on-use"
a.cost             { [slot] = number } swap cost (lower is cheaper)
a.preferredTrinket 13 | 14 | nil
a.lastSlot         { [ruleId] = slot }
a.trinketBudget    max trinket slots speed items may take
]]
function Planner.Plan(a)
    local rules = Planner.SortRules(a.rules or {})
    local equipped = a.equipped or {}
    local plan, usedKeys, excluded = {}, {}, {}
    local trinketsUsed = 0
    local budget = a.trinketBudget or 2

    for _, r in ipairs(rules) do
        for _, ex in ipairs(r.excludes or {}) do
            if ex ~= r.id then excluded[ex] = true end
        end
    end

    for _, rule in ipairs(rules) do
        local key = Planner.MatchKey(rule.match)
        if not excluded[rule.id] and not usedKeys[key] then
            local chosen
            -- Already worn in one of its slots: keep it there.
            for _, s in ipairs(rule.slots or {}) do
                if not plan[s] and Planner.Matches(rule.match, equipped[s]) then
                    chosen = s
                    break
                end
            end
            if not chosen then
                local cands = {}
                for _, s in ipairs(rule.slots or {}) do
                    if not plan[s]
                        and not (a.locked and a.locked[s])
                        and not (a.forbidden and a.forbidden[s]) then
                        cands[#cands + 1] = s
                    end
                end
                chosen = Planner.PickSlot(rule, cands, a)
            end
            if chosen and TRINKET[chosen] then
                if trinketsUsed >= budget then
                    chosen = nil
                else
                    trinketsUsed = trinketsUsed + 1
                end
            end
            if chosen then
                plan[chosen] = rule
                usedKeys[key] = true
            end
        end
    end
    return plan
end

return Planner
