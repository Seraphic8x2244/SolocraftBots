-- SoloCraft Bots
-- Clean-sheet SoloCraft PartyBot controller for WoW 1.12.1.
-- Version is sourced from SoloCraftBots.toc.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots
local T = SoloCraftBotsLocale or {}
function SCB_L(key, fallback)
    return T[key] or fallback or key
end

-- SavedVariables are loaded before addon Lua files. Initialize the table
-- defensively here as well as during login so startup does not depend on the
-- addon folder name matching an ADDON_LOADED string literal.
SoloCraftBotsDB = SoloCraftBotsDB or {}
SoloCraftBotsCharDB = SoloCraftBotsCharDB or {}
SoloCraftBotsCharDB.helpers = SoloCraftBotsCharDB.helpers or {}

SCB.version = (GetAddOnMetadata and GetAddOnMetadata("SoloCraftBots", "Version")) or SCB_L("UNKNOWN")
SCB.prefix = SCB_L("CHAT_PREFIX")
SCB.assetRoot = "Interface\\AddOns\\SoloCraftBots\\artwork\\"
SCB.commandButtons = {}
SCB.presetSlotButtons = {}
SCB.presetMenuButtons = {}
SCB.presetEditorSlots = {}
SCB.presetEditorPlayers = {}
SCB.presetPlayerFrames = {}
SCB.presetPlayerPoolButtons = {}
SCB.presetSlotRows = {}
SCB.presetDropTargets = {}
SCB.draggedPresetPlayer = nil
SCB.draggedPresetPlayerOriginSlot = nil
SCB.pendingBotAdds = 0
SCB.pendingBotAddsExpires = 0
SCB.presetSpawnQueue = {}
SCB.presetSpawnElapsed = 0
SCB.presetSpawnInterval = 0.10
SCB.presetGroupWaitRemaining = 0
SCB.presetCombatRetryWaitRemaining = 0
SCB.presetCombatRetryFailures = 0
SCB.presetCombatRetryResetPending = nil
SCB.initialSessionValidationPending = false
SCB.activeRosterReconcilePending = true
SCB.lastRoster = nil
SCB.refillState = nil

BINDING_HEADER_SOLOCRAFTBOTS = SCB_L("BINDING_HEADER")
BINDING_NAME_SOLOCRAFTBOTS_TOGGLE = SCB_L("BINDING_TOGGLE")

function SCB_Print(text)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(SCB.prefix .. text)
    end
end

function SCB_SendCommand(command)
    if not command or command == "" then
        return
    end
    -- Control commands use party chat so they can still be issued while dead.
    -- Bot spawning is intentionally handled separately and always uses SAY.
    SendChatMessage(".partybot " .. command, "PARTY")
end

function SCB_QueueDelayedCommand(command, delay)
    local frame
    if not command or command == "" then return end

    frame = SCB.delayedCommandFrame
    if not frame then
        frame = CreateFrame("Frame", "SoloCraftBotsDelayedCommandFrame", UIParent)
        frame:Hide()
        frame:SetScript("OnUpdate", function()
            local queued
            this.scbElapsed = (this.scbElapsed or 0) + (arg1 or 0)
            if this.scbElapsed < (this.scbDelay or 0) then return end
            queued = this.scbCommand
            this.scbCommand = nil
            this.scbDelay = nil
            this.scbElapsed = 0
            this:Hide()
            if queued then SCB_SendCommand(queued) end
        end)
        SCB.delayedCommandFrame = frame
    end

    -- Do not restart an already-pending command when a macro is spammed; the
    -- first press still fires after its original delay instead of being pushed
    -- back indefinitely.
    if frame.scbCommand then return end
    frame.scbCommand = command
    frame.scbDelay = delay or 0.25
    frame.scbElapsed = 0
    frame:Show()
end

function SCB_ButtonBackdrop(button)
    button:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    button:SetBackdropColor(0.04, 0.04, 0.04, 0.90)
    button:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
end

function SCB_CreateTextButton(parent, name, width, height, text, allowRightClick)
    local button = CreateFrame("Button", name, parent)
    button:SetWidth(width)
    button:SetHeight(height)
    button:EnableMouse(true)
    if allowRightClick then
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    else
        button:RegisterForClicks("LeftButtonUp")
    end
    SCB_ButtonBackdrop(button)

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(1, 1, 1, 1)
    button.label = label

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    highlight:SetTexture(1, 1, 1, 0.12)
    return button
end

function SCB_CreateArtButton(parent, name, size, texturePath, allowRightClick, highlightTexturePath)
    local button = CreateFrame("Button", name, parent)
    button:SetWidth(size)
    button:SetHeight(size)
    button:EnableMouse(true)
    if allowRightClick then
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    else
        button:RegisterForClicks("LeftButtonUp")
    end

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexture(texturePath)
    button.icon = icon

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    if highlightTexturePath then
        highlight:SetTexture(highlightTexturePath)
        highlight:SetBlendMode("BLEND")
        highlight:SetAlpha(1)
    else
        highlight:SetTexture(texturePath)
        highlight:SetBlendMode("ADD")
        highlight:SetAlpha(0.22)
    end
    button.highlight = highlight
    button.scbNormalTexture = texturePath
    button.scbHighlightTexture = highlightTexturePath

    return button
end

function SCB_SetArtButtonTexture(button, texturePath, highlightTexturePath)
    if not button or not button.icon then
        return
    end
    button.scbNormalTexture = texturePath
    button.scbHighlightTexture = highlightTexturePath
    button.icon:SetTexture(texturePath)
    if button.highlight then
        button.highlight:SetTexture(highlightTexturePath or texturePath)
        if highlightTexturePath then
            button.highlight:SetBlendMode("BLEND")
            button.highlight:SetAlpha(1)
        else
            button.highlight:SetBlendMode("ADD")
            button.highlight:SetAlpha(0.22)
        end
    end
end

function SCB_SetArtButtonAvailable(button, available)
    if not button or not button.icon then
        return
    end
    button.scbAvailable = available
    if available then
        button.icon:SetVertexColor(1, 1, 1, 1)
        button:SetAlpha(1)
    else
        button.icon:SetVertexColor(0.45, 0.45, 0.45, 1)
        button:SetAlpha(1)
    end
end

