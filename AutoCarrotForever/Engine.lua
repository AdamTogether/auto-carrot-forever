local ADDON, ns = ...

local API, Planner = ns.API, ns.Planner

local Engine = {}
ns.Engine = Engine

local FLIGHT_TIMEOUT = 1.5   -- seconds to wait for PLAYER_EQUIPMENT_CHANGED
local MAX_FAILURES = 3
local DEBOUNCE = 0.5         -- min seconds between equips on one slot
local TICK = 0.25            -- polled trigger interval
local TRINKET_SLOTS = { 13, 14 }
local COST_SLOTS = { 11, 12, 13, 14 }

--------------------------------------------------------------------------------
-- Triggers (DESIGN.md §6.3)
--------------------------------------------------------------------------------

-- label:  short text for buttons ("When: ...")
-- menu:   longer text for menus (defaults to label)
-- phrase: used in sentences, "Swap in X <phrase>"
-- The keys ("always", ...) are saved data and slash-command words; only the
-- player-facing text says what they mean.
ns.TRIGGERS = {
    mounted = {
        label = "Mounted", phrase = "while mounted",
        test = function() return IsMounted() and not UnitOnTaxi("player") end,
    },
    swimming = {
        label = "Swimming", phrase = "while swimming", polled = true,
        test = function() return IsSwimming() end,
    },
    submerged = {
        label = "Underwater", phrase = "while underwater", polled = true,
        test = function() return IsSubmerged ~= nil and IsSubmerged() end,
    },
    resting = {
        label = "Resting (cities/inns)", phrase = "while resting in a city or inn",
        test = function() return IsResting() end,
    },
    -- "Always" means: whenever AutoCarrot is turned on. Turning AutoCarrot off
    -- (minimap/toggle button, /ac off) puts the normal gear back.
    always = {
        label = "Always (while on)",
        menu = "Always, while AutoCarrot is on",
        phrase = "whenever AutoCarrot is on",
        warning = "Worn whenever AutoCarrot is turned on (and you are in this rule's zones), including during fights, " ..
            "because armor can't be swapped in combat. Turn AutoCarrot off to put your normal gear back.",
        test = function() return true end,
    },
}
ns.TRIGGER_ORDER = { "mounted", "swimming", "submerged", "resting", "always" }

--------------------------------------------------------------------------------
-- Runtime state (never saved)
--------------------------------------------------------------------------------

local state = {
    ready = false,          -- false during loading screens / before bags are known
    inFlight = nil,         -- the one equip or restore currently waiting for the client
    flightToken = 0,
    plan = {},              -- [slot] = rule, from the last Refresh
    rules = {},             -- all rules, normalised
    rulesById = {},
    enabledRules = {},
    suppressed = {},        -- [slot] = true: player changed it by hand during this trigger window
    failures = {},          -- [ruleId | "restore:slot"] = count
    failed = {},            -- [ruleId | "restore:slot"] = true
    lastEquipAt = {},       -- [slot] = GetTime()
    restoreAt = {},         -- [slot] = time the scheduled restore becomes due
    immediate = false,      -- ignore restoreDelay (after combat, on disable)
    blocked = nil,          -- reason the last Refresh could not swap
    warned = {},            -- one-shot chat warnings
    bindAsked = {},         -- [ruleId] = true once the client asked to bind
    expectChange = {},      -- [slot] = time until which an equipment change there is our own side effect
    useCursor = false,      -- EquipItemByName was blocked: equip via the cursor instead
    equipBlocked = false,   -- every equip method was blocked by the client
    unequipBlocked = false, -- PickupInventoryItem was blocked: can't empty a slot
}
Engine.state = state

local function now() return GetTime() end

function Engine:WarnOnce(key, msg)
    if state.warned[key] then return end
    state.warned[key] = true
    ns.Print(msg)
end

--------------------------------------------------------------------------------
-- Scheduling
--------------------------------------------------------------------------------

local requestPending = false

-- Coalesces every trigger in one frame into a single Refresh.
function Engine:Request()
    if requestPending then return end
    requestPending = true
    C_Timer.After(0, function()
        requestPending = false
        Engine:Refresh()
    end)
end

local retryTimer, retryAt

function Engine:RetryLater(seconds)
    local due = now() + seconds
    if retryTimer and retryAt and retryAt <= due then return end
    if retryTimer then retryTimer:Cancel() end
    retryAt = due
    retryTimer = C_Timer.NewTimer(seconds, function()
        retryTimer, retryAt = nil, nil
        Engine:Refresh()
    end)
end

--------------------------------------------------------------------------------
-- Rules
--------------------------------------------------------------------------------

local function equipLocOf(itemID)
    return itemID and select(4, API.GetItemInfoInstant(itemID)) or nil
end

function Engine:SlotsForCustom(c)
    if type(c.slot) == "number" then return { c.slot } end
    local loc = c.equipLoc or equipLocOf(c.match and c.match.itemID)
    return ns.EQUIP_LOC_SLOTS[loc or ""] or {}
end

function Engine:IsTwoHand(itemID)
    return ns.TWO_HAND_LOCS[equipLocOf(itemID) or ""] == true
end

-- Set pieces: { itemID } -> { match, slots, twoHand } (DESIGN.md §5.6)
local function buildPieces(list)
    local pieces = {}
    for _, p in ipairs(list or {}) do
        local loc = equipLocOf(p.itemID)
        pieces[#pieces + 1] = {
            match = { itemID = p.itemID },
            slots = ns.EQUIP_LOC_SLOTS[loc or ""] or {},
            twoHand = ns.TWO_HAND_LOCS[loc or ""] == true,
        }
    end
    return pieces
end

