-- Unit tests for AutoCarrotForever/Planner.lua (pure Lua, no WoW API).
-- Run from the repository root with Lua 5.1 (the WoW Lua version) or newer:
--   lua tests/test_planner.lua

local ns = {}
local chunk = assert(loadfile("AutoCarrotForever/Planner.lua"))
chunk("AutoCarrotForever", ns)
local P = ns.Planner

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function item(id, enchant)
    return P.ParseItemString("item:" .. id .. ":" .. (enchant or 0) .. ":0:0:0:0:0:0:70")
end

local function rule(id, itemID, priority, slots, extra)
    local r = {
        id = id, match = { itemID = itemID }, slots = slots or { 13, 14 },
        priority = priority or 100, source = "builtin", order = 0,
    }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

-- Hypothetical custom mount trinkets (Forever has no Riding Crop or Skybreaker Whip).
local WHIP = rule("whip", 900002, 120)
local CROP = rule("crop", 900001, 110)
local CARROT = rule("carrot", 11122, 100)
local GLOVES = { id = "gloves", match = { enchantID = 930 }, slots = { 10 }, priority = 100, source = "builtin", order = 4 }

-- ParseItemString ---------------------------------------------------------------

test("parse link", function()
    local it = P.ParseItemString("|cff0070dd|Hitem:11122:930:0:0:0:0:-5:12345:70|h[Carrot]|h|r")
    eq(it.itemID, 11122)
    eq(it.enchantID, 930)
    eq(it.suffixID, -5)
    eq(it.key, "11122:930:-5")
end)

test("parse empty fields", function()
    local it = P.ParseItemString("item:7052::::::::70")
    eq(it.itemID, 7052)
    eq(it.enchantID, 0)
    eq(it.key, "7052:0:0")
end)

test("parse garbage", function()
    eq(P.ParseItemString("hello"), nil)
    eq(P.ParseItemString(nil), nil)
end)

test("matches enchant", function()
    eq(P.Matches({ enchantID = 930 }, item(1234, 930)), true)
    eq(P.Matches({ enchantID = 930 }, item(1234, 0)), false)
    eq(P.Matches({ itemID = 1234 }, nil), false)
end)

-- Plan --------------------------------------------------------------------------

test("two speed trinkets by default (stacking)", function()
    local plan = P.Plan({ rules = { CARROT, CROP, WHIP }, equipped = {}, trinketBudget = 2 })
    local got = {}
    for _, r in pairs(plan) do got[r.id] = true end
    eq(got.whip, true, "whip")
    eq(got.crop, true, "crop")
    eq(got.carrot, nil, "carrot")
end)

test("budget 1 keeps only the best", function()
    local plan = P.Plan({ rules = { CARROT, CROP }, equipped = {}, trinketBudget = 1 })
    local n = 0
    for _, r in pairs(plan) do n = n + 1; eq(r.id, "crop") end
    eq(n, 1)
end)

test("budget reduced while both are worn releases one slot", function()
    local plan = P.Plan({
        rules = { CARROT, CROP },
        equipped = { [13] = item(900001), [14] = item(11122) },
        trinketBudget = 1,
    })
    eq(plan[13] and plan[13].id, "crop")
    eq(plan[14], nil)
end)

test("gloves and trinkets together (no excludes)", function()
    local plan = P.Plan({ rules = { CROP, GLOVES }, equipped = {}, trinketBudget = 2 })
    eq(plan[10] and plan[10].id, "gloves")
end)

test("already worn stays in its slot", function()
    local plan = P.Plan({ rules = { CARROT }, equipped = { [13] = item(11122) }, trinketBudget = 2 })
    eq(plan[13] and plan[13].id, "carrot")
    eq(plan[14], nil)
end)

test("locked slot is skipped", function()
    local plan = P.Plan({ rules = { CARROT }, equipped = {}, locked = { [14] = true }, trinketBudget = 1 })
    eq(plan[13] and plan[13].id, "carrot")
end)

test("cheapest slot: passive trinket swapped, on-use kept", function()
    local plan = P.Plan({
        rules = { CARROT }, equipped = { [13] = item(1), [14] = item(2) },
        cost = { [13] = 1, [14] = 4 }, trinketBudget = 2,
    })
    eq(plan[13] and plan[13].id, "carrot")
end)