function SCB_TooltipOnEnter()
    if not this or not this.scbTooltip then
        return
    end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(this.scbTooltip, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

function SCB_TooltipOnLeave()
    GameTooltip:Hide()
end

function SCB_RefreshVisibleTooltip(button)
    if not button or not button.scbTooltip or not GameTooltip or not GameTooltip.IsOwned then return end
    if GameTooltip:IsOwned(button) then
        GameTooltip:SetText(button.scbTooltip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end
end

function SCB_CreateSectionTitle(parent, text, x, y)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    title:SetText(text)
    title:SetTextColor(0.82, 0.82, 0.82, 1)
    return title
end

local SCB_ARROW_TEXTURE = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"

function SCB_SetArrowDirection(texture, direction)
    if not texture then return end
    texture:SetTexture(SCB_ARROW_TEXTURE)
    if direction == "left" then
        texture:SetTexCoord(0, 1, 0, 1)
    elseif direction == "right" then
        texture:SetTexCoord(1, 0, 0, 1)
    elseif direction == "down" then
        texture:SetTexCoord(1, 1, 0, 1, 1, 0, 0, 0)
    else -- up
        texture:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
    end
end

function SCB_CreateArrowButton(parent, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(size or 18)
    button:SetHeight(size or 18)
    local texture = button:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(button)
    button.scbArrowTexture = texture
    return button
end

SCB.sections = SCB.sections or {}
SCB.sectionOrder = { "commands", "assignments", "summon" }
local SCB_LayoutSections

function SCB_EnsureSectionDB()
    SoloCraftBotsDB.sections = SoloCraftBotsDB.sections or {}
end

SCB.commandLayoutDefaults = SCB.commandLayoutDefaults or {
    horizontalSpacing = -3,
    verticalSpacing = -1,
    groupVerticalSpacing = 8,
}
SCB.presetLayoutDefaults = SCB.presetLayoutDefaults or {
    groupWidth = 85,
    groupHeight = 154,
    roleSize = 20,
    classSize = 25,
    buffSize = 20,
    borderHorizontal = 4,
    borderVertical = 6,
    iconHorizontal = 0,
    iconVertical = 2,
}

function SCB_EnsureOptionsDB()
    local options, key
    SoloCraftBotsDB.options = SoloCraftBotsDB.options or {}
    options = SoloCraftBotsDB.options
    if options.autoLootMethod == nil then options.autoLootMethod = "off" end
    if options.showSafetyMessages == nil then options.showSafetyMessages = true end
    if options.hideBotSummonMessage == nil then options.hideBotSummonMessage = false end
    if options.hideBotGroupMessages == nil then options.hideBotGroupMessages = false end
    if options.hideBotMovementMessages == nil then options.hideBotMovementMessages = false end
    if options.hideBotPauseMessages == nil then options.hideBotPauseMessages = false end
    if options.hideBotAttackMessages == nil then options.hideBotAttackMessages = false end
    if options.autoSwapPresetGroup == nil then options.autoSwapPresetGroup = false end

    -- Debug layout values are the raw internal baseline.  Seed command values
    -- from the old spacing settings so existing test profiles keep their exact
    -- geometry when this layout editor first appears.
    options.commandLayoutDebug = options.commandLayoutDebug or {}
    if options.commandLayoutDebug.horizontalSpacing == nil then
        options.commandLayoutDebug.horizontalSpacing = options.commandHorizontalSpacing
        if options.commandLayoutDebug.horizontalSpacing == nil then options.commandLayoutDebug.horizontalSpacing = SCB.commandLayoutDefaults.horizontalSpacing end
    end
    if options.commandLayoutDebug.verticalSpacing == nil then
        options.commandLayoutDebug.verticalSpacing = options.commandVerticalSpacing
        if options.commandLayoutDebug.verticalSpacing == nil then options.commandLayoutDebug.verticalSpacing = SCB.commandLayoutDefaults.verticalSpacing end
    end
    if options.commandLayoutDebug.groupVerticalSpacing == nil then
        options.commandLayoutDebug.groupVerticalSpacing = options.commandGroupVerticalSpacing
        if options.commandLayoutDebug.groupVerticalSpacing == nil then options.commandLayoutDebug.groupVerticalSpacing = SCB.commandLayoutDefaults.groupVerticalSpacing end
    end
    options.commandLayoutUser = options.commandLayoutUser or {}
    for key in pairs(SCB.commandLayoutDefaults) do
        if options.commandLayoutUser[key] == nil then options.commandLayoutUser[key] = 0 end
    end

    options.presetLayoutDebug = options.presetLayoutDebug or {}
    options.presetLayoutUser = options.presetLayoutUser or {}
    for key in pairs(SCB.presetLayoutDefaults) do
        if options.presetLayoutDebug[key] == nil then options.presetLayoutDebug[key] = SCB.presetLayoutDefaults[key] end
        if options.presetLayoutUser[key] == nil then options.presetLayoutUser[key] = 0 end
    end

    -- 0.4.25 promotes the visually-tuned debug geometry to the shipped
    -- baseline. Only untouched 0.4.24 baseline values are migrated; any raw
    -- value already changed in Debug mode is respected.
    if not options.layoutBaselineVersion or options.layoutBaselineVersion < 425 then
        if options.commandLayoutDebug.horizontalSpacing == 3 then options.commandLayoutDebug.horizontalSpacing = -3 end
        if options.commandLayoutDebug.verticalSpacing == 0 then options.commandLayoutDebug.verticalSpacing = -1 end
        if options.commandLayoutDebug.groupVerticalSpacing == 6 then options.commandLayoutDebug.groupVerticalSpacing = 8 end
        if options.presetLayoutDebug.groupWidth == 92 then options.presetLayoutDebug.groupWidth = 85 end
        if options.presetLayoutDebug.groupHeight == 158 then options.presetLayoutDebug.groupHeight = 154 end
        if options.presetLayoutDebug.roleSize == 24 then options.presetLayoutDebug.roleSize = 20 end
        if options.presetLayoutDebug.classSize == 24 then options.presetLayoutDebug.classSize = 25 end
        if options.presetLayoutDebug.buffSize == 24 then options.presetLayoutDebug.buffSize = 20 end
        if options.presetLayoutDebug.borderHorizontal == 4 then options.presetLayoutDebug.borderHorizontal = 4 end
        if options.presetLayoutDebug.borderVertical == 8 then options.presetLayoutDebug.borderVertical = 6 end
        if options.presetLayoutDebug.iconHorizontal == 0 then options.presetLayoutDebug.iconHorizontal = 0 end
        if options.presetLayoutDebug.iconVertical == 3 then options.presetLayoutDebug.iconVertical = 2 end
        options.layoutBaselineVersion = 425
    end
end

function SCB_GetLayoutValue(sectionKey, valueKey)
    local options, baseline, user
    SCB_EnsureOptionsDB()
    options = SoloCraftBotsDB.options
    if sectionKey == "command" then
        baseline = options.commandLayoutDebug[valueKey] or 0
        user = options.commandLayoutUser[valueKey] or 0
    else
        baseline = options.presetLayoutDebug[valueKey] or 0
        user = options.presetLayoutUser[valueKey] or 0
    end
    -- Debug mode deliberately shows the raw baseline without personal offsets.
    if SCB.optionsDebugMode and SCB.optionsDebugMode[sectionKey] then return baseline end
    return baseline + user
end

function SCB_SectionToggleOnClick()
    if not this or not this.scbSectionKey then
        return
    end
    SCB_EnsureSectionDB()
    SoloCraftBotsDB.sections[this.scbSectionKey] = not SoloCraftBotsDB.sections[this.scbSectionKey]
    if SCB_LayoutSections then
        SCB_LayoutSections()
    end
end

function SCB_CreateCollapsibleSection(parent, key, titleText, contentHeight)
    local section = CreateFrame("Frame", nil, parent)
    section:SetWidth(parent:GetWidth())
    section:SetHeight(26 + contentHeight)
    section.scbKey = key
    section.scbExpandedHeight = 26 + contentHeight
    section.scbCollapsedHeight = 26

    local toggle = SCB_CreateArrowButton(section, 18)
    toggle:SetPoint("TOPLEFT", section, "TOPLEFT", 12, -3)
    toggle.scbSectionKey = key
    toggle.scbTooltip = string.format(SCB_L("TIP_COLLAPSE_EXPAND"), titleText)
    toggle:SetScript("OnClick", SCB_SectionToggleOnClick)
    toggle:SetScript("OnEnter", SCB_TooltipOnEnter)
    toggle:SetScript("OnLeave", SCB_TooltipOnLeave)
    section.scbToggle = toggle

    section.scbTitle = SCB_CreateSectionTitle(section, titleText, 36, -4)

    local content = CreateFrame("Frame", nil, section)
    content:SetWidth(parent:GetWidth())
    content:SetHeight(contentHeight)
    content:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -26)
    section.scbContent = content

    SCB.sections[key] = section
    return section, content
end

function SCB_GetPlayerFaction()
    local faction
    if UnitFactionGroup then
        faction = UnitFactionGroup("player")
        if faction == "Alliance" or faction == "Horde" then
            return faction
        end
    end

    if UnitRace then
        local race = UnitRace("player")
        if race == "Human" or race == "Dwarf" or race == "Night Elf" or race == "Gnome" then
            return "Alliance"
        elseif race == "Orc" or race == "Undead" or race == "Tauren" or race == "Troll" then
            return "Horde"
        end
    end
    return nil
end

SCB.PALADIN_BLESSINGS = {
    { key = "BoK", label = SCB_L("BLESSING_KINGS"), texture = "Interface\\Icons\\Spell_Magic_GreaterBlessingofKings" },
    { key = "BoM", label = SCB_L("BLESSING_MIGHT"), texture = "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings" },
    { key = "BoS", label = SCB_L("BLESSING_SALVATION"), texture = "Interface\\Icons\\Spell_Holy_GreaterBlessingofSalvation" },
    { key = "BoW", label = SCB_L("BLESSING_WISDOM"), texture = "Interface\\Icons\\Spell_Holy_GreaterBlessingofWisdom" },
    { key = "BoL", label = SCB_L("BLESSING_LIGHT"), texture = "Interface\\Icons\\Spell_Holy_GreaterBlessingofLight" },
}

function SCB_FindPaladinBlessing(key)
    local i
    for i = 1, table.getn(SCB.PALADIN_BLESSINGS) do
        if SCB.PALADIN_BLESSINGS[i].key == key then
            return SCB.PALADIN_BLESSINGS[i], i
        end
    end
    return SCB.PALADIN_BLESSINGS[1], 1
end

SCB.SHAMAN_TOTEMS = {
    air = {
        { key = "windfury", label = SCB_L("TOTEM_WINDFURY"), texture = "Interface\\Icons\\Spell_Nature_Windfury" },
        { key = "graceofair", label = SCB_L("TOTEM_GRACE_OF_AIR"), texture = "Interface\\Icons\\Spell_Nature_InvisibilityTotem" },
        { key = "tranquilair", label = SCB_L("TOTEM_TRANQUIL_AIR"), texture = "Interface\\Icons\\Spell_Nature_Brilliance" },
        { key = "natureresistance", label = SCB_L("TOTEM_NATURE_RESISTANCE"), texture = "Interface\\Icons\\Spell_Nature_NatureResistanceTotem" },
    },
    earth = {
        { key = "strengthofearth", label = SCB_L("TOTEM_STRENGTH_OF_EARTH"), texture = "Interface\\Icons\\Spell_Nature_EarthBindTotem" },
        { key = "stoneskin", label = SCB_L("TOTEM_STONESKIN"), texture = "Interface\\Icons\\Spell_Nature_StoneSkinTotem" },
        { key = "earthbind", label = SCB_L("TOTEM_EARTHBIND"), texture = "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02" },
        { key = "tremor", label = SCB_L("TOTEM_TREMOR"), texture = "Interface\\Icons\\Spell_Nature_TremorTotem" },
    },
    fire = {
        { key = "searing", label = SCB_L("TOTEM_SEARING"), texture = "Interface\\Icons\\Spell_Fire_SearingTotem" },
        { key = "magma", label = SCB_L("TOTEM_MAGMA"), texture = "Interface\\Icons\\Spell_Fire_SelfDestruct" },
        { key = "firenova", label = SCB_L("TOTEM_FIRE_NOVA"), texture = "Interface\\Icons\\Spell_Fire_SealOfFire" },
        { key = "flametongue", label = SCB_L("TOTEM_FLAMETONGUE"), texture = "Interface\\Icons\\Spell_Nature_GuardianWard" },
        { key = "frostresistance", label = SCB_L("TOTEM_FROST_RESISTANCE"), texture = "Interface\\Icons\\Spell_FrostResistanceTotem_01" },
    },
    water = {
        { key = "manaspring", label = SCB_L("TOTEM_MANA_SPRING"), texture = "Interface\\Icons\\Spell_Nature_ManaRegenTotem" },
        { key = "healingstream", label = SCB_L("TOTEM_HEALING_STREAM"), texture = "Interface\\Icons\\INV_Spear_04" },
        { key = "poisoncleansing", label = SCB_L("TOTEM_POISON_CLEANSING"), texture = "Interface\\Icons\\Spell_Nature_PoisonCleansingTotem" },
        { key = "diseasecleansing", label = SCB_L("TOTEM_DISEASE_CLEANSING"), texture = "Interface\\Icons\\Spell_Nature_DiseaseCleansingTotem" },
        { key = "fireresistance", label = SCB_L("TOTEM_FIRE_RESISTANCE"), texture = "Interface\\Icons\\Spell_FireResistanceTotem_01" },
        { key = "manatide", label = SCB_L("TOTEM_MANA_TIDE"), texture = "Interface\\Icons\\Spell_Frost_SummonWaterElemental" },
    },
}

SCB.SHAMAN_TOTEM_ORDER = { "air", "earth", "fire", "water" }
SCB.DEFAULT_SHAMAN_TOTEMS = "windfury strengthofearth searing poisoncleansing"

function SCB_ParseShamanTotems(extra)
    local result = {}
    local i, key, value
    if extra and extra ~= "" then
        i = 1
        for value in string.gfind(extra, "%S+") do
            key = SCB.SHAMAN_TOTEM_ORDER[i]
            if not key then break end
            result[key] = value
            i = i + 1
        end
    end

    local defaults = { air = "windfury", earth = "strengthofearth", fire = "searing", water = "poisoncleansing" }
    for i = 1, table.getn(SCB.SHAMAN_TOTEM_ORDER) do
        key = SCB.SHAMAN_TOTEM_ORDER[i]
        if not result[key] then result[key] = defaults[key] end
    end
    return result
end

function SCB_FindShamanTotem(groupKey, totemKey)
    local list = SCB.SHAMAN_TOTEMS[groupKey]
    local i
    if not list then return nil, 1 end
    for i = 1, table.getn(list) do
        if list[i].key == totemKey then return list[i], i end
    end
    return list[1], 1
end

function SCB_BuildShamanTotemExtra(totems)
    return (totems.air or "windfury") .. " "
        .. (totems.earth or "strengthofearth") .. " "
        .. (totems.fire or "searing") .. " "
        .. (totems.water or "poisoncleansing")
end

SCB.classes = {
    {
        key = "warrior", name = SCB_L("CLASS_WARRIOR"), icon = "warrior.tga",
        roles = {
            { role = "meleedps", label = SCB_L("ROLE_MELEE"), icon = "melee.tga" },
            { role = "tank", label = SCB_L("ROLE_TANK"), icon = "tank.tga" },
        },
    },
    {
        key = "rogue", name = SCB_L("CLASS_ROGUE"), icon = "rogue.tga",
        roles = {
            { role = "meleedps", label = SCB_L("ROLE_MELEE"), icon = "melee.tga" },
        },
    },
    {
        key = "paladin", name = SCB_L("CLASS_PALADIN"), faction = "Alliance", icon = "paladin.tga",
        roles = {
            { role = "healer", label = SCB_L("ROLE_HEALER"), icon = "healer.tga" },
            { role = "meleedps", label = SCB_L("ROLE_MELEE"), icon = "melee.tga" },
            { role = "tank", label = SCB_L("ROLE_TANK"), icon = "tank.tga" },
        },
    },
    {
        key = "shaman", name = SCB_L("CLASS_SHAMAN"), faction = "Horde", icon = "shaman.tga",
        roles = {
            { role = "healer", label = SCB_L("ROLE_HEALER"), icon = "healer.tga" },
            { role = "meleedps", label = SCB_L("ROLE_MELEE"), icon = "melee.tga" },
            { role = "rangedps", label = SCB_L("ROLE_RANGED"), icon = "ranged.tga" },
            { role = "tank", label = SCB_L("ROLE_TANK"), icon = "tank.tga" },
        },
    },
    {
        key = "hunter", name = SCB_L("CLASS_HUNTER"), icon = "hunter.tga",
        roles = {
            { role = "rangedps", label = SCB_L("ROLE_RANGED"), icon = "ranged.tga" },
        },
    },
    {
        key = "druid", name = SCB_L("CLASS_DRUID"), icon = "druid.tga",
        roles = {
            { role = "tank", label = SCB_L("ROLE_TANK"), icon = "tank.tga" },
            { role = "meleedps", label = SCB_L("ROLE_MELEE"), icon = "melee.tga" },
            { role = "healer", label = SCB_L("ROLE_HEALER"), icon = "healer.tga" },
            { role = "rangedps", label = SCB_L("ROLE_RANGED"), icon = "ranged.tga" },
        },
    },
    {
        key = "priest", name = SCB_L("CLASS_PRIEST"), icon = "priest.tga",
        roles = {
            { role = "healer", label = SCB_L("ROLE_HEALER"), icon = "healer.tga" },
            { role = "rangedps", label = SCB_L("ROLE_RANGED"), icon = "ranged.tga" },
        },
    },
    {
        key = "mage", name = SCB_L("CLASS_MAGE"), icon = "mage.tga",
        roles = {
            { role = "rangedps", label = SCB_L("ROLE_FIRE"), texture = "Interface\\Icons\\Spell_Fire_FlameBolt", extra = "fire" },
            { role = "rangedps", label = SCB_L("ROLE_FROST"), texture = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
        },
    },
    {
        key = "warlock", name = SCB_L("CLASS_WARLOCK"), icon = "warlock.tga",
        roles = {
            { role = "rangedps", label = SCB_L("ROLE_RANGED"), icon = "ranged.tga" },
        },
    },
}

function SCB_GetVisibleClasses()
    local visible = {}
    local faction = SCB_GetPlayerFaction()
    local i, classInfo
    for i = 1, table.getn(SCB.classes) do
        classInfo = SCB.classes[i]
        if not classInfo.faction or classInfo.faction == faction then
            table.insert(visible, classInfo)
        end
    end
    return visible
end

function SCB_FindClass(classKey)
    local i
    for i = 1, table.getn(SCB.classes) do
        if SCB.classes[i].key == classKey then
            return SCB.classes[i]
        end
    end
    return nil
end

function SCB_GetPlayerClassInfo()
    if not UnitClass then
        return nil
    end
    local localized, classToken = UnitClass("player")
    local key = classToken or localized
    if key then
        key = string.lower(key)
        return SCB_FindClass(key)
    end
    return nil
end

function SCB_FindRoleEntry(classInfo, role, extra)
    local i, entry
    if not classInfo then
        return nil, nil
    end

    for i = 1, table.getn(classInfo.roles) do
        entry = classInfo.roles[i]
        if entry.role == role and entry.extra == extra then
            return entry, i
        end
    end
    for i = 1, table.getn(classInfo.roles) do
        entry = classInfo.roles[i]
        if entry.role == role then
            return entry, i
        end
    end
    return classInfo.roles[1], 1
end

function SCB_RoleTexture(roleInfo)
    if not roleInfo then
        return nil
    end
    if roleInfo.texture then
        return roleInfo.texture
    end
    return SCB.assetRoot .. roleInfo.icon
end

function SCB_RoleHighlightTexture(roleInfo)
    if not roleInfo or roleInfo.texture or not roleInfo.icon then
        return nil
    end
    return SCB.assetRoot .. string.gsub(roleInfo.icon, "%.tga$", "_h.tga")
end

-- -------------------------------------------------------------------------
-- Spawning
-- -------------------------------------------------------------------------

function SCB_BuildSpawnCommand(classKey, role, extra)
    local command = "add " .. classKey .. " " .. role
    if classKey == "paladin" then
        if not UnitLevel or UnitLevel("player") ~= 60 then
            extra = nil
        elseif not extra or extra == "" then
            extra = "BoK"
        end
    elseif classKey == "shaman" and (not extra or extra == "") then
        extra = SCB.DEFAULT_SHAMAN_TOTEMS
    end
    if extra and extra ~= "" then
        command = command .. " " .. extra
    end
    return command
end

function SCB_IsValidSpawnAssignment(classKey, role, extra)
    local classInfo = SCB_FindClass(classKey)
    local i, entry, blessing, values, value, groupKey, totem
    if not classInfo or not role then return false end

    if extra == "" then extra = nil end

    if classKey == "paladin" then
        local roleValid = false
        for i = 1, table.getn(classInfo.roles) do
            if classInfo.roles[i].role == role then roleValid = true break end
        end
        if not roleValid then return false end
        if not extra then return true end
        blessing = SCB_FindPaladinBlessing(extra)
        return blessing and blessing.key == extra
    end

    if classKey == "shaman" then
        local roleValid = false
        for i = 1, table.getn(classInfo.roles) do
            if classInfo.roles[i].role == role then roleValid = true break end
        end
        if not roleValid then return false end
        if not extra then return true end
        values = {}
        for value in string.gfind(extra, "%S+") do table.insert(values, value) end
        if table.getn(values) ~= 4 then return false end
        for i = 1, table.getn(SCB.SHAMAN_TOTEM_ORDER) do
            groupKey = SCB.SHAMAN_TOTEM_ORDER[i]
            totem = SCB_FindShamanTotem(groupKey, values[i])
            if not totem or totem.key ~= values[i] then return false end
        end
        return true
    end

    -- For all other classes, role + spec extra must exactly match one of the
    -- class definitions. This also validates Mage Fire/Frost without accepting
    -- arbitrary text that could later reach .partybot chat commands.
    for i = 1, table.getn(classInfo.roles) do
        entry = classInfo.roles[i]
        if entry.role == role and entry.extra == extra then return true end
    end
    return false
end

function SCB_SendSpawnCommand(command)
    if not command or command == "" then
        return
    end
    SCB_RegisterSpawnIntent()
    SendChatMessage(".partybot " .. command, "SAY")
end

function SCB_RefreshMainPaladinBlessingButton()
    local button = SCB.mainPaladinBlessingButton
    local blessing
    local available
    if not button then return end

    blessing = SCB_FindPaladinBlessing(SCB.mainPaladinBlessing or "BoK")
    SCB.mainPaladinBlessing = blessing.key
    SCB_SetArtButtonTexture(button, blessing.texture, nil)
    available = UnitLevel and UnitLevel("player") == 60
    SCB_SetArtButtonAvailable(button, available)
    if available then
        button.scbTooltip = SCB_L("TIP_PALADIN_BLESSING")
        button.scbTooltip = string.gsub(button.scbTooltip, "%%s", blessing.label)
    else
        button.scbTooltip = SCB_L("TIP_PALADIN_BLESSING_LEVEL")
    end
    SCB_RefreshVisibleTooltip(SCB.mainPaladinBlessingButton)
end

function SCB_MainPaladinBlessingOnClick()
    local blessing, currentIndex, newIndex
    if not UnitLevel or UnitLevel("player") ~= 60 then
        SCB_RefreshMainPaladinBlessingButton()
        return
    end
    blessing, currentIndex = SCB_FindPaladinBlessing(SCB.mainPaladinBlessing or "BoK")
    if arg1 == "RightButton" then
        newIndex = currentIndex - 1
        if newIndex < 1 then newIndex = table.getn(SCB.PALADIN_BLESSINGS) end
    else
        newIndex = currentIndex + 1
        if newIndex > table.getn(SCB.PALADIN_BLESSINGS) then newIndex = 1 end
    end
    SCB.mainPaladinBlessing = SCB.PALADIN_BLESSINGS[newIndex].key
    SCB_RefreshMainPaladinBlessingButton()
end

function SCB_SpawnOnClick()
    local extra
    if not this.scbClass or not this.scbRole then
        return
    end
    extra = this.scbExtra
    if this.scbClass == "paladin" then
        extra = SCB.mainPaladinBlessing or "BoK"
    end
    if SCB_AllowActiveRosterAdoption then SCB_AllowActiveRosterAdoption() end
    SCB_SendSpawnCommand(SCB_BuildSpawnCommand(this.scbClass, this.scbRole, extra))
end

function SCB_DistanceOnClick()
    SCB_EnsureSessionDB()
    if SoloCraftBotsDB.session.state.distance == "far" then
        SCB_SendCommand("distance off")
        SoloCraftBotsDB.session.state.distance = "near"
    else
        SCB_SendCommand("distance on")
        SoloCraftBotsDB.session.state.distance = "far"
    end
    SCB_RefreshDistanceButtons()
end

-- Preset subsystem is defined in Presets.lua.

-- -------------------------------------------------------------------------
-- Escape / top-level visibility
-- -------------------------------------------------------------------------

function SCB_SetEscapeProxyShown(show)
    if not SCB.escapeProxy then
        return
    end
    if show then
        SCB.escapeProxy:Show()
    elseif SCB.escapeProxy:IsShown() then
        SCB.ignoreEscapeProxyHide = true
        SCB.escapeProxy:Hide()
        SCB.ignoreEscapeProxyHide = false
    end
end

function SCB_ProcessEscapeProxyHide()
    if not SCB.frame or not SCB.frame:IsShown() then
        return
    end

    -- Blizzard hides UISpecialFrames as part of losing player control too.
    -- PLAYER_CONTROL_LOST can arrive after the proxy's OnHide, so this check
    -- deliberately runs one frame later rather than interpreting OnHide itself
    -- as Escape.
    if SCB.playerControlLost then
        SCB_SetEscapeProxyShown(true)
        return
    end

    -- Side drawers close before the main SCB frame.
    if SCB.optionsPanel and SCB.optionsPanel:IsShown() then
        SCB_SetOptionsPanelShown(false)
        SCB_SetEscapeProxyShown(true)
        return
    end
    if SCB.presetPanel and SCB.presetPanel:IsShown() then
        SCB_SetPresetPanelShown(false)
        SCB_SetEscapeProxyShown(true)
        return
    end

    SCB.frame:Hide()
end

function SCB_EscapeProxyOnHide()
    if SCB.ignoreEscapeProxyHide then
        return
    end
    if not SCB.frame or not SCB.frame:IsShown() then
        return
    end

    if not SCB.escapeHideDeferred then
        SCB.escapeHideDeferred = CreateFrame("Frame")
        SCB.escapeHideDeferred:Hide()
        SCB.escapeHideDeferred:SetScript("OnUpdate", function()
            this:Hide()
            SCB_ProcessEscapeProxyHide()
        end)
    end
    SCB.escapeHideDeferred:Show()
end

function SCB_MainFrameOnShow()
    SCB_SetEscapeProxyShown(true)
end

function SCB_MainFrameOnHide()
    SCB_SetPresetPanelShown(false, true)
    SCB_SetOptionsPanelShown(false)
    SCB_SetEscapeProxyShown(false)
end

-- -------------------------------------------------------------------------
-- Frame position / top-level UI
-- -------------------------------------------------------------------------

function SCB_SavePosition()
    if not SoloCraftBotsDB or not SCB.frame then
        return
    end
    local point, relativeTo, relativePoint, x, y = SCB.frame:GetPoint()
    SoloCraftBotsDB.point = point or "CENTER"
    SoloCraftBotsDB.relativePoint = relativePoint or point or "CENTER"
    SoloCraftBotsDB.x = x or 0
    SoloCraftBotsDB.y = y or 0
end

function SCB_RestorePosition()
    if not SCB.frame then
        return
    end
    SCB.frame:ClearAllPoints()
    if SoloCraftBotsDB and SoloCraftBotsDB.point then
        SCB.frame:SetPoint(
            SoloCraftBotsDB.point,
            UIParent,
            SoloCraftBotsDB.relativePoint or SoloCraftBotsDB.point,
            SoloCraftBotsDB.x or 0,
            SoloCraftBotsDB.y or 0
        )
    else
        SCB.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function SCB_FrameDragStart()
    this:StartMoving()
end

function SCB_FrameDragStop()
    this:StopMovingOrSizing()
    SCB_SavePosition()
end

function SCB_CloseOnClick()
    if SCB.frame then
        SCB.frame:Hide()
    end
end

function SCB_CreateSummonUI(frame)
    local section, content = SCB_CreateCollapsibleSection(frame, "summon", SCB_L("SECTION_SUMMON"), 196)

    -- One state button: silver binoculars = Spawn Near (distance off, default),
    -- gold binoculars = Spawn Far (distance on).
    local distance = SCB_CreateArtButton(section, "SoloCraftBotsDistanceToggle", 22, SCB.assetRoot .. "distance_off.tga")
    distance:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, -2)
    distance:SetScript("OnClick", SCB_DistanceOnClick)
    distance:SetScript("OnEnter", SCB_TooltipOnEnter)
    distance:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.distanceButton = distance

    local visibleClasses = SCB_GetVisibleClasses()
    local gridLeft = 16
    local gridTop = -4
    local cellWidth = 56
    local cellHeight = 94
    local classSize = 42
    local roleSize = 18
    local roleGap = 3
    local i, j, classInfo, roleInfo, row, col
    local cellX, cellY, classFrame, classTexture, roleButton, roleTexture, roleHighlightTexture
    local roleCount, roleRow, roleCol, rolesThisRow, rowStartX, roleX, roleY

    for i = 1, table.getn(visibleClasses) do
        classInfo = visibleClasses[i]
        row = math.floor((i - 1) / 4)
        col = math.mod(i - 1, 4)
        cellX = gridLeft + (col * cellWidth)
        cellY = gridTop - (row * cellHeight)

        classFrame = CreateFrame("Frame", nil, content)
        classFrame:SetWidth(classSize)
        classFrame:SetHeight(classSize)
        classFrame:SetPoint("TOPLEFT", content, "TOPLEFT", cellX + ((cellWidth - classSize) / 2), cellY)
        classFrame:EnableMouse(true)
        classFrame.scbTooltip = classInfo.name
        classFrame:SetScript("OnEnter", SCB_TooltipOnEnter)
        classFrame:SetScript("OnLeave", SCB_TooltipOnLeave)

        classTexture = classFrame:CreateTexture(nil, "ARTWORK")
        classTexture:SetAllPoints(classFrame)
        classTexture:SetTexture(SCB.assetRoot .. classInfo.icon)

        if classInfo.key == "paladin" then
            local blessingButton = SCB_CreateArtButton(content, "SoloCraftBotsMainPaladinBlessing", roleSize, SCB.PALADIN_BLESSINGS[1].texture, true)
            blessingButton:SetPoint("TOPLEFT", classFrame, "TOPLEFT", -2, 2)
            blessingButton:SetFrameLevel(classFrame:GetFrameLevel() + 2)
            blessingButton:SetScript("OnClick", SCB_MainPaladinBlessingOnClick)
            blessingButton:SetScript("OnEnter", SCB_TooltipOnEnter)
            blessingButton:SetScript("OnLeave", SCB_TooltipOnLeave)
            SCB.mainPaladinBlessingButton = blessingButton
            if not SCB.mainPaladinBlessing then SCB.mainPaladinBlessing = "BoK" end
            SCB_RefreshMainPaladinBlessingButton()
        end

        roleCount = table.getn(classInfo.roles)
        for j = 1, roleCount do
            roleInfo = classInfo.roles[j]
            roleRow = math.floor((j - 1) / 2)
            roleCol = math.mod(j - 1, 2)

            if roleRow == 0 then
                rolesThisRow = math.min(roleCount, 2)
            else
                rolesThisRow = roleCount - 2
            end

            rowStartX = cellX + ((cellWidth - ((rolesThisRow * roleSize) + ((rolesThisRow - 1) * roleGap))) / 2)
            roleX = rowStartX + (roleCol * (roleSize + roleGap))
            roleY = cellY - classSize - 5 - (roleRow * (roleSize + roleGap))

            roleTexture = SCB_RoleTexture(roleInfo)
            roleHighlightTexture = SCB_RoleHighlightTexture(roleInfo)
            roleButton = SCB_CreateArtButton(content, nil, roleSize, roleTexture, nil, roleHighlightTexture)
            roleButton:SetPoint("TOPLEFT", content, "TOPLEFT", roleX, roleY)
            roleButton.scbClass = classInfo.key
            roleButton.scbRole = roleInfo.role
            roleButton.scbExtra = roleInfo.extra
            roleButton.scbTooltip = string.format(SCB_L("TIP_SPAWN_ROLE"), classInfo.name, roleInfo.label)
            roleButton:SetScript("OnClick", SCB_SpawnOnClick)
            roleButton:SetScript("OnEnter", SCB_TooltipOnEnter)
            roleButton:SetScript("OnLeave", SCB_TooltipOnLeave)
        end
    end
end

function SCB_LayoutCommandUI()
    local layout = SCB.commandLayout
    local options, gap, rowGap, groupGap, buttonSize, maxColumns, maxRowWidth, left, y
    local r, i, row, button, standaloneWidth, standaloneLeft
    if not layout or not layout.content then return end

    SCB_EnsureOptionsDB()
    options = SoloCraftBotsDB.options
    gap = SCB_GetLayoutValue("command", "horizontalSpacing")
    rowGap = SCB_GetLayoutValue("command", "verticalSpacing")
    groupGap = SCB_GetLayoutValue("command", "groupVerticalSpacing")
    buttonSize = layout.buttonSize or 36
    maxColumns = 5
    maxRowWidth = (maxColumns * buttonSize) + ((maxColumns - 1) * gap)
    left = math.floor((SCB.frame:GetWidth() - maxRowWidth) / 2)
    y = -2

    for r = 1, table.getn(layout.rows) do
        row = layout.rows[r]
        if row.gapBefore then y = y - groupGap end

        row.layoutY = y
        row.recipientButton:ClearAllPoints()
        row.recipientButton:SetPoint("TOPLEFT", layout.content, "TOPLEFT", left, y)

        for i = 1, table.getn(row.commandButtons) do
            button = row.commandButtons[i]
            button:ClearAllPoints()
            button:SetPoint(
                "TOPLEFT", layout.content, "TOPLEFT",
                left + ((i + (row.indent or 0)) * (buttonSize + gap)), y
            )
        end
        y = y - buttonSize - rowGap
    end

    -- The three paired Come controls deliberately do not create rows. They sit
    -- in the otherwise-empty second column, centred vertically between the
    -- role rows they address, to show that each button targets two roles.
    for i = 1, table.getn(layout.pairedComeButtons or {}) do
        local pair = layout.pairedComeButtons[i]
        local upperRow = layout.rows[pair.upperRow]
        local lowerRow = layout.rows[pair.lowerRow]
        if pair.button and upperRow and lowerRow then
            local pairY = (upperRow.layoutY + lowerRow.layoutY) / 2
            pair.button:ClearAllPoints()
            pair.button:SetPoint("TOPLEFT", layout.content, "TOPLEFT", left + buttonSize + gap, pairY)
        end
    end

    y = y - groupGap
    -- Standalone command row is visually grouped as:
    -- AOE | Attack Start + Attack Stop | Use Object.
    -- Use the existing Group Spacing value for the two larger separators so
    -- this row stays aligned with the user's command-layout tuning.
    standaloneWidth = (4 * buttonSize) + gap + (2 * groupGap)
    standaloneLeft = math.floor((SCB.frame:GetWidth() - standaloneWidth) / 2)
    local standaloneX = standaloneLeft
    for i = 1, table.getn(layout.standaloneButtons) do
        button = layout.standaloneButtons[i]
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", layout.content, "TOPLEFT", standaloneX, y)
        standaloneX = standaloneX + buttonSize
        if i == 1 or i == 3 then
            standaloneX = standaloneX + groupGap
        elseif i < table.getn(layout.standaloneButtons) then
            standaloneX = standaloneX + gap
        end
    end

    y = y - buttonSize - 6
    -- Explicit maintenance actions: Replace Dead preserves the tracked preset
    -- assignment, while Kick All is the manual safe-clear action.
    local utilityWidth = 96
    local utilityGap = 6
    local utilityTotal = (2 * utilityWidth) + utilityGap
    local utilityLeft = math.floor((SCB.frame:GetWidth() - utilityTotal) / 2)

    layout.replaceDead:ClearAllPoints()
    layout.replaceDead:SetWidth(utilityWidth)
    layout.replaceDead:SetPoint("TOPLEFT", layout.content, "TOPLEFT", utilityLeft, y)
    layout.kickAll:ClearAllPoints()
    layout.kickAll:SetWidth(utilityWidth)
    layout.kickAll:SetPoint("LEFT", layout.replaceDead, "RIGHT", utilityGap, 0)

    -- Positive spacing can make the command block taller than its original
    -- fixed content area. Grow the section only when needed; negative spacing
    -- can compact the controls without leaving the following section misplaced.
    local neededHeight = math.max(310, (-y) + 28)
    if layout.content:GetHeight() ~= neededHeight then
        layout.content:SetHeight(neededHeight)
        layout.section.scbExpandedHeight = 26 + neededHeight
        if SoloCraftBotsDB.sections.commands ~= true then
            layout.section:SetHeight(layout.section.scbExpandedHeight)
        end
        if SCB_LayoutSections then SCB_LayoutSections() end
    end
    SCB_UpdateLayoutDebugBorders()
end

function SCB_CreateCommandUI(frame)
    local section, content = SCB_CreateCollapsibleSection(frame, "commands", SCB_L("SECTION_COMMANDS"), 310)
    local buttonSize = 36
    SCB.targetCommandButtons = {}
    local rows = {
        { recipient = "all", indent = 0, commands = { "play", "move", "stay", "pause" } },
        { recipient = "target", indent = 0, commands = { "play", "move", "stay", "pause" } },
        { gapBefore = true, recipient = "tank", indent = 1, commands = { "move", "stay", "pull" } },
        { recipient = "melee", indent = 1, commands = { "move", "stay" } },
        { recipient = "ranged", indent = 1, commands = { "move", "stay", "spreadtoggle" } },
        { recipient = "healer", indent = 1, commands = { "move", "stay" } },
    }
    local recipientByKey = {}
    local layoutRows = {}
    local pairedComeButtons = {}
    local standaloneButtons = {}
    local i, r, row, recipient, commandKey, commandInfo, button, layoutRow, comeRecipientLabel

    for i = 1, table.getn(SCB.recipients) do
        recipientByKey[SCB.recipients[i].key] = SCB.recipients[i]
    end

    for r = 1, table.getn(rows) do
        row = rows[r]
        recipient = recipientByKey[row.recipient]
        layoutRow = { indent = row.indent or 0, gapBefore = row.gapBefore, commandButtons = {} }

        button = SCB_CreateArtButton(
            content, nil, buttonSize,
            SCB.assetRoot .. recipient.icon,
            nil,
            SCB.assetRoot .. recipient.highlightIcon
        )
        button.scbCommandKey = "come"
        button.scbRecipientKey = row.recipient
        button.scbRecipientLabel = recipient.label
        comeRecipientLabel = row.recipient == "target" and SCB_L("RECIPIENT_TARGET") or recipient.label
        button.scbTooltip = string.format(SCB_L("TIP_COME_RECIPIENT"), comeRecipientLabel, comeRecipientLabel)
        button:SetScript("OnClick", SCB_DirectCommandOnClick)
        button:SetScript("OnEnter", SCB_TooltipOnEnter)
        button:SetScript("OnLeave", SCB_TooltipOnLeave)
        layoutRow.recipientButton = button
        if row.recipient == "target" then
            table.insert(SCB.targetCommandButtons, button)
        end

        for i = 1, table.getn(row.commands) do
            commandKey = row.commands[i]
            commandInfo = SCB.commands[commandKey]
            button = SCB_CreateArtButton(
                content, nil, buttonSize,
                SCB.assetRoot .. commandInfo.icon,
                nil,
                SCB.assetRoot .. commandInfo.highlightIcon
            )
            button.scbCommandKey = commandKey
            button.scbRecipientKey = row.recipient
            button.scbRecipientLabel = recipient.label
            button.scbTooltip = string.format(SCB_L("COMMAND_TOOLTIP"), recipient.label, commandInfo.label)
            if commandKey == "spreadtoggle" then
                SCB.spreadToggleButton = button
                SCB_RefreshSpreadToggle(button)
                button:SetScript("OnClick", SCB_SpreadToggleOnClick)
            else
                button:SetScript("OnClick", SCB_DirectCommandOnClick)
            end
            button:SetScript("OnEnter", SCB_TooltipOnEnter)
            button:SetScript("OnLeave", SCB_TooltipOnLeave)
            table.insert(layoutRow.commandButtons, button)
            if row.recipient == "target" then
                table.insert(SCB.targetCommandButtons, button)
            end
        end
        table.insert(layoutRows, layoutRow)
    end

    local pairDefs = {
        { key = "tankmelee", upperRow = 3, lowerRow = 4, tooltipKey = "TIP_COME_TANK_MELEE" },
        { key = "meleeranged", upperRow = 4, lowerRow = 5, tooltipKey = "TIP_COME_MELEE_RANGED" },
        { key = "rangedhealer", upperRow = 5, lowerRow = 6, tooltipKey = "TIP_COME_RANGED_HEALER" },
    }
    for i = 1, table.getn(pairDefs) do
        local pair = pairDefs[i]
        button = SCB_CreateArtButton(
            content, nil, buttonSize,
            SCB.assetRoot .. SCB.commands.come.icon,
            nil,
            SCB.assetRoot .. SCB.commands.come.highlightIcon
        )
        button.scbCommandKey = "come"
        button.scbRecipientKey = pair.key
        button.scbRecipientLabel = pair.key
        button.scbTooltip = SCB_L(pair.tooltipKey)
        button:SetScript("OnClick", SCB_DirectCommandOnClick)
        button:SetScript("OnEnter", SCB_TooltipOnEnter)
        button:SetScript("OnLeave", SCB_TooltipOnLeave)
        table.insert(pairedComeButtons, {
            button = button,
            upperRow = pair.upperRow,
            lowerRow = pair.lowerRow,
        })
    end

    local standalone = { "aoe", "attackstart", "attackstop", "object" }
    for i = 1, table.getn(standalone) do
        commandKey = standalone[i]
        commandInfo = SCB.commands[commandKey]
        button = SCB_CreateArtButton(
            content, nil, buttonSize,
            SCB.assetRoot .. commandInfo.icon,
            nil,
            SCB.assetRoot .. commandInfo.highlightIcon
        )
        button.scbCommandKey = commandKey
        button.scbRecipientKey = "all"
        button.scbRecipientLabel = SCB_L("RECIPIENT_ALL")
        button.scbTooltip = string.format(SCB_L("COMMAND_TOOLTIP_ALL"), commandInfo.label, SCB_L("RECIPIENT_ALL"))
        button:SetScript("OnClick", SCB_DirectCommandOnClick)
        button:SetScript("OnEnter", SCB_TooltipOnEnter)
        button:SetScript("OnLeave", SCB_TooltipOnLeave)
        table.insert(standaloneButtons, button)
    end

    -- One maintenance button changes meaning from live Active Roster state:
    -- Dead-only -> Replace Dead; any absent expected bot -> Replace Missing.
    local replaceDead = SCB_CreateTextButton(content, "SoloCraftBotsReplaceDead", 96, 24, SCB_L("REPLACE_DEAD"))
    replaceDead.scbTooltip = SCB_L("REPLACE_DEAD_NONE")
    replaceDead:SetScript("OnClick", SCB_MaintenanceReplaceOnClick)
    replaceDead:SetScript("OnEnter", SCB_TooltipOnEnter)
    replaceDead:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.replaceDeadButton = replaceDead
    SCB_SetPresetButtonGrey(replaceDead)

    local kickAll = SCB_CreateTextButton(content, "SoloCraftBotsKickAll", 96, 24, SCB_L("KICK_ALL"))
    kickAll.scbTooltip = SCB_L("TIP_KICK_ALL")
    kickAll:SetScript("OnClick", SCB_KickAllOnClick)
    kickAll:SetScript("OnEnter", SCB_TooltipOnEnter)
    kickAll:SetScript("OnLeave", SCB_TooltipOnLeave)

    SCB.commandLayout = {
        section = section,
        content = content,
        buttonSize = buttonSize,
        rows = layoutRows,
        pairedComeButtons = pairedComeButtons,
        standaloneButtons = standaloneButtons,
        replaceDead = replaceDead,
        kickAll = kickAll,
    }
    SCB_LayoutCommandUI()
    SCB_RefreshTargetCommandRow()
end

function SCB_CreateRaidmarkUI(frame)
    local section, content = SCB_CreateCollapsibleSection(frame, "assignments", SCB_L("SECTION_ASSIGNMENTS"), 34)
    local toggleSize = 18

    -- One always-highlighted state button. Focus is the default; clicking it
    -- swaps between Focus and CC assignment modes.
    local clearMarks = SCB_CreateArtButton(section, nil, toggleSize, SCB.assetRoot .. "bin.tga")
    clearMarks:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, -2)
    clearMarks.scbTooltip = SCB_L("TIP_CLEAR_MARKS")
    clearMarks:SetScript("OnClick", function() SendChatMessage(".partybot clearmarks", "PARTY") end)
    clearMarks:SetScript("OnEnter", SCB_TooltipOnEnter)
    clearMarks:SetScript("OnLeave", SCB_TooltipOnLeave)

    local mode = SCB_CreateArtButton(section, nil, toggleSize, SCB.assetRoot .. "focus_h.tga")
    mode:SetPoint("RIGHT", clearMarks, "LEFT", -4, 0)
    mode:SetScript("OnClick", SCB_RaidmarkModeOnClick)
    mode:SetScript("OnEnter", SCB_TooltipOnEnter)
    mode:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.assignmentModeButton = mode

    SCB.raidMarkMode = "focus"
    SCB_RefreshRaidmarkModeButton()

    local markSize = 24
    local gap = 2
    local totalWidth = (8 * markSize) + (7 * gap)
    local left = math.floor((frame:GetWidth() - totalWidth) / 2)
    local y = -4
    local i, mark, button

    for i = 1, table.getn(SCB.raidMarks) do
        mark = SCB.raidMarks[i]
        button = SCB_CreateArtButton(content, nil, markSize, SCB.assetRoot .. mark.key .. ".tga")
        button:SetPoint("TOPLEFT", content, "TOPLEFT", left + ((i - 1) * (markSize + gap)), y)
        button.scbMark = mark.key
        button.scbTooltip = string.format(SCB_L("TIP_RAID_MARK"), mark.name)
        button:SetScript("OnClick", SCB_RaidMarkOnClick)
        button:SetScript("OnEnter", SCB_TooltipOnEnter)
        button:SetScript("OnLeave", SCB_TooltipOnLeave)
    end
end

-- Preset panel construction is defined in Presets.lua.

SCB_LayoutSections = function()
    if not SCB.frame then
        return
    end
    SCB_EnsureSectionDB()

    local y = -64
    local sectionGap = 4
    local i, key, section, collapsed

    for i = 1, table.getn(SCB.sectionOrder) do
        key = SCB.sectionOrder[i]
        section = SCB.sections[key]
        if section then
            collapsed = SoloCraftBotsDB.sections[key] == true
            section:ClearAllPoints()
            section:SetPoint("TOPLEFT", SCB.frame, "TOPLEFT", 0, y)

            if collapsed then
                section:SetHeight(section.scbCollapsedHeight)
                section.scbContent:Hide()
                SCB_SetArrowDirection(section.scbToggle.scbArrowTexture, "down")
            else
                section:SetHeight(section.scbExpandedHeight)
                section.scbContent:Show()
                SCB_SetArrowDirection(section.scbToggle.scbArrowTexture, "up")
            end

            y = y - section:GetHeight() - sectionGap
        end
    end

    SCB.frame:SetHeight((-y) + 8)
end

function SCB_CreateUI()
    local frame = CreateFrame("Frame", "SoloCraftBotsFrame", UIParent)
    SCB.frame = frame
    frame:SetWidth(256)
    frame:SetHeight(640)
    frame:SetFrameLevel(20)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 24,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.96)
    frame:SetScript("OnDragStart", SCB_FrameDragStart)
    frame:SetScript("OnDragStop", SCB_FrameDragStop)
    frame:SetScript("OnShow", SCB_MainFrameOnShow)
    frame:SetScript("OnHide", SCB_MainFrameOnHide)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -13)
    title:SetText(SCB_L("ADDON_TITLE") .. (string.find(SCB.version or "", "%-dev$") and SCB_L("DEV_SUFFIX") or ""))

    local close = SCB_CreateArtButton(frame, "SoloCraftBotsCloseButton", 18, SCB.assetRoot .. "close.tga")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -9)
    close.scbTooltip = SCB_L("TIP_CLOSE")
    close:SetScript("OnClick", SCB_CloseOnClick)
    close:SetScript("OnEnter", SCB_TooltipOnEnter)
    close:SetScript("OnLeave", SCB_TooltipOnLeave)

    local config = SCB_CreateArtButton(frame, "SoloCraftBotsConfigButton", 18, SCB.assetRoot .. "config.tga")
    config:SetPoint("RIGHT", close, "LEFT", -2, 0)
    config.scbTooltip = SCB_L("TIP_CONFIG")
    config:SetScript("OnClick", SCB_ConfigOnClick)
    config:SetScript("OnEnter", SCB_TooltipOnEnter)
    config:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.configButton = config

    SCB.rangedSpreadOn = false
    SCB_CreateCommandUI(frame)
    SCB_CreateRaidmarkUI(frame)
    SCB_CreateSummonUI(frame)
    SCB_CreatePresetUI(frame)
    SCB_CreateOptionsUI(frame)
    SCB_LayoutSections()

    local safety = CreateFrame("Frame", "SoloCraftBotsSafetyMessage", UIParent)
    safety:SetWidth(520)
    safety:SetHeight(40)
    safety:SetPoint("CENTER", UIParent, "CENTER", 0, 110)
    safety:SetFrameStrata("DIALOG")
    safety:EnableMouse(false)
    local safetyText = safety:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    safetyText:SetPoint("CENTER", safety, "CENTER", 0, 0)
    safetyText:SetText(SCB_L("SURVIVOR_MESSAGE"))
    safetyText:SetTextColor(1, 0.82, 0, 1)
    safety.text = safetyText
    safety:Hide()
    SCB.safetyMessageFrame = safety

    local escapeProxy = CreateFrame("Frame", "SoloCraftBotsEscapeFrame", UIParent)
    escapeProxy:SetWidth(1)
    escapeProxy:SetHeight(1)
    escapeProxy:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
    escapeProxy:SetScript("OnHide", SCB_EscapeProxyOnHide)
    escapeProxy:Hide()
    SCB.escapeProxy = escapeProxy
    table.insert(UISpecialFrames, "SoloCraftBotsEscapeFrame")

    SCB.presetSpawnQueueFrame = CreateFrame("Frame", "SoloCraftBotsPresetSpawnQueueFrame", UIParent)
    SCB.presetSpawnQueueFrame:SetScript("OnUpdate", SCB_PresetSpawnQueueOnUpdate)

    SCB_RestorePosition()
    SCB_RefreshDistanceButtons()
    frame:Hide()

    if not PCPFrame and not PCPFrameRemake then
        PCPFrameRemake = frame
    end