function Engine:BuildRules()
    local rules, byId, customKeys = {}, {}, {}
    for i, c in ipairs(ns.gdb.custom) do
        local r = {
            id = "custom:" .. c.id,
            customId = c.id,
            triggers = c.triggers or {},
            priority = tonumber(c.priority) or 50,
            source = "custom",
            order = i,
            enabled = c.enabled ~= false,
            allowBind = c.allowBind,
            noInstance = c.noInstance,
            zones = c.zones,
            entry = c,
        }
        if c.kind == "set" then
            r.pieces = buildPieces(c.pieces)
            r.need = tonumber(c.need) or 2
        else
            r.match = c.match
            r.slots = self:SlotsForCustom(c)
            r.twoHand = (c.slot == "auto" or c.slot == 16) and self:IsTwoHand(c.match.itemID)
            if r.enabled then customKeys[Planner.MatchKey(c.match)] = true end
        end
        rules[#rules + 1] = r
        byId[r.id] = r
    end
    for i, b in ipairs(ns.BUILTINS) do
        -- A custom item rule for the same item or enchant overrides the built-in.
        local overridden = false
        if b.match then overridden = customKeys[Planner.MatchKey(b.match)] == true end
        local r = {
            id = b.id,
            name = b.name,
            match = b.match,
            slots = b.slots,
            twoHand = b.twoHand,
            triggers = { [b.trigger] = true },
            priority = b.priority,
            excludes = b.excludes,
            zones = b.zones,
            source = "builtin",
            order = 1000 + i,
            enabled = ns.db.builtins[b.id] ~= false and not overridden,
            overridden = overridden,
        }
        if b.kind == "set" then
            r.pieces = buildPieces(b.pieces)
            r.need = b.need
        end
        rules[#rules + 1] = r
        byId[r.id] = r
    end
    state.rules, state.rulesById = rules, byId
    local enabled = {}
    for _, r in ipairs(rules) do
        if r.enabled then enabled[#enabled + 1] = r end
    end
    state.enabledRules = enabled
    return rules
end

function Engine:GetRule(id)
    return state.rulesById[id]
end

function Engine:AnyTrigger(rule)
    for key in pairs(rule.triggers) do
        local t = ns.TRIGGERS[key]
        if t and t.test() then return true end
    end
    return false
end

function Engine:IsSpeedItem(item)
    if not item then return false end
    for _, r in ipairs(state.enabledRules) do
        if Planner.RuleMatches(r, item) then return true end
    end
    return false
end

-- Display name for an enchant rule: the stored label ("Mithril Spurs"), or
-- read from the item the rule was made from (and remembered), or "#464".
function Engine:EnchantLabel(c)
    local label = c.label and (c.label:gsub("^[Ee]nchanted:%s*", ""))
    if (not label or label == "") and c.link then
        label = API.GetEnchantName(c.link)
        if label then c.label = label end -- backfill rules saved without a name
    end
    return (label and label ~= "") and label or ("#" .. tostring(c.match.enchantID))
end

function Engine:RuleLabel(rule)
    local c = rule.entry or rule
    if rule.name then return rule.name end
    if c.kind == "set" then
        local names = {}
        for _, p in ipairs(c.pieces or {}) do
            local name = API.GetItemInfo(p.itemID)
            names[#names + 1] = name or ("#" .. p.itemID)
        end
        return (c.label or "Set") .. " (" .. (c.need or 2) .. " of: " .. table.concat(names, ", ") .. ")"
    end
    if c.match and c.match.enchantID then
        return "enchant " .. self:EnchantLabel(c)
    end
    local itemID = c.match and c.match.itemID
    local name, link = API.GetItemInfo(itemID or 0)
    return link or name or ("item " .. tostring(itemID))
end

--------------------------------------------------------------------------------
-- Inventory
--------------------------------------------------------------------------------

local REAGENT_BAG = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or 5

function Engine:ScanInventory()
    local inv = { bags = {}, equipped = {}, free = {} }
    for bag = API.FirstBag(), API.LastBag() do
        local slots = API.GetBagSlots(bag)
        local _, family = API.GetBagFreeSlots(bag)
        for slot = 1, slots do
            local info = API.GetBagItemInfo(bag, slot)
            if info and info.hyperlink then
                local item = Planner.ParseItemString(info.hyperlink)
                if item then
                    item.bag, item.slot, item.link = bag, slot, info.hyperlink
                    item.isBound, item.isLocked = info.isBound, info.isLocked
                    inv.bags[#inv.bags + 1] = item
                end
            elseif (family or 0) == 0 and bag ~= REAGENT_BAG then
                inv.free[#inv.free + 1] = { bag = bag, slot = slot }
            end
        end
    end
    for s = 1, 19 do
        local link = GetInventoryItemLink("player", s)
        local item = link and Planner.ParseItemString(link)
        if item then
            item.link = link
            inv.equipped[s] = item
        end
    end
    return inv
end

-- May this bag item be equipped for this rule without an unwanted bind?
--   * already soulbound                         -> yes
--   * never binds (bind type None: most white
--     items, e.g. enchanted Knitted Sandals kept
--     unbound to share between alts)            -> yes
--   * Bind on Equip/Use, not bound yet          -> only if the rule allows
--     binding and the player didn't decline the client's prompt
-- Returns ok, reason ("bind" | "uncached"). Silent: HasMatch decides whether
-- to tell the player. Checked before planning (via HasMatch), so a rule that
-- can't equip anything never claims a slot ahead of one that can (§6.6).
function Engine:CanEquipFromBags(item, rule)
    if item.isBound then return true end
    local bindType = API.GetBindType(item.link)
    if bindType == nil then
        -- Not cached yet: ask for it and re-check when it arrives.
        API.LoadItem(item.itemID, function() Engine:Request() end)
        return false, "uncached"
    end
    if bindType == API.BIND_NONE then return true end
    if rule and rule.allowBind and not state.bindAsked[rule.id] then return true end
    return false, "bind"
end

function Engine:WarnBind(rule, item)
    if rule.source == "custom" then
        self:WarnOnce("bind:" .. rule.id, (item.link or "An item") ..
            " would become soulbound. Tick 'Allow binding' (the Bind box) for its rule in the item editor (/ac) to allow it.")
    else
        self:WarnOnce("bind:" .. rule.id, (item.link or rule.name or "An item") ..
            " would become soulbound, so the built-in rule skips it. Equip it once by hand, " ..
            "or add it as a custom item with 'Allow binding' ticked.")
    end
end

-- rule: when given, bag items only count if CanEquipFromBags allows them.
-- Worn items always count (they are already on, so already bound or bind-free).
-- The bind message is shown only when no copy at all is usable, so owning a
-- white pair and an unbound BoE pair equips the white pair without a warning.
function Engine:HasMatch(inv, match, rule)
    for _, it in pairs(inv.equipped) do
        if Planner.Matches(match, it) then return true end
    end
    local blocked
    for _, it in ipairs(inv.bags) do
        if Planner.Matches(match, it) then
            if not rule then return true end
            local ok, reason = self:CanEquipFromBags(it, rule)
            if ok then return true end
            if reason == "bind" then blocked = blocked or it end
        end
    end
    if blocked then self:WarnBind(rule, blocked) end
    return false
end

function Engine:Has(inv, rule)
    if rule.pieces then return #self:UsablePieces(inv, rule) >= (rule.need or 2) end
    return self:HasMatch(inv, rule.match, rule)
end

-- Set pieces this character owns and can wear.
function Engine:UsablePieces(inv, rule)
    local list = {}
    for _, p in ipairs(rule.pieces) do
        if #p.slots > 0 and self:HasMatch(inv, p.match, rule) and API.MeetsLevel(p.match.itemID) then
            list[#list + 1] = p
        end
    end
    return list
end

function Engine:FindInBags(inv, test)
    local lockedHit
    for _, it in ipairs(inv.bags) do
        if test(it) then
            if not it.isLocked then return it end
            lockedHit = lockedHit or it
        end
    end
    return lockedHit
end

--------------------------------------------------------------------------------
-- Guards (DESIGN.md §6.6)
--------------------------------------------------------------------------------

local BLOCKING_FRAMES = { "MerchantFrame", "MailFrame", "TradeFrame", "BankFrame", "BankPanel", "LootFrame", "GuildBankFrame" }

local function isCasting()
    local ok, casting = pcall(function()
        return (UnitCastingInfo("player") or UnitChannelInfo("player")) ~= nil
    end)
    return ok and casting
end

function Engine:IsDisarmed()
    if not (C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount) then return false end
    local ok, disarmed = pcall(function()
        for i = 1, C_LossOfControl.GetActiveLossOfControlDataCount() do
            local data = C_LossOfControl.GetActiveLossOfControlData(i)
            if data and data.locType == "DISARM" then return true end
        end
        return false
    end)
    return ok and disarmed
end

function Engine:Blocker()
    if state.equipBlocked then return "restricted" end
    if InCombatLockdown() or UnitAffectingCombat("player") then return "combat" end
    if UnitIsDeadOrGhost("player") then return "dead" end
    if isCasting() then return "casting" end
    if GetCursorInfo() then return "cursor" end
    for _, name in ipairs(BLOCKING_FRAMES) do
        local f = _G[name]
        -- IsVisible, not IsShown: child panels such as the retail BankPanel
        -- stay "shown" while their parent window is closed, which blocked
        -- every swap.
        if f and f.IsVisible and f:IsVisible() then return "window", name end
    end
    return nil
end

function Engine:Debounced(slot)
    local last = state.lastEquipAt[slot]
    if last and now() - last < DEBOUNCE then
        self:RetryLater(DEBOUNCE - (now() - last) + 0.05)
        return true
    end
    return false
end

function Engine:CanUse(rule)
    if rule.pieces then return true end -- checked per piece in UsablePieces
    if rule.match.itemID then
        return API.MeetsLevel(rule.match.itemID)
    end
    return true
end

-- Swap cost for slot choice (DESIGN.md §6.5 step 6). Returns cost, forbidden.
function Engine:SlotCost(slot, inv, speedWorn)
    local it = inv.equipped[slot]
    if not it or speedWorn[slot] then return 0, false end
    if not API.GetItemSpell(it.itemID) then return 1, false end
    -- Cooldowns can be secret values on Midnight-engine clients; arithmetic on
    -- a secret throws, so read them defensively and assume "ready" if unknown.
    local remaining = 0
    local ok, value = pcall(function()
        local start, duration = GetInventoryItemCooldown("player", slot)
        if API.IsSecret(start) or API.IsSecret(duration) then return 0 end
        if start and duration and start > 0 and duration > 0 then
            return math.max(0, start + duration - now())
        end
        return 0
    end)
    if ok and type(value) == "number" then remaining = value end
    local forbidden = ns.db.neverSwapOnUse and true or false
    if remaining > 30 then return 2, forbidden end
    return 3 + (30 - remaining) / 30, forbidden
end

function Engine:RestoreDelayFor(ruleId)
    local rule = state.rulesById[ruleId]
    if not rule then return 0 end
    local delay = 0
    for key in pairs(rule.triggers) do
        delay = math.max(delay, tonumber(ns.db.restoreDelay[key]) or 0)
    end
    return delay
end

--------------------------------------------------------------------------------
-- Refresh: the single entry point (DESIGN.md §6.1)
--------------------------------------------------------------------------------

-- Errors inside Refresh are reported once per distinct message instead of on
-- every event (Forever pauses all Lua error reporting after 100 errors).
local reportedErrors = {}

function Engine:Refresh()
    local ok, err = xpcall(function() return Engine:RefreshUnsafe() end, function(e)
        return tostring(e) .. "\n" .. (debugstack and debugstack(2) or "")
    end)
    if not ok then
        local key = tostring(err):match("^[^\n]*") or "?"
        if not reportedErrors[key] then
            reportedErrors[key] = true
            geterrorhandler()(err)
        end
    end
end

function Engine:RefreshUnsafe()
    if not state.ready or not ns.db then return end
    local db = ns.db

    self:BuildRules()

    local blocked, detail = self:Blocker()
    if blocked ~= state.blocked then
        ns.Debug(blocked and ("Waiting: " .. blocked .. (detail and (" (" .. detail .. ")") or "")) or "No longer waiting")
    end
    state.blocked = blocked
    if blocked then
        if blocked == "combat" then
            -- Armor waits for PLAYER_REGEN_ENABLED; weapons go back now (§6.9).
            self:CombatWeaponPass()
        elseif blocked == "restricted" then
            -- Nothing to retry until /reload.
        else
            self:RetryLater(1)
        end
        ns:Fire("AC_STATUS")
        return
    end
    if state.inFlight then return end

    local inv = self:ScanInventory()
    local t = now()
    local inInstance = IsInInstance()
    local zone = API.GetCurrentZone()
    state.zone = zone

    local active = {}
    if db.enabled then
        for _, r in ipairs(state.enabledRules) do
            if not state.failed[r.id]
                and self:AnyTrigger(r)
                and self:Has(inv, r)
                and self:CanUse(r)
                and Planner.ZoneMatches(r.zones, zone, ns.gdb.zoneGroups)
                and not (r.noInstance and inInstance) then
                if r.pieces then
                    -- Plan with a copy limited to the pieces we can actually wear.
                    active[#active + 1] = {
                        id = r.id, name = r.name, pieces = self:UsablePieces(inv, r), need = r.need,
                        priority = r.priority, source = r.source, order = r.order, allowBind = r.allowBind,
                    }
                else
                    active[#active + 1] = r
                end
            end
        end
    end

    local speedWorn, cost, forbidden = {}, {}, {}
    for s, it in pairs(inv.equipped) do
        if self:IsSpeedItem(it) then speedWorn[s] = true end
    end
    for _, s in ipairs(COST_SLOTS) do
        cost[s], forbidden[s] = self:SlotCost(s, inv, speedWorn)
    end

    local unlockedTrinkets = 0
    for _, s in ipairs(TRINKET_SLOTS) do
        if not db.lockedSlots[s] and not forbidden[s] then unlockedTrinkets = unlockedTrinkets + 1 end
    end

    local plan = Planner.Plan({
        rules = active,
        equipped = inv.equipped,
        speedWorn = speedWorn,
        locked = db.lockedSlots,
        forbidden = forbidden,
        cost = cost,
        preferredTrinket = tonumber(db.trinketSlot),
        lastSlot = db.lastSlot,
        trinketBudget = math.min(tonumber(db.speedTrinketSlots) or 2, unlockedTrinkets),
    })
    state.plan = plan

    -- Every slot the plan touches or we currently own.
    local slots, seen = {}, {}
    for s in pairs(plan) do seen[s] = true end
    for s in pairs(db.slotOwner) do seen[s] = true end
    for s in pairs(seen) do slots[#slots + 1] = s end
    table.sort(slots)

    -- A manual change only holds until the trigger window closes.
    for s in pairs(state.suppressed) do
        if not plan[s] then state.suppressed[s] = nil end
    end

    local nextWake
    for _, slot in ipairs(slots) do
        local wanted = plan[slot]
        local owner = db.slotOwner[slot]
        local current = inv.equipped[slot]

        if state.suppressed[slot] then
            -- changed by hand during this trigger window: leave it alone
        elseif wanted then
            state.restoreAt[slot] = nil
            if Planner.Matches(wanted.match, current) then
                if owner and owner ~= wanted.id then
                    db.slotOwner[slot] = wanted.id -- hand-over; saved[slot] untouched
                end
            elseif not self:Debounced(slot) then
                if self:EquipRule(wanted, slot, inv) then
                    ns:Fire("AC_STATUS")
                    return
                end
            end
        elseif owner and not state.failed["restore:" .. slot] and not self:CompanionBlocked(slot, plan) then
            local due = state.restoreAt[slot]
            if state.immediate then
                due = t
            elseif not due then
                due = t + self:RestoreDelayFor(owner)
            end
            state.restoreAt[slot] = due
            if t >= due then
                if not self:Debounced(slot) and self:Restore(slot, inv) then
                    ns:Fire("AC_STATUS")
                    return
                end
            else
                nextWake = math.min(nextWake or math.huge, due - t)
            end
        end
    end

    if nextWake then
        self:RetryLater(nextWake + 0.05)
    else
        state.immediate = false
    end
    ns:Fire("AC_STATUS")
end

--------------------------------------------------------------------------------
-- Weapons (DESIGN.md §6.9)
--------------------------------------------------------------------------------

-- A slot whose restore would undo something still wanted: the off hand while a
-- planned two-hander holds the main hand, or a two-handed normal weapon while a
-- planned off-hand speed item is worn.
function Engine:CompanionBlocked(slot, plan)
    if slot == 17 and plan[16] and plan[16].twoHand then return true end
    if slot == 16 and plan[17] then
        local saved = Planner.ParseItemString(ns.db.saved[16])
        if saved and self:IsTwoHand(saved.itemID) then return true end
    end
    return false
end

-- In combat armor is locked but weapons are not: put the real weapons back at
-- once, main hand first, one swap per pass (each success triggers the next).
function Engine:CombatWeaponPass()
    if state.inFlight or not ns.db then return end
    if UnitIsDeadOrGhost("player") or isCasting() or GetCursorInfo() then return end
    if self:IsDisarmed() then
        self:RetryLater(1)
        return
    end
    local inv
    for _, slot in ipairs({ 16, 17, 18 }) do
        if ns.db.slotOwner[slot] and not state.failed["restore:" .. slot] then
            inv = inv or self:ScanInventory()
            if self:Restore(slot, inv) then return end
        end
    end
end

--------------------------------------------------------------------------------
-- Equip and restore (DESIGN.md §6.2)
--------------------------------------------------------------------------------

function Engine:StartFlight(flight)
    state.flightToken = state.flightToken + 1
    flight.token = state.flightToken
    flight.started = now()
    state.inFlight = flight
    state.lastEquipAt[flight.slot] = flight.started
    local token = flight.token
    C_Timer.After(FLIGHT_TIMEOUT, function()
        if state.inFlight and state.inFlight.token == token then
            Engine:FlightFailed()
        end
    end)
end

-- If the client refuses the swap, the item stays on the cursor; FlightFailed
-- drops it back into its bag slot when the flight times out.
local function equipFromCursor(slot)
    if not CursorHasItem() then return false end
    EquipCursorItem(slot)
    return true
end

-- Puts a bag item into an equipment slot. C_Item.EquipItemByName with the full
-- link is the primary method: it picks the exact copy, shows the client's own
-- bind confirmation, and does not touch the cursor (cursor calls such as
-- PickupInventoryItem have been reported as forbidden in some contexts on
-- Forever). The cursor path is the fallback if the client blocks it.
function Engine:SendEquip(item, slot)
    if not state.useCursor and API.CanEquipByName() then
        API.EquipItemByName(item.link, slot)
        return true
    end
    API.PickupBagItem(item.bag, item.slot)
    return equipFromCursor(slot)
end

function Engine:EquipRule(rule, slot, inv)
    local db = ns.db
    -- Only copies this rule may equip (bound, bind-free, or binding allowed).
    local item = self:FindInBags(inv, function(it)
        return Planner.Matches(rule.match, it) and self:CanEquipFromBags(it, rule)
    end)
    if not item then return false end
    if item.isLocked then
        self:RetryLater(0.5)
        return false
    end

    -- Slots the client will empty as a side effect (two-handers, §6.9).
    local displaced = {}
    if slot == 16 and rule.twoHand and inv.equipped[17] then
        displaced[#displaced + 1] = 17
    elseif slot == 17 and inv.equipped[16] and self:IsTwoHand(inv.equipped[16].itemID) then
        displaced[#displaced + 1] = 16
    end
    if #displaced > 0 and #inv.free == 0 then
        self:WarnOnce("bagsfull:weapon", "Bags are full, so " .. (item.link or "the speed weapon") ..
            " can't be equipped (the other hand needs somewhere to go).")
        return false
    end

    -- Remember the normal item (DESIGN.md §5.1), never a speed item.
    local function remember(s)
        if db.slotOwner[s] then return end
        local current = inv.equipped[s]
        if not current then
            db.saved[s] = false
        elseif not self:IsSpeedItem(current) then
            db.saved[s] = current.str
        elseif db.saved[s] == nil then
            db.saved[s] = false
        end
    end
    remember(slot)
    for _, d in ipairs(displaced) do
        remember(d)
        db.slotOwner[d] = rule.id
        state.expectChange[d] = now() + 3
    end

    local started = self:SendEquip(item, slot)
    if not started then
        self:CountFailure(rule.id, slot)
        return false
    end

    db.slotOwner[slot] = rule.id
    db.lastSlot[rule.id] = slot
    ns.Debug("Equipping " .. (item.link or "?") .. " in slot " .. slot)
    self:StartFlight({ kind = "equip", slot = slot, ruleId = rule.id, match = rule.match })
    return true
end

function Engine:ClearSlot(slot)
    local db = ns.db
    db.saved[slot] = nil
    db.slotOwner[slot] = nil
    state.restoreAt[slot] = nil
end

function Engine:Restore(slot, inv)
    local db = ns.db
    local saved = db.saved[slot]
    local current = inv.equipped[slot]

    if saved == nil then
        self:ClearSlot(slot)
        return false
    end

    if saved == false then
        -- The slot was empty: take the speed item off into the bags.
        if not current then
            self:ClearSlot(slot)
            return false
        end
        if state.unequipBlocked then
            self:WarnOnce("unequip", "The game blocked taking items off, so " .. (current.link or "the speed item") ..
                " stays on. Take it off by hand.")
            self:ClearSlot(slot)
            return false
        end
        local free = inv.free[1]
        if not free then
            self:WarnOnce("bagsfull:" .. slot, "Bags are full, so " .. (current.link or "the speed item") ..
                " stays equipped until a bag slot is free.")
            return false
        end
        state.warned["bagsfull:" .. slot] = nil
        PickupInventoryItem(slot)
        if not CursorHasItem() then return false end
        API.PickupBagItem(free.bag, free.slot)
        ns.Debug("Unequipping slot " .. slot .. " into bags")
        self:StartFlight({ kind = "restore", slot = slot, expectEmpty = true })
        return true
    end

    local want = Planner.ParseItemString(saved)
    if not want then
        self:ClearSlot(slot)
        return false
    end
    if current and current.key == want.key then
        self:ClearSlot(slot)
        return false
    end

    -- Moved by hand to another slot: don't pull it out of there.
    for s, it in pairs(inv.equipped) do
        if s ~= slot and it.key == want.key then
            db.saved[slot] = false
            return self:Restore(slot, inv)
        end
    end

    local item = self:FindInBags(inv, function(it) return it.key == want.key end)
        or self:FindInBags(inv, function(it) return it.itemID == want.itemID end)
    if not item then
        local _, link = API.GetItemInfo(want.itemID)
        if API.GetItemCount(want.itemID, true) > API.GetItemCount(want.itemID, false) then
            self:WarnOnce("bank:" .. slot, (link or "Your normal item") ..
                " is in the bank. It will be put back once it is in your bags.")
        else
            self:WarnOnce("gone:" .. slot, (link or "Your normal item") ..
                " is no longer in your bags, so the speed item stays on.")
            self:ClearSlot(slot)
        end
        return false
    end
    if item.isLocked then
        self:RetryLater(0.5)
        return false
    end

    if not self:SendEquip(item, slot) then
        self:CountFailure(nil, slot)
        return false
    end
    ns.Debug("Restoring " .. (item.link or "?") .. " to slot " .. slot)
    self:StartFlight({ kind = "restore", slot = slot, expectKey = item.key })
    return true
end

function Engine:CountFailure(ruleId, slot)
    local key = ruleId or ("restore:" .. slot)
    state.failures[key] = (state.failures[key] or 0) + 1
    if state.failures[key] >= MAX_FAILURES then
        state.failed[key] = true
        if ruleId then
            local rule = state.rulesById[ruleId]
            ns.Print("Could not equip " .. (rule and self:RuleLabel(rule) or ruleId) ..
                " after " .. MAX_FAILURES .. " tries; skipping it until you edit the rule, /reload or /ac restore.")
            -- Put back whatever the failed attempts displaced.
            if ns.db.slotOwner[slot] == ruleId then
                state.restoreAt[slot] = now()
            end
        else
            ns.Print("Could not restore slot " .. slot .. " after " .. MAX_FAILURES ..
                " tries. Use /ac restore to try again.")
        end
        ns:Fire("AC_RULES")
    end
    self:RetryLater(DEBOUNCE)
end

function Engine:FlightFailed()
    local f = state.inFlight
    -- The event may simply have been missed: check the slot before blaming anyone.
    local link = GetInventoryItemLink("player", f.slot)
    local current = link and Planner.ParseItemString(link)
    if (f.kind == "equip" and Planner.Matches(f.match, current))
        or (f.expectEmpty and current == nil)
        or (f.expectKey and current and current.key == f.expectKey) then
        self:FlightSucceeded(f)
        return
    end
    state.inFlight = nil
    if CursorHasItem() then ClearCursor() end
    ns.Debug("Swap in slot " .. f.slot .. " did not complete")
    self:CountFailure(f.kind == "equip" and f.ruleId or nil, f.slot)
end

function Engine:FlightSucceeded(f)
    state.inFlight = nil
    if f.kind == "equip" then
        state.failures[f.ruleId] = nil
    else
        state.failures["restore:" .. f.slot] = nil
        self:ClearSlot(f.slot)
    end
    self:Request()
end

function Engine:OnEquipmentChanged(slot)
    if not ns.db or not slot then return end
    local link = GetInventoryItemLink("player", slot)
    local current = link and Planner.ParseItemString(link)
    local f = state.inFlight
    if f and f.slot == slot then
        local ok
        if f.kind == "equip" then
            ok = Planner.Matches(f.match, current)
        elseif f.expectEmpty then
            ok = current == nil
        else
            ok = current ~= nil and current.key == f.expectKey
        end
        if ok then self:FlightSucceeded(f) end
        return
    end
    self:CheckManualChange(slot, current)
    self:Request()
end

-- Someone else (the player, the Equipment Manager, another addon) put a normal
-- item into a slot we manage: it becomes the normal item (DESIGN.md §6.6).
function Engine:CheckManualChange(slot, current)
    if not state.ready then return end
    if state.expectChange[slot] and now() < state.expectChange[slot] then return end -- our own side effect
    local db = ns.db
    local owner = db.slotOwner[slot]
    local planned = state.plan[slot]
    if not owner and not planned then return end
    if current and self:IsSpeedItem(current) then return end
    if owner then
        db.slotOwner[slot] = nil
        db.saved[slot] = nil
    end
    state.restoreAt[slot] = nil
    if planned then state.suppressed[slot] = true end
    ns.Debug("Slot " .. slot .. " changed by hand; leaving it alone")
end

function Engine:OnBindConfirm()
    local f = state.inFlight
    if f and f.kind == "equip" then
        -- Keep slotOwner: if the player accepts, the restore later still works;
        -- if they decline, the normal item is still worn and Restore clears it.
        state.bindAsked[f.ruleId] = true
        state.inFlight = nil
        ns.Debug("Client asked to confirm binding; waiting for the player")
    end
end

-- The client refused one of our calls (ADDON_ACTION_FORBIDDEN/BLOCKED).
-- Switch method where there is an alternative; otherwise stop and say why.
local CURSOR_FUNCS = { PickupContainerItem = true, EquipCursorItem = true }

function Engine:OnActionBlocked(addon, func)
    if addon ~= ADDON then return end
    -- The event reports names like "PickupInventoryItem()" or "C_Item.EquipItemByName()".
    func = (tostring(func or "?"):gsub("%(%)$", ""))
    local short = func:match("([%w_]+)$") or func
    state.inFlight = nil
    if CursorHasItem() then ClearCursor() end
    if short == "EquipItemByName" then
        if state.useCursor then state.equipBlocked = true else state.useCursor = true end
    elseif CURSOR_FUNCS[short] then
        if state.useCursor or not API.CanEquipByName() then state.equipBlocked = true end
    elseif short == "PickupInventoryItem" then
        state.unequipBlocked = true
    end
    if state.equipBlocked then
        self:WarnOnce("blocked", "The game is blocking addons from equipping items (" .. func ..
            "), so automatic swaps are off this session. Please report this with your client build.")
    else
        self:WarnOnce("blocked:" .. func, "The game blocked " .. func .. "(); switching to another method.")
    end
    ns:Fire("AC_STATUS")
    self:RetryLater(1)
end

--------------------------------------------------------------------------------
-- Public controls
--------------------------------------------------------------------------------

function Engine:SetEnabled(on, auto)
    ns.db.enabled = on and true or false
    if not auto then ns.db.wasAutoDisabled = false end
    if not on then state.immediate = true end
    wipe(state.suppressed)
    self:UpdateTicker()
    self:Request()
    ns:Fire("AC_STATUS")
end

function Engine:CheckInstance()
    local db = ns.db
    if not db then return end
    local inInstance, kind = IsInInstance()
    if inInstance and kind and db.instanceTypes[kind] then
        if db.enabled then
            self:SetEnabled(false, true)
            db.wasAutoDisabled = true
            ns.Print("Disabled inside this instance type; it turns back on when you leave.")
        end
    elseif not db.enabled and db.wasAutoDisabled then
        db.wasAutoDisabled = false
        self:SetEnabled(true, true)
        ns.Print("Re-enabled after leaving the instance.")
    end
end

-- Clears failure and manual-change flags and re-syncs gear now.
function Engine:Resync()
    wipe(state.failed)
    wipe(state.failures)
    wipe(state.suppressed)
    wipe(state.warned)
    wipe(state.bindAsked)
    state.immediate = true
    self:Request()
end

function Engine:OnSettingsChanged()
    self:BuildRules()
    self:UpdateTicker()
    self:Request()
    ns:Fire("AC_RULES")
    ns:Fire("AC_STATUS")
end

--------------------------------------------------------------------------------
-- Custom rules
--------------------------------------------------------------------------------

-- spec: { input = link | itemID | "12345", byEnchant, triggers, slot, label }
function Engine:AddCustomRule(spec)
    local input = spec.input
    local parsed = type(input) == "string" and Planner.ParseItemString(input)
    local itemID = parsed and parsed.itemID or tonumber(input)
    if not itemID then
        return nil, "Not an item link or item ID: " .. tostring(input)
    end
    local _, _, _, equipLoc = API.GetItemInfoInstant(itemID)
    if not equipLoc or equipLoc == "" then
        return nil, "That item is not equippable (or the ID is unknown)."
    end
    local slots = ns.EQUIP_LOC_SLOTS[equipLoc]
    if not slots then
        return nil, "Shirts and tabards are not supported."
    end

    local match
    if spec.byEnchant then
        if not parsed or parsed.enchantID == 0 then
            return nil, "That item link has no enchant to match."
        end
        match = { enchantID = parsed.enchantID }
    else
        match = { itemID = itemID }
    end

    local slot = spec.slot or "auto"
    if slot ~= "auto" then
        local valid = false
        for _, s in ipairs(slots) do if s == slot then valid = true end end
        if not valid then
            return nil, "Slot " .. tostring(slot) .. " does not fit this item."
        end
    end

    local gdb = ns.gdb
    for _, z in ipairs(spec.zones or {}) do
        if z.group then self:GroupZones(z.group) end -- create "<x> areas" groups on first use
    end
    -- Enchant rules are labelled with the enchant's name ("Mithril Spurs"),
    -- read from the tooltip of the item they were made from.
    local label = spec.label and (spec.label:gsub("^[Ee]nchanted:%s*", ""))
    if spec.byEnchant and not label and parsed then label = API.GetEnchantName(input) end
    local entry = {
        id = gdb.nextRuleId,
        match = match,
        slot = slot,
        equipLoc = equipLoc,
        triggers = spec.triggers or { mounted = true },
        priority = 50,
        enabled = true,
        allowBind = false,
        noInstance = false,
        zones = spec.zones,
        link = parsed and input or nil,
        label = label,
    }
    gdb.nextRuleId = gdb.nextRuleId + 1
    table.insert(gdb.custom, entry)
    ns.Discovery:Forget(match)
    self:OnSettingsChanged()
    return entry
end

-- spec: { pieces = { link | itemID ... }, need, triggers, zones, label }
function Engine:AddSetRule(spec)
    local pieces, seen = {}, {}
    for _, input in ipairs(spec.pieces or {}) do
        local parsed = type(input) == "string" and Planner.ParseItemString(input)
        local itemID = parsed and parsed.itemID or tonumber(input)
        if not itemID then return nil, "Not an item link or item ID: " .. tostring(input) end
        local loc = equipLocOf(itemID)
        if not loc or not ns.EQUIP_LOC_SLOTS[loc] then
            return nil, "Item " .. itemID .. " can't be used in a set rule (not equippable, or a shirt/tabard)."
        end
        if not seen[itemID] then
            seen[itemID] = true
            pieces[#pieces + 1] = { itemID = itemID }
        end
    end
    local need = tonumber(spec.need) or 2
    if #pieces < 2 then return nil, "A set rule needs at least two different items." end
    if need < 1 or need > #pieces then return nil, "Pieces needed must be between 1 and " .. #pieces .. "." end
    local gdb = ns.gdb
    for _, z in ipairs(spec.zones or {}) do
        if z.group then self:GroupZones(z.group) end
    end
    local entry = {
        id = gdb.nextRuleId,
        kind = "set",
        pieces = pieces,
        need = need,
        triggers = spec.triggers or { mounted = true },
        priority = 50,
        enabled = true,
        allowBind = false,
        noInstance = false,
        zones = spec.zones,
        label = spec.label,
    }
    gdb.nextRuleId = gdb.nextRuleId + 1
    table.insert(gdb.custom, entry)
    for _, p in ipairs(pieces) do ns.Discovery:Forget({ itemID = p.itemID }) end
    self:OnSettingsChanged()
    return entry
end

function Engine:FindCustom(id)
    for i, c in ipairs(ns.gdb.custom) do
        if c.id == id then return c, i end
    end
end

function Engine:RemoveCustomRule(id)
    local _, index = self:FindCustom(id)
    if not index then return false end
    table.remove(ns.gdb.custom, index)
    state.failed["custom:" .. id] = nil
    state.failures["custom:" .. id] = nil
    self:OnSettingsChanged()
    return true
end

-- target: rule number, item ID or item link.
function Engine:RemoveCustomRulesMatching(target)
    local parsed = Planner.ParseItemString(target)
    local number = tonumber(target)
    local ids = {}
    for _, c in ipairs(ns.gdb.custom) do
        local hit
        local probe = parsed or (number and { itemID = number, enchantID = 0 })
        if c.kind == "set" then
            for _, p in ipairs(c.pieces) do
                if probe and p.itemID == probe.itemID then hit = true end
            end
            if number and c.id == number then hit = true end
        elseif parsed then
            hit = c.match.itemID == parsed.itemID
                or (c.match.enchantID and c.match.enchantID == parsed.enchantID)
        elseif number then
            hit = c.id == number or c.match.itemID == number
        end
        if hit then ids[#ids + 1] = c.id end
    end
    for _, id in ipairs(ids) do self:RemoveCustomRule(id) end
    return #ids
end

function Engine:MoveCustomRule(id, delta)
    local list = ns.gdb.custom
    local _, i = self:FindCustom(id)
    local j = i and i + delta
    if not j or j < 1 or j > #list then return end
    list[i], list[j] = list[j], list[i]
    self:OnSettingsChanged()
end

-- Called when the user edits a rule in the editor.
function Engine:RuleEdited(id)
    state.failed["custom:" .. id] = nil
    state.failures["custom:" .. id] = nil
    state.bindAsked["custom:" .. id] = nil
    state.warned["bind:custom:" .. id] = nil
    self:OnSettingsChanged()
end

--------------------------------------------------------------------------------
-- Zones (DESIGN.md §5.5)
--------------------------------------------------------------------------------

function Engine:GroupLabel(key)
    local words = key:gsub("_", " ")
    return (words:sub(1, 1):upper() .. words:sub(2)) .. " areas"
end

function Engine:ZoneLabel(zones)
    if not zones or #zones == 0 then return "Any zone" end
    local parts = {}
    for _, z in ipairs(zones) do
        parts[#parts + 1] = z.group and self:GroupLabel(z.group) or (z.name or ("map " .. tostring(z.mapID)))
    end
    return table.concat(parts, ", ")
end

function Engine:GroupZones(key)
    ns.gdb.zoneGroups[key] = ns.gdb.zoneGroups[key] or {}
    return ns.gdb.zoneGroups[key]
end

function Engine:GroupKeys()
    local keys = {}
    for key in pairs(ns.gdb.zoneGroups) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

-- Index of the current zone in a zone list, or nil.
function Engine:FindZone(list, zone)
    if not zone then return nil end
    for i, z in ipairs(list) do
        if Planner.ZoneMatches({ z }, zone, nil) then return i end
    end
end

-- Adds or removes the player's current zone from a zone list in place.
function Engine:ToggleCurrentZone(list, add)
    local zone = API.GetCurrentZone()
    if not zone then return nil end
    local i = self:FindZone(list, zone)
    if add and not i then
        list[#list + 1] = { name = zone.name, mapID = zone.mapID }
    elseif add and i then
        list[i].mapID = list[i].mapID or zone.mapID -- learn the map ID for a name-only entry
    elseif not add and i then
        table.remove(list, i)
    end
    self:OnSettingsChanged()
    return zone
end

function Engine:IsInGroup(key, zone)
    return self:FindZone(self:GroupZones(key), zone or API.GetCurrentZone()) ~= nil
end

function Engine:RemoveGroupZone(key, index)
    local list = self:GroupZones(key)
    if list[index] then
        table.remove(list, index)
        self:OnSettingsChanged()
    end
end

-- "Snowy", "snowy areas" -> key "snowy" (label "Snowy areas").
function Engine:CreateGroup(name)
    local key = strtrim((name or ""):lower()):gsub("%s+areas?$", ""):gsub("[^%a%d]+", "_")
    key = key:gsub("^_+", ""):gsub("_+$", "")
    if key == "" then return nil, "Type a name, e.g. Snowy." end
    if ns.gdb.zoneGroups[key] then return nil, self:GroupLabel(key) .. " already exists." end
    ns.gdb.zoneGroups[key] = {}
    self:OnSettingsChanged()
    return key
end

-- Built-in and custom rules whose zone condition uses this group.
function Engine:RulesUsingGroup(key)
    local labels = {}
    for _, r in ipairs(state.rules) do
        for _, z in ipairs(r.zones or {}) do
            if z.group == key then
                labels[#labels + 1] = self:RuleLabel(r)
                break
            end
        end
    end
    return labels
end

function Engine:DeleteGroup(key)
    if #self:RulesUsingGroup(key) > 0 then return false end
    ns.gdb.zoneGroups[key] = nil
    self:OnSettingsChanged()
    return true
end

-- Adds back any default zones that were removed (keeps the player's additions).
function Engine:RestoreGroupDefaults(key)
    local defaults = ns.ZONE_GROUP_DEFAULTS[key]
    if not defaults then return end
    local list = self:GroupZones(key)
    for _, z in ipairs(defaults) do
        if not self:FindZone(list, { name = z.name }) then
            list[#list + 1] = { name = z.name, mapID = z.mapID }
        end
    end
    self:OnSettingsChanged()
end

--------------------------------------------------------------------------------
-- Status for the UI
--------------------------------------------------------------------------------

-- "worn" | "planned" | "failed" | "disabled" | "idle"
function Engine:RuleStatus(ruleId)
    if state.failed[ruleId] then return "failed" end
    local rule = state.rulesById[ruleId]
    if not rule or not rule.enabled then return "disabled" end
    for slot, owner in pairs(ns.db.slotOwner) do
        if owner == ruleId and (not state.inFlight or state.inFlight.slot ~= slot) then return "worn" end
    end
    for _, r in pairs(state.plan) do
        if r.id == ruleId then return "planned" end
    end
    return "idle"
end

function Engine:PendingRestores()
    local n = 0
    for slot in pairs(ns.db.slotOwner) do
        if not state.plan[slot] then n = n + 1 end
    end
    return n
end

local BLOCK_TEXT = {
    combat = "combat",
    dead = "dead",
    casting = "casting",
    cursor = "item on cursor",
    window = "a trade, mail, vendor, bank or loot window is open",
    restricted = "the game is blocking addon equipment swaps",
}

function Engine:StatusLines()
    local db = ns.db
    local lines = {}
    lines[#lines + 1] = db.enabled and "|cff00ff00Enabled|r" or "|cffff4040Disabled|r"
    if state.blocked and (self:PendingRestores() > 0 or next(state.plan)) then
        lines[#lines + 1] = "|cffffd100Swap pending (" .. (BLOCK_TEXT[state.blocked] or state.blocked) .. ")|r"
    end
    for slot = 1, 19 do
        local owner = db.slotOwner[slot]
        if owner then
            local rule = state.rulesById[owner]
            local name = ns.SLOT_NAMES[slot] or ("Slot " .. slot)
            local label = rule and self:RuleLabel(rule) or owner
            if state.plan[slot] then
                lines[#lines + 1] = name .. ": " .. label
            else
                lines[#lines + 1] = name .. ": " .. label .. " |cffffd100(restore pending)|r"
            end
        end
    end
    return lines
end

function Engine:IsPending()
    return state.blocked ~= nil and (self:PendingRestores() > 0 or next(state.plan) ~= nil)
end

local function UI_TriggerText(triggers)
    local parts = {}
    for _, key in ipairs(ns.TRIGGER_ORDER) do
        if triggers[key] then parts[#parts + 1] = ns.TRIGGERS[key].label end
    end
    return #parts > 0 and table.concat(parts, "/") or "never"
end

-- /ac check: explain how the engine sees one item (DESIGN.md §8.5).
function Engine:CheckItem(input)
    local item = Planner.ParseItemString(input)
    if not item and tonumber(input) then item = Planner.ParseItemString("item:" .. tonumber(input)) end
    if not item then
        ns.Print("Not an item link or item ID: " .. tostring(input))
        return
    end
    self:BuildRules()
    local _, link = API.GetItemInfo(item.itemID)
    item.link = Planner.ParseItemString(input) and input or link
    local _, _, _, equipLoc = API.GetItemInfoInstant(item.itemID)
    local bindType = API.GetBindType(item.link or item.itemID)
    local bindText = { [0] = "never binds", [1] = "bind on pickup", [2] = "bind on equip", [3] = "bind on use", [4] = "quest item" }
    ns.Print((item.link or ("item " .. item.itemID)) .. ":")
    ns.Print(string.format("  item ID %d, enchant ID %s, slot type %s", item.itemID,
        item.enchantID ~= 0 and tostring(item.enchantID) or "none", tostring(equipLoc or "?")))
    -- Where is it, and is that copy bound?
    local inv = self:ScanInventory()
    local where, bagCopy
    for s, it in pairs(inv.equipped) do
        if it.key == item.key then where = "equipped (" .. (ns.SLOT_NAMES[s] or s) .. ")" end
    end
    for _, it in ipairs(inv.bags) do
        if not where and it.key == item.key then
            where = "in your bags, " .. (it.isBound and "soulbound" or "not soulbound")
            bagCopy = it
        end
    end
    ns.Print("  " .. (where or "not in your bags or gear") .. "; " ..
        (bindType and (bindText[bindType] or ("bind type " .. bindType)) or "bind type unknown (item not cached yet)"))
    local any = false
    for _, r in ipairs(state.rules) do
        if Planner.RuleMatches(r, item) then
            any = true
            local status = self:RuleStatus(r.id)
            if r.overridden then status = "overridden by a custom rule" end
            if bagCopy and not r.overridden then
                local ok, reason = self:CanEquipFromBags(bagCopy, r)
                status = status .. (ok and ", this copy can be swapped" or
                    (reason == "bind" and ", |cffff5050skipped: it would become soulbound|r" or ", item info still loading"))
            end
            ns.Print("  matched by: " .. self:RuleLabel(r) .. " (" .. (r.source == "custom" and "custom" or "built-in") ..
                ", " .. UI_TriggerText(r.triggers) .. ", " .. status .. ")")
        end
    end
    if not any then
        ns.Print("  |cffffd100No rule matches it.|r Add it with /ac (drag it onto the editor; tick 'Match the enchant' for an enchanted item).")
    end
end

function Engine:PrintRules()
    self:BuildRules()
    ns.Print("Rules (priority, triggers, status):")
    for _, r in ipairs(Planner.SortRules(state.rules)) do
        local triggers = {}
        for _, key in ipairs(ns.TRIGGER_ORDER) do
            if r.triggers[key] then triggers[#triggers + 1] = key end
        end
        local tag = r.source == "custom" and ("#" .. r.customId) or "built-in"
        local status = self:RuleStatus(r.id)
        if r.overridden then status = "overridden by a custom rule" end
        if state.failed[r.id] then status = "|cffff4040failed|r" end
        local where = (r.zones and #r.zones > 0) and ("  in " .. self:ZoneLabel(r.zones)) or ""
        ns.Print(string.format("  [%s] %s  pri %d  %s%s  %s", tag, self:RuleLabel(r), r.priority,
            table.concat(triggers, ","), where, status))
    end
end

--------------------------------------------------------------------------------
-- Polled triggers (swimming / submerged have no events)
--------------------------------------------------------------------------------

local ticker, lastPolled

local function polledSignature()
    local sig = ""
    for _, key in ipairs(ns.TRIGGER_ORDER) do
        local t = ns.TRIGGERS[key]
        if t.polled then sig = sig .. (t.test() and "1" or "0") end
    end
    return sig
end

function Engine:UpdateTicker()
    local need = false
    if ns.db and ns.db.enabled then
        for _, r in ipairs(state.enabledRules) do
            for key in pairs(r.triggers) do
                if ns.TRIGGERS[key] and ns.TRIGGERS[key].polled then need = true end
            end
        end
    end
    if need and not ticker then
        lastPolled = polledSignature()
        ticker = C_Timer.NewTicker(TICK, function()
            local sig = polledSignature()
            if sig ~= lastPolled then
                lastPolled = sig
                Engine:Request()
            end
        end)
    elseif not need and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

--------------------------------------------------------------------------------
-- Events (DESIGN.md §6.4)
--------------------------------------------------------------------------------

local waitingForBags = false

local function markReady()
    if state.ready then return end
    state.ready = true
    waitingForBags = false
    Engine:BuildRules()
    Engine:UpdateTicker()
    Engine:Request()
end

local function request() Engine:Request() end

ns:On("AC_LOADED", function()
    Engine:BuildRules()
end)

ns:On("PLAYER_ENTERING_WORLD", function()
    state.ready = false
    waitingForBags = true
    state.inFlight = nil
    Engine:CheckInstance()
    C_Timer.After(2, markReady)
end)

ns:On("PLAYER_LEAVING_WORLD", function()
    state.ready = false
end)

ns:On("BAG_UPDATE_DELAYED", function()
    if waitingForBags then
        markReady()
    else
        request()
    end
end)

ns:On("ZONE_CHANGED_NEW_AREA", function()
    Engine:CheckInstance()
    request()
end)

ns:On("PLAYER_REGEN_ENABLED", function()
    -- Restore right away after combat, skipping restoreDelay (DESIGN.md §6.6).
    state.immediate = true
    request()
end)

ns:On("PLAYER_REGEN_DISABLED", function()
    state.blocked = "combat"
    request() -- swap speed weapons back right away (§6.9)
end)

ns:On("ADDON_ACTION_FORBIDDEN", function(addon, func) Engine:OnActionBlocked(addon, func) end)
ns:On("ADDON_ACTION_BLOCKED", function(addon, func) Engine:OnActionBlocked(addon, func) end)

ns:On("LOSS_OF_CONTROL_UPDATE", request)
ns:On("LOSS_OF_CONTROL_ADDED", request)

ns:On("PLAYER_EQUIPMENT_CHANGED", function(slot)
    Engine:OnEquipmentChanged(slot)
end)

for _, event in ipairs({
    "PLAYER_MOUNT_DISPLAY_CHANGED",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "PLAYER_CONTROL_LOST",
    "PLAYER_CONTROL_GAINED",
    "PLAYER_UPDATE_RESTING",
    "PLAYER_ALIVE",
    "PLAYER_UNGHOST",
    "ITEM_LOCK_CHANGED",
    "TRADE_CLOSED",
    "MAIL_CLOSED",
    "MERCHANT_CLOSED",
    "LOOT_CLOSED",
    "BANKFRAME_CLOSED",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
}) do
    ns:On(event, request)
end

for _, event in ipairs({
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED",
}) do
    ns:On(event, request, "player")
end

for _, event in ipairs({
    "EQUIP_BIND_CONFIRM",
    "EQUIP_BIND_TRADEABLE_CONFIRM",
    "EQUIP_BIND_REFUNDABLE_CONFIRM",
}) do
    ns:On(event, function() Engine:OnBindConfirm() end)
end
