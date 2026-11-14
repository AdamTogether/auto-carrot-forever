local ADDON, ns = ...

local UI = ns.UI
local TITLE = "AutoCarrot Forever"

-- Options > AddOns > AutoCarrot Forever (DESIGN.md §8.1).
--
-- A canvas page built from plain widgets rather than the Settings list
-- (vertical layout): the list could not hold the collapsible zone-group lists,
-- its button rows showed empty hover boxes on Forever, and switching to a
-- separate page from a button is blocked in combat. Everything, including the
-- zone groups, lives on this one page.

local LABEL_X, CONTROL_X = 20, 300
local ROW_H = 30

local category
local refreshers = {}   -- functions that re-read db into the controls

local function changed()
    ns.Engine:OnSettingsChanged()
    UI.UpdateButtons()
end

--------------------------------------------------------------------------------
-- Page builder: controls are stacked top to bottom at a running y offset
--------------------------------------------------------------------------------

local Page = {}
Page.__index = Page

local function NewPage(content)
    return setmetatable({ content = content, y = 8 }, Page)
end

function Page:Label(text, tooltip)
    local hit = CreateFrame("Frame", nil, self.content)
    hit:SetPoint("TOPLEFT", LABEL_X, -self.y)
    hit:SetSize(CONTROL_X - LABEL_X - 10, ROW_H)
    local fs = hit:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetAllPoints()
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    if tooltip then UI.SetTooltip(hit, tooltip) end
    return hit
end

function Page:Header(text)
    self.y = self.y + 10
    local fs = self.content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", LABEL_X - 8, -self.y)
    fs:SetText(text)
    local line = self.content:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", LABEL_X - 8, -(self.y + 22))
    line:SetPoint("RIGHT", self.content, "RIGHT", -16, 0)
    self.y = self.y + 32
end

