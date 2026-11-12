local ADDON, ns = ...

local UI = ns.UI
local TITLE = "AutoCarrot Forever"

local category

local function changed()
    ns.Engine:OnSettingsChanged()
    UI.UpdateButtons()
end

-- Each control is created in its own pcall: a Settings API change in a beta
-- build should cost one control, not the whole panel.
local function try(what, fn)
    local ok, err = pcall(fn)
    if not ok then ns.Debug("Settings: could not create '" .. what .. "': " .. tostring(err)) end
end

local CreateCheckbox = Settings and (Settings.CreateCheckbox or Settings.CreateCheckBox)

local function checkbox(key, label, tooltip, get, set)
    try(label, function()
        local setting = Settings.RegisterProxySetting(category, "ACF_" .. key, Settings.VarType.Boolean,
            label, get(), get, function(v) set(v) changed() end)
        CreateCheckbox(category, setting, tooltip)
    end)
end

local function slider(key, label, tooltip, min, max, step, default, get, set, fmt)
    try(label, function()
        local setting = Settings.RegisterProxySetting(category, "ACF_" .. key, Settings.VarType.Number,
            label, default, get, function(v) set(v) changed() end)
        local options = Settings.CreateSliderOptions(min, max, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
            return string.format(fmt or "%.1f", v)
        end)
        Settings.CreateSlider(category, setting, options, tooltip)
    end)
end

local function dropdown(key, label, tooltip, varType, default, values, get, set)
    try(label, function()
        local setting = Settings.RegisterProxySetting(category, "ACF_" .. key, varType,
            label, default, get, function(v) set(v) changed() end)
        Settings.CreateDropdown(category, setting, function()
            local container = Settings.CreateControlTextContainer()
            for _, v in ipairs(values) do container:Add(v[1], v[2]) end
            return container:GetData()
        end, tooltip)
    end)
end

local function header(layout, text)
    try(text, function()
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end)
end

local function button(layout, label, text, tooltip, onClick)
    try(label, function()
        layout:AddInitializer(CreateSettingsButtonInitializer(label, text, onClick, tooltip, true))
    end)
end

