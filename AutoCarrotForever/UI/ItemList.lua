local ADDON, ns = ...

local UI, API, Planner = ns.UI, ns.API, ns.Planner

local WIDTH, HEIGHT = 800, 540
local ROW_H = 28
local CONTENT_W = 740

local editor          -- the window
local pending = {}    -- triggers/label carried over from a suggestion

local STATUS_COLOR = {
    worn = { 0.2, 1, 0.2 },
    planned = { 1, 0.82, 0 },
    failed = { 1, 0.25, 0.25 },
    disabled = { 0.4, 0.4, 0.4 },
    idle = { 0.6, 0.6, 0.6 },
}
local STATUS_TEXT = {
    worn = "Equipped by AutoCarrot right now.",
    planned = "Wanted now; waiting to swap (combat, casting, cursor or a window).",
    failed = "Could not be equipped after several tries. Edit the rule or use /ac restore.",
    disabled = "Disabled.",
    idle = "Not needed right now (its trigger is off or the item is not in your bags).",
}

local function edited(c)
    ns.Engine:RuleEdited(c.id)
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

local function CreateWindow()
    local ok, f = pcall(CreateFrame, "Frame", "AutoCarrotForeverEditor", UIParent, "BasicFrameTemplateWithInset")
    if not ok or not f then
        f = CreateFrame("Frame", "AutoCarrotForeverEditor", UIParent, "BackdropTemplate")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG") -- above the options panel when opened from it
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "AutoCarrotForeverEditor")

    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if not f.TitleText then title:SetPoint("TOP", 0, -6) end
    title:SetText("AutoCarrot Forever - Custom Items (shared by all your characters)")
    return f
end

--------------------------------------------------------------------------------
-- Add bar
--------------------------------------------------------------------------------

local function currentInput()
    return strtrim(editor.input:GetText() or "")
end

local function updateAddBar()
    local parsed = Planner.ParseItemString(currentInput())
    local hasEnchant = parsed and parsed.enchantID ~= 0
    editor.byEnchant:SetShown(hasEnchant)
    if not hasEnchant then editor.byEnchant:SetChecked(false) end
    editor.trigger:SetText("When: " .. UI.TriggerText(pending.triggers))
end

local function setMessage(text, isError)
    editor.message:SetText(text or "")
    if isError then
        editor.message:SetTextColor(1, 0.3, 0.3)
    else
        editor.message:SetTextColor(0.4, 1, 0.4)
    end
end

local function resetPending()
    pending = { triggers = { mounted = true } }
end

local function doAdd()
    local text = currentInput()
    if text == "" then
        setMessage("Drag an item onto the slot, shift-click a link, or type an item ID.", true)
        return
    end
    local rule, err = ns.Engine:AddCustomRule({
        input = text,
        byEnchant = editor.byEnchant:IsShown() and editor.byEnchant:GetChecked(),
        triggers = CopyTable(pending.triggers),
        zones = pending.zones and CopyTable(pending.zones) or nil,
        label = pending.label,
    })
    if not rule then
        setMessage(err, true)
        return
    end
    local note = ""
    for _, r in ipairs(ns.Engine.state.rules) do
        if r.source == "builtin" and r.overridden and Planner.MatchKey(r.match) == Planner.MatchKey(rule.match) then
            note = " It overrides the built-in " .. r.name .. "."
        end
    end
    setMessage("Added rule #" .. rule.id .. "." .. note .. UI.ZoneNote(rule.zones))
    editor.input:SetText("")
    editor.input:ClearFocus()
    resetPending()
    updateAddBar()
end

local function takeCursorItem()
    local kind, itemID, link = GetCursorInfo()
    if kind ~= "item" then return end
    editor.input:SetText(link or tostring(itemID))
    ClearCursor() -- the item drops back into its bag
    updateAddBar()
end