test("on-use already on long cooldown is cheaper than a ready one", function()
    local plan = P.Plan({
        rules = { CARROT }, equipped = { [13] = item(1), [14] = item(2) },
        cost = { [13] = 4, [14] = 2 }, trinketBudget = 2,
    })
    eq(plan[14] and plan[14].id, "carrot")
end)

test("tie goes to lastSlot, otherwise the second slot", function()
    local plan = P.Plan({ rules = { CARROT }, equipped = {}, cost = { [13] = 1, [14] = 1 }, trinketBudget = 2 })
    eq(plan[14] and plan[14].id, "carrot", "default")
    plan = P.Plan({ rules = { CARROT }, equipped = {}, cost = { [13] = 1, [14] = 1 },
        lastSlot = { carrot = 13 }, trinketBudget = 2 })
    eq(plan[13] and plan[13].id, "carrot", "lastSlot")
end)

test("preferred trinket slot wins over cost", function()
    local plan = P.Plan({ rules = { CARROT }, equipped = {}, cost = { [13] = 4, [14] = 1 },
        preferredTrinket = 13, trinketBudget = 2 })
    eq(plan[13] and plan[13].id, "carrot")
end)

test("forbidden on-use slot is never used", function()
    local plan = P.Plan({ rules = { CARROT }, equipped = {}, forbidden = { [13] = true, [14] = true }, trinketBudget = 2 })
    eq(next(plan), nil)
end)

test("excludes drop the named rule", function()
    local a = rule("a", 1, 100, { 13, 14 }, { excludes = { "b" } })
    local b = rule("b", 2, 200, { 13, 14 })
    local plan = P.Plan({ rules = { a, b }, equipped = {}, trinketBudget = 2 })
    for _, r in pairs(plan) do eq(r.id, "a") end
end)

test("custom beats built-in on equal priority", function()
    local custom = rule("custom:1", 99, 100, { 14 }, { source = "custom", order = 1 })
    local builtin = rule("carrot", 11122, 100, { 14 })
    local plan = P.Plan({ rules = { builtin, custom }, equipped = {}, trinketBudget = 2 })
    eq(plan[14].id, "custom:1")
end)

test("same item in two rules is equipped once", function()
    local a = rule("custom:1", 500, 100, { 13, 14 }, { source = "custom", order = 1 })
    local b = rule("custom:2", 500, 90, { 13, 14 }, { source = "custom", order = 2 })
    local plan = P.Plan({ rules = { a, b }, equipped = {}, trinketBudget = 2 })
    local n = 0
    for _ in pairs(plan) do n = n + 1 end
    eq(n, 1)
end)

test("custom swim belt and carrot use different slots", function()
    local belt = rule("belt", 900003, 100, { 6 })
    local plan = P.Plan({ rules = { CARROT, belt }, equipped = {}, trinketBudget = 2 })
    eq(plan[6].id, "belt")
end)

-- ZoneMatches --------------------------------------------------------------------

local GROUPS = { desert = { { name = "Tanaris" }, { name = "Silithus", mapID = 81 } } }

test("no zones means anywhere", function()
    eq(P.ZoneMatches(nil, { name = "Elwynn Forest" }, GROUPS), true)
    eq(P.ZoneMatches({}, nil, GROUPS), true)
end)

test("zone group by name, case-insensitive", function()
    eq(P.ZoneMatches({ { group = "desert" } }, { name = "tanaris" }, GROUPS), true)
    eq(P.ZoneMatches({ { group = "desert" } }, { name = "Durotar" }, GROUPS), false)
end)

test("zone group by map ID", function()
    eq(P.ZoneMatches({ { group = "desert" } }, { name = "Silithus (renamed)", mapID = 81 }, GROUPS), true)
end)

test("explicit zone and unknown group", function()
    eq(P.ZoneMatches({ { name = "The Barrens" } }, { name = "The Barrens" }, GROUPS), true)
    eq(P.ZoneMatches({ { group = "snowy" } }, { name = "Winterspring" }, GROUPS), false)
end)

test("zone-limited rule needs a known zone", function()
    eq(P.ZoneMatches({ { group = "desert" } }, nil, GROUPS), false)
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