function Page:Checkbox(text, tooltip, get, set)
    self:Label(text, tooltip)
    local cb = UI.CreateCheck(self.content, nil, tooltip, function(v)
        set(v)
        changed()
    end)
    cb:SetPoint("TOPLEFT", CONTROL_X, -(self.y + 3))
    refreshers[#refreshers + 1] = function() cb:SetChecked(get() and true or false) end
    self.y = self.y + ROW_H
    return cb
end

-- Number with < value > buttons (no slider template: those differ by version).
function Page:Stepper(text, tooltip, min, max, step, fmt, get, set)
    self:Label(text, tooltip)
    local value = self.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    local function show() value:SetText(string.format(fmt, get())) end
    local function bump(delta)
        local v = math.min(max, math.max(min, (tonumber(get()) or min) + delta))
        v = math.floor(v / step + 0.5) * step
        set(v)
        show()
        changed()
    end
    local less = UI.CreateButton(self.content, "<", 26, function() bump(-step) end)
    less:SetPoint("TOPLEFT", CONTROL_X, -(self.y + 4))
    value:SetPoint("LEFT", less, "RIGHT", 6, 0)
    value:SetWidth(54)
    local more = UI.CreateButton(self.content, ">", 26, function() bump(step) end)
    more:SetPoint("LEFT", value, "RIGHT", 6, 0)
    if tooltip then
        UI.SetTooltip(less, tooltip)
        UI.SetTooltip(more, tooltip)
    end
    refreshers[#refreshers + 1] = show
    self.y = self.y + ROW_H
end

-- A button that opens a radio menu. values = { { value, text }, ... }
function Page:Choice(text, tooltip, values, get, set)
    self:Label(text, tooltip)
    local button = UI.CreateButton(self.content, "", 170, nil)
    button:SetPoint("TOPLEFT", CONTROL_X, -(self.y + 4))
    local function show()
        for _, v in ipairs(values) do
            if v[1] == get() then button:SetText(v[2]) end
        end
    end
    button:SetScript("OnClick", function(self)
        local entries = {}
        for _, v in ipairs(values) do
            entries[#entries + 1] = {
                text = v[2], radio = true,
                checked = function() return get() == v[1] end,
                func = function()
                    set(v[1])
                    show()
                    changed()
                end,
            }
        end
        UI.ShowMenu(self, entries)
    end)
    if tooltip then UI.SetTooltip(button, tooltip) end
    refreshers[#refreshers + 1] = show
    self.y = self.y + ROW_H
end

function Page:Button(text, buttonText, tooltip, onClick)
    self:Label(text, tooltip)
    local button = UI.CreateButton(self.content, buttonText, 170, onClick)
    button:SetPoint("TOPLEFT", CONTROL_X, -(self.y + 4))
    if tooltip then UI.SetTooltip(button, tooltip) end
    self.y = self.y + ROW_H
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local function Build()
    local db = ns.db

    local panel = CreateFrame("Frame")
    panel.name = TITLE

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText(TITLE)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -48)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)

    local page = NewPage(content)

    page:Checkbox("Enabled", "Turn AutoCarrot on or off. While it is on, speed gear is swapped in automatically, " ..
        "including items set to Always. Turning it off puts your normal gear back.",
        function() return db.enabled end,
        function(v) ns.Engine:SetEnabled(v) end)

    page:Header("Turn off inside")
    local kinds = {
        { "party", "Dungeons" }, { "raid", "Raids" }, { "pvp", "Battlegrounds" },
        { "arena", "Arenas" }, { "scenario", "Scenarios" },
    }
    for _, k in ipairs(kinds) do
        page:Checkbox(k[2], "Turn AutoCarrot off while inside " .. k[2]:lower() .. ". It turns back on when you leave.",
            function() return db.instanceTypes[k[1]] end,
            function(v) db.instanceTypes[k[1]] = v; ns.Engine:CheckInstance() end)
    end

    page:Header("Built-in items")
    for _, b in ipairs(ns.BUILTINS) do
        local where = b.zones and (", only in " .. ns.Engine:ZoneLabel(b.zones)) or ""
        local tooltip = "Swap in " .. b.name .. " " .. UI.TriggerPhrase({ [b.trigger] = true }) .. where .. "."
        if b.twoHand then
            tooltip = tooltip .. " Off by default: the real weapon goes back on as soon as combat starts, which costs a global cooldown at the start of a fight."
        end
        page:Checkbox(b.name, tooltip,
            function() return db.builtins[b.id] ~= false end,
            function(v) db.builtins[b.id] = v end)
    end

    page:Header("Behaviour")
    page:Choice("Trinket slots for speed items",
        "Mount-speed bonuses stack in Forever, so two speed trinkets are faster. " ..
        "Both normal trinkets then come back on a 30-second cooldown after you dismount.",
        { { 2, "Two (fastest)" }, { 1, "One" } },
        function() return db.speedTrinketSlots end,
        function(v) db.speedTrinketSlots = v end)
    page:Choice("Preferred trinket slot",
        "Which trinket slot to use first. Auto picks the one that is cheapest to swap.",
        { { 0, "Auto" }, { 13, "Top (13)" }, { 14, "Bottom (14)" } },
        function() return tonumber(db.trinketSlot) or 0 end,
        function(v) db.trinketSlot = (v == 0) and "auto" or v end)
    local locks = { { 13, "Lock trinket 1" }, { 14, "Lock trinket 2" }, { 11, "Lock ring 1" }, { 12, "Lock ring 2" } }
    for _, l in ipairs(locks) do
        page:Checkbox(l[2], "Never swap this slot, for example to keep a PvP trinket on.",
            function() return db.lockedSlots[l[1]] == true end,
            function(v) db.lockedSlots[l[1]] = v or nil end)
    end
    page:Checkbox("Never swap out on-use trinkets",
        "Swapping a trinket back on puts it on a 30-second cooldown. When this is on, trinkets with a Use: effect are never removed. If both trinkets have one, no speed trinket is used.",
        function() return db.neverSwapOnUse end,
        function(v) db.neverSwapOnUse = v end)
    local delays = { { "mounted", "Restore delay: mounted" }, { "swimming", "Restore delay: swimming" }, { "submerged", "Restore delay: underwater" } }
    for _, d in ipairs(delays) do
        page:Stepper(d[2],
            "Seconds to wait before putting normal gear back. If the trigger comes back first (remounting after gathering, bobbing at the water surface), nothing is swapped. Ignored right after combat.",
            0, 5, 0.5, "%.1f s",
            function() return db.restoreDelay[d[1]] or 0 end,
            function(v) db.restoreDelay[d[1]] = v end)
    end

    page:Header("Interface")
    page:Checkbox("Show toggle button", "A movable on/off button. Hold Alt and drag it to move it.",
        function() return db.button.shown end,
        function(v) db.button.shown = v end)
    page:Stepper("Toggle button scale", nil, 0.5, 2, 0.1, "%.1f",
        function() return db.button.scale end,
        function(v) db.button.scale = v end)
    page:Checkbox("Show minimap button", nil,
        function() return not db.minimap.hide end,
        function(v) db.minimap.hide = not v end)
    page:Checkbox("Show speed-item suggestions in chat",
        "Announce bag items whose tooltip mentions mount, swim or movement speed.",
        function() return db.chatSuggestions end,
        function(v) db.chatSuggestions = v end)
    page:Button("Button positions", "Reset", "Put both buttons back in their default spots.",
        function() UI.ResetButtons() end)
    page:Button("Custom items", "Open item editor", "Add your own speed items, enchants and sets.",
        function() UI.OpenEditor() end)
    page:Checkbox("Debug messages", "Explain every swap decision in chat.",
        function() return db.debug end,
        function(v) db.debug = v end)

    -- Zone groups last: its height changes as groups are expanded.
    page:Header("Zone groups")
    local staticHeight = page.y
    local zones = UI.CreateZoneGroupsSection(content, function(height)
        content:SetHeight(staticHeight + height + 24)
    end)
    zones:SetPoint("TOPLEFT", LABEL_X, -staticHeight)
    zones:SetPoint("RIGHT", content, "RIGHT", -16, 0)
    content:SetHeight(staticHeight + 200)

    local function refreshAll()
        for _, fn in ipairs(refreshers) do fn() end
        zones:Refresh()
    end
    panel:SetScript("OnShow", function()
        content:SetWidth(scroll:GetWidth())
        refreshAll()
    end)
    -- Settings canvas callbacks (names differ between client versions).
    panel.OnRefresh, panel.refresh = refreshAll, refreshAll
    panel.OnCommit, panel.okay = function() end, function() end
    panel.OnDefault, panel.default = function() end, function() end
    panel.cancel = function() end

    -- Slash commands and other UI change settings too: keep the page current.
    ns:On("AC_STATUS", function() if panel:IsVisible() then for _, fn in ipairs(refreshers) do fn() end end end)

    category = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
    Settings.RegisterAddOnCategory(category)
    UI.settingsCategory = category
end

function UI.OpenSettings()
    if not (category and Settings and Settings.OpenToCategory) then
        ns.Print("The options panel is not available on this client; type /ac help for commands.")
        return
    end
    if InCombatLockdown() then
        ns.Print("The options panel can't be opened during combat; try again afterwards.")
        return
    end
    local ok = pcall(Settings.OpenToCategory, category:GetID())
    if not ok then ns.Print("Could not open the options panel; type /ac help for commands.") end
end

-- Zone groups are part of the main page now.
UI.OpenZoneGroups = UI.OpenSettings

ns:On("AC_LOADED", function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then
        ns.Debug("Settings API not available; use /ac commands.")
        return
    end
    local ok, err = pcall(Build)
    if not ok then ns.Debug("Options page: " .. tostring(err)) end
end)