local function CreateAddBar(f)
    local drop = CreateFrame("Button", nil, f)
    drop:SetSize(52, 52)
    drop:SetPoint("TOPLEFT", 16, -34)
    local bg = drop:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    bg:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    drop:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local dropText = drop:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    dropText:SetPoint("CENTER")
    dropText:SetText("Drop\nitem")
    drop:SetScript("OnReceiveDrag", takeCursorItem)
    drop:SetScript("OnClick", takeCursorItem)
    UI.SetTooltip(drop, "Drag an item from your bags here.")

    local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", drop, "TOPRIGHT", 14, -2)
    label:SetText("Item link or ID (shift-click an item while this box has focus):")

    local input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    input:SetSize(300, 22)
    input:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 6, -4)
    input:SetAutoFocus(false)
    input:SetScript("OnEnterPressed", doAdd)
    input:SetScript("OnEscapePressed", input.ClearFocus)
    input:SetScript("OnTextChanged", updateAddBar)
    input:SetScript("OnReceiveDrag", takeCursorItem)
    input:HookScript("OnMouseDown", takeCursorItem)
    f.input = input

    local trigger = UI.CreateButton(f, "When: Mounted", 190, nil)
    UI.ClampButtonText(trigger)
    UI.SetTooltip(trigger, function(tt)
        tt:SetText("When the new item is worn", 1, 1, 1)
        tt:AddLine(UI.TriggerText(pending.triggers), 1, 0.82, 0, true)
    end)
    trigger:SetPoint("LEFT", input, "RIGHT", 10, 0)
    trigger:SetScript("OnClick", function(self)
        local entries = { { text = "Active when any of these is true", isTitle = true } }
        for _, key in ipairs(ns.TRIGGER_ORDER) do
            entries[#entries + 1] = {
                text = ns.TRIGGERS[key].menu or ns.TRIGGERS[key].label,
                checked = function() return pending.triggers[key] == true end,
                func = function()
                    pending.triggers[key] = (not pending.triggers[key]) or nil
                    updateAddBar()
                end,
            }
        end
        UI.ShowMenu(self, entries)
    end)
    f.trigger = trigger

    local add = UI.CreateButton(f, "Add", 80, doAdd)
    add:SetPoint("LEFT", trigger, "RIGHT", 8, 0)

    local byEnchant = UI.CreateCheck(f, "Match the enchant (any item carrying it), not this item",
        "Use this for speed enchants: the rule then matches any item carrying that enchant, whatever the item is called.")
    byEnchant:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -6, -2)
    byEnchant:Hide()
    f.byEnchant = byEnchant

    local message = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    message:SetPoint("TOPLEFT", drop, "BOTTOMLEFT", 0, -28)
    message:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    message:SetJustifyH("LEFT")
    f.message = message
end

--------------------------------------------------------------------------------
-- Scroll lists (plain ScrollFrame: works on every client version)
--------------------------------------------------------------------------------

local function CreateList(f, top, bottom)
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, top)
    scroll:SetPoint("BOTTOMRIGHT", -34, bottom)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(CONTENT_W, 1)
    scroll:SetScrollChild(child)
    scroll.child = child
    scroll.rows = {}
    local empty = child:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    empty:SetPoint("TOPLEFT", 8, -8)
    scroll.empty = empty
    return scroll
end

local function header(f, text, anchorY)
    local h = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h:SetPoint("TOPLEFT", 18, anchorY)
    h:SetText(text)
    return h
end

--------------------------------------------------------------------------------
-- Rule rows
--------------------------------------------------------------------------------

local function ruleSlots(c)
    if c.kind == "set" then return {} end
    local slots = ns.EQUIP_LOC_SLOTS[c.equipLoc or ""]
    if not slots and c.match.itemID then
        slots = ns.EQUIP_LOC_SLOTS[select(4, API.GetItemInfoInstant(c.match.itemID)) or ""]
    end
    return slots or {}
end

local function slotText(c)
    if c.kind == "set" then return "Set" end
    if c.slot == "auto" then
        local slots = ruleSlots(c)
        if #slots == 1 then return ns.SLOT_NAMES[slots[1]] or "Auto" end
        return "Auto"
    end
    return ns.SLOT_NAMES[c.slot] or ("Slot " .. tostring(c.slot))
end

