local ADDON, ns = ...

local UI, API = ns.UI, ns.API

-- Options > AddOns > AutoCarrot Forever > Zone Groups (DESIGN.md §8.1).
-- A plain canvas page: every group is a collapsible list of its zones.

local ROW_H = 26
local panel, subcategory
local expanded = {}   -- [group key] = true while open (per session)
local rows = {}

local GREY, GREEN = "|cff999999", "|cff40ff40"

local function zoneText(z)
    return z.name or ("map " .. tostring(z.mapID))
end

--------------------------------------------------------------------------------
-- Rows: one pooled frame type, configured as a group header or a zone line
--------------------------------------------------------------------------------

local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)

    row.toggle = CreateFrame("Button", nil, row)
    row.toggle:SetSize(16, 16)
    row.toggle:SetPoint("LEFT", 4, 0)
    row.toggle:SetScript("OnClick", function()
        expanded[row.key] = not expanded[row.key]
        UI.RefreshZoneGroups()
    end)

    row.labelHit = CreateFrame("Button", nil, row)
    row.labelHit:SetPoint("LEFT", 26, 0)
    row.labelHit:SetPoint("RIGHT", row, "RIGHT", -300, 0)
    row.labelHit:SetHeight(ROW_H)
    row.label = row.labelHit:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.label:SetAllPoints()
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.labelHit:SetScript("OnClick", function()
        if row.kind == "group" then
            expanded[row.key] = not expanded[row.key]
            UI.RefreshZoneGroups()
        end
    end)
    UI.SetTooltip(row.labelHit, function(tt)
        if row.kind == "group" then
            local E = ns.Engine
            tt:SetText(E:GroupLabel(row.key), 1, 1, 1)
            local zones = E:GroupZones(row.key)
            if #zones == 0 then
                tt:AddLine("No zones yet.", 1, 0.82, 0)
            else
                for _, z in ipairs(zones) do tt:AddLine(zoneText(z), 0.9, 0.9, 0.9) end
            end
            local used = E:RulesUsingGroup(row.key)
            tt:AddLine(" ")
            tt:AddLine(#used > 0 and ("Used by: " .. table.concat(used, ", ")) or "Not used by any rule yet.", 0.6, 0.8, 1, true)
            tt:AddLine("Click to show or hide the zone list.", 0.6, 0.6, 0.6)
        elseif row.kind == "zone" then
            tt:SetText(zoneText(row.zone), 1, 1, 1)
            if row.zone.mapID then
                tt:AddLine("Map ID " .. row.zone.mapID, 0.6, 0.6, 0.6)
            else
                tt:AddLine("Matched by name. Its map ID is recorded the next time you add it while standing in it.", 0.6, 0.6, 0.6, true)
            end
        else
            return
        end
    end)

    row.button1 = UI.CreateButton(row, "", 150, function()
        if row.action1 then row.action1() end
    end)
    row.button1:SetPoint("RIGHT", row, "RIGHT", -110, 0)

    row.button2 = UI.CreateButton(row, "", 100, function()
        if row.action2 then row.action2() end
    end)
    row.button2:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    row.remove = UI.CreateButton(row, "X", 24, function()
        if row.kind == "zone" then
            ns.Engine:RemoveGroupZone(row.key, row.index)
        end
    end)
    row.remove:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    UI.SetTooltip(row.remove, "Remove this zone from the group.")

    return row
end

local function setToggle(row, open)
    local state = open and "Minus" or "Plus"
    row.toggle:SetNormalTexture("Interface\\Buttons\\UI-" .. state .. "Button-Up")
    row.toggle:SetPushedTexture("Interface\\Buttons\\UI-" .. state .. "Button-Down")
    row.toggle:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
end

local function FillGroupRow(row, key, zone)
    local E = ns.Engine
    local zones = E:GroupZones(key)
    local here = zone and E:IsInGroup(key, zone)
    row.kind, row.key = "group", key
    row.toggle:Show()
    setToggle(row, expanded[key])
    row.labelHit:SetPoint("LEFT", 26, 0)
    row.label:SetFontObject("GameFontNormal")
    row.label:SetText(E:GroupLabel(key) .. "  " .. GREY .. "(" .. #zones .. (#zones == 1 and " zone" or " zones") .. ")|r" ..
        (here and ("  " .. GREEN .. "you are here|r") or ""))

    row.button1:Show()
    row.button1:SetEnabled(zone ~= nil)
    if here then
        row.button1:SetText("Remove current zone")
        row.action1 = function() E:ToggleCurrentZone(zones, false) end
    else
        row.button1:SetText("Add current zone")
        row.action1 = function() E:ToggleCurrentZone(zones, true) end
    end

    row.action2 = nil
    if ns.ZONE_GROUP_DEFAULTS[key] then
        row.button2:SetText("Defaults")
        row.button2:SetEnabled(true)
        row.action2 = function() E:RestoreGroupDefaults(key) end
        row.button2:Show()
    else
        local inUse = #E:RulesUsingGroup(key) > 0
        row.button2:SetText("Delete")
        row.button2:SetEnabled(not inUse)
        row.action2 = function() E:DeleteGroup(key) end
        row.button2:Show()
    end
    row.remove:Hide()
end

local function FillZoneRow(row, key, index, z, zone)
    row.kind, row.key, row.index, row.zone = "zone", key, index, z
    row.toggle:Hide()
    row.labelHit:SetPoint("LEFT", 44, 0)
    row.label:SetFontObject("GameFontHighlight")
    local here = zone and ns.Planner.ZoneMatches({ z }, zone, nil)
    row.label:SetText(zoneText(z) ..
        (z.mapID and (GREY .. "  map " .. z.mapID .. "|r") or "") ..
        (here and ("  " .. GREEN .. "you are here|r") or ""))
    row.button1:Hide()
    row.button2:Hide()
    row.remove:Show()
end

local function FillEmptyRow(row, key)
    row.kind, row.key = "empty", key
    row.toggle:Hide()
    row.labelHit:SetPoint("LEFT", 44, 0)
    row.label:SetFontObject("GameFontDisable")
    row.label:SetText("No zones yet. Stand in one and press Add current zone.")
    row.button1:Hide()
    row.button2:Hide()
    row.remove:Hide()
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

function UI.RefreshZoneGroups()
    if not panel or not panel:IsVisible() then return end
    local E = ns.Engine
    local zone = API.GetCurrentZone()

    local inGroups = {}
    for _, key in ipairs(E:GroupKeys()) do
        if zone and E:IsInGroup(key, zone) then inGroups[#inGroups + 1] = E:GroupLabel(key) end
    end
    panel.current:SetText("You are in: " .. (zone and ("|cffffffff" .. zone.name .. "|r") or "unknown") ..
        "   " .. GREY .. (#inGroups > 0 and ("(in " .. table.concat(inGroups, ", ") .. ")") or "(not in any group)") .. "|r")

    local n = 0
    local function nextRow()
        n = n + 1
        local row = rows[n]
        if not row then
            row = CreateRow(panel.child)
            rows[n] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(n - 1) * ROW_H)
        row:SetPoint("RIGHT", panel.child, "RIGHT", 0, 0)
        row:Show()
        return row
    end

    for _, key in ipairs(E:GroupKeys()) do
        FillGroupRow(nextRow(), key, zone)
        if expanded[key] then
            local zones = E:GroupZones(key)
            if #zones == 0 then
                FillEmptyRow(nextRow(), key)
            end
            for i, z in ipairs(zones) do
                FillZoneRow(nextRow(), key, i, z, zone)
            end
        end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    panel.child:SetHeight(math.max(1, n * ROW_H))
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

local function Build()
    panel = CreateFrame("Frame")

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Zone Groups")

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("Some Forever items only work in certain zones, such as The Desert Rose in Desert areas. " ..
        "Blizzard doesn't list which zones count, so stand in a zone where the bonus works " ..
        "(check with /ac speed while mounted) and add it here. Groups are shared by all your characters.")

    panel.current = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.current:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)
    panel.current:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    panel.current:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel.current, "BOTTOMLEFT", -4, -10)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 52)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnSizeChanged", function(self, width) child:SetWidth(width) end)
    panel.child = child

    -- New group
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", 16, 22)
    label:SetText("New group:")
    local input = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    input:SetSize(160, 22)
    input:SetPoint("LEFT", label, "RIGHT", 12, 0)
    input:SetAutoFocus(false)
    local message = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    local function create()
        local key, err = ns.Engine:CreateGroup(input:GetText())
        if key then
            expanded[key] = true
            input:SetText("")
            input:ClearFocus()
            message:SetText(GREEN .. ns.Engine:GroupLabel(key) .. " created. Pick it under Where in the item editor.|r")
        else
            message:SetText("|cffff5050" .. err .. "|r")
        end
        UI.RefreshZoneGroups()
    end
    input:SetScript("OnEnterPressed", create)
    input:SetScript("OnEscapePressed", input.ClearFocus)
    local createButton = UI.CreateButton(panel, "Create", 80, create)
    createButton:SetPoint("LEFT", input, "RIGHT", 8, 0)
    UI.SetTooltip(createButton, "Type a kind of area, e.g. Snowy, to create \"Snowy areas\".")
    message:SetPoint("LEFT", createButton, "RIGHT", 12, 0)
    message:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    message:SetJustifyH("LEFT")

    panel:SetScript("OnShow", function()
        message:SetText("")
        child:SetWidth(scroll:GetWidth())
        UI.RefreshZoneGroups()
    end)
    return panel
end

function UI.OpenZoneGroups()
    if subcategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(subcategory:GetID())
    else
        ns.Print("The options panel is not available on this client; use /ac zone.")
    end
end

ns:On("AC_LOADED", function()
    local category = UI.settingsCategory
    if not (category and Settings and Settings.RegisterCanvasLayoutSubcategory) then return end
    local ok, err = pcall(function()
        subcategory = Settings.RegisterCanvasLayoutSubcategory(category, Build(), "Zone Groups")
    end)
    if not ok then ns.Debug("Zone Groups page: " .. tostring(err)) end
end)

local function refresh() UI.RefreshZoneGroups() end
ns:On("AC_RULES", refresh)
ns:On("ZONE_CHANGED_NEW_AREA", refresh)
ns:On("ZONE_CHANGED", refresh)
ns:On("ZONE_CHANGED_INDOORS", refresh)
