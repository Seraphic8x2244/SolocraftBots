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
    if not this or not this.scbLootMethod then return end
    SCB_EnsureOptionsDB()
    SoloCraftBotsDB.options.autoLootMethod = this.scbLootMethod
    SCB_RefreshAutoLootSelector()
    if SCB.optionAutoLootMenu then SCB.optionAutoLootMenu:Hide() end
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
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -46)
    label:SetWidth(72)
    label:SetJustifyH("LEFT")
    label:SetText(SCB_L("OPTION_AUTO_LOOT", "Auto Loot"))
    label:SetTextColor(0.90, 0.90, 0.90, 1)
    SCB.optionAutoLootLabel = label

    selector = SCB_CreateTextButton(parent, "SoloCraftBotsAutoLootSelector", 118, 22, "Off")
    selector:SetPoint("LEFT", label, "RIGHT", 2, 0)
    selector.label:ClearAllPoints()
    selector.label:SetPoint("LEFT", selector, "LEFT", 7, 0)
    selector.label:SetPoint("RIGHT", selector, "RIGHT", -22, 0)
    selector.label:SetJustifyH("LEFT")
    selector:SetScript("OnClick", SCB_AutoLootSelectorOnClick)
    SCB.optionAutoLootSelector = selector

    arrow = selector:CreateTexture(nil, "ARTWORK")
    arrow:SetWidth(18)
    arrow:SetHeight(18)
    arrow:SetPoint("RIGHT", selector, "RIGHT", -2, 0)
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")

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
    if not this or not this.scbOptionKey then return end
    SCB_EnsureOptionsDB()
    SoloCraftBotsDB.options[this.scbOptionKey] = this:GetChecked() and true or false
end

function SCB_CreateOptionCheck(parent, key, labelKey, y)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetWidth(24)
    check:SetHeight(24)
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
    check.scbOptionKey = key
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetText(SCB_L(labelKey))
    label:SetTextColor(0.90, 0.90, 0.90, 1)
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
    local shown, r, i, row, frame
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
    value = (target[valueKey] or 0) + delta
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    target[valueKey] = value
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
    label:SetTextColor(0.82, 0.82, 0.82, 1)

    minus = SCB_CreateTextButton(parent, nil, 22, 20, "-")
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
    value:SetTextColor(1, 0.82, 0, 1)

    plus = SCB_CreateTextButton(parent, nil, 22, 20, "+")
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

    if SCB.developerDebugEnabled then
        SCB_Print(SCB_L("DEBUG_MODE_ENABLED", "Debug mode enabled."))
    else
        SCB_Print(SCB_L("DEBUG_MODE_DISABLED", "Debug mode disabled."))
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
    local toggle, title, debugCheck, debugLabel, content
    section:SetWidth(parent:GetWidth())
    section.scbExpanded = false
    section.scbCollapsedHeight = 26
    section.scbExpandedHeight = expandedHeight

    toggle = SCB_CreateArrowButton(section, 18)
    toggle:SetPoint("TOPLEFT", section, "TOPLEFT", 12, -3)
    toggle.scbOptionsSection = section
    toggle:SetScript("OnClick", SCB_OptionsSubsectionToggleOnClick)
    section.scbToggle = toggle

    title = section:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", section, "TOPLEFT", 36, -5)
    title:SetText(SCB_L(labelKey))
    title:SetTextColor(0.82, 0.82, 0.82, 1)
    section.scbTitle = title

    debugCheck = CreateFrame("CheckButton", nil, section, "UICheckButtonTemplate")
    debugCheck:SetWidth(20)
    debugCheck:SetHeight(20)
    debugCheck:SetPoint("TOPRIGHT", section, "TOPRIGHT", -10, -2)
    debugCheck.scbLayoutSection = sectionKey
    debugCheck:SetScript("OnClick", SCB_OptionsDebugOnClick)
    section.scbDebugCheck = debugCheck

    debugLabel = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    debugLabel:SetPoint("RIGHT", debugCheck, "LEFT", -2, 0)
    debugLabel:SetText(SCB_L("OPTION_DEBUG"))
    debugLabel:SetTextColor(0.65, 0.65, 0.65, 1)
    section.scbDebugLabel = debugLabel

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
        SCB_SetArrowDirection(section.scbToggle.scbArrowTexture, "down")
        section.scbContent:Show()
    else
        SCB_SetArrowDirection(section.scbToggle.scbArrowTexture, "right")
        section.scbContent:Hide()
    end
