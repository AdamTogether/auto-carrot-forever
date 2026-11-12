local ADDON, ns = ...

local UI = ns.UI

local ICON = 134010 -- carrot

local toggle, minimap

local function statusTooltip(tt)
    tt:AddLine("AutoCarrot Forever")
    for _, line in ipairs(ns.Engine:StatusLines()) do
        tt:AddLine(line, 1, 1, 1)
    end
end

-- kind: "toggle" | "minimap" | "compartment"
local function hints(tt, kind)
    tt:AddLine(" ")
    tt:AddLine("Left-click: turn on/off", 0.6, 0.8, 1)
    tt:AddLine("Right-click: custom item editor", 0.6, 0.8, 1)
    if kind == "minimap" then
        tt:AddLine("Shift-click: options", 0.6, 0.8, 1)
        tt:AddLine("Drag: move around the minimap", 0.6, 0.8, 1)
    elseif kind == "toggle" then
        tt:AddLine("Alt-drag: move", 0.6, 0.8, 1)
    end
end

local function onClick(button, minimapButton)
    if minimapButton and IsShiftKeyDown() then
        UI.OpenSettings()
    elseif button == "RightButton" then
        UI.ToggleEditor()
    else
        ns.Engine:SetEnabled(not ns.db.enabled)
    end
end

--------------------------------------------------------------------------------
-- Toggle button (3.01 behaviour, DESIGN.md §8.3)
--------------------------------------------------------------------------------

-- Position lives in our SavedVariables, not in the client's layout cache:
-- Forever's Edit Mode re-lays out UIParent children and does not know this
-- button, so SetUserPlaced positions were not reliable.
local function applyTogglePosition()
    local pos = ns.db.button.pos
    toggle:ClearAllPoints()
    if pos then
        toggle:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        toggle:SetPoint("CENTER")
    end
end

local function saveTogglePosition()
    local point, _, relPoint, x, y = toggle:GetPoint(1)
    ns.db.button.pos = { point, relPoint, x, y }
end

-- Plain Button, no ActionButtonTemplate: the Mainline template brings its own
-- scripts and drag handling, which swallowed Alt-drag on Forever.
local function CreateToggle()
    local b = CreateFrame("Button", "AutoCarrotForeverButton", UIParent)
    b:SetSize(36, 36)
    b:SetFrameStrata("MEDIUM")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexture(ICON)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0, 0, 0, 0.8)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b.overlay = b:CreateTexture(nil, "OVERLAY")
    b.overlay:SetPoint("TOPLEFT", 2, -2)
    b.overlay:SetPoint("BOTTOMRIGHT", -2, 2)

    b:EnableMouse(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetMovable(true)
    b:SetClampedToScreen(true)
    b:SetUserPlaced(false)

    -- Alt + left mouse button moves it. Handled on mouse down/up directly
    -- instead of OnDragStart, which needs the cursor to pass a drag threshold
    -- first and can be eaten by other handlers.
    b:SetScript("OnMouseDown", function(self, button)
        self.suppressClick = false
        if button == "LeftButton" and IsAltKeyDown() then
            self.moving = true
            self:StartMoving()
        end
    end)
    b:SetScript("OnMouseUp", function(self)
        if self.moving then
            self:StopMovingOrSizing()
            self:SetUserPlaced(false) -- StartMoving marks it; keep it out of the layout cache
            self.moving = false
            self.suppressClick = true -- this mouse-up ends a move, not a click
            saveTogglePosition()
            applyTogglePosition()
        end
    end)
    b:SetScript("OnHide", function(self)
        if self.moving then
            self:StopMovingOrSizing()
            self.moving = false
            saveTogglePosition()
        end
    end)
    b:SetScript("OnClick", function(self, button)
        if self.suppressClick then
            self.suppressClick = false
            return
        end
        if IsAltKeyDown() then return end -- Alt is reserved for moving
        onClick(button, false)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        statusTooltip(GameTooltip)
        hints(GameTooltip, "toggle")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

--------------------------------------------------------------------------------
-- Minimap button (hand-rolled, no LibDBIcon; DESIGN.md §8.4)
--------------------------------------------------------------------------------

local atan2 = math.atan2 or math.atan

local function positionMinimap()
    local angle = math.rad(ns.db.minimap.angle or 225)
    local x, y = math.cos(angle), math.sin(angle)
    local halfW = Minimap:GetWidth() / 2 + 5
    local halfH = Minimap:GetHeight() / 2 + 5
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        local diag = math.sqrt(2 * halfW * halfW) - 10
        x = math.max(-halfW, math.min(x * diag, halfW))
        y = math.max(-halfH, math.min(y * diag, halfH))
    else
        x, y = x * halfW, y * halfH
    end
    minimap:ClearAllPoints()
    minimap:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CreateMinimap()
    local b = CreateFrame("Button", "AutoCarrotForeverMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(17, 17)
    b.icon:SetTexture(ICON)
    b.icon:SetPoint("TOPLEFT", 7, -6)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button) onClick(button, true) end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            ns.db.minimap.angle = math.deg(atan2(py - my, px - mx)) % 360
            positionMinimap()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        statusTooltip(GameTooltip)
        hints(GameTooltip, "minimap")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

--------------------------------------------------------------------------------
-- Updates
--------------------------------------------------------------------------------

function UI.UpdateButtons()
    if not toggle then return end
    local db = ns.db
    if not db.enabled then
        toggle.overlay:SetColorTexture(1, 0, 0, 0.5)
    elseif ns.Engine:IsPending() then
        toggle.overlay:SetColorTexture(1, 0.8, 0, 0.4)
    else
        toggle.overlay:SetColorTexture(0, 1, 0, 0.3)
    end
    toggle:SetScale(db.button.scale or 1)
    toggle:SetShown(db.button.shown)

    minimap:SetShown(not db.minimap.hide)
    minimap.icon:SetDesaturated(not db.enabled)
    if db.enabled and ns.Engine:IsPending() then
        minimap.icon:SetVertexColor(1, 0.85, 0.3)
    else
        minimap.icon:SetVertexColor(1, 1, 1)
    end
end

function UI.ResetButtons()
    local db = ns.db
    db.button.pos = nil
    applyTogglePosition()
    db.button.scale = 1
    db.minimap.angle = 225
    positionMinimap()
    UI.UpdateButtons()
end

ns:On("AC_LOADED", function()
    toggle = CreateToggle()
    applyTogglePosition()
    minimap = CreateMinimap()
    positionMinimap()
    UI.UpdateButtons()
end)

ns:On("AC_STATUS", function() UI.UpdateButtons() end)

--------------------------------------------------------------------------------
-- Addon compartment (TOC AddonCompartmentFunc)
--------------------------------------------------------------------------------

function AutoCarrotForever_OnCompartmentClick(_, button)
    onClick(button, false)
end

function AutoCarrotForever_OnCompartmentEnter(_, frame)
    GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    statusTooltip(GameTooltip)
    hints(GameTooltip, "compartment")
    GameTooltip:Show()
end

function AutoCarrotForever_OnCompartmentLeave()
    GameTooltip:Hide()
end