local function ruleName(c)
    if c.kind == "set" then
        local names = {}
        for _, p in ipairs(c.pieces) do
            local name = API.GetItemInfo(p.itemID)
            if not name then
                API.LoadItem(p.itemID, function() if editor and editor:IsShown() then UI.RefreshEditor() end end)
            end
            names[#names + 1] = name or ("#" .. p.itemID)
        end
        return "|cff1eff00Set|r " .. c.need .. " of: " .. table.concat(names, ", "), nil
    end
    if c.match.enchantID then
        -- Labels come from the tooltip line, e.g. "Enchanted: Minor Speed".
        return "Enchant: " .. ns.Engine:EnchantLabel(c), c.link
    end
    local name, link, quality = API.GetItemInfo(c.match.itemID)
    if not name then
        API.LoadItem(c.match.itemID, function() if editor and editor:IsShown() then UI.RefreshEditor() end end)
        return "Item #" .. c.match.itemID, nil
    end
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    return (color and color.hex or "") .. name .. "|r", link
end

local function confirmRemove(c, label)
    StaticPopupDialogs["AUTOCARROTFOREVER_REMOVE"] = StaticPopupDialogs["AUTOCARROTFOREVER_REMOVE"] or {
        text = "Remove the AutoCarrot rule for %s?",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function(_, data) ns.Engine:RemoveCustomRule(data) end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("AUTOCARROTFOREVER_REMOVE", label, nil, c.id)
end

local function CreateRuleRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(CONTENT_W, ROW_H)

    row.status = row:CreateTexture(nil, "ARTWORK")
    row.status:SetSize(8, 8)
    row.status:SetPoint("LEFT", 2, 0)
    row.status:SetColorTexture(1, 1, 1)
    row.statusHit = CreateFrame("Frame", nil, row)
    row.statusHit:SetSize(14, ROW_H)
    row.statusHit:SetPoint("LEFT", 0, 0)
    UI.SetTooltip(row.statusHit, function(tt) tt:SetText(STATUS_TEXT[row.statusKey] or "", 1, 1, 1, 1, true) end)

    row.enable = UI.CreateCheck(row, nil, "Enable or disable this rule.", function(v)
        row.entry.enabled = v
        edited(row.entry)
    end)
    row.enable:SetPoint("LEFT", 12, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 38, 0)

    row.nameHit = CreateFrame("Frame", nil, row)
    row.nameHit:SetSize(150, ROW_H)
    row.nameHit:SetPoint("LEFT", 62, 0)
    row.name = row.nameHit:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.name:SetAllPoints()
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    UI.SetTooltip(row.nameHit, function(tt)
        local c = row.entry
        if c.kind == "set" then
            tt:SetText("Set rule: wear " .. c.need .. " of these together", 1, 1, 1)
            for _, p in ipairs(c.pieces) do
                local name = API.GetItemInfo(p.itemID)
                tt:AddLine((name or ("item #" .. p.itemID)), 0.8, 0.8, 0.8)
            end
            tt:AddLine("All needed pieces go on together or not at all.", 0.6, 0.8, 1, true)
        elseif row.link then
            tt:SetHyperlink(row.link)
        elseif c.match.itemID then
            tt:SetItemByID(c.match.itemID)
        else
            tt:SetText("Matches any item with enchant #" .. c.match.enchantID, 1, 1, 1)
        end
        if row.unusable then
            tt:AddLine("This character can't use it (" .. row.unusable .. "); it is skipped here.", 1, 0.3, 0.3, true)
        end
        tt:AddLine("Rule #" .. c.id, 0.6, 0.6, 0.6)
    end)

    row.slot = UI.CreateButton(row, "Auto", 90, nil)
    UI.ClampButtonText(row.slot)
    row.slot:SetScript("OnClick", function(self)
        local c = row.entry
        local slots = ruleSlots(c)
        local entries = { { text = "Slot", isTitle = true } }
        entries[#entries + 1] = {
            text = "Auto", radio = true,
            checked = function() return c.slot == "auto" end,
            func = function() c.slot = "auto"; edited(c) end,
        }
        for _, s in ipairs(slots) do
            entries[#entries + 1] = {
                text = ns.SLOT_NAMES[s] or tostring(s), radio = true,
                checked = function() return c.slot == s end,
                func = function() c.slot = s; edited(c) end,
            }
        end
        UI.ShowMenu(self, entries)
    end)
    row.slot:SetPoint("LEFT", 216, 0)

    row.trigger = UI.CreateButton(row, "", 140, nil)
    UI.ClampButtonText(row.trigger)
    row.trigger:SetScript("OnClick", function(self)
        local c = row.entry
        local entries = { { text = "Active when any of these is true", isTitle = true } }
        for _, key in ipairs(ns.TRIGGER_ORDER) do
            entries[#entries + 1] = {
                text = ns.TRIGGERS[key].menu or ns.TRIGGERS[key].label,
                checked = function() return c.triggers[key] == true end,
                func = function()
                    c.triggers[key] = (not c.triggers[key]) or nil
                    edited(c)
                end,
            }
        end
        UI.ShowMenu(self, entries)
    end)
    row.trigger:SetPoint("LEFT", 310, 0)
    UI.SetTooltip(row.trigger, function(tt)
        tt:SetText("When this item is worn", 1, 1, 1)
        tt:AddLine(UI.TriggerText(row.entry.triggers), 1, 0.82, 0, true)
        tt:AddLine("Only while AutoCarrot is turned on. Turning it off puts your normal gear back.", 0.8, 0.8, 0.8, true)
        if row.entry.triggers.always then
            tt:AddLine(ns.TRIGGERS.always.warning, 1, 0.82, 0, true)
        end
        if row.isWeapon then
            tt:AddLine("Weapons: the real weapon goes back on as soon as combat starts (costs a global cooldown), and the speed weapon returns after combat.", 1, 0.82, 0, true)
        end
    end)

    row.zones = UI.CreateButton(row, "", 120, function(self) UI.ShowZoneMenu(self, row.entry) end)
    UI.ClampButtonText(row.zones)
    row.zones:SetPoint("LEFT", 454, 0)
    UI.SetTooltip(row.zones, function(tt)
        tt:SetText("Where this item works", 1, 1, 1)
        tt:AddLine(ns.Engine:ZoneLabel(row.entry.zones), 1, 0.82, 0, true)
        tt:AddLine("Some Forever items only work in certain zones, such as 'in Desert areas'. Zone groups like Desert areas are shared by every rule and character.", nil, nil, nil, true)
        tt:AddLine("Current zone: " .. ((ns.API.GetCurrentZone() or {}).name or "unknown"), 0.6, 0.8, 1)
    end)

    row.priority = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.priority:SetSize(30, 20)
    row.priority:SetPoint("LEFT", 584, 0)
    row.priority:SetAutoFocus(false)
    row.priority:SetNumeric(true)
    row.priority:SetMaxLetters(3)
    local function commitPriority(self)
        local v = math.min(200, math.max(0, tonumber(self:GetText()) or 50))
        self:SetText(tostring(v))
        self:ClearFocus()
        if row.entry.priority ~= v then
            row.entry.priority = v
            edited(row.entry)
        end
    end
    row.priority:SetScript("OnEnterPressed", commitPriority)
    row.priority:SetScript("OnEditFocusLost", commitPriority)
    UI.SetTooltip(row.priority, "Priority 0-200. When two rules want the same slot, the higher one wins. Built-ins use 100-120.")

    row.noInstance = UI.CreateCheck(row, nil, "Outside instances only: never use this rule inside dungeons, raids, battlegrounds or arenas.",
        function(v) row.entry.noInstance = v; edited(row.entry) end)
    row.noInstance:SetPoint("LEFT", 618, 0)

    row.bind = UI.CreateCheck(row, nil, "Allow binding: let AutoCarrot equip a Bind on Equip item that isn't soulbound yet (the game asks you to confirm once). " ..
        "Not needed for items that never bind, such as most white items: those are always swapped.",
        function(v) row.entry.allowBind = v; edited(row.entry) end)
    row.bind:SetPoint("LEFT", 642, 0)

    row.up = UI.CreateButton(row, "^", 22, function() ns.Engine:MoveCustomRule(row.entry.id, -1) end)
    row.up:SetPoint("LEFT", 668, 0)
    UI.SetTooltip(row.up, "Move up (breaks priority ties).")
    row.down = UI.CreateButton(row, "v", 22, function() ns.Engine:MoveCustomRule(row.entry.id, 1) end)
    row.down:SetPoint("LEFT", 690, 0)
    UI.SetTooltip(row.down, "Move down.")

    row.remove = UI.CreateButton(row, "X", 24, function()
        confirmRemove(row.entry, row.plainName or ("rule #" .. row.entry.id))
    end)
    row.remove:SetPoint("LEFT", 714, 0)
    UI.SetTooltip(row.remove, "Remove this rule.")

    return row
end

local function FillRuleRow(row, c)
    row.entry = c
    local name, link = ruleName(c)
    row.link = link or c.link
    row.plainName = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")

    local iconID
    if c.kind == "set" then
        iconID = c.pieces[1] and c.pieces[1].itemID
    else
        iconID = c.match.itemID or (c.link and Planner.ParseItemString(c.link) or {}).itemID
    end
    row.icon:SetTexture(iconID and API.GetItemIcon(iconID) or 136244)

    row.isWeapon = false
    for _, slot in ipairs(ruleSlots(c)) do
        if ns.WEAPON_SLOTS[slot] then row.isWeapon = true end
    end

    row.unusable = nil
    if c.kind ~= "set" and c.match.itemID then
        local ok, why = API.CanUseItem(c.match.itemID)
        if not ok then row.unusable = why == "level" and "level too low" or "class or armor type" end
    end
    if row.unusable then
        row.name:SetText("|cff808080" .. row.plainName .. "|r")
        row.icon:SetDesaturated(true)
    else
        row.name:SetText(name)
        row.icon:SetDesaturated(false)
    end

    row.enable:SetChecked(c.enabled ~= false)
    row.slot:SetText(slotText(c))
    row.slot:SetEnabled(#ruleSlots(c) > 1)
    local warn = c.triggers.always and " |TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:14|t" or ""
    row.trigger:SetText(UI.TriggerText(c.triggers) .. warn)
    row.zones:SetText(ns.Engine:ZoneLabel(c.zones))
    if not row.priority:HasFocus() then row.priority:SetText(tostring(c.priority or 50)) end
    row.noInstance:SetChecked(c.noInstance)
    row.bind:SetChecked(c.allowBind)

    row.statusKey = ns.Engine:RuleStatus("custom:" .. c.id)
    local color = STATUS_COLOR[row.statusKey] or STATUS_COLOR.idle
    row.status:SetColorTexture(color[1], color[2], color[3])
end

--------------------------------------------------------------------------------
-- Suggestion rows
--------------------------------------------------------------------------------

local function CreateSuggestionRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(CONTENT_W, ROW_H)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 4, 0)

    row.nameHit = CreateFrame("Frame", nil, row)
    row.nameHit:SetSize(220, ROW_H)
    row.nameHit:SetPoint("LEFT", 28, 0)
    row.name = row.nameHit:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.name:SetAllPoints()
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    UI.SetTooltip(row.nameHit, function(tt)
        if row.s.link then tt:SetHyperlink(row.s.link) else tt:SetItemByID(row.s.itemID) end
    end)

    -- Laid out from the right: [Ignore] at the edge, [Add ...] sized to its
    -- text left of it, and the quoted tooltip text takes what is left (and
    -- truncates), so a long button label can never overflow.
    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.text:SetHeight(ROW_H)
    row.text:SetPoint("LEFT", 254, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row.add = UI.CreateButton(row, "Add", 150, function()
        local s = row.s
        if s.isSet then
            local rule, err = ns.Engine:AddSetRule({
                pieces = s.pieces, need = s.need,
                triggers = { [s.trigger] = true },
                zones = s.zones and CopyTable(s.zones) or nil,
            })
            setMessage(rule and ("Added set rule #" .. rule.id .. "." .. UI.ZoneNote(rule.zones)) or err, not rule)
            return
        end
        local rule, err = ns.Engine:AddCustomRule({
            input = s.link or s.itemID,
            byEnchant = s.byEnchant,
            triggers = { [s.trigger] = true },
            zones = s.zones and CopyTable(s.zones) or nil,
            label = s.byEnchant and s.text or nil,
        })
        setMessage(rule and ("Added rule #" .. rule.id .. "." .. UI.ZoneNote(rule.zones)) or err, not rule)
    end)

    row.ignore = UI.CreateButton(row, "Ignore", 64, function()
        ns.Discovery:Ignore(row.s.key)
    end)
    row.ignore:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.add:SetPoint("RIGHT", row.ignore, "LEFT", -6, 0)
    row.text:SetPoint("RIGHT", row.add, "LEFT", -8, 0)
    UI.SetTooltip(row.ignore, "Never suggest this again (on any character).")
    return row
end

local function FillSuggestionRow(row, s)
    row.s = s
    row.icon:SetTexture(API.GetItemIcon(s.itemID))
    local prefix = s.byEnchant and "Enchant on " or (s.isSet and "Set with " or "")
    row.name:SetText(prefix .. (s.link or ("Item #" .. s.itemID)))
    row.text:SetText('"' .. s.text .. '"')
    if s.isSet then
        row.add:SetText(s.pieces and ("Add set (" .. s.need .. " pieces)") or "Use /ac addset")
        row.add:SetEnabled(s.pieces ~= nil)
    else
        row.add:SetText("Add as " .. ns.TRIGGERS[s.trigger].label)
        row.add:SetEnabled(true)
    end
    -- Fit the button to its label (UIPanelButtonTemplate needs ~24 px of padding).
    local fs = row.add:GetFontString()
    local textWidth = fs and fs:GetStringWidth() or 0
    row.add:SetWidth(math.max(110, math.ceil(textWidth) + 28))
end

--------------------------------------------------------------------------------
-- Zones menu (DESIGN.md §8.2)
--------------------------------------------------------------------------------

-- Warns when a rule is limited to a zone group that has no zones yet.
function UI.ZoneNote(zones)
    for _, z in ipairs(zones or {}) do
        if z.group and #ns.Engine:GroupZones(z.group) == 0 then
            local label = ns.Engine:GroupLabel(z.group)
            return " " .. label .. " has no zones yet: stand in one and use Where > Add current zone to " .. label .. "."
        end
    end
    return ""
end

local function hasGroup(c, key)
    for i, z in ipairs(c.zones or {}) do
        if z.group == key then return i end
    end
end

function UI.ShowZoneMenu(owner, c)
    local E = ns.Engine
    local zone = ns.API.GetCurrentZone()
    local here = zone and zone.name or "unknown zone"
    local entries = { { text = "Where this item works", isTitle = true } }
    entries[#entries + 1] = {
        text = "Any zone", radio = true,
        checked = function() return not c.zones or #c.zones == 0 end,
        func = function() c.zones = nil; edited(c) end,
    }
    for _, key in ipairs(E:GroupKeys()) do
        local names = {}
        for _, z in ipairs(E:GroupZones(key)) do names[#names + 1] = z.name or ("map " .. tostring(z.mapID)) end
        entries[#entries + 1] = {
            text = E:GroupLabel(key) .. " (" .. (#names > 0 and table.concat(names, ", ") or "no zones yet") .. ")",
            checked = function() return hasGroup(c, key) ~= nil end,
            func = function()
                local i = hasGroup(c, key)
                c.zones = c.zones or {}
                if i then table.remove(c.zones, i) else table.insert(c.zones, { group = key }) end
                edited(c)
            end,
        }
    end
    for i, z in ipairs(c.zones or {}) do
        if not z.group then
            entries[#entries + 1] = {
                text = "Zone: " .. (z.name or ("map " .. tostring(z.mapID))),
                checked = function() return true end,
                func = function() table.remove(c.zones, i); edited(c) end,
            }
        end
    end
    if zone then
        local explicit = {}
        for _, z in ipairs(c.zones or {}) do if not z.group then explicit[#explicit + 1] = z end end
        if not E:FindZone(explicit, zone) then
            entries[#entries + 1] = {
                text = "Add current zone (" .. here .. ")",
                func = function()
                    c.zones = c.zones or {}
                    table.insert(c.zones, { name = zone.name, mapID = zone.mapID })
                    edited(c)
                end,
            }
        end
        for _, z in ipairs(c.zones or {}) do
            if z.group then
                local key = z.group
                local inGroup = E:IsInGroup(key, zone)
                entries[#entries + 1] = {
                    text = (inGroup and "Remove " or "Add ") .. here .. (inGroup and " from " or " to ") .. E:GroupLabel(key),
                    func = function()
                        E:ToggleCurrentZone(E:GroupZones(key), not inGroup)
                        UI.RefreshEditor()
                    end,
                }
            end
        end
    end
    UI.ShowMenu(owner, entries)
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

local function layoutList(scroll, items, create, fill, emptyText)
    for i, item in ipairs(items) do
        local row = scroll.rows[i]
        if not row then
            row = create(scroll.child)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            scroll.rows[i] = row
        end
        fill(row, item)
        row:Show()
    end
    for i = #items + 1, #scroll.rows do scroll.rows[i]:Hide() end
    scroll.child:SetHeight(math.max(1, #items * ROW_H))
    scroll.empty:SetText(#items == 0 and emptyText or "")
end

function UI.RefreshEditor()
    if not editor or not editor:IsShown() then return end
    layoutList(editor.rules, ns.gdb.custom, CreateRuleRow, FillRuleRow,
        "No custom items yet. Add one above, or accept a suggestion below.")
    layoutList(editor.suggestions, ns.Discovery:List(), CreateSuggestionRow, FillSuggestionRow,
        "No suggestions. Speed items found in your bags will show up here.")
end

local function Build()
    editor = CreateWindow()
    CreateAddBar(editor)

    header(editor, "Rules", -136)
    local cols = {
        { "Item", 82 }, { "Slot", 250 }, { "When", 364 }, { "Where", 498 }, { "Pri", 600 },
        { "Out", 630 }, { "Bind", 654 },
    }
    for _, c in ipairs(cols) do
        local t = editor:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        t:SetPoint("TOPLEFT", c[2], -140)
        t:SetText(c[1])
    end
    editor.rules = CreateList(editor, -156, 190)

    header(editor, "Suggestions from your bags", -(HEIGHT - 168))
    local scan = UI.CreateButton(editor, "Scan now", 90, function() ns.Discovery:Scan(true) end)
    scan:SetPoint("TOPRIGHT", -40, -(HEIGHT - 164))
    editor.suggestions = CreateList(editor, -(HEIGHT - 146), 14)

    editor:SetScript("OnShow", UI.RefreshEditor)
    resetPending()
    updateAddBar()
end

-- prefill: a Discovery suggestion (from the chat [Add] link) or nil.
function UI.OpenEditor(prefill)
    if not editor then Build() end
    editor:Show()
    editor:Raise()
    if prefill and prefill.isSet then
        setMessage("Set bonus found: use the Add set button in Suggestions below.")
    elseif prefill then
        resetPending()
        pending.triggers = { [prefill.trigger] = true }
        pending.label = prefill.byEnchant and prefill.text or nil
        pending.zones = prefill.zones
        editor.input:SetText(prefill.link or tostring(prefill.itemID))
        updateAddBar()
        editor.byEnchant:SetChecked(prefill.byEnchant and true or false)
        local where = prefill.zones and (" Only in: " .. ns.Engine:ZoneLabel(prefill.zones) .. ".") or ""
        setMessage("Check the suggested setting, then press Add." .. where)
    end
    UI.RefreshEditor()
end

function UI.ToggleEditor()
    if editor and editor:IsShown() then editor:Hide() else UI.OpenEditor() end
end

-- Shift-clicking an item while the input box has focus puts its link there.
local function insertLink(link)
    if editor and editor:IsShown() and editor.input:HasFocus() and type(link) == "string" then
        editor.input:SetText(link)
        updateAddBar()
    end
end

ns:On("AC_LOADED", function()
    if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", insertLink) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", insertLink) end
end)

ns:On("AC_RULES", function() UI.RefreshEditor() end)
ns:On("AC_STATUS", function() UI.RefreshEditor() end)
ns:On("AC_SUGGESTIONS", function() UI.RefreshEditor() end)