local function Build()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then
        ns.Debug("Settings API not available; use /ac commands.")
        return
    end
    local db = ns.db
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory(TITLE)

    checkbox("enabled", "Enabled", "Automatically equip speed gear.",
        function() return db.enabled end,
        function(v) ns.Engine:SetEnabled(v) end)

    header(layout, "Turn off inside")
    local kinds = {
        { "party", "Dungeons" }, { "raid", "Raids" }, { "pvp", "Battlegrounds" },
        { "arena", "Arenas" }, { "scenario", "Scenarios" },
    }
    for _, k in ipairs(kinds) do
        checkbox("inst_" .. k[1], k[2], "Turn AutoCarrot off while inside " .. k[2]:lower() ..
            ". It turns back on when you leave.",
            function() return db.instanceTypes[k[1]] end,
            function(v) db.instanceTypes[k[1]] = v; ns.Engine:CheckInstance() end)
    end

    header(layout, "Built-in items")
    for _, b in ipairs(ns.BUILTINS) do
        local where = b.zones and (", only in " .. ns.Engine:ZoneLabel(b.zones)) or ""
        checkbox("builtin_" .. b.id, b.name, "Swap in " .. b.name .. " (" ..
            UI.TriggerText({ [b.trigger] = true }):lower() .. where .. ").",
            function() return db.builtins[b.id] ~= false end,
            function(v) db.builtins[b.id] = v end)
    end

    header(layout, "Behaviour")
    dropdown("speedTrinkets", "Trinket slots for speed items",
        "Mount-speed bonuses stack in Forever, so two speed trinkets are faster. " ..
        "Both normal trinkets then come back on a 30-second cooldown after you dismount.",
        Settings.VarType.Number, 2, { { 2, "Two (fastest)" }, { 1, "One" } },
        function() return db.speedTrinketSlots end,
        function(v) db.speedTrinketSlots = v end)
    dropdown("trinketSlot", "Preferred trinket slot",
        "Which trinket slot to use first. Auto picks the one that is cheapest to swap.",
        Settings.VarType.Number, 0, { { 0, "Auto" }, { 13, "Top (13)" }, { 14, "Bottom (14)" } },
        function() return tonumber(db.trinketSlot) or 0 end,
        function(v) db.trinketSlot = (v == 0) and "auto" or v end)
    local locks = { { 13, "Lock trinket 1" }, { 14, "Lock trinket 2" }, { 11, "Lock ring 1" }, { 12, "Lock ring 2" } }
    for _, l in ipairs(locks) do
        checkbox("lock_" .. l[1], l[2], "Never swap this slot, for example to keep a PvP trinket on.",
            function() return db.lockedSlots[l[1]] == true end,
            function(v) db.lockedSlots[l[1]] = v or nil end)
    end
    checkbox("neverSwapOnUse", "Never swap out on-use trinkets",
        "Swapping a trinket back on puts it on a 30-second cooldown. When this is on, trinkets with a Use: effect are never removed. If both trinkets have one, no speed trinket is used.",
        function() return db.neverSwapOnUse end,
        function(v) db.neverSwapOnUse = v end)
    local delays = { { "mounted", "Restore delay: mounted" }, { "swimming", "Restore delay: swimming" }, { "submerged", "Restore delay: underwater" } }
    for _, d in ipairs(delays) do
        slider("delay_" .. d[1], d[2],
            "Seconds to wait before putting normal gear back. If the trigger comes back first (remounting after gathering, bobbing at the water surface), nothing is swapped. Ignored right after combat.",
            0, 5, 0.5, d[1] == "mounted" and 0 or 1,
            function() return db.restoreDelay[d[1]] or 0 end,
            function(v) db.restoreDelay[d[1]] = v end, "%.1f s")
    end

    header(layout, "Zone groups")
    for _, key in ipairs(ns.Engine:GroupKeys()) do
        local label = ns.Engine:GroupLabel(key)
        button(layout, label, "Add current zone",
            "Items such as The Desert Rose only work in " .. label .. ". Which zones count is not published, so stand in a zone where the item works and add it here. Type /ac zone to see the list.",
            function()
                local zone = ns.Engine:ToggleCurrentZone(ns.Engine:GroupZones(key), true)
                if zone then ns.Print(zone.name .. " added to " .. label .. ".") end
            end)
        button(layout, " ", "Remove current zone", nil, function()
            local zone = ns.Engine:ToggleCurrentZone(ns.Engine:GroupZones(key), false)
            if zone then ns.Print(zone.name .. " removed from " .. label .. ".") end
        end)
    end

    header(layout, "Interface")
    checkbox("button", "Show toggle button", "A movable on/off button (Alt-drag to move).",
        function() return db.button.shown end,
        function(v) db.button.shown = v end)
    slider("buttonScale", "Toggle button scale", nil, 0.5, 2, 0.1, 1,
        function() return db.button.scale end,
        function(v) db.button.scale = v end, "%.1f")
    checkbox("minimap", "Show minimap button", nil,
        function() return not db.minimap.hide end,
        function(v) db.minimap.hide = not v end)
    checkbox("chatSuggestions", "Show speed-item suggestions in chat",
        "Announce bag items whose tooltip mentions mount, swim or movement speed.",
        function() return db.chatSuggestions end,
        function(v) db.chatSuggestions = v end)
    button(layout, "Button positions", "Reset", "Put both buttons back in their default spots.",
        function() UI.ResetButtons() end)
    checkbox("debug", "Debug messages", "Explain every swap decision in chat.",
        function() return db.debug end,
        function(v) db.debug = v end)

    Settings.RegisterAddOnCategory(category)

    -- Sub-page that opens the custom item editor window.
    try("Custom Items", function()
        local panel = CreateFrame("Frame")
        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Custom Items")
        local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
        text:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
        text:SetJustifyH("LEFT")
        text:SetText("Add any equippable item or enchant, choose its slot and when it is worn, " ..
            "and review speed items found in your bags. Custom items are shared by all your characters.")
        local open = UI.CreateButton(panel, "Open item editor", 160, function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
            UI.OpenEditor()
        end)
        open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -16)
        Settings.RegisterCanvasLayoutSubcategory(category, panel, "Custom Items")
    end)
end

function UI.OpenSettings()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    else
        ns.Print("The options panel is not available on this client; type /ac help for commands.")
    end
end

ns:On("AC_LOADED", function()
    try("panel", Build)
end)
