-- SoloCraft Bots - Options drawer
-- Loaded after SoloCraftBots.lua; intentionally behavior-preserving.

local SCB = SoloCraftBots

-- -------------------------------------------------------------------------
-- Options drawer
-- -------------------------------------------------------------------------

function SCB_RefreshAutoLootSelector()
    local info
    SCB_EnsureOptionsDB()
    info = SCB_GetAutoLootInfo(SoloCraftBotsDB.options.autoLootMethod)
    if SCB.optionAutoLootSelector and SCB.optionAutoLootSelector.label then
        SCB.optionAutoLootSelector.label:SetText(info.label)
    end
end

function SCB_AutoLootOptionOnClick()
    local partyCount, raidCount
    if not this or not this.scbLootMethod then return end
    SCB_EnsureOptionsDB()
    SoloCraftBotsDB.options.autoLootMethod = this.scbLootMethod
    SCB_RefreshAutoLootSelector()
    if SCB.optionAutoLootMenu then SCB.optionAutoLootMenu:Hide() end

    partyCount = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if partyCount > 0 or raidCount > 0 then
        SCB_ApplyAutoLootMethod()
        SCB_QueueAutoLootApply()
    end
end

function SCB_AutoLootSelectorOnClick()
    if not SCB.optionAutoLootMenu then return end
    if SCB.optionAutoLootMenu:IsShown() then
        SCB.optionAutoLootMenu:Hide()
    else
        SCB.optionAutoLootMenu:Show()
        SCB.optionAutoLootMenu:Raise()
    end
end

function SCB_CreateAutoLootOption(parent)
    local label, selector, arrow, menu, i, info, button

    label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -8)
    label:SetWidth(118)
    label:SetJustifyH("LEFT")
    label:SetText(SCB_L("OPTION_AUTO_LOOT"))
    SCB_SetFontColor(label, "text")
    SCB.optionAutoLootLabel = label

    selector = SCB_CreateTextButton(parent, "SoloCraftBotsAutoLootSelector", 118, 22, SCB_L("LOOT_OFF"))
    selector:SetPoint("LEFT", label, "RIGHT", 2, 0)
    selector.label:ClearAllPoints()
    selector.label:SetPoint("LEFT", selector, "LEFT", 7, 0)
    selector.label:SetPoint("RIGHT", selector, "RIGHT", -22, 0)
    selector.label:SetJustifyH("LEFT")
    selector:SetScript("OnClick", SCB_AutoLootSelectorOnClick)
    SCB.optionAutoLootSelector = selector

    arrow = selector:CreateTexture(nil, "ARTWORK")
    SCB_SetTextureRenderSize(arrow, SCB.LUCIDE_ICON_SIZE, selector)
    arrow:ClearAllPoints()
    arrow:SetPoint("RIGHT", selector, "RIGHT", -2, 0)
    arrow:SetTexture(SCB.assetRoot .. "lucide_chevron_down.tga")

    menu = CreateFrame("Frame", "SoloCraftBotsAutoLootMenu", parent)
    menu:SetWidth(118)
    menu:SetHeight(8 + (table.getn(SCB.AUTO_LOOT_METHODS) * 20))
    menu:SetPoint("TOPLEFT", selector, "BOTTOMLEFT", 0, -1)
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    menu:SetBackdropColor(0.03, 0.03, 0.03, 0.98)
    menu:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
    menu:SetFrameStrata("DIALOG")
    menu:Hide()
    SCB.optionAutoLootMenu = menu

    for i = 1, table.getn(SCB.AUTO_LOOT_METHODS) do
        info = SCB.AUTO_LOOT_METHODS[i]
        button = SCB_CreateTextButton(menu, nil, 110, 20, info.label)
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - ((i - 1) * 20))
        button.scbLootMethod = info.key
        button:SetScript("OnClick", SCB_AutoLootOptionOnClick)
    end

    SCB_RefreshAutoLootSelector()
end

function SCB_OptionCheckOnClick()
    local key = this and this.scbOptionKey or nil
    if not key then return end
    SCB_EnsureOptionsDB()
    SoloCraftBotsDB.options[this.scbOptionKey] = this:GetChecked() and true or false
    if this.scbOptionKey == "hideSCBScreenWarnings" and SoloCraftBotsDB.options.hideSCBScreenWarnings
        and SCB.safetyMessageFrame then SCB.safetyMessageFrame:Hide() end
    if this.scbOptionKey == "autoPromotePlayers" then SCB_ApplyAutoPromotePlayers() end
    if this.scbOptionKey == "autoSwapPresetGroup" and SoloCraftBotsDB.options.autoSwapPresetGroup and SCB_ApplyCurrentLocationPresetGroup then
        SCB_ApplyCurrentLocationPresetGroup()
    end
    if key == "confirmBotRolesFromCombat" then
        if SCB_RefreshRoleDetectionLifecycle then SCB_RefreshRoleDetectionLifecycle() end
        if SCB_RefreshPresetRoleIndicators then SCB_RefreshPresetRoleIndicators() end
    end

end

function SCB_CreateOptionCheck(parent, key, labelKey, y)
    local check = SCB_CreateMiniCheckButton(parent, 24)
    check:SetWidth(24)
    check:SetHeight(24)
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
    check.scbOptionKey = key
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetText(SCB_L(labelKey))
    SCB_SetFontColor(label, "text")
    check.scbLabel = label
    check:SetScript("OnClick", SCB_OptionCheckOnClick)
    return check
end