end

function SoloCraftBots_Toggle()
    if not SCB.frame then
        return
    end
    if SCB.frame:IsShown() then
        SCB.frame:Hide()
    else
        SCB.frame:Show()
        SCB.frame:Raise()
    end
end

SLASH_SOLOCRAFTBOTS1 = "/scb"
SLASH_SOLOCRAFTBOTS2 = "/solocraftbots"
SlashCmdList["SOLOCRAFTBOTS"] = function(msg)
    local command = string.lower(string.gsub(msg or "", "^%s*(.-)%s*$", "%1"))
    if command == "attackstart" then
        SCB_QueueDelayedCommand("attackstart", 0.25)
        return
    elseif command == "location" then
        SCB_PrintLocationProbe()
        return
    elseif command == "tutorialreset" then
        SCB_ResetTutorialHelpers()
        return
    elseif command == "debug" then
        SCB_SetDeveloperDebugEnabled(not SCB.developerDebugEnabled)
        return
    elseif command == "debugroster" then
        if not SCB.developerDebugEnabled then
            SCB_Print(SCB_L("DEBUG_MODE_REQUIRED"))
            return
        end
        if not SCB.debugFrame then SCB_CreateDebugUI() end
        SCB_DebugSnapshotRoster()
        SCB.debugFrame:Show()
        SCB.debugFrame:Raise()
        return
    end
    SoloCraftBots_Toggle()
