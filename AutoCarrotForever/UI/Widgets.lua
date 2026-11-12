local ADDON, ns = ...

local UI = {}
ns.UI = UI

--[[
ShowMenu(owner, entries)
entries: list of
  { text = "Title", isTitle = true }
  { text = "Item", func = fn }                               -- button
  { text = "Item", checked = fn, func = fn }                 -- checkbox (stays open)
  { text = "Item", checked = fn, func = fn, radio = true }   -- radio
Uses MenuUtil (Mainline); falls back to UIDropDownMenu if that is all there is.
]]
local fallbackMenu

function UI.ShowMenu(owner, entries)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            for _, e in ipairs(entries) do
                if e.isTitle then
                    root:CreateTitle(e.text)
                elseif e.checked and e.radio then
                    root:CreateRadio(e.text, function() return e.checked() end, function() e.func() end)
                elseif e.checked then
                    root:CreateCheckbox(e.text, function() return e.checked() end, function() e.func() end)
                else
                    root:CreateButton(e.text, function() e.func() end)
                end
            end
        end)
        return
    end
    if UIDropDownMenu_Initialize and ToggleDropDownMenu then
        fallbackMenu = fallbackMenu or CreateFrame("Frame", "AutoCarrotForeverMenu", UIParent, "UIDropDownMenuTemplate")
        UIDropDownMenu_Initialize(fallbackMenu, function()
            for _, e in ipairs(entries) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = e.text
                info.isTitle = e.isTitle
                info.notCheckable = not e.checked
                info.checked = e.checked and e.checked() or nil
                info.isNotRadio = not e.radio
                info.keepShownOnClick = e.checked and not e.radio
                info.func = e.func and function() e.func() end
                UIDropDownMenu_AddButton(info)
            end
        end, "MENU")
        ToggleDropDownMenu(1, nil, fallbackMenu, owner, 0, 0)
    end
end

-- A check button with its own label (template label fields differ by version).
function UI.CreateCheck(parent, label, tooltip, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    if label then
        cb.label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 0, 1)
        cb.label:SetText(label)
    end
    if tooltip then UI.SetTooltip(cb, tooltip) end
    cb:SetScript("OnClick", function(self)
        if onClick then onClick(self:GetChecked() and true or false) end
    end)
    return cb
end

function UI.CreateButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 80, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- tooltip: string or function(GameTooltip)
function UI.SetTooltip(frame, tooltip)
    frame:EnableMouse(true) -- plain Frames ignore the mouse otherwise
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if type(tooltip) == "function" then
            tooltip(GameTooltip, self)
        else
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI.TriggerText(triggers)
    local parts = {}
    for _, key in ipairs(ns.TRIGGER_ORDER) do
        if triggers[key] then parts[#parts + 1] = ns.TRIGGERS[key].label end
    end
    return #parts > 0 and table.concat(parts, ", ") or "Never"
end

-- Replaced by the real implementations in Settings.lua / ItemList.lua / Buttons.lua.
function UI.OpenSettings() end
function UI.OpenZoneGroups() end
function UI.RefreshZoneGroups() end
function UI.OpenEditor() end
function UI.UpdateButtons() end
function UI.ResetButtons() end