function SCB_SetDebugOutline(frame, shown)
    local edge, i
    if not frame then return end
    if not frame.scbDebugOutline then
        frame.scbDebugOutline = {}
        for i = 1, 4 do
            edge = frame:CreateTexture(nil, "OVERLAY")
            edge:SetTexture(1, 0, 0, 1)
            frame.scbDebugOutline[i] = edge
        end
        frame.scbDebugOutline[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.scbDebugOutline[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.scbDebugOutline[1]:SetHeight(1)
        frame.scbDebugOutline[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.scbDebugOutline[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.scbDebugOutline[2]:SetHeight(1)
        frame.scbDebugOutline[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.scbDebugOutline[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.scbDebugOutline[3]:SetWidth(1)
        frame.scbDebugOutline[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.scbDebugOutline[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.scbDebugOutline[4]:SetWidth(1)
    end
    for i = 1, 4 do
        if shown then frame.scbDebugOutline[i]:Show() else frame.scbDebugOutline[i]:Hide() end
    end
end

function SCB_UpdateLayoutDebugBorders()
    local shown, r, i, row
    shown = SCB.optionsDebugMode and SCB.optionsDebugMode.command
    if SCB.commandLayout then
        for r = 1, table.getn(SCB.commandLayout.rows or {}) do
            row = SCB.commandLayout.rows[r]
            SCB_SetDebugOutline(row.recipientButton, shown)
            for i = 1, table.getn(row.commandButtons or {}) do SCB_SetDebugOutline(row.commandButtons[i], shown) end
        end
        for i = 1, table.getn(SCB.commandLayout.pairedComeButtons or {}) do SCB_SetDebugOutline(SCB.commandLayout.pairedComeButtons[i].button, shown) end
        for i = 1, table.getn(SCB.commandLayout.standaloneButtons or {}) do SCB_SetDebugOutline(SCB.commandLayout.standaloneButtons[i], shown) end
        SCB_SetDebugOutline(SCB.commandLayout.refill, shown)
        SCB_SetDebugOutline(SCB.commandLayout.kickDead, shown)
        SCB_SetDebugOutline(SCB.commandLayout.kickAll, shown)
    end

    shown = SCB.optionsDebugMode and SCB.optionsDebugMode.preset
    for i = 1, 8 do SCB_SetDebugOutline(SCB.presetGroupFrames and SCB.presetGroupFrames[i], shown) end
    for i = 1, 40 do
        row = SCB.presetSlotRows and SCB.presetSlotRows[i]
        if row then
            SCB_SetDebugOutline(row, shown)
            SCB_SetDebugOutline(row.roleButton, shown)
            SCB_SetDebugOutline(row.classButton, shown)
            SCB_SetDebugOutline(row.blessingButton, shown)
            SCB_SetDebugOutline(row.playerRoleButton, shown)
            SCB_SetDebugOutline(row.playerOverlay, shown)
        end
    end
end

function SCB_AdjustLayoutOption()
    local sectionKey, valueKey, delta, minimum, maximum, options, target, value
    if not this then return end
    sectionKey = this.scbLayoutSection
    valueKey = this.scbLayoutKey
    delta = this.scbDelta or 0
    if not sectionKey or not valueKey then return end
    SCB_EnsureOptionsDB()
    options = SoloCraftBotsDB.options
    if SCB.optionsDebugMode and SCB.optionsDebugMode[sectionKey] then
        target = sectionKey == "command" and options.commandLayoutDebug or options.presetLayoutDebug
        minimum = this.scbDebugMinimum
        maximum = this.scbDebugMaximum
    else
        target = sectionKey == "command" and options.commandLayoutUser or options.presetLayoutUser
        minimum = this.scbUserMinimum or -20
        maximum = this.scbUserMaximum or 20
    end
    if valueKey == "iconSize" and not (SCB.optionsDebugMode and SCB.optionsDebugMode[sectionKey]) then
        value = SCB_GetLayoutValue(sectionKey, valueKey) + delta
        if minimum and value < minimum then value = minimum end
        if maximum and value > maximum then value = maximum end
        local baseline = sectionKey == "command" and options.commandLayoutDebug[valueKey] or options.presetLayoutDebug[valueKey]
        target[valueKey] = value - (baseline or 0)
    else
        value = (target[valueKey] or 0) + delta
        if minimum and value < minimum then value = minimum end
        if maximum and value > maximum then value = maximum end
        target[valueKey] = value
    end
    SCB_RefreshOptionsUI()
    if sectionKey == "command" and SCB_LayoutCommandUI then SCB_LayoutCommandUI() end
    if sectionKey == "preset" and SCB_LayoutPresetGroups then SCB_LayoutPresetGroups() end
    SCB_UpdateLayoutDebugBorders()
end

function SCB_CreateLayoutControl(parent, sectionKey, valueKey, labelKey, y, debugMinimum, debugMaximum, userMinimum, userMaximum)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local minus, value, plus
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    label:SetWidth(116)
    label:SetJustifyH("LEFT")
    label:SetText(SCB_L(labelKey))
    SCB_SetFontColor(label, "text")

    minus = SCB_CreateArtButton(parent, nil, 20, SCB.assetRoot .. "lucide_minus.tga")
    minus:SetWidth(22)
    minus:SetPoint("LEFT", label, "RIGHT", 2, 0)
    minus.scbLayoutSection = sectionKey
    minus.scbLayoutKey = valueKey
    minus.scbDelta = -1
    minus.scbDebugMinimum = debugMinimum
    minus.scbDebugMaximum = debugMaximum
    minus.scbUserMinimum = userMinimum
    minus.scbUserMaximum = userMaximum
    minus:SetScript("OnClick", SCB_AdjustLayoutOption)

    value = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    value:SetPoint("LEFT", minus, "RIGHT", 3, 0)
    value:SetWidth(24)
    value:SetJustifyH("CENTER")
    SCB_SetFontColor(value, "text")

    plus = SCB_CreateArtButton(parent, nil, 20, SCB.assetRoot .. "lucide_plus.tga")
    plus:SetWidth(22)
    plus:SetPoint("LEFT", value, "RIGHT", 3, 0)
    plus.scbLayoutSection = sectionKey
    plus.scbLayoutKey = valueKey
    plus.scbDelta = 1
    plus.scbDebugMinimum = debugMinimum
    plus.scbDebugMaximum = debugMaximum
    plus.scbUserMinimum = userMinimum
    plus.scbUserMaximum = userMaximum
    plus:SetScript("OnClick", SCB_AdjustLayoutOption)

    return { label = label, minus = minus, value = value, plus = plus, sectionKey = sectionKey, valueKey = valueKey }
end

function SCB_OptionsSubsectionToggleOnClick()
    if not this or not this.scbOptionsSection then return end
    this.scbOptionsSection.scbExpanded = not this.scbOptionsSection.scbExpanded
    SCB_LayoutOptionsUI()
end

SCB.developerDebugEnabled = false

function SCB_SetDeveloperDebugEnabled(enabled)
    SCB.developerDebugEnabled = enabled and true or false
    SCB.optionsDebugMode = SCB.optionsDebugMode or { command = false, preset = false }

    if not SCB.developerDebugEnabled then
        SCB.optionsDebugMode.command = false
        SCB.optionsDebugMode.preset = false
        if SCB.debugFrame and SCB.debugFrame:IsShown() then SCB.debugFrame:Hide() end
        if SCB.debug then
            SCB.debug.batchRunning = false
            SCB.debug.batchWaitRemaining = nil
        end
    end

    if SCB_RefreshOptionsUI then SCB_RefreshOptionsUI() end
    if SCB_LayoutCommandUI then SCB_LayoutCommandUI() end
    if SCB_LayoutPresetGroups then SCB_LayoutPresetGroups() end
    if SCB_UpdateLayoutDebugBorders then SCB_UpdateLayoutDebugBorders() end
    if SCB_UpdateDebugTimerState then SCB_UpdateDebugTimerState() end
    if SCB_UpdateDebugEventRegistration then SCB_UpdateDebugEventRegistration(SCB.developerDebugEnabled) end

    if SCB.developerDebugEnabled then
        SCB_Print(SCB_L("DEBUG_MODE_ENABLED"))
    else
        SCB_Print(SCB_L("DEBUG_MODE_DISABLED"))
    end
end

function SCB_OptionsDebugOnClick()
    if not SCB.developerDebugEnabled then
        if this then this:SetChecked(nil) end
        return
    end
    local sectionKey = this and this.scbLayoutSection
    if not sectionKey then return end
    SCB.optionsDebugMode = SCB.optionsDebugMode or {}
    SCB.optionsDebugMode[sectionKey] = this:GetChecked() and true or false
    SCB_RefreshOptionsUI()
    if sectionKey == "command" and SCB_LayoutCommandUI then SCB_LayoutCommandUI() end
    if sectionKey == "preset" and SCB_LayoutPresetGroups then SCB_LayoutPresetGroups() end
    SCB_UpdateLayoutDebugBorders()
end

function SCB_CreateOptionsSubsection(parent, sectionKey, labelKey, expandedHeight)
    local section = CreateFrame("Frame", nil, parent)
    local toggle, debugCheck, debugLabel, content
    section:SetWidth(parent:GetWidth())
    section.scbExpanded = sectionKey == nil
    section.scbCollapsedHeight = 26
    section.scbExpandedHeight = expandedHeight

    toggle = SCB_CreateArrowButton(section, 18)
    if sectionKey == "command" then
        SCB_SetTextureRenderSize(toggle.scbArrowTexture, SCB_GetLayoutValue("command", "iconSize"), toggle)
    elseif sectionKey == "preset" then
        SCB_SetTextureRenderSize(toggle.scbArrowTexture, SCB_GetLayoutValue("preset", "iconSize"), toggle)
    end
    toggle:SetPoint("TOPLEFT", section, "TOPLEFT", 12, -3)
    toggle.scbOptionsSection = section
    toggle:SetScript("OnClick", SCB_OptionsSubsectionToggleOnClick)
    section.scbToggle = toggle

    section.scbTitle = SCB_CreateSectionTitle(section, SCB_L(labelKey), 36, -4)
    toggle.scbTooltip = string.format(SCB_L("TIP_COLLAPSE_EXPAND"), SCB_L(labelKey))
    toggle:SetScript("OnEnter", SCB_TooltipOnEnter)
    toggle:SetScript("OnLeave", SCB_TooltipOnLeave)

    if sectionKey then
        debugCheck = SCB_CreateMiniCheckButton(section, 20)
        debugCheck:SetWidth(20)
        debugCheck:SetHeight(20)
        debugCheck:SetPoint("TOPRIGHT", section, "TOPRIGHT", -10, -2)
        debugCheck.scbLayoutSection = sectionKey
        debugCheck:SetScript("OnClick", SCB_OptionsDebugOnClick)
        section.scbDebugCheck = debugCheck

        debugLabel = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        debugLabel:SetPoint("RIGHT", debugCheck, "LEFT", -2, 0)
        debugLabel:SetText(SCB_L("OPTION_DEBUG"))
        SCB_SetFontColor(debugLabel, "text")
        section.scbDebugLabel = debugLabel
    end

    content = CreateFrame("Frame", nil, section)
    content:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -26)
    content:SetWidth(parent:GetWidth())
    content:SetHeight(expandedHeight - 26)
    section.scbContent = content
    return section
end

function SCB_RefreshOptionsSectionArrow(section)
    if not section or not section.scbToggle or not section.scbToggle.scbArrowTexture then return end
    if section.scbExpanded then
        SCB_SetArrowDirection(section.scbToggle.scbArrowTexture, "up")
        section.scbContent:Show()
    else
        SCB_SetArrowDirection(section.scbToggle.scbArrowTexture, "down")
        section.scbContent:Hide()
    end
end

local function SCB_LayoutOptionsSection(section, parent, y)
    local height = section.scbExpanded and section.scbExpandedHeight or section.scbCollapsedHeight
    section:ClearAllPoints()
    section:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    section:SetHeight(height)
    SCB_RefreshOptionsSectionArrow(section)
    return y - height
end

function SCB_LayoutOptionsUI()
    local y, layoutY
    if not SCB.optionsPanel then return end
    layoutY = SCB_LayoutOptionsSection(SCB.optionCommandSection, SCB.optionLayoutSection.scbContent, 0)
    layoutY = SCB_LayoutOptionsSection(SCB.optionPresetSection, SCB.optionLayoutSection.scbContent, layoutY)
    SCB.optionLayoutSection.scbContent:SetHeight(-layoutY)
    SCB.optionLayoutSection.scbExpandedHeight = 26 - layoutY

    y = SCB_LayoutOptionsSection(SCB.optionMiscSection, SCB.optionsPanel, -40)
    y = SCB_LayoutOptionsSection(SCB.optionChatSection, SCB.optionsPanel, y)
    y = SCB_LayoutOptionsSection(SCB.optionLayoutSection, SCB.optionsPanel, y)
    SCB.optionsPanel:SetHeight(-y + 38)
    if SCB.optionVersion then
        SCB.optionVersion:ClearAllPoints()
        SCB.optionVersion:SetPoint("BOTTOMLEFT", SCB.optionsPanel, "BOTTOMLEFT", 16, 14)
    end
end

function SCB_RefreshOptionsUI()
    local options, sectionKey, valueKey, target, i, control
    SCB_EnsureOptionsDB()
    options = SoloCraftBotsDB.options
    SCB_RefreshAutoLootSelector()
    if SCB.optionAutoPromotePlayersCheck then SCB.optionAutoPromotePlayersCheck:SetChecked(options.autoPromotePlayers and 1 or nil) end
    if SCB.optionSCBChatCheck then SCB.optionSCBChatCheck:SetChecked(options.hideSCBChatMessages and 1 or nil) end
    if SCB.optionSCBScreenCheck then SCB.optionSCBScreenCheck:SetChecked(options.hideSCBScreenWarnings and 1 or nil) end
    if SCB.optionAutoSwapPresetGroupCheck then SCB.optionAutoSwapPresetGroupCheck:SetChecked(options.autoSwapPresetGroup and 1 or nil) end
    if SCB.optionBotSummonMessageCheck then SCB.optionBotSummonMessageCheck:SetChecked(options.hideBotSummonMessage and 1 or nil) end
    if SCB.optionBotGroupMessagesCheck then SCB.optionBotGroupMessagesCheck:SetChecked(options.hideBotGroupMessages and 1 or nil) end
    if SCB.optionBotMovementMessagesCheck then SCB.optionBotMovementMessagesCheck:SetChecked(options.hideBotMovementMessages and 1 or nil) end
    if SCB.optionBotPauseMessagesCheck then SCB.optionBotPauseMessagesCheck:SetChecked(options.hideBotPauseMessages and 1 or nil) end
    if SCB.optionBotAttackMessagesCheck then SCB.optionBotAttackMessagesCheck:SetChecked(options.hideBotAttackMessages and 1 or nil) end
    SCB.optionsDebugMode = SCB.optionsDebugMode or { command = false, preset = false }
    if SCB.optionCommandSection and SCB.optionCommandSection.scbDebugCheck then
        SCB.optionCommandSection.scbDebugCheck:SetChecked(SCB.optionsDebugMode.command and 1 or nil)
    end
    if SCB.optionPresetSection and SCB.optionPresetSection.scbDebugCheck then
        SCB.optionPresetSection.scbDebugCheck:SetChecked(SCB.optionsDebugMode.preset and 1 or nil)
    end
    if SCB.optionCommandSection and SCB.optionCommandSection.scbToggle then
        SCB_SetTextureRenderSize(
            SCB.optionCommandSection.scbToggle.scbArrowTexture,
            SCB_GetLayoutValue("command", "iconSize"),
            SCB.optionCommandSection.scbToggle
        )
    end
    if SCB.optionPresetSection and SCB.optionPresetSection.scbToggle then
        SCB_SetTextureRenderSize(
            SCB.optionPresetSection.scbToggle.scbArrowTexture,
            SCB_GetLayoutValue("preset", "iconSize"),
            SCB.optionPresetSection.scbToggle
        )
    end
    local debugControlsShown = SCB.developerDebugEnabled and true or false
    local sections = { SCB.optionCommandSection, SCB.optionPresetSection }
    local section
    for i = 1, table.getn(sections) do
        section = sections[i]
        if section then
            if section.scbDebugCheck then
                if debugControlsShown then section.scbDebugCheck:Show() else section.scbDebugCheck:Hide() end
            end
            if section.scbDebugLabel then
                if debugControlsShown then section.scbDebugLabel:Show() else section.scbDebugLabel:Hide() end
            end
        end
    end
    for i = 1, table.getn(SCB.optionLayoutControls or {}) do
        control = SCB.optionLayoutControls[i]
        sectionKey = control.sectionKey
        valueKey = control.valueKey
        if SCB.optionsDebugMode[sectionKey] then
            target = sectionKey == "command" and options.commandLayoutDebug or options.presetLayoutDebug
        else
            target = sectionKey == "command" and options.commandLayoutUser or options.presetLayoutUser
        end
        if valueKey == "iconSize" then
            control.value:SetText(SCB_GetLayoutValue(sectionKey, valueKey))
        else
            control.value:SetText(target[valueKey] or 0)
        end
    end
    SoloCraftBotsDB = SoloCraftBotsDB or {}
    SoloCraftBotsDB.options = SoloCraftBotsDB.options or {}
    if SoloCraftBotsDB.options.confirmBotRolesFromCombat == nil then
        SoloCraftBotsDB.options.confirmBotRolesFromCombat = false
    end
    if SCB.optionConfirmBotRolesCheck then
        SCB.optionConfirmBotRolesCheck:SetChecked(SoloCraftBotsDB.options.confirmBotRolesFromCombat and 1 or nil)
    end

end

function SCB_SetOptionsPanelShown(show)
    if not SCB.optionsPanel then return end
    if show then
        SCB_RefreshOptionsUI()
        SCB_LayoutOptionsUI()
        SCB.optionsPanel:Show()
        if SCB_LayoutSidePanels then SCB_LayoutSidePanels() end
    else
        SCB.optionsPanel:Hide()
        if SCB_LayoutSidePanels then SCB_LayoutSidePanels() end
    end
end

function SCB_ConfigOnClick()
    if not SCB.optionsPanel then return end
    SCB_SetOptionsPanelShown(not SCB.optionsPanel:IsShown())
end

function SCB_CreateOptionsUI(frame)
    local panel = CreateFrame("Frame", "SoloCraftBotsOptionsPanel", UIParent)
    local heading, resetTutorials, miscContent, chatContent, layoutContent, commandContent, presetContent, sublabel, control, check
    panel:SetWidth(290)
    panel:SetHeight(220)
    panel:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 24,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.96)
    panel:SetFrameStrata(frame:GetFrameStrata())
    panel:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    SCB.optionsPanel = panel
    SCB.optionsDebugMode = { command = false, preset = false }
    SCB.optionLayoutControls = {}

    heading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOP", panel, "TOP", 0, -13)
    heading:SetText(SCB_L("OPTIONS_TITLE"))
    SCB_SetFontColor(heading, "header")

    SCB.optionsCloseButton = SCB_CreateArtButton(panel, nil, 18, SCB.assetRoot .. "lucide_x.tga")
    SCB.optionsCloseButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -9)
    SCB.optionsCloseButton.scbTooltip = SCB_L("TIP_CLOSE")
    SCB.optionsCloseButton:SetScript("OnClick", function() SCB_SetOptionsPanelShown(false) end)
    SCB.optionsCloseButton:SetScript("OnEnter", SCB_TooltipOnEnter)
    SCB.optionsCloseButton:SetScript("OnLeave", SCB_TooltipOnLeave)

    SCB.optionMiscSection = SCB_CreateOptionsSubsection(panel, nil, "OPTIONS_MISC", 140)
    miscContent = SCB.optionMiscSection.scbContent
    miscContent:ClearAllPoints()
    miscContent:SetPoint("TOPLEFT", SCB.optionMiscSection, "TOPLEFT", 12, -26)
    miscContent:SetWidth(panel:GetWidth() - 12)
    SCB_CreateAutoLootOption(miscContent)
    SCB.optionAutoSwapPresetGroupCheck = SCB_CreateOptionCheck(miscContent, "autoSwapPresetGroup", "OPTION_AUTO_SWAP_PRESET_GROUP", -30)
    SCB.optionAutoPromotePlayersCheck = SCB_CreateOptionCheck(miscContent, "autoPromotePlayers", "OPTION_AUTO_PROMOTE_PLAYERS", -54)
    resetTutorials = SCB_CreateTextButton(miscContent, nil, 112, 22, SCB_L("RESET_TUTORIALS"))
    resetTutorials:SetPoint("TOPLEFT", miscContent, "TOPLEFT", 16, -84)
    resetTutorials:SetScript("OnClick", SCB_ResetTutorialsOnClick)

    SCB.optionChatSection = SCB_CreateOptionsSubsection(panel, nil, "OPTIONS_BOT_CHAT_FILTER", 202)
    SCB.optionChatSection.scbExpanded = false
    chatContent = SCB.optionChatSection.scbContent
    chatContent:ClearAllPoints()
    chatContent:SetPoint("TOPLEFT", SCB.optionChatSection, "TOPLEFT", 12, -26)
    chatContent:SetWidth(panel:GetWidth() - 12)
    SCB.optionSCBChatCheck = SCB_CreateOptionCheck(chatContent, "hideSCBChatMessages", "OPTION_HIDE_SCB_CHAT_MESSAGES", -2)
    SCB.optionSCBScreenCheck = SCB_CreateOptionCheck(chatContent, "hideSCBScreenWarnings", "OPTION_HIDE_SCB_SCREEN_WARNINGS", -26)
    SCB.optionBotSummonMessageCheck = SCB_CreateOptionCheck(chatContent, "hideBotSummonMessage", "OPTION_HIDE_BOT_SUMMON_MESSAGE", -50)
    SCB.optionBotGroupMessagesCheck = SCB_CreateOptionCheck(chatContent, "hideBotGroupMessages", "OPTION_HIDE_BOT_GROUP_MESSAGES", -74)
    SCB.optionBotMovementMessagesCheck = SCB_CreateOptionCheck(chatContent, "hideBotMovementMessages", "OPTION_HIDE_BOT_MOVEMENT_MESSAGES", -98)
    SCB.optionBotPauseMessagesCheck = SCB_CreateOptionCheck(chatContent, "hideBotPauseMessages", "OPTION_HIDE_BOT_PAUSE_MESSAGES", -122)
    SCB.optionBotAttackMessagesCheck = SCB_CreateOptionCheck(chatContent, "hideBotAttackMessages", "OPTION_HIDE_BOT_ATTACK_MESSAGES", -146)

    SCB.optionLayoutSection = SCB_CreateOptionsSubsection(panel, nil, "OPTIONS_LAYOUT_TITLE", 78)
    SCB.optionLayoutSection.scbExpanded = false
    layoutContent = SCB.optionLayoutSection.scbContent
    layoutContent:ClearAllPoints()
    layoutContent:SetPoint("TOPLEFT", SCB.optionLayoutSection, "TOPLEFT", 12, -26)
    layoutContent:SetWidth(panel:GetWidth() - 12)
    SCB.optionCommandSection = SCB_CreateOptionsSubsection(layoutContent, "command", "OPTION_COMMAND_BUTTONS", 130)
    commandContent = SCB.optionCommandSection.scbContent
    control = SCB_CreateLayoutControl(commandContent, "command", "horizontalSpacing", "OPTION_COMMAND_H_SPACING", -2, -10, 10, -10, 10); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(commandContent, "command", "verticalSpacing", "OPTION_COMMAND_V_SPACING", -28, -10, 10, -10, 10); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(commandContent, "command", "groupVerticalSpacing", "OPTION_COMMAND_GROUP_SPACING", -54, -10, 10, -10, 10); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(commandContent, "command", "iconSize", "OPTION_ICON_SIZE", -80, 8, 24, 8, 24); table.insert(SCB.optionLayoutControls, control)

    SCB.optionPresetSection = SCB_CreateOptionsSubsection(layoutContent, "preset", "OPTION_PRESET_GROUPS", 320)
    presetContent = SCB.optionPresetSection.scbContent
    control = SCB_CreateLayoutControl(presetContent, "preset", "groupWidth", "OPTION_GROUP_WIDTH", -2, 60, 160, -30, 30); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(presetContent, "preset", "groupHeight", "OPTION_GROUP_HEIGHT", -26, 100, 240, -50, 50); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(presetContent, "preset", "roleSize", "OPTION_ROLE_SIZE", -54, 12, 40, -12, 12); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(presetContent, "preset", "classSize", "OPTION_CLASS_SIZE", -78, 12, 40, -12, 12); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(presetContent, "preset", "buffSize", "OPTION_BUFF_SIZE", -102, 12, 40, -12, 12); table.insert(SCB.optionLayoutControls, control)

    sublabel = presetContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sublabel:SetPoint("TOPLEFT", presetContent, "TOPLEFT", 16, -130)
    sublabel:SetText(SCB_L("OPTION_BORDER_OFFSET"))
    SCB_SetFontColor(sublabel, "subheader")
    control = SCB_CreateLayoutControl(presetContent, "preset", "borderHorizontal", "OPTION_HORIZONTAL", -150, -10, 30, -20, 20); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(presetContent, "preset", "borderVertical", "OPTION_VERTICAL", -174, -10, 30, -20, 20); table.insert(SCB.optionLayoutControls, control)

    sublabel = presetContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sublabel:SetPoint("TOPLEFT", presetContent, "TOPLEFT", 16, -202)
    sublabel:SetText(SCB_L("OPTION_ICON_SPACING"))
    SCB_SetFontColor(sublabel, "subheader")
    control = SCB_CreateLayoutControl(presetContent, "preset", "iconHorizontal", "OPTION_HORIZONTAL", -222, -10, 20, -20, 20); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(presetContent, "preset", "iconVertical", "OPTION_VERTICAL", -246, -10, 30, -20, 20); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(presetContent, "preset", "iconSize", "OPTION_ICON_SIZE", -272, 8, 24, 8, 24); table.insert(SCB.optionLayoutControls, control)

    SCB.optionVersion = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    SCB.optionVersion:SetText(SCB_L("VERSION_LABEL") .. ": " .. SCB.version)
    SCB_SetFontColor(SCB.optionVersion, "text")

    SCB_RefreshOptionsUI()
    SCB_LayoutOptionsUI()
    panel:Hide()
    if miscContent and SCB_CreateOptionCheck and not SCB.optionConfirmBotRolesCheck then
        check = SCB_CreateOptionCheck(miscContent, "confirmBotRolesFromCombat", "OPTION_CONFIRM_BOT_ROLES", -112)
        check.scbTooltip = SCB_L("OPTION_CONFIRM_BOT_ROLES_TIP")
        check:SetScript("OnEnter", SCB_TooltipOnEnter)
        check:SetScript("OnLeave", SCB_TooltipOnLeave)
        SCB.optionConfirmBotRolesCheck = check
        SCB.optionMiscSection.scbExpandedHeight = 168
        miscContent:SetHeight(142)
    end
    SCB_RefreshOptionsUI()
    if SCB_LayoutOptionsUI then SCB_LayoutOptionsUI() end

end

-- -------------------------------------------------------------------------
-- Bot chat filtering
-- -------------------------------------------------------------------------

local SCB_MOVEMENT_ROLE_PREFIXES = {
    "Tanks ",
    "Melee DPS ",
    "Range DPS ",
    "Ranged DPS ",
    "Healers ",
}

local SCB_MISSING_ROLE_NAMES = {
    "tanks",
    "melee dps",
    "range dps",
    "ranged dps",
    "healers",
    "range dos bits",
}

local function SCB_StartsWith(text, prefix)
    return string.sub(text or "", 1, string.len(prefix)) == prefix
end

local function SCB_IsMovementActorLine(text)
    local i
    if SCB_StartsWith(text, "All party bots ") or SCB_StartsWith(text, "All bots ") then return true end
    if string.find(text, "^[^%s]+%* ") then return true end
    for i = 1, table.getn(SCB_MOVEMENT_ROLE_PREFIXES) do
        if SCB_StartsWith(text, SCB_MOVEMENT_ROLE_PREFIXES[i]) then return true end
    end
    return false
end

local function SCB_IsMovementFailure(text)
    local lower = string.lower(text or "")
    local i, prefix
    for i = 1, table.getn(SCB_MISSING_ROLE_NAMES) do
        prefix = "there are no " .. SCB_MISSING_ROLE_NAMES[i] .. " in the group"
        if lower == prefix .. "." then return true end
        if lower == prefix .. " or they cannot move." then return true end
        if lower == prefix .. " or they cannot stay." then return true end
        if lower == prefix .. " or they cannot come." then return true end
    end
    if string.find(lower, "^[^%s]+%* is not a party bot or it cannot move%.$") then return true end
    if string.find(lower, "^[^%s]+%* is not a party bot or it cannot stay%.$") then return true end
    if string.find(lower, "^[^%s]+%* is not a party bot or it cannot come%.$") then return true end
    return false
end

local function SCB_ShouldHideBotChatMessage(text)
    local options
    if not text or text == "" then return false end
    SCB_EnsureOptionsDB()
    options = SoloCraftBotsDB.options

    if options.hideBotSummonMessage and text == "New party bot added." then return true end

    if options.hideBotGroupMessages then
        if string.find(text, "^[^%s]+%* joins the party%.$") then return true end
        if string.find(text, "^[^%s]+%* leaves the party%.$") then return true end
        if string.find(text, "^[^%s]+%* has joined the raid group%.?$") then return true end
        if string.find(text, "^[^%s]+%* has left the raid group%.?$") then return true end
    end

    if options.hideBotMovementMessages then
        if SCB_IsMovementFailure(text) then return true end
        if SCB_IsMovementActorLine(text) then
            if string.find(text, "are coming to your position%.$") or string.find(text, "is coming to your position%.$") then return true end
            if string.find(text, "are now moving%.$") or string.find(text, "are moving%.$") then return true end
            if string.find(text, "is now moving%.$") or string.find(text, "is moving%.$") then return true end
            if string.find(text, "are now staying%.$") or string.find(text, "are staying%.$") then return true end
            if string.find(text, "is now staying%.$") or string.find(text, "is staying%.$") then return true end
        end
    end

    if options.hideBotPauseMessages then
        local botLine = SCB_StartsWith(text, "All party bots ") or SCB_StartsWith(text, "All bots ") or string.find(text, "^[^%s]+%* ")
        if botLine then
            if string.find(text, "paused for 30 seconds%.$") then return true end
            if string.find(text, "unpaused%.$") then return true end
        end
    end

    if options.hideBotAttackMessages then
        if SCB_StartsWith(text, "All party bots are now attacking ") then return true end
        if SCB_StartsWith(text, "All party bots have stopped attacking ") then return true end
        if SCB_StartsWith(text, "All party bots are casting AoE spells at") then return true end
        if SCB_StartsWith(text, "All bots are attacking ") or text == "All bots are attacking." then return true end
        if SCB_StartsWith(text, "All bots have stopped attacking ") or text == "All bots have stopped attacking." then return true end
        if SCB_StartsWith(text, "All bots are casting AoE spells at") then return true end
    end

    return false
end

local function SCB_TapTargetedCommandServerMessage(frame, text)
    local now
    if not text or not SCB.targetedCommandState or not SCB_TargetedCommandHandleServerMessage then return end

    -- One server line may be routed to several ChatFrames. Suppress only those
    -- cross-frame copies; a genuine repeated reply during an immediate retry
    -- must still reach the sequencer.
    now = GetTime and GetTime() or 0
    if SCB.targetedAckLastChatText == text
        and SCB.targetedAckLastChatFrame ~= frame
        and SCB.targetedAckLastChatAt
        and (now - SCB.targetedAckLastChatAt) < 0.05 then
        return
    end
    SCB.targetedAckLastChatText = text
    SCB.targetedAckLastChatFrame = frame
    SCB.targetedAckLastChatAt = now
    SCB_TargetedCommandHandleServerMessage(text)
end

local function SCB_FilteredChatFrameAddMessage(frame, text, r, g, b, id)
    SCB_TapTargetedCommandServerMessage(frame, text)
    if SCB_ShouldHideBotChatMessage(text) then return end
    if frame and frame.scbBotChatOriginalAddMessage then
        return frame.scbBotChatOriginalAddMessage(frame, text, r, g, b, id)
    end
end

function SCB_InstallBotChatFilter()
    local i, count, frame
    if SCB.botChatFilterInstalled then return end
    count = NUM_CHAT_WINDOWS or 7
    for i = 1, count do
        frame = getglobal and getglobal("ChatFrame" .. i) or nil
        if frame and frame.AddMessage and not frame.scbBotChatOriginalAddMessage then
            frame.scbBotChatOriginalAddMessage = frame.AddMessage
            frame.AddMessage = SCB_FilteredChatFrameAddMessage
        end
    end
    SCB.botChatFilterInstalled = true
end

-- -------------------------------------------------------------------------
-- Optional role-confirmation option bridge
-- -------------------------------------------------------------------------
-- Detection owns the scanner lifecycle. Options owns the setting/UI and calls
-- the detector explicitly; no later DetectionLifecycle file is needed to wrap
-- Options after load.

if SoloCraftBotsLocale then
    SoloCraftBotsLocale["OPTION_CONFIRM_BOT_ROLES"] = SoloCraftBotsLocale["OPTION_CONFIRM_BOT_ROLES"] or "Confirm bot roles from combat"
    SoloCraftBotsLocale["OPTION_CONFIRM_BOT_ROLES_TIP"] = SoloCraftBotsLocale["OPTION_CONFIRM_BOT_ROLES_TIP"] or "Validate requested bot roles from combat text. Disabled by default for performance."
end

-- -------------------------------------------------------------------------
-- Developer diagnostics (absorbed from Debug.lua in 0.8.33).
-- Scoped to preserve the former file's local namespace.
-- -------------------------------------------------------------------------

do
-- SoloCraft Bots - Debug laboratory
-- Loaded after SoloCraftBots.lua; intentionally behavior-preserving.

local SCB = SoloCraftBots

-- ---------------------------------------------------------------------------
-- Debug laboratory
-- ---------------------------------------------------------------------------

SCB.debug = SCB.debug or {
    lines = {},
    batch = {},
    batchIndex = 1,
    batchElapsed = 0,
    batchRunning = false,
    combatStates = {},
    roster = {},
    petTraces = {},
}

function SCB_DebugTimestamp()
    if GetTime then return string.format("%.3f", GetTime()) end
    return "0.000"
end

function SCB_DebugRefreshLog()
    if not SCB.debugLogEditBox then return end

    local text = table.concat(SCB.debug.lines, "\n")
    local lineCount = table.getn(SCB.debug.lines)
    local height = math.max(250, (lineCount * 14) + 12)

    SCB.debugLogEditBox:SetText(text)
    SCB.debugLogEditBox:SetHeight(height)

    if SCB.debugLogScroll and SCB.debugLogScroll.UpdateScrollChildRect then
        SCB.debugLogScroll:UpdateScrollChildRect()
        SCB.debugLogScroll:SetVerticalScroll(math.max(0, height - SCB.debugLogScroll:GetHeight()))
    end
end

function SCB_DebugLog(kind, text)
    if not SCB.developerDebugEnabled then return end
    if not text then return end
    table.insert(SCB.debug.lines, SCB_DebugTimestamp() .. "  " .. kind .. "  " .. tostring(text))

    while table.getn(SCB.debug.lines) > 2000 do
        table.remove(SCB.debug.lines, 1)
    end

    SCB_DebugRefreshLog()
end

function SCB_DebugClear()
    SCB.debug.lines = {}
    SCB_DebugRefreshLog()
    if SCB.debugLogScroll then
        SCB.debugLogScroll:SetVerticalScroll(0)
    end
    if SCB.debugLogEditBox and SCB.debugLogEditBox.SetCursorPosition then
        SCB.debugLogEditBox:SetCursorPosition(0)
    end
end

function SCB_DebugSelectAll()
    if not SCB.debugLogEditBox then return end
    SCB.debugLogEditBox:SetFocus()
    SCB.debugLogEditBox:HighlightText()
end

function SCB_DebugUnitSummary(unit, subgroup)
    local name = UnitName(unit)
    if not name then return nil end

    local _, class = UnitClass(unit)
    local bot = string.sub(name, -1) == "*"
    local status = UnitIsDeadOrGhost(unit) and SCB_L("DEBUG_DEAD") or SCB_L("DEBUG_ALIVE")
    local combat = UnitAffectingCombat and UnitAffectingCombat(unit) and SCB_L("DEBUG_COMBAT") or SCB_L("DEBUG_CLEAR")

    local result = name .. " [" .. (class or "?") .. "]"
    if subgroup then result = result .. string.format(SCB_L("DEBUG_GROUP_SUFFIX"), subgroup) end
    result = result .. " " .. status .. " " .. combat
    if bot then result = result .. " " .. SCB_L("DEBUG_BOT") else result = result .. " " .. SCB_L("DEBUG_PLAYER") end
    return result
end

function SCB_DebugCollectRoster()
    local roster = {}
    local count, i, name, subgroup, unit

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        count = GetNumRaidMembers()
        for i = 1, count do
            name, _, subgroup = GetRaidRosterInfo(i)
            unit = "raid" .. i
            if name then
                local _, class = UnitClass(unit)
                roster[name] = {
                    summary = SCB_DebugUnitSummary(unit, subgroup) or name,
                    unit = unit,
                    class = class,
                }
            end
        end
    else
        name = UnitName("player")
        if name then
            local _, class = UnitClass("player")
            roster[name] = {
                summary = SCB_DebugUnitSummary("player", nil) or name,
                unit = "player",
                class = class,
            }
        end

        count = GetNumPartyMembers and GetNumPartyMembers() or 0
        for i = 1, count do
            unit = "party" .. i
            name = UnitName(unit)
            if name then
                local _, class = UnitClass(unit)
                roster[name] = {
                    summary = SCB_DebugUnitSummary(unit, nil) or name,
                    unit = unit,
                    class = class,
                }
            end
        end
    end

    return roster
end

function SCB_DebugStartPetTrace(name, class)
    if not name or (class ~= "HUNTER" and class ~= "WARLOCK") then return end
    SCB.debug.petTraces[name] = {
        class = class,
        expires = (GetTime and GetTime() or 0) + 2.5,
        exists = false,
        petName = nil,
        combat = nil,
    }
    if SCB.debugCombatCheck and SCB.debugCombatCheck:GetChecked() then
        SCB_DebugLog(SCB_L("DEBUG_KIND_PET_TRACE"), string.format(SCB_L("DEBUG_PET_TRACE_STARTED"), name, class))
    end
end

function SCB_DebugFindGroupUnitByName(wantedName)
    local i, unit, name
    if not wantedName then return nil end

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            unit = "raid" .. i
            name = UnitName(unit)
            if name == wantedName then return unit end
        end
    else
        if UnitName("player") == wantedName then return "player" end
        local count = GetNumPartyMembers and GetNumPartyMembers() or 0
        for i = 1, count do
            unit = "party" .. i
            name = UnitName(unit)
            if name == wantedName then return unit end
        end
    end
    return nil
end

function SCB_DebugScanPetTraces()
    local now = GetTime and GetTime() or 0
    local ownerName, trace
    for ownerName, trace in pairs(SCB.debug.petTraces) do
        if now > (trace.expires or 0) then
            SCB.debug.petTraces[ownerName] = nil
        else
            local ownerUnit = SCB_DebugFindGroupUnitByName(ownerName)
            if ownerUnit then
                local petUnit = ownerUnit .. "pet"
                local exists = UnitExists and UnitExists(petUnit) and true or false
                local petName = exists and UnitName(petUnit) or nil
                local petCombat = exists and UnitAffectingCombat and UnitAffectingCombat(petUnit) and true or false

                if exists and not trace.exists then
                    SCB_DebugLog(SCB_L("DEBUG_KIND_PET"), string.format(SCB_L("DEBUG_PET_APPEARED"), ownerName, trace.class, petUnit, petName or "?", petCombat and SCB_L("DEBUG_COMBAT") or SCB_L("DEBUG_CLEAR")))
                elseif not exists and trace.exists then
                    SCB_DebugLog(SCB_L("DEBUG_KIND_PET"), string.format(SCB_L("DEBUG_PET_DISAPPEARED"), ownerName, trace.class))
                elseif exists and trace.petName and petName ~= trace.petName then
                    SCB_DebugLog(SCB_L("DEBUG_KIND_PET"), string.format(SCB_L("DEBUG_PET_CHANGED"), ownerName, trace.class, petUnit, trace.petName, petName or "?"))
                end

                if exists and trace.combat ~= nil and petCombat ~= trace.combat then
                    SCB_DebugLog(SCB_L("DEBUG_KIND_PET_COMBAT"), string.format(SCB_L("DEBUG_PET_COMBAT_CHANGED"), ownerName, trace.class, petName or "?", petUnit, petCombat and SCB_L("DEBUG_IN") or SCB_L("DEBUG_OUT")))
                end

                trace.exists = exists
                trace.petName = petName
                trace.combat = exists and petCombat or nil
            end
        end
    end
end

function SCB_DebugRosterChanged()
    if not SCB.developerDebugEnabled then return end
    local current = SCB_DebugCollectRoster()
    local name, data

    if SCB.debugRosterCheck and SCB.debugRosterCheck:GetChecked() then
        for name, data in pairs(current) do
            if not SCB.debug.roster[name] then
                SCB_DebugLog(SCB_L("DEBUG_KIND_ROSTER"), "+ " .. data.summary)
                SCB_DebugStartPetTrace(name, data.class)
            elseif SCB.debug.roster[name].summary ~= data.summary then
                SCB_DebugLog(SCB_L("DEBUG_KIND_ROSTER"), "~ " .. data.summary)
            end
        end

        for name, data in pairs(SCB.debug.roster) do
            if not current[name] then
                SCB_DebugLog(SCB_L("DEBUG_KIND_ROSTER"), "- " .. data.summary)
            end
        end
    end

    SCB.debug.roster = current
end

function SCB_DebugSnapshotRoster()
    local current = SCB_DebugCollectRoster()
    local name, data

    SCB_DebugLog(SCB_L("DEBUG_KIND_ROSTER"), SCB_L("DEBUG_ROSTER_SNAPSHOT"))
    for name, data in pairs(current) do
        SCB_DebugLog(SCB_L("DEBUG_KIND_ROSTER"), data.summary)
    end
    SCB.debug.roster = current
end

function SCB_DebugCollectCombatStates()
    local states = {}
    local count, i

    local function add(unitID)
        local name = UnitName(unitID)
        if not name then return end
        states[name] = UnitAffectingCombat and UnitAffectingCombat(unitID) and true or false
    end

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        count = GetNumRaidMembers()
        for i = 1, count do add("raid" .. i) end
    else
        add("player")
        count = GetNumPartyMembers and GetNumPartyMembers() or 0
        for i = 1, count do add("party" .. i) end
    end

    return states
end

function SCB_DebugPollCombat()
    local current = SCB_DebugCollectCombatStates()
    local name, state

    if SCB.debugCombatCheck and SCB.debugCombatCheck:GetChecked() then
        for name, state in pairs(current) do
            if SCB.debug.combatStates[name] ~= nil and SCB.debug.combatStates[name] ~= state then
                SCB_DebugLog(SCB_L("DEBUG_KIND_COMBAT_POLL"), name .. " -> " .. (state and SCB_L("DEBUG_IN") or SCB_L("DEBUG_OUT")))
            end
        end
    end

    SCB.debug.combatStates = current
end

function SCB_DebugParseBatch()
    local text = SCB.debugInput and SCB.debugInput:GetText() or ""
    local batch = {}
    local line

    for line in string.gfind(text, "[^\r\n]+") do
        line = string.gsub(line, "^%s+", "")
        line = string.gsub(line, "%s+$", "")

        if line ~= "" and string.sub(line, 1, 1) ~= "#" then
            if string.sub(string.lower(line), 1, 10) == ".partybot " then
                line = string.sub(line, 11)
            end
            table.insert(batch, line)
        end
    end

    return batch
end

function SCB_DebugSendLine(line)
    local channel
    if not line or line == "" then return end

    SCB_DebugLog(SCB_L("DEBUG_KIND_SEND"), ".partybot " .. line)
    channel = string.sub(string.lower(line), 1, 4) == "add " and "SAY" or "GUILD"
    if SCB_SendPartyBotCommand then
        SCB_SendPartyBotCommand(line, { channel = channel })
    end
end

function SCB_DebugStartBatch()
    local delay = tonumber(SCB.debugDelay and SCB.debugDelay:GetText() or "") or 0.10

    if delay < 0 then delay = 0 end
    if delay > 5 then delay = 5 end
    if SCB.debugDelay then SCB.debugDelay:SetText(string.format("%.2f", delay)) end

    SCB.debug.batch = SCB_DebugParseBatch()
    SCB.debug.batchIndex = 1
    SCB.debug.batchElapsed = delay
    SCB.debug.batchDelay = delay
    SCB.debug.batchWaitRemaining = nil
    SCB.debug.batchRunning = table.getn(SCB.debug.batch) > 0

    if SCB.debug.batchRunning then
        SCB_DebugLog(SCB_L("DEBUG_KIND_BATCH"), string.format(SCB_L("DEBUG_BATCH_START"), table.getn(SCB.debug.batch), delay))
    else
        SCB_DebugLog(SCB_L("DEBUG_KIND_BATCH"), SCB_L("DEBUG_BATCH_NONE"))
    end
end

function SCB_DebugStopBatch()
    if SCB.debug.batchRunning then
        SCB.debug.batchRunning = false
        SCB_DebugLog(SCB_L("DEBUG_KIND_BATCH"), SCB_L("DEBUG_BATCH_STOPPED"))
    end
end

function SCB_DebugProcessNextBatchLine()
    local line = SCB.debug.batch[SCB.debug.batchIndex]
    if not line then
        SCB.debug.batchRunning = false
        SCB_DebugLog(SCB_L("DEBUG_KIND_BATCH"), SCB_L("DEBUG_BATCH_COMPLETE"))
        return false
    end

    local _, _, waitText = string.find(string.lower(line), "^wait%s+([%d%.]+)$")
    local waitSeconds = waitText and tonumber(waitText) or nil
    if waitSeconds then
        if waitSeconds < 0 then waitSeconds = 0 end
        if waitSeconds > 30 then waitSeconds = 30 end
        SCB.debug.batchIndex = SCB.debug.batchIndex + 1
        SCB.debug.batchWaitRemaining = waitSeconds
        SCB_DebugLog(SCB_L("DEBUG_KIND_BATCH"), string.format(SCB_L("DEBUG_BATCH_WAIT"), waitSeconds))
        return false
    end

    SCB_DebugSendLine(line)
    SCB.debug.batchIndex = SCB.debug.batchIndex + 1
    return true
end

function SCB_DebugOnUpdate()
    if not SCB.developerDebugEnabled then return end
    local elapsed = arg1 or 0

    if SCB.debugCombatCheck and SCB.debugCombatCheck:GetChecked() then
        SCB.debug.combatElapsed = (SCB.debug.combatElapsed or 0) + elapsed
        if SCB.debug.combatElapsed >= 0.25 then
            SCB.debug.combatElapsed = 0
            SCB_DebugPollCombat()
        end
    else
        SCB.debug.combatElapsed = 0
    end

    if SCB.debug.petTraces and next(SCB.debug.petTraces) ~= nil then
        SCB_DebugScanPetTraces()
    end

    if not SCB.debug.batchRunning then return end

    if SCB.debug.batchWaitRemaining then
        SCB.debug.batchWaitRemaining = SCB.debug.batchWaitRemaining - elapsed
        if SCB.debug.batchWaitRemaining > 0 then return end
        SCB.debug.batchWaitRemaining = nil
        SCB.debug.batchElapsed = SCB.debug.batchDelay
        SCB_DebugLog(SCB_L("DEBUG_KIND_BATCH"), SCB_L("DEBUG_BATCH_WAIT_COMPLETE"))
    end

    -- A true 0.00 delay is an intentional stress-test mode: consume commands
    -- in the same frame until a WAIT boundary or the batch ends.
    if SCB.debug.batchDelay <= 0 then
        while SCB.debug.batchRunning and not SCB.debug.batchWaitRemaining do
            if not SCB_DebugProcessNextBatchLine() then break end
        end
        return
    end

    SCB.debug.batchElapsed = SCB.debug.batchElapsed + elapsed
    if SCB.debug.batchElapsed < SCB.debug.batchDelay then return end
    SCB.debug.batchElapsed = 0
    SCB_DebugProcessNextBatchLine()
end

function SCB_DebugMakeCheck(parent, label)
    local check = SCB_CreateMiniCheckButton(parent, 22)
    check:SetWidth(22)
    check:SetHeight(22)
    check:SetChecked(1)

    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", check, "RIGHT", 1, 0)
    text:SetText(label)
    text:SetTextColor(0.9, 0.9, 0.9, 1)

    check.scbLabel = text
    return check
end

function SCB_CreateDebugUI()
    if SCB.debugFrame then return end

    local frame = CreateFrame("Frame", "SoloCraftBotsDebugFrame", UIParent)
    frame:SetWidth(560)
    frame:SetHeight(520)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(60)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    SCB_ButtonBackdrop(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)
    title:SetText(SCB_L("DEBUG_TITLE"))
    title:SetTextColor(1, 0.82, 0, 1)

    local close = SCB_CreateArtButton(frame, nil, 22, SCB.assetRoot .. "lucide_x.tga")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    close.scbTooltip = SCB_L("DEBUG_CLOSE")
    close:SetScript("OnClick", function() frame:Hide() end)
    close:SetScript("OnEnter", SCB_TooltipOnEnter)
    close:SetScript("OnLeave", SCB_TooltipOnLeave)

    local inputLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    inputLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -42)
    inputLabel:SetText(SCB_L("DEBUG_BATCH_COMMANDS"))
    inputLabel:SetTextColor(0.9, 0.9, 0.9, 1)

    local inputScroll = CreateFrame("ScrollFrame", "SoloCraftBotsDebugInputScroll", frame, "UIPanelScrollFrameTemplate")
    inputScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -58)
    inputScroll:SetWidth(512)
    inputScroll:SetHeight(68)
    SCB_ButtonBackdrop(inputScroll)

    local input = CreateFrame("EditBox", nil, inputScroll)
    input:SetWidth(490)
    input:SetHeight(68)
    input:SetMultiLine(true)
    input:SetAutoFocus(false)
    input:SetFontObject(ChatFontNormal)
    input:SetTextInsets(6, 6, 4, 4)
    input:SetMaxLetters(8192)
    input:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    input:SetScript("OnTextChanged", function()
        local _, lines = string.gsub(this:GetText() or "", "\n", "\n")
        local height = math.max(68, ((lines or 0) + 1) * 14 + 10)
        this:SetHeight(height)
        if inputScroll.UpdateScrollChildRect then
            inputScroll:UpdateScrollChildRect()
            inputScroll:SetVerticalScroll(math.max(0, height - inputScroll:GetHeight()))
        end
    end)
    inputScroll:SetScrollChild(input)
    SCB.debugInput = input
    SCB.debugInputScroll = inputScroll

    local delayLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    delayLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -134)
    delayLabel:SetText(SCB_L("DEBUG_DELAY"))
    delayLabel:SetTextColor(0.9, 0.9, 0.9, 1)

    local delay = CreateFrame("EditBox", nil, frame)
    delay:SetWidth(48)
    delay:SetHeight(22)
    delay:SetPoint("LEFT", delayLabel, "RIGHT", 8, 0)
    delay:SetAutoFocus(false)
    delay:SetFontObject(ChatFontNormal)
    delay:SetText("0.10")
    delay:SetJustifyH("CENTER")
    delay:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    SCB_ButtonBackdrop(delay)
    SCB.debugDelay = delay

    local send = SCB_CreateTextButton(frame, nil, 82, 22, SCB_L("DEBUG_SEND_BATCH"))
    send:SetPoint("LEFT", delay, "RIGHT", 8, 0)
    send:SetScript("OnClick", SCB_DebugStartBatch)

    local stop = SCB_CreateTextButton(frame, nil, 48, 22, SCB_L("DEBUG_STOP"))
    stop:SetPoint("LEFT", send, "RIGHT", 6, 0)
    stop:SetScript("OnClick", SCB_DebugStopBatch)

    local snapshot = SCB_CreateTextButton(frame, nil, 92, 22, SCB_L("DEBUG_ROSTER_NOW"))
    snapshot:SetPoint("LEFT", stop, "RIGHT", 6, 0)
    snapshot:SetScript("OnClick", SCB_DebugSnapshotRoster)

    local rosterCheck = SCB_DebugMakeCheck(frame, SCB_L("DEBUG_CHECK_ROSTER"))
    rosterCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -158)
    SCB.debugRosterCheck = rosterCheck

    local combatCheck = SCB_DebugMakeCheck(frame, SCB_L("DEBUG_CHECK_COMBAT"))
    combatCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 100, -158)
    SCB.debugCombatCheck = combatCheck

    local serverCheck = SCB_DebugMakeCheck(frame, SCB_L("DEBUG_CHECK_SERVER"))
    serverCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 188, -158)
    SCB.debugServerCheck = serverCheck

    local logLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    logLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -188)
    logLabel:SetText(SCB_L("DEBUG_RESULT_LOG"))
    logLabel:SetTextColor(0.9, 0.9, 0.9, 1)

    local scroll = CreateFrame("ScrollFrame", "SoloCraftBotsDebugScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -204)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 46)
    SCB_ButtonBackdrop(scroll)
    SCB.debugLogScroll = scroll

    local log = CreateFrame("EditBox", nil, scroll)
    log:SetWidth(500)
    log:SetHeight(250)
    log:SetMultiLine(true)
    log:SetAutoFocus(false)
    log:SetFontObject(ChatFontNormal)
    log:SetTextInsets(5, 5, 5, 5)
    log:SetMaxLetters(200000)
    log:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    scroll:SetScrollChild(log)
    SCB.debugLogEditBox = log

    local selectAll = SCB_CreateTextButton(frame, nil, 74, 22, SCB_L("DEBUG_SELECT_ALL"))
    selectAll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 14)
    selectAll:SetScript("OnClick", SCB_DebugSelectAll)

    local clear = SCB_CreateTextButton(frame, nil, 54, 22, SCB_L("DEBUG_CLEAR_BUTTON"))
    clear:SetPoint("LEFT", selectAll, "RIGHT", 6, 0)
    clear:SetScript("OnClick", SCB_DebugClear)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 18)
    hint:SetText(SCB_L("DEBUG_COPY_HINT"))
    hint:SetTextColor(0.6, 0.6, 0.6, 1)

    frame:SetScript("OnShow", function()
        SCB.debug.roster = SCB_DebugCollectRoster()
        SCB.debug.combatStates = SCB_DebugCollectCombatStates()
        SCB_DebugRefreshLog()
    end)

    frame:Hide()
    SCB.debugFrame = frame

    if UISpecialFrames then
        table.insert(UISpecialFrames, "SoloCraftBotsDebugFrame")
    end