end

function SCB_LayoutOptionsUI()
    local y, commandHeight, presetHeight, panelHeight
    if not SCB.optionsPanel then return end
    y = -162
    if SCB.optionCommandSection then
        commandHeight = SCB.optionCommandSection.scbExpanded and SCB.optionCommandSection.scbExpandedHeight or SCB.optionCommandSection.scbCollapsedHeight
        SCB.optionCommandSection:ClearAllPoints()
        SCB.optionCommandSection:SetPoint("TOPLEFT", SCB.optionsPanel, "TOPLEFT", 0, y)
        SCB.optionCommandSection:SetHeight(commandHeight)
        SCB_RefreshOptionsSectionArrow(SCB.optionCommandSection)
        y = y - commandHeight
    end
    if SCB.optionPresetSection then
        presetHeight = SCB.optionPresetSection.scbExpanded and SCB.optionPresetSection.scbExpandedHeight or SCB.optionPresetSection.scbCollapsedHeight
        SCB.optionPresetSection:ClearAllPoints()
        SCB.optionPresetSection:SetPoint("TOPLEFT", SCB.optionsPanel, "TOPLEFT", 0, y)
        SCB.optionPresetSection:SetHeight(presetHeight)
        SCB_RefreshOptionsSectionArrow(SCB.optionPresetSection)
        y = y - presetHeight
    end
    panelHeight = (-y) + 38
    if panelHeight < 280 then panelHeight = 280 end
    SCB.optionsPanel:SetHeight(panelHeight)
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
    if SCB.optionSafetyCheck then SCB.optionSafetyCheck:SetChecked(options.showSafetyMessages and 1 or nil) end
    SCB.optionsDebugMode = SCB.optionsDebugMode or { command = false, preset = false }
    if SCB.optionCommandSection and SCB.optionCommandSection.scbDebugCheck then
        SCB.optionCommandSection.scbDebugCheck:SetChecked(SCB.optionsDebugMode.command and 1 or nil)
    end
    if SCB.optionPresetSection and SCB.optionPresetSection.scbDebugCheck then
        SCB.optionPresetSection.scbDebugCheck:SetChecked(SCB.optionsDebugMode.preset and 1 or nil)
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
        control.value:SetText(target[valueKey] or 0)
    end
end

function SCB_SetOptionsPanelShown(show)
    if not SCB.optionsPanel then return end
    if show then
        SCB_RefreshOptionsUI()
        SCB_LayoutOptionsUI()
        SCB.optionsPanel:ClearAllPoints()
        SCB.optionsPanel:SetPoint("TOPLEFT", SCB.frame, "TOPRIGHT", 2, 0)
        SCB.optionsPanel:Show()
    else
        SCB.optionsPanel:Hide()
    end
end

function SCB_ConfigOnClick()
    if not SCB.optionsPanel then return end
    SCB_SetOptionsPanelShown(not SCB.optionsPanel:IsShown())
end