end

local eventFrame = CreateFrame("Frame", "SoloCraftBotsEventFrame", UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("PLAYER_CONTROL_LOST")
eventFrame:RegisterEvent("PLAYER_CONTROL_GAINED")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_FLAGS")
eventFrame:RegisterEvent("UNIT_COMBAT")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("CHAT_MSG_PARTY")
eventFrame:RegisterEvent("CHAT_MSG_RAID")
eventFrame:RegisterEvent("CHAT_MSG_SAY")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:SetScript("OnEvent", function()
    if event == "PLAYER_TARGET_CHANGED" then
        if SCB_RefreshTargetCommandRow then SCB_RefreshTargetCommandRow() end
        return
    end
    if event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
        if SCB_QueueLocationRefresh then SCB_QueueLocationRefresh(0.20) end
        return
    end
    if event == "ADDON_LOADED" and arg1 == "SoloCraftBots" then
        SoloCraftBotsDB = SoloCraftBotsDB or {}
        SoloCraftBotsCharDB = SoloCraftBotsCharDB or {}
        SoloCraftBotsCharDB.helpers = SoloCraftBotsCharDB.helpers or {}
        SCB_EnsureSessionDB()
        SCB_EnsurePresetDB()
        SCB_EnsureSectionDB()
        SCB_EnsureOptionsDB()
    elseif event == "PLAYER_LOGIN" then
        -- Do not rely on ADDON_LOADED having matched a hard-coded folder name.
        -- This also makes first-run SavedVariables initialization explicit.
        SoloCraftBotsDB = SoloCraftBotsDB or {}
        SoloCraftBotsCharDB = SoloCraftBotsCharDB or {}
        SoloCraftBotsCharDB.helpers = SoloCraftBotsCharDB.helpers or {}
        SCB_EnsureSessionDB()
        SCB_EnsurePresetDB()
        SCB_EnsureSectionDB()
        SCB_EnsureOptionsDB()
        if not SCB.frame then
            SCB_CreateUI()
        end
        SCB.initialSessionValidationPending = true
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Freeze normal Active Roster sync from the first frame of a loading-
        -- screen completion. Roster events/UI refreshes may fire before WoW has
        -- repopulated every unit; only the delayed reconciliation is allowed to
        -- decide reload continuity versus a vanished relog/DC session.
        SCB.activeRosterReconcilePending = true
        if SCB_QueueLocationRefresh then SCB_QueueLocationRefresh(0.25) end
        if SCB_InstallBotChatFilter then SCB_InstallBotChatFilter() end
        if RequestRaidInfo then RequestRaidInfo() end
        SCB_RefreshMainPaladinBlessingButton()
        if SCB.presetPanel then SCB_RefreshPresetPlayers() end
        SCB_TryFinalizeRaidRoleTracking()
        SCB_ApplyTrackedPfUITankRoles(SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker)
        SCB_RefreshRefillButton()
        -- Loading-screen completion is our continuity boundary. Reconcile the
        -- persisted Active Roster only after roster APIs have settled: surviving
        -- saved names mean reload/zone continuity; zero survivors means relog/DC.
        SCB.initialSessionValidationPending = false
        if SCB_QueueActiveRosterWorldReconcile then
            SCB_QueueActiveRosterWorldReconcile(0.75)
        else
            SCB_ValidateSavedSession()
        end
    elseif event == "PLAYER_LEVEL_UP" then
        SCB_RefreshMainPaladinBlessingButton()
        if SCB.presetPanel then
            if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() else SCB_RefreshPresetSlots() end
        end
    elseif event == "PLAYER_CONTROL_LOST" then
        SCB.playerControlLost = true
    elseif event == "PLAYER_CONTROL_GAINED" then
        SCB.playerControlLost = nil
        if SCB.frame and SCB.frame:IsShown() then
            SCB_SetEscapeProxyShown(true)
        end
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        SCB_HandleRosterChange()
        if SCB.presetPanel then
            SCB_RefreshPresetPlayers()
        end
        SCB_TryFinalizeRaidRoleTracking()
        SCB_RefreshRefillButton()
        SCB_DebugRosterChanged()
    elseif event == "UNIT_FLAGS" then
        SCB_DebugUnitFlags(arg1)
    elseif event == "UNIT_COMBAT" then
        SCB_DebugUnitCombat(arg1, arg2, arg3, arg4, arg5)
    elseif event == "CHAT_MSG_SYSTEM" then
        if arg1 == "Cannot add more bots. Instance is full."
            and SCB_HasBotSpawnOperation and SCB_HasBotSpawnOperation()
            and SCB_AbortBotSpawnOperations then
            -- Spawn commands are consumed optimistically. If the server rejects
            -- one because the instance is still physically full, later roster
            -- barriers can never succeed. Abort immediately so Summon is usable.
            SCB_AbortBotSpawnOperations()
        end
        if arg1 and string.find(arg1, "Cannot add bots while any party member is in combat", 1, true)
            and SCB.presetSpawnQueue and table.getn(SCB.presetSpawnQueue) > 0
            and SCB.presetLastBurstCommands and table.getn(SCB.presetLastBurstCommands) > 0
            and not SCB.presetLastBurstRequeued then
            -- The server is authoritative when the local UnitAffectingCombat
            -- scan misses a distant/in-transition member. Treat every same-frame
            -- burst as one attempt even if the server emits several identical
            -- rejection lines. Requeue that exact logical group at the very
            -- front so no later preset group can leapfrog it.
            local retryDelays = { 1.0, 5.0, 10.0, 15.0 }
            local failures = (SCB.presetCombatRetryFailures or 0) + 1
            SCB.presetCombatRetryFailures = failures
            SCB.presetCombatRetryResetPending = nil
            SCB.presetLastBurstRequeued = true

            if failures <= table.getn(retryDelays) then
                local retry = {}
                local ri
                table.insert(retry, SCB.PRESET_CHECK_COMBAT)
                for ri = 1, table.getn(SCB.presetLastBurstCommands) do
                    table.insert(retry, SCB.presetLastBurstCommands[ri])
                end
                for ri = table.getn(retry), 1, -1 do
                    table.insert(SCB.presetSpawnQueue, 1, retry[ri])
                end

                -- Replace any normal inter-group wait already running for the
                -- failed burst with the bounded server-error backoff. The combat
                -- marker remains at queue head after the delay, so the normal
                -- live combat gate still gets the final say before resending.
                SCB.presetGroupWaitRemaining = 0
                SCB.presetCombatRetryWaitRemaining = retryDelays[failures]
                SCB.presetCombatPollRemaining = 0
            else
                -- Fifth rejected attempt: stop rather than looping forever or
                -- letting a later logical group corrupt the intended raid comp.
                SCB.presetSpawnQueue = {}
                SCB.presetGroupWaitRemaining = 0
                SCB.presetCombatRetryWaitRemaining = 0
                SCB.presetCombatPollRemaining = nil
                SCB.presetLastBurstCommands = nil
                SCB.presetLastBurstRequeued = nil
                SCB.presetCombatRetryFailures = 0
                SCB.presetCombatRetryResetPending = nil
                if SCB_CancelActiveRosterPresetTransition then SCB_CancelActiveRosterPresetTransition() end
                SCB_Print(SCB_L("PRESET_SUMMON_COMBAT_ABORT"))
            end
        end
        if SCB.refillState and SCB.refillState.active and SCB.refillState.phase == "waitgroup" and arg1 and string.find(arg1, "Cannot add bots while any party member is in combat", 1, true) then
            -- The pre-burst combat gate should normally prevent this. If combat
            -- begins in the tiny race between checking and sending, do not retry
            -- the whole burst blindly: some commands may already have been
            -- accepted, which would make duplicate role requests ambiguous.
            SCB.refillState.active = false
            SCB.refillState.phase = nil
            SCB.refillState.group = nil
            SCB.refillState.assignments = nil
            SCB.refillState.beforeNames = nil
            SCB.refillState.fullSeenAt = nil
            SCB_RefreshRefillButton()
        end
        if SCB.developerDebugEnabled and SCB.debugServerCheck and SCB.debugServerCheck:GetChecked() then
            SCB_DebugLog(SCB_L("DEBUG_KIND_SYSTEM"), arg1 or "")
        end
    elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_SAY" then
        if SCB.developerDebugEnabled and SCB.debugServerCheck and SCB.debugServerCheck:GetChecked() then
            local sender = arg2 or ""
            local message = arg1 or ""
            if sender == "" or sender ~= UnitName("player") then
                SCB_DebugLog(SCB_L("DEBUG_KIND_CHAT"), (sender ~= "" and (sender .. ": ") or "") .. message)
            end
        end
    elseif event == "PLAYER_LOGOUT" then
        SCB_SavePosition()
    end
end)