end

function SCB_DebugIsGroupUnit(unit)
    if not unit then return false end
    if unit == "player" or unit == "pet" then return true end
    if string.find(unit, "^party%d+$") or string.find(unit, "^raid%d+$") then return true end
    if string.find(unit, "^party%d+pet$") or string.find(unit, "^raid%d+pet$") then return true end
    return false
end

function SCB_DebugDescribeEventUnit(unit)
    local name = UnitName(unit) or "?"
    local _, class = UnitClass(unit)
    if string.find(unit or "", "pet$") then
        local ownerUnit = string.gsub(unit, "pet$", "")
        local ownerName = UnitName(ownerUnit) or "?"
        local _, ownerClass = UnitClass(ownerUnit)
        return name .. string.format(SCB_L("DEBUG_PET_OWNER"), ownerName, ownerClass or "?") .. " " .. unit
    end
    return name .. " [" .. (class or "?") .. "] " .. unit
end

function SCB_DebugUnitFlags(unit)
    if not SCB.developerDebugEnabled then return end
    if not (SCB.debugCombatCheck and SCB.debugCombatCheck:GetChecked()) then return end
    if not SCB_DebugIsGroupUnit(unit) then return end
    if not UnitName(unit) then return end

    local state = UnitAffectingCombat and UnitAffectingCombat(unit) and true or false
    local name = UnitName(unit)
    local oldState = SCB.debug.combatStates[name]
    if oldState ~= nil and oldState ~= state then
        SCB_DebugLog(SCB_L("DEBUG_KIND_COMBAT_EVENT"), SCB_DebugDescribeEventUnit(unit) .. " -> " .. (state and SCB_L("DEBUG_IN") or SCB_L("DEBUG_OUT")))
    end
    SCB.debug.combatStates[name] = state
