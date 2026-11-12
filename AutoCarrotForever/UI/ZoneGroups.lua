local ADDON, ns = ...

local UI, API = ns.UI, ns.API

-- The "Zone groups" section of the main options page (DESIGN.md §8.1): every
-- group is a collapsible list of its zones. It is a plain frame embedded in
-- the page, so nothing here switches settings pages (which is blocked in
-- combat).

local ROW_H = 26
local GREY, GREEN = "|cff999999", "|cff40ff40"

local function zoneText(z)
    return z.name or ("map " .. tostring(z.mapID))
end

--------------------------------------------------------------------------------
-- Rows: one pooled frame type, configured as a group header or a zone line
--------------------------------------------------------------------------------

local function CreateRow(section, parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)

    row.toggle = CreateFrame("Button", nil, row)
    row.toggle:SetSize(16, 16)
    row.toggle:SetPoint("LEFT", 4, 0)
    row.toggle:SetScript("OnClick", function()
        section.expanded[row.key] = not section.expanded[row.key]
        section:Refresh()
    end)

    row.labelHit = CreateFrame("Button", nil, row)
    row.labelHit:SetPoint("LEFT", 26, 0)
    row.labelHit:SetPoint("RIGHT", row, "RIGHT", -270, 0)
    row.labelHit:SetHeight(ROW_H)
    row.label = row.labelHit:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.label:SetAllPoints()
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.labelHit:SetScript("OnClick", function()
        if row.kind == "group" then
            section.expanded[row.key] = not section.expanded[row.key]
            section:Refresh()
        end
    end)
    UI.SetTooltip(row.labelHit, function(tt)
        local E = ns.Engine
        if row.kind == "group" then
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
            tt:SetText("Stand in a zone where the item works and press Add current zone.", 1, 1, 1, 1, true)
        end
    end)

    row.button1 = UI.CreateButton(row, "", 150, function()
        if row.action1 then row.action1() end
    end)
    row.button1:SetPoint("RIGHT", row, "RIGHT", -96, 0)

    row.button2 = UI.CreateButton(row, "", 88, function()
        if row.action2 then row.action2() end
    end)
    row.button2:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    row.remove = UI.CreateButton(row, "X", 24, function()
        if row.kind == "zone" then ns.Engine:RemoveGroupZone(row.key, row.index) end
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

local function FillGroupRow(section, row, key, zone)
    local E = ns.Engine
    local zones = E:GroupZones(key)
    local here = zone and E:IsInGroup(key, zone)
    row.kind, row.key = "group", key
    row.toggle:Show()
    setToggle(row, section.expanded[key])
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

    row.button2:Show()
    if ns.ZONE_GROUP_DEFAULTS[key] then
        row.button2:SetText("Defaults")
        row.button2:SetEnabled(true)
        row.action2 = function() E:RestoreGroupDefaults(key) end
    else
        row.button2:SetText("Delete")
        row.button2:SetEnabled(#E:RulesUsingGroup(key) == 0)
        row.action2 = function() E:DeleteGroup(key) end
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
    row.label:SetText("No zones yet.")
    row.button1:Hide()
    row.button2:Hide()
    row.remove:Hide()
end

--------------------------------------------------------------------------------
-- Section
--------------------------------------------------------------------------------

local Section = {}

function Section:Refresh()
    if not self:IsVisible() then return end
    local E = ns.Engine
    local zone = API.GetCurrentZone()

    local inGroups = {}
    for _, key in ipairs(E:GroupKeys()) do
        if zone and E:IsInGroup(key, zone) then inGroups[#inGroups + 1] = E:GroupLabel(key) end
    end
    self.current:SetText("You are in: " .. (zone and ("|cffffffff" .. zone.name .. "|r") or "unknown") ..
        "   " .. GREY .. (#inGroups > 0 and ("(in " .. table.concat(inGroups, ", ") .. ")") or "(not in any group)") .. "|r")

    local n = 0
    local function nextRow()
        n = n + 1
        local row = self.rows[n]
        if not row then
            row = CreateRow(self, self.list)
            self.rows[n] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -(n - 1) * ROW_H)
        row:SetPoint("RIGHT", self.list, "RIGHT", 0, 0)
        row:Show()
        return row
    end
    for _, key in ipairs(E:GroupKeys()) do
        FillGroupRow(self, nextRow(), key, zone)
        if self.expanded[key] then
            local zones = E:GroupZones(key)
            if #zones == 0 then FillEmptyRow(nextRow(), key) end
            for i, z in ipairs(zones) do FillZoneRow(nextRow(), key, i, z, zone) end
        end
    end
    for i = n + 1, #self.rows do self.rows[i]:Hide() end
    self.list:SetHeight(math.max(1, n * ROW_H))

    local descHeight = self.desc:GetStringHeight()
    if not descHeight or descHeight < 1 then descHeight = 40 end
    local height = descHeight + 10 + 20 + 8 + n * ROW_H + 12 + 26
    self:SetHeight(height)
    if self.onResize then self.onResize(height) end
end

-- Builds the section inside `parent`. onResize(height) is called whenever its
-- height changes (groups expanded or collapsed, zones added or removed).
function UI.CreateZoneGroupsSection(parent, onResize)
    local section = CreateFrame("Frame", nil, parent)
    for k, v in pairs(Section) do section[k] = v end
    section.rows, section.expanded, section.onResize = {}, {}, onResize

    section.desc = section:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    section.desc:SetPoint("TOPLEFT", 0, 0)
    section.desc:SetPoint("RIGHT", section, "RIGHT", 0, 0)
    section.desc:SetJustifyH("LEFT")
    section.desc:SetText("Some Forever items only work in certain zones, such as The Desert Rose in Desert areas. " ..
        "Blizzard doesn't list which zones count, so stand in a zone where the bonus works " ..
        "(check with /ac speed while mounted) and add it here. Groups are shared by all your characters.")

    section.current = section:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    section.current:SetPoint("TOPLEFT", section.desc, "BOTTOMLEFT", 0, -10)
    section.current:SetPoint("RIGHT", section, "RIGHT", 0, 0)
    section.current:SetJustifyH("LEFT")
    section.current:SetHeight(20)

    section.list = CreateFrame("Frame", nil, section)
    section.list:SetPoint("TOPLEFT", section.current, "BOTTOMLEFT", 0, -8)
    section.list:SetPoint("RIGHT", section, "RIGHT", 0, 0)
    section.list:SetHeight(1)

    -- New group
    local label = section:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", section.list, "BOTTOMLEFT", 4, -16)
    label:SetText("New group:")
    local input = CreateFrame("EditBox", nil, section, "InputBoxTemplate")
    input:SetSize(150, 22)
    input:SetPoint("LEFT", label, "RIGHT", 12, 0)
    input:SetAutoFocus(false)
    local message = section:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    local function create()
        local key, err = ns.Engine:CreateGroup(input:GetText())
        if key then
            section.expanded[key] = true
            input:SetText("")
            input:ClearFocus()
            message:SetText(GREEN .. ns.Engine:GroupLabel(key) .. " created. Pick it under Where in the item editor.|r")
        else
            message:SetText("|cffff5050" .. err .. "|r")
        end
        section:Refresh()
    end
    input:SetScript("OnEnterPressed", create)
    input:SetScript("OnEscapePressed", input.ClearFocus)
    local createButton = UI.CreateButton(section, "Create", 80, create)
    createButton:SetPoint("LEFT", input, "RIGHT", 8, 0)
    UI.SetTooltip(createButton, "Type a kind of area, e.g. Snowy, to create \"Snowy areas\".")
    message:SetPoint("LEFT", createButton, "RIGHT", 12, 0)
    message:SetPoint("RIGHT", section, "RIGHT", 0, 0)
    message:SetJustifyH("LEFT")

    section:SetScript("OnShow", function(self)
        message:SetText("")
        self:Refresh()
    end)

    local function refresh() section:Refresh() end
    ns:On("AC_RULES", refresh)
    ns:On("ZONE_CHANGED_NEW_AREA", refresh)
    ns:On("ZONE_CHANGED", refresh)
    ns:On("ZONE_CHANGED_INDOORS", refresh)
    return section
end