function SCB_CreateOptionsUI(frame)
    local panel = CreateFrame("Frame", "SoloCraftBotsOptionsPanel", UIParent)
    local heading, resetTutorials, layoutHeading, commandContent, presetContent, sublabel, control
    panel:SetWidth(230)
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
    heading:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
    heading:SetText(SCB_L("OPTIONS_TITLE"))
    heading:SetTextColor(1, 0.82, 0, 1)

    SCB_CreateAutoLootOption(panel)
    SCB.optionSafetyCheck = SCB_CreateOptionCheck(panel, "showSafetyMessages", "OPTION_SAFETY_MESSAGES", -70)

    resetTutorials = SCB_CreateTextButton(panel, nil, 112, 22, SCB_L("RESET_TUTORIALS", "Reset tutorials"))
    resetTutorials:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -99)
    resetTutorials:SetScript("OnClick", SCB_ResetTutorialsOnClick)

    layoutHeading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    layoutHeading:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -132)
    layoutHeading:SetText(SCB_L("OPTIONS_LAYOUT_TITLE", "Layout"))
    layoutHeading:SetTextColor(1, 0.82, 0, 1)
    SCB.optionLayoutHeading = layoutHeading

    SCB.optionCommandSection = SCB_CreateOptionsSubsection(panel, "command", "OPTION_COMMAND_BUTTONS", 104)
    commandContent = SCB.optionCommandSection.scbContent
    control = SCB_CreateLayoutControl(commandContent, "command", "horizontalSpacing", "OPTION_COMMAND_H_SPACING", -2, -10, 10, -10, 10); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(commandContent, "command", "verticalSpacing", "OPTION_COMMAND_V_SPACING", -28, -10, 10, -10, 10); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(commandContent, "command", "groupVerticalSpacing", "OPTION_COMMAND_GROUP_SPACING", -54, -10, 10, -10, 10); table.insert(SCB.optionLayoutControls, control)

    SCB.optionPresetSection = SCB_CreateOptionsSubsection(panel, "preset", "OPTION_PRESET_GROUPS", 286)
    presetContent = SCB.optionPresetSection.scbContent
    control = SCB_CreateLayoutControl(presetContent, "preset", "groupWidth", "OPTION_GROUP_WIDTH", -2, 60, 160, -30, 30); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(presetContent, "preset", "groupHeight", "OPTION_GROUP_HEIGHT", -26, 100, 240, -50, 50); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(presetContent, "preset", "roleSize", "OPTION_ROLE_SIZE", -54, 12, 40, -12, 12); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(presetContent, "preset", "classSize", "OPTION_CLASS_SIZE", -78, 12, 40, -12, 12); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(presetContent, "preset", "buffSize", "OPTION_BUFF_SIZE", -102, 12, 40, -12, 12); table.insert(SCB.optionLayoutControls, control)

    sublabel = presetContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sublabel:SetPoint("TOPLEFT", presetContent, "TOPLEFT", 16, -130)
    sublabel:SetText(SCB_L("OPTION_BORDER_OFFSET"))
    sublabel:SetTextColor(1, 0.82, 0, 1)
    control = SCB_CreateLayoutControl(presetContent, "preset", "borderHorizontal", "OPTION_HORIZONTAL", -150, -10, 30, -20, 20); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(presetContent, "preset", "borderVertical", "OPTION_VERTICAL", -174, -10, 30, -20, 20); table.insert(SCB.optionLayoutControls, control)

    sublabel = presetContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sublabel:SetPoint("TOPLEFT", presetContent, "TOPLEFT", 16, -202)
    sublabel:SetText(SCB_L("OPTION_ICON_SPACING"))
    sublabel:SetTextColor(1, 0.82, 0, 1)
    control = SCB_CreateLayoutControl(presetContent, "preset", "iconHorizontal", "OPTION_HORIZONTAL", -222, -10, 20, -20, 20); table.insert(SCB.optionLayoutControls, control)
    control = SCB_CreateLayoutControl(presetContent, "preset", "iconVertical", "OPTION_VERTICAL", -246, -10, 30, -20, 20); table.insert(SCB.optionLayoutControls, control)

    SCB.optionVersion = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    SCB.optionVersion:SetText(SCB_L("VERSION_LABEL") .. ": " .. SCB.version)
    SCB.optionVersion:SetTextColor(0.6, 0.6, 0.6, 1)

    SCB_RefreshOptionsUI()
    SCB_LayoutOptionsUI()
    panel:Hide()
end