end

function SCB_DebugUnitCombat(unit, action, critical, amount, damageType)
    if not SCB.developerDebugEnabled then return end
    if not (SCB.debugCombatCheck and SCB.debugCombatCheck:GetChecked()) then return end
    if not SCB_DebugIsGroupUnit(unit) then return end
    if not UnitName(unit) then return end

    local parts = { SCB_DebugDescribeEventUnit(unit) }
    if action ~= nil then table.insert(parts, tostring(action)) end
    if critical ~= nil then table.insert(parts, "crit=" .. tostring(critical)) end
    if amount ~= nil then table.insert(parts, "amount=" .. tostring(amount)) end
    if damageType ~= nil then table.insert(parts, "type=" .. tostring(damageType)) end
    SCB_DebugLog(SCB_L("DEBUG_KIND_UNIT_COMBAT"), table.concat(parts, " "))
end

function SCB_DebugToggle()
    if not SCB.debugFrame then SCB_CreateDebugUI() end

    if SCB.debugFrame:IsShown() then
        SCB.debugFrame:Hide()
    else
        SCB.debugFrame:Show()
        SCB.debugFrame:Raise()
    end
end

local debugUpdateFrame = CreateFrame("Frame", "SoloCraftBotsDebugUpdateFrame", UIParent)
debugUpdateFrame:SetScript("OnUpdate", SCB_DebugOnUpdate)
debugUpdateFrame:Hide()

function SCB_UpdateDebugTimerState()
    if SCB.developerDebugEnabled then
        debugUpdateFrame:Show()
    else
        debugUpdateFrame:Hide()
    end
end
end
