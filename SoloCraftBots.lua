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

SCB.version = (GetAddOnMetadata and GetAddOnMetadata("SoloCraftBots", "Version")) or "unknown"
SCB.prefix = "|cff88ccff[SCB]|r "
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
SCB.lastRoster = nil
SCB.refillState = nil

BINDING_HEADER_SOLOCRAFTBOTS = "SoloCraft Bots"
BINDING_NAME_SOLOCRAFTBOTS_TOGGLE = "Toggle SoloCraft Bots"

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
    toggle.scbTooltip = "Collapse/expand " .. titleText
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

local SCB_PALADIN_BLESSINGS = {
    { key = "BoK", label = SCB_L("BLESSING_KINGS"), texture = "Interface\\Icons\\Spell_Magic_GreaterBlessingofKings" },
    { key = "BoM", label = SCB_L("BLESSING_MIGHT"), texture = "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings" },
    { key = "BoS", label = SCB_L("BLESSING_SALVATION"), texture = "Interface\\Icons\\Spell_Holy_GreaterBlessingofSalvation" },
    { key = "BoW", label = SCB_L("BLESSING_WISDOM"), texture = "Interface\\Icons\\Spell_Holy_GreaterBlessingofWisdom" },
    { key = "BoL", label = SCB_L("BLESSING_LIGHT"), texture = "Interface\\Icons\\Spell_Holy_GreaterBlessingofLight" },
}

function SCB_FindPaladinBlessing(key)
    local i
    for i = 1, table.getn(SCB_PALADIN_BLESSINGS) do
        if SCB_PALADIN_BLESSINGS[i].key == key then
            return SCB_PALADIN_BLESSINGS[i], i
        end
    end
    return SCB_PALADIN_BLESSINGS[1], 1
end

local SCB_SHAMAN_TOTEMS = {
    air = {
        { key = "windfury", label = "Windfury", texture = "Interface\\Icons\\Spell_Nature_Windfury" },
        { key = "graceofair", label = "Grace of Air", texture = "Interface\\Icons\\Spell_Nature_InvisibilityTotem" },
        { key = "tranquilair", label = "Tranquil Air", texture = "Interface\\Icons\\Spell_Nature_Brilliance" },
        { key = "natureresistance", label = "Nature Resistance", texture = "Interface\\Icons\\Spell_Nature_NatureResistanceTotem" },
    },
    earth = {
        { key = "strengthofearth", label = "Strength of Earth", texture = "Interface\\Icons\\Spell_Nature_EarthBindTotem" },
        { key = "stoneskin", label = "Stoneskin", texture = "Interface\\Icons\\Spell_Nature_StoneSkinTotem" },
        { key = "earthbind", label = "Earthbind", texture = "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02" },
        { key = "tremor", label = "Tremor", texture = "Interface\\Icons\\Spell_Nature_TremorTotem" },
    },
    fire = {
        { key = "searing", label = "Searing", texture = "Interface\\Icons\\Spell_Fire_SearingTotem" },
        { key = "magma", label = "Magma", texture = "Interface\\Icons\\Spell_Fire_SelfDestruct" },
        { key = "firenova", label = "Fire Nova", texture = "Interface\\Icons\\Spell_Fire_SealOfFire" },
        { key = "flametongue", label = "Flametongue", texture = "Interface\\Icons\\Spell_Nature_GuardianWard" },
        { key = "frostresistance", label = "Frost Resistance", texture = "Interface\\Icons\\Spell_FrostResistanceTotem_01" },
    },
    water = {
        { key = "manaspring", label = "Mana Spring", texture = "Interface\\Icons\\Spell_Nature_ManaRegenTotem" },
        { key = "healingstream", label = "Healing Stream", texture = "Interface\\Icons\\INV_Spear_04" },
        { key = "poisoncleansing", label = "Poison Cleansing", texture = "Interface\\Icons\\Spell_Nature_PoisonCleansingTotem" },
        { key = "diseasecleansing", label = "Disease Cleansing", texture = "Interface\\Icons\\Spell_Nature_DiseaseCleansingTotem" },
        { key = "fireresistance", label = "Fire Resistance", texture = "Interface\\Icons\\Spell_FireResistanceTotem_01" },
        { key = "manatide", label = "Mana Tide", texture = "Interface\\Icons\\Spell_Frost_SummonWaterElemental" },
    },
}

local SCB_SHAMAN_TOTEM_ORDER = { "air", "earth", "fire", "water" }
local SCB_DEFAULT_SHAMAN_TOTEMS = "windfury strengthofearth searing poisoncleansing"

function SCB_ParseShamanTotems(extra)
    local result = {}
    local i, key, value
    if extra and extra ~= "" then
        i = 1
        for value in string.gfind(extra, "%S+") do
            key = SCB_SHAMAN_TOTEM_ORDER[i]
            if not key then break end
            result[key] = value
            i = i + 1
        end
    end

    local defaults = { air = "windfury", earth = "strengthofearth", fire = "searing", water = "poisoncleansing" }
    for i = 1, table.getn(SCB_SHAMAN_TOTEM_ORDER) do
        key = SCB_SHAMAN_TOTEM_ORDER[i]
        if not result[key] then result[key] = defaults[key] end
    end
    return result
end

function SCB_FindShamanTotem(groupKey, totemKey)
    local list = SCB_SHAMAN_TOTEMS[groupKey]
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
        key = "warrior", name = "Warrior", icon = "warrior.tga",
        roles = {
            { role = "tank", label = "Tank", icon = "tank.tga" },
            { role = "meleedps", label = "Melee", icon = "melee.tga" },
        },
    },
    {
        key = "rogue", name = "Rogue", icon = "rogue.tga",
        roles = {
            { role = "meleedps", label = "Melee", icon = "melee.tga" },
        },
    },
    {
        key = "paladin", name = "Paladin", faction = "Alliance", icon = "paladin.tga",
        roles = {
            { role = "healer", label = "Healer", icon = "healer.tga" },
            { role = "meleedps", label = "Melee", icon = "melee.tga" },
            { role = "tank", label = "Tank", icon = "tank.tga" },
        },
    },
    {
        key = "shaman", name = "Shaman", faction = "Horde", icon = "shaman.tga",
        roles = {
            { role = "healer", label = "Healer", icon = "healer.tga" },
            { role = "meleedps", label = "Melee", icon = "melee.tga" },
            { role = "rangedps", label = "Ranged", icon = "ranged.tga" },
            { role = "tank", label = "Tank", icon = "tank.tga" },
        },
    },
    {
        key = "hunter", name = "Hunter", icon = "hunter.tga",
        roles = {
            { role = "rangedps", label = "Ranged", icon = "ranged.tga" },
        },
    },
    {
        key = "druid", name = "Druid", icon = "druid.tga",
        roles = {
            { role = "tank", label = "Tank", icon = "tank.tga" },
            { role = "meleedps", label = "Melee", icon = "melee.tga" },
            { role = "healer", label = "Healer", icon = "healer.tga" },
            { role = "rangedps", label = "Ranged", icon = "ranged.tga" },
        },
    },
    {
        key = "priest", name = "Priest", icon = "priest.tga",
        roles = {
            { role = "healer", label = "Healer", icon = "healer.tga" },
            { role = "rangedps", label = "Ranged", icon = "ranged.tga" },
        },
    },
    {
        key = "mage", name = "Mage", icon = "mage.tga",
        roles = {
            { role = "rangedps", label = "Fire", texture = "Interface\\Icons\\Spell_Fire_FlameBolt", extra = "fire" },
            { role = "rangedps", label = "Frost", texture = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
        },
    },
    {
        key = "warlock", name = "Warlock", icon = "warlock.tga",
        roles = {
            { role = "rangedps", label = "Ranged", icon = "ranged.tga" },
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
        extra = SCB_DEFAULT_SHAMAN_TOTEMS
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
        for i = 1, table.getn(SCB_SHAMAN_TOTEM_ORDER) do
            groupKey = SCB_SHAMAN_TOTEM_ORDER[i]
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
        if newIndex < 1 then newIndex = table.getn(SCB_PALADIN_BLESSINGS) end
    else
        newIndex = currentIndex + 1
        if newIndex > table.getn(SCB_PALADIN_BLESSINGS) then newIndex = 1 end
    end
    SCB.mainPaladinBlessing = SCB_PALADIN_BLESSINGS[newIndex].key
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

-- -------------------------------------------------------------------------
-- Presets
-- -------------------------------------------------------------------------

SCB.presetGroupMenuButtons = SCB.presetGroupMenuButtons or {}
SCB.presetNameMenuButtons = SCB.presetNameMenuButtons or {}
SCB.presetEditorPlayerRoles = SCB.presetEditorPlayerRoles or {}
SCB.presetGroupFrames = SCB.presetGroupFrames or {}
SCB.presetGroupTitles = SCB.presetGroupTitles or {}
SCB.dragGhost = SCB.dragGhost or nil

local SCB_DEFAULT_PRESET_GROUPS = {
    { id = "5man", name = SCB_L("GROUP_WORLD", "World"), size = 5 },
    { id = "10man", name = SCB_L("GROUP_DUNGEON", "Dungeon"), size = 10 },
    { id = "ubrs", name = SCB_L("GROUP_BRS", "Blackrock Spire"), size = 15 },
    { id = "zg", name = SCB_L("GROUP_ZG", "Zul'Gurub"), size = 20 },
    { id = "aq20", name = SCB_L("GROUP_AQ20", "Ruins of Ahn'Qiraj"), size = 20 },
    { id = "mc", name = SCB_L("GROUP_MC", "Molten Core"), size = 40 },
    { id = "onyxia", name = SCB_L("GROUP_ONYXIA", "Onyxia's Lair"), size = 40 },
    { id = "bwl", name = SCB_L("GROUP_BWL", "Blackwing Lair"), size = 40 },
    { id = "aq40", name = SCB_L("GROUP_AQ40", "Temple of Ahn'Qiraj"), size = 40 },
    { id = "naxx", name = SCB_L("GROUP_NAXX", "Naxxramas"), size = 40 },
    { id = "worldboss", name = SCB_L("GROUP_WORLDBOSS", "World Boss"), size = 40 },
}

local SCB_PLAYER_ROLES = {
    { role = "tank", label = "Tank", icon = "tank.tga" },
    { role = "healer", label = "Healer", icon = "healer.tga" },
    { role = "meleedps", label = "Melee", icon = "melee.tga" },
    { role = "rangedps", label = "Ranged", icon = "ranged.tga" },
}

function SCB_CopySlot(slot)
    return {
        class = slot.class,
        role = slot.role,
        extra = slot.extra,
    }
end

function SCB_CopySlots(slots)
    local copy = {}
    local i
    if not slots then
        return copy
    end
    for i = 1, table.getn(slots) do
        copy[i] = SCB_CopySlot(slots[i])
    end
    return copy
end

function SCB_DefaultPlayerRoleForClass(classInfo)
    if classInfo and classInfo.roles and classInfo.roles[1] then
        return classInfo.roles[1].role
    end
    return "meleedps"
end

function SCB_DefaultPresetSlots(size)
    local slots = {}
    local pattern = {
        { class = "warrior", role = "tank" },
        { class = "priest", role = "healer" },
        { class = "rogue", role = "meleedps" },
        { class = "mage", role = "rangedps" },
        { class = "hunter", role = "rangedps" },
    }
    local playerClass = SCB_GetPlayerClassInfo()
    local i, patternIndex
    size = size or 10

    for i = 1, size do
        patternIndex = math.mod(i - 1, 5) + 1
        slots[i] = SCB_CopySlot(pattern[patternIndex])
    end

    -- A brand-new preset sacrifices a bot matching the player's class in the
    -- default self slot. Once saved/edited, the stored assignment wins.
    if playerClass and slots[1] then
        slots[1].class = playerClass.key
        slots[1].role = SCB_DefaultPlayerRoleForClass(playerClass)
        slots[1].extra = nil
    end
    return slots
end

function SCB_NormalizePresetSlots(slots, size)
    local defaults = SCB_DefaultPresetSlots(size)
    local normalized = {}
    local i, slot
    size = size or 10

    -- 0.2.3 and earlier stored nine bot positions because self was hard-coded.
    if size == 10 and slots and table.getn(slots) == 9 then
        normalized[1] = SCB_CopySlot(defaults[1])
        for i = 1, 9 do
            slot = slots[i]
            if slot and slot.class and slot.role then
                normalized[i + 1] = SCB_CopySlot(slot)
            else
                normalized[i + 1] = SCB_CopySlot(defaults[i + 1])
            end
        end
        return normalized
    end

    for i = 1, size do
        slot = slots and slots[i] or nil
        if slot and slot.class and slot.role then
            normalized[i] = SCB_CopySlot(slot)
        else
            normalized[i] = SCB_CopySlot(defaults[i])
        end
    end
    return normalized
end

function SCB_CopyPlayerSlots(playerSlots, size)
    local copy = {}
    local key, slot
    size = size or 10
    if playerSlots then
        for key, slot in pairs(playerSlots) do
            if type(key) == "string" and type(slot) == "number" and slot >= 1 and slot <= size then
                copy[key] = slot
            end
        end
    end
    if not copy["$self"] then
        copy["$self"] = 1
    end
    return copy
end

function SCB_CopyPlayerGroups(playerGroups, size, legacySlots)
    local copy = {}
    local key, value, groupCount
    size = size or 10
    groupCount = math.max(1, math.ceil(size / 5))
    if playerGroups then
        for key, value in pairs(playerGroups) do
            if type(key) == "string" and type(value) == "number" then
                if legacySlots then value = math.floor((value - 1) / 5) + 1 end
                if value >= 1 and value <= groupCount then copy[key] = value end
            end
        end
    end
    if not copy["$self"] then copy["$self"] = 1 end
    return copy
end

function SCB_CopyPlayerRoles(playerRoles)
    local copy = {}
    local key, selection
    if playerRoles then
        for key, selection in pairs(playerRoles) do
            if type(key) == "string" then
                if type(selection) == "table" and type(selection.role) == "string" then
                    copy[key] = { role = selection.role, extra = selection.extra }
                elseif type(selection) == "string" then
                    -- Legacy playerRoles stored only the broad role. Keep it
                    -- readable; class-aware refresh will resolve the matching
                    -- spec and the next save upgrades it to role + extra.
                    copy[key] = { role = selection }
                end
            end
        end
    end
    return copy
end

function SCB_GetPlayerRoleSelection(selection, fallbackRole, fallbackExtra)
    if type(selection) == "table" and type(selection.role) == "string" then
        return selection.role, selection.extra
    elseif type(selection) == "string" then
        return selection, nil
    end
    return fallbackRole, fallbackExtra
end

function SCB_MakePlayerRoleSelection(role, extra)
    return { role = role, extra = extra }
end

function SCB_GetPlayerClassRoleInfo(info, selection)
    local classInfo, role, extra
    if info and info.classToken then
        classInfo = SCB_FindClass(string.lower(info.classToken))
    end
    if not classInfo or not classInfo.roles or table.getn(classInfo.roles) == 0 then
        return nil
    end
    role, extra = SCB_GetPlayerRoleSelection(selection, classInfo.roles[1].role, classInfo.roles[1].extra)
    return SCB_FindRoleEntry(classInfo, role, extra)
end

function SCB_GetDefaultPresetGroups()
    local groups = {}
    local i, def
    for i = 1, table.getn(SCB_DEFAULT_PRESET_GROUPS) do
        def = SCB_DEFAULT_PRESET_GROUPS[i]
        groups[i] = {
            id = def.id,
            name = def.name,
            size = def.size,
            isDefault = true,
            presets = {},
            currentPreset = nil,
        }
    end
    return groups
end

function SCB_CurrentPresetGroup()
    if not SoloCraftBotsDB.presetGroups then
        return nil
    end
    return SoloCraftBotsDB.presetGroups[SoloCraftBotsDB.currentPresetGroup or 1]
end

function SCB_CurrentPreset()
    local group = SCB_CurrentPresetGroup()
    if not group or not group.currentPreset then
        return nil
    end
    return group.presets and group.presets[group.currentPreset] or nil
end

function SCB_CurrentPresetSize()
    local group = SCB_CurrentPresetGroup()
    return (group and group.size) or 10
end

function SCB_CurrentGroupCount()
    return math.floor((SCB_CurrentPresetSize() + 4) / 5)
end

function SCB_PresetSlotLabel(index)
    local group = math.floor((index - 1) / 5) + 1
    local slot = math.mod(index - 1, 5) + 1
    return "Group " .. group .. " / Slot " .. slot
end

function SCB_PresetPlayerDisplayName(key)
    if key == "$self" then
        return (UnitName and UnitName("player")) or "YOU"
    end
    return key
end

function SCB_IsKnownBotName(name)
    if not name then
        return false
    end
    SCB_EnsureSessionDB()
    if SoloCraftBotsDB.session.knownBots[name] then
        return true
    end
    return string.find(name, "%*", 1) ~= nil
end

function SCB_GetHumanRoster()
    local roster = {}
    local seen = {}
    local function AddUnit(unit, key)
        local name, _, classToken
        if not UnitExists or not UnitExists(unit) then
            return
        end
        name = UnitName(unit)
        if not name or seen[name] or (key ~= "$self" and SCB_IsKnownBotName(name)) then
            return
        end
        seen[name] = true
        if UnitClass then
            _, classToken = UnitClass(unit)
        end
        table.insert(roster, {
            key = key or name,
            name = name,
            unit = unit,
            classToken = classToken,
        })
    end

    AddUnit("player", "$self")
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        local i
        for i = 1, GetNumRaidMembers() do
            AddUnit("raid" .. i, nil)
        end
    elseif GetNumPartyMembers then
        local i
        for i = 1, GetNumPartyMembers() do
            AddUnit("party" .. i, nil)
        end
    end
    return roster
end

function SCB_GetPresentHumanMap()
    local map = {}
    local roster = SCB_GetHumanRoster()
    local i
    for i = 1, table.getn(roster) do
        map[roster[i].key] = roster[i]
    end
    return map
end

function SCB_ClassColor(classToken)
    local fallbackClassColors = {
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
        PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
        HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
        ROGUE = { r = 1.00, g = 0.96, b = 0.41 },
        PRIEST = { r = 1.00, g = 1.00, b = 1.00 },
        SHAMAN = { r = 0.14, g = 0.35, b = 1.00 },
        MAGE = { r = 0.41, g = 0.80, b = 0.94 },
        WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
        DRUID = { r = 1.00, g = 0.49, b = 0.04 },
    }
    if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
        return RAID_CLASS_COLORS[classToken]
    end
    return classToken and fallbackClassColors[classToken] or nil
end

function SCB_PlayerRoleInfo(role)
    local i
    for i = 1, table.getn(SCB_PLAYER_ROLES) do
        if SCB_PLAYER_ROLES[i].role == role then
            return SCB_PLAYER_ROLES[i], i
        end
    end
    return SCB_PLAYER_ROLES[3], 3
end

function SCB_DefaultPlayerRole(info)
    local classInfo
    if info and info.classToken then
        classInfo = SCB_FindClass(string.lower(info.classToken))
    end
    return SCB_DefaultPlayerRoleForClass(classInfo)
end

function SCB_GetCharacterDefaultRoleSelection()
    local classInfo = SCB_GetPlayerClassInfo()
    local storedRole = SoloCraftBotsCharDB and SoloCraftBotsCharDB.defaultPlayerRole or nil
    local storedExtra = SoloCraftBotsCharDB and SoloCraftBotsCharDB.defaultPlayerExtra or nil
    local i, entry

    SoloCraftBotsCharDB = SoloCraftBotsCharDB or {}
    if classInfo and classInfo.roles and table.getn(classInfo.roles) > 0 then
        -- Prefer an exact role + extra match. Older characters stored only the
        -- broad role; in that case resolve to the first matching class spec.
        for i = 1, table.getn(classInfo.roles) do
            entry = classInfo.roles[i]
            if entry.role == storedRole and entry.extra == storedExtra then
                return entry.role, entry.extra
            end
        end
        for i = 1, table.getn(classInfo.roles) do
            entry = classInfo.roles[i]
            if entry.role == storedRole then
                SoloCraftBotsCharDB.defaultPlayerRole = entry.role
                SoloCraftBotsCharDB.defaultPlayerExtra = entry.extra
                return entry.role, entry.extra
            end
        end
        entry = classInfo.roles[1]
        SoloCraftBotsCharDB.defaultPlayerRole = entry.role
        SoloCraftBotsCharDB.defaultPlayerExtra = entry.extra
        return entry.role, entry.extra
    end

    SoloCraftBotsCharDB.defaultPlayerRole = "meleedps"
    SoloCraftBotsCharDB.defaultPlayerExtra = nil
    return "meleedps", nil
end

function SCB_GetCharacterDefaultRole()
    local role = SCB_GetCharacterDefaultRoleSelection()
    return role
end

function SCB_GetCharacterDefaultRoleTable()
    local role, extra = SCB_GetCharacterDefaultRoleSelection()
    return SCB_MakePlayerRoleSelection(role, extra)
end

function SCB_RefreshCharacterPresetIdentity()
    local classInfo = SCB_GetPlayerClassInfo()
    local role, extra, roleInfo
    if SCB.presetSelfClassIcon and classInfo then
        SCB.presetSelfClassIcon:SetTexture(SCB.assetRoot .. classInfo.icon)
        SCB.presetSelfClassFrame.scbTooltip = classInfo.name
    end
    role, extra = SCB_GetCharacterDefaultRoleSelection()
    roleInfo = SCB_FindRoleEntry(classInfo, role, extra)
    if SCB.presetSelfRoleButton and roleInfo then
        SCB_SetArtButtonTexture(SCB.presetSelfRoleButton, SCB_RoleTexture(roleInfo), SCB_RoleHighlightTexture(roleInfo))
        SCB.presetSelfRoleButton.scbTooltip = SCB_L("TIP_CHARACTER_ROLE", "Default role for new presets") .. "\n" .. roleInfo.label
    end
end

function SCB_CharacterPresetRoleOnClick()
    local classInfo = SCB_GetPlayerClassInfo()
    local currentRole, currentExtra = SCB_GetCharacterDefaultRoleSelection()
    local currentIndex, newIndex, roleInfo
    if not classInfo or not classInfo.roles or table.getn(classInfo.roles) == 0 then return end
    roleInfo, currentIndex = SCB_FindRoleEntry(classInfo, currentRole, currentExtra)
    currentIndex = currentIndex or 1
    if arg1 == "RightButton" then
        newIndex = currentIndex - 1
        if newIndex < 1 then newIndex = table.getn(classInfo.roles) end
    else
        newIndex = currentIndex + 1
        if newIndex > table.getn(classInfo.roles) then newIndex = 1 end
    end
    roleInfo = classInfo.roles[newIndex]
    SoloCraftBotsCharDB = SoloCraftBotsCharDB or {}
    SoloCraftBotsCharDB.defaultPlayerRole = roleInfo.role
    SoloCraftBotsCharDB.defaultPlayerExtra = roleInfo.extra
    SCB_RefreshCharacterPresetIdentity()
end

function SCB_EnsurePresetDB()
    local groups, legacyPresets, legacyCurrent, tenGroup, i, preset

    if not SoloCraftBotsDB.presetGroups then
        groups = SCB_GetDefaultPresetGroups()
        legacyPresets = SoloCraftBotsDB.presets
        legacyCurrent = SoloCraftBotsDB.currentPreset
        tenGroup = groups[2]

        if legacyPresets and table.getn(legacyPresets) > 0 then
            for i = 1, table.getn(legacyPresets) do
                preset = legacyPresets[i]
                table.insert(tenGroup.presets, {
                    name = preset.name or ("Preset " .. i),
                    slots = SCB_NormalizePresetSlots(preset.slots, 10),
                    playerSlots = SCB_CopyPlayerSlots(preset.playerSlots, 10),
                    playerRoles = SCB_CopyPlayerRoles(preset.playerRoles),
                })
            end
            tenGroup.currentPreset = legacyCurrent or 1
            SoloCraftBotsDB.currentPresetGroup = 2
        else
            table.insert(tenGroup.presets, {
                name = "Preset 1",
                slots = SCB_DefaultPresetSlots(10),
                playerSlots = { ["$self"] = 1 },
                playerRoles = { ["$self"] = SCB_GetCharacterDefaultRoleTable() },
            })
            tenGroup.currentPreset = 1
            SoloCraftBotsDB.currentPresetGroup = 2
        end
        SoloCraftBotsDB.presetGroups = groups
    end

    if not SoloCraftBotsDB.currentPresetGroup or not SoloCraftBotsDB.presetGroups[SoloCraftBotsDB.currentPresetGroup] then
        SoloCraftBotsDB.currentPresetGroup = 1
    end

    for i = 1, table.getn(SoloCraftBotsDB.presetGroups) do
        groups = SoloCraftBotsDB.presetGroups[i]
        if groups.isDefault and groups.id then
            local defIndex, def
            for defIndex = 1, table.getn(SCB_DEFAULT_PRESET_GROUPS) do
                def = SCB_DEFAULT_PRESET_GROUPS[defIndex]
                if def.id == groups.id then
                    groups.name = def.name
                    groups.size = def.size
                    break
                end
            end
        end
        groups.presets = groups.presets or {}
        if table.getn(groups.presets) == 0 then
            groups.currentPreset = nil
        elseif not groups.currentPreset or not groups.presets[groups.currentPreset] then
            groups.currentPreset = 1
        end
    end
end

local SCB_SetPresetDirty
local SCB_RefreshPresetPlayers
local SCB_LayoutPresetGroups
local SCB_RefreshPresetSummonWarning
local SCB_RefreshPresetCounters

function SCB_SetPresetButtonGrey(button)
    if not button or not button.label then return end
    button.label:SetTextColor(0.90, 0.90, 0.90, 1)
    button:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
end

function SCB_PresetButtonPulseOnUpdate()
    local elapsed = arg1 or 0
    local t, mix, r, g, b
    this.scbPulseElapsed = (this.scbPulseElapsed or 0) + elapsed
    t = this.scbPulseElapsed

    if this.scbPulseMode == "redloop" then
        t = math.mod(t, 4)
        if t <= 2 then
            mix = 1 - (t / 2)
        else
            mix = (t - 2) / 2
        end
        r = 0.90 + (0.10 * mix)
        g = 0.90 - (0.72 * mix)
        b = 0.90 - (0.72 * mix)
        this.label:SetTextColor(r, g, b, 1)
        this:SetBackdropBorderColor(0.45 + (0.50 * mix), 0.45 - (0.30 * mix), 0.45 - (0.30 * mix), 1)
        return
    end

    if this.scbPulseMode == "greenloop" then
        t = math.mod(t, 2)
        if t <= 1 then
            mix = 1 - t
        else
            mix = t - 1
        end
        r = 0.90 - (0.55 * mix)
        g = 0.90 + (0.10 * mix)
        b = 0.90 - (0.50 * mix)
        this.label:SetTextColor(r, g, b, 1)
        this:SetBackdropBorderColor(0.45 - (0.20 * mix), 0.45 + (0.35 * mix), 0.45 - (0.20 * mix), 1)
        return
    end

    if this.scbPulseMode == "greensave" then
        if t >= 2 then
            this:SetScript("OnUpdate", nil)
            this.scbPulseMode = nil
            this.scbPulseElapsed = nil
            SCB_SetPresetButtonGrey(this)
            return
        end
        mix = 1 - (t / 2)
        r = 0.90 - (0.55 * mix)
        g = 0.90 + (0.10 * mix)
        b = 0.90 - (0.50 * mix)
        this.label:SetTextColor(r, g, b, 1)
        this:SetBackdropBorderColor(0.45 - (0.20 * mix), 0.45 + (0.35 * mix), 0.45 - (0.20 * mix), 1)
    end
end

function SCB_StartPresetButtonPulse(button, mode)
    if not button then return end
    button.scbPulseMode = mode
    button.scbPulseElapsed = 0

    -- Apply the first frame immediately.  In particular, saved feedback
    -- should visibly turn green on the click instead of waiting for OnUpdate.
    if (mode == "greensave" or mode == "greenloop") and button.label then
        button.label:SetTextColor(0.35, 1.00, 0.40, 1)
        button:SetBackdropBorderColor(0.25, 0.80, 0.25, 1)
    elseif mode == "redloop" and button.label then
        button.label:SetTextColor(1.00, 0.18, 0.18, 1)
        button:SetBackdropBorderColor(0.95, 0.15, 0.15, 1)
    end

    button:SetScript("OnUpdate", SCB_PresetButtonPulseOnUpdate)
end

function SCB_StopPresetButtonPulse(button)
    if not button then return end
    button:SetScript("OnUpdate", nil)
    button.scbPulseMode = nil
    button.scbPulseElapsed = nil
    SCB_SetPresetButtonGrey(button)
end

SCB_SetPresetDirty = function(dirty, savedFeedback)
    SCB.presetDirty = dirty == true
    if not SCB.presetSaveButton or not SCB.presetSaveButton.label then
        return
    end

    if SCB.presetDirty then
        SCB.presetSaveButton.label:SetText(SCB_L("UNSAVED", "Unsaved Changes"))
        SCB_StartPresetButtonPulse(SCB.presetSaveButton, "redloop")
    else
        SCB.presetSaveButton.label:SetText(SCB_L("SAVED", "Preset Saved"))
        if savedFeedback then
            SCB_StartPresetButtonPulse(SCB.presetSaveButton, "greensave")
        else
            SCB_StopPresetButtonPulse(SCB.presetSaveButton)
        end
    end
end

function SCB_UpdatePresetSelectorText()
    local group, preset
    if not SCB.presetGroupSelector or not SCB.presetSelector then
        return
    end
    SCB_EnsurePresetDB()
    group = SCB_CurrentPresetGroup()
    preset = SCB_CurrentPreset()
    SCB.presetGroupSelector.label:SetText(group and group.name or "No Group")
    if group and group.isDefault then
        SCB.presetGroupSelector.label:SetTextColor(1, 0.82, 0, 1)
    else
        SCB.presetGroupSelector.label:SetTextColor(0.82, 0.82, 0.82, 1)
    end
    SCB.presetSelector.label:SetText(preset and preset.name or "No Preset")
    SCB.presetSelector.label:SetTextColor(0.90, 0.90, 0.90, 1)
end

function SCB_RefreshPresetSlots()
    local size = SCB_CurrentPresetSize()
    local present = SCB_GetPresentHumanMap()
    local i, slot, classInfo, roleInfo, row, playerKey, playerInfo, playerRole, blessingInfo, shamanTotems, totemInfo, totemKey

    for i = 1, 40 do
        row = SCB.presetSlotRows[i]
        if row then
            row.scbPresentPlayerKey = nil
            if i <= size then
                row:Show()
                slot = SCB.presetEditorSlots[i]
                if slot then
                    classInfo = SCB_FindClass(slot.class)
                    roleInfo = SCB_FindRoleEntry(classInfo, slot.role, slot.extra)
                    SCB_SetArtButtonTexture(row.classButton, SCB.assetRoot .. classInfo.icon, nil)
                    row.classButton.scbTooltip = SCB_PresetSlotLabel(i) .. ": " .. classInfo.name .. "\n" .. SCB_L("TIP_CLASS_CYCLE", "Left-click next class; right-click previous") .. "\n" .. SCB_L("TIP_CLASS_GROUP", "Shift-click: match group; repeat to rotate")
                    SCB_SetArtButtonTexture(row.roleButton, SCB_RoleTexture(roleInfo), SCB_RoleHighlightTexture(roleInfo))
                    row.roleButton.scbTooltip = roleInfo.label .. "\nLeft-click next role/spec; right-click previous"

                    if row.blessingButton then
                        if slot.class == "paladin" then
                            blessingInfo = SCB_FindPaladinBlessing(slot.extra)
                            row.blessingButton.icon:Show()
                            SCB_SetArtButtonTexture(row.blessingButton, blessingInfo.texture, nil)
                            if row.blessingButton.totemIcons then
                                for totemKey = 1, 4 do row.blessingButton.totemIcons[totemKey]:Hide() end
                            end
                            if UnitLevel and UnitLevel("player") == 60 then
                                SCB_SetArtButtonAvailable(row.blessingButton, true)
                                row.blessingButton.scbTooltip = SCB_L("TIP_PRESET_BLESSING")
                                row.blessingButton.scbTooltip = string.gsub(row.blessingButton.scbTooltip, "%%s", blessingInfo.label)
                            else
                                SCB_SetArtButtonAvailable(row.blessingButton, false)
                                row.blessingButton.scbTooltip = SCB_L("TIP_PALADIN_BLESSING_LEVEL")
                            end
                            row.blessingButton:Show()
                        elseif slot.class == "shaman" then
                            shamanTotems = SCB_ParseShamanTotems(slot.extra)
                            SCB_SetArtButtonAvailable(row.blessingButton, true)
                            row.blessingButton.icon:Hide()
                            if row.blessingButton.totemIcons then
                                for totemKey = 1, 4 do
                                    local groupKey = SCB_SHAMAN_TOTEM_ORDER[totemKey]
                                    totemInfo = SCB_FindShamanTotem(groupKey, shamanTotems[groupKey])
                                    row.blessingButton.totemIcons[totemKey]:SetTexture(totemInfo.texture)
                                    row.blessingButton.totemIcons[totemKey]:Show()
                                end
                            end
                            row.blessingButton.scbTooltip =
                                "Shaman Totems\n"
                                .. "Air: " .. SCB_FindShamanTotem("air", shamanTotems.air).label .. "\n"
                                .. "Earth: " .. SCB_FindShamanTotem("earth", shamanTotems.earth).label .. "\n"
                                .. "Fire: " .. SCB_FindShamanTotem("fire", shamanTotems.fire).label .. "\n"
                                .. "Water: " .. SCB_FindShamanTotem("water", shamanTotems.water).label
                                .. "\nClick a quadrant to cycle; right-click reverses"
                            row.blessingButton:Show()
                        else
                            row.blessingButton:Hide()
                        end
                        SCB_RefreshVisibleTooltip(row.blessingButton)
                    end
                    SCB_RefreshVisibleTooltip(row.classButton)
                    SCB_RefreshVisibleTooltip(row.roleButton)
                end
            else
                row:Hide()
            end
        end
    end

    if SCB_RefreshPresetCounters then
        SCB_RefreshPresetCounters()
    end
end

function SCB_FrameContainsCursor(frame)
    local x, y, scale
    if not frame or not frame:IsShown() then
        return false
    end
    if MouseIsOver then
        return MouseIsOver(frame)
    end
    if not GetCursorPosition or not UIParent or not UIParent.GetEffectiveScale then
        return false
    end
    x, y = GetCursorPosition()
    scale = UIParent:GetEffectiveScale()
    if not scale or scale == 0 then
        scale = 1
    end
    x = x / scale
    y = y / scale
    return frame:GetLeft() and frame:GetRight() and frame:GetTop() and frame:GetBottom()
        and x >= frame:GetLeft() and x <= frame:GetRight()
        and y >= frame:GetBottom() and y <= frame:GetTop()
end

function SCB_AssignPresetPlayer(key, groupIndex)
    local size = SCB_CurrentPresetSize()
    local groupCount = math.max(1, math.ceil(size / 5))
    if size <= 5 or not key or not groupIndex or groupIndex < 1 or groupIndex > groupCount then return end
    SCB.presetEditorPlayers = SCB.presetEditorPlayers or {}
    SCB.presetEditorPlayers[key] = groupIndex
    SCB_SetPresetDirty(true)
end

function SCB_SetPresetGroupDragHighlight(groupIndex, alpha)
    local i, frame
    for i = 1, 8 do
        frame = SCB.presetGroupFrames[i]
        if frame then
            if i == groupIndex then
                frame:SetBackdropBorderColor(1, 0.82, 0.08, alpha or 1)
            else
                frame:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)
            end
        end
    end
end

function SCB_UpdateDragGhost()
    local x, y, scale
    if not SCB.dragGhost or not SCB.dragGhost:IsShown() or not GetCursorPosition then
        return
    end
    x, y = GetCursorPosition()
    scale = UIParent:GetEffectiveScale() or 1
    SCB.dragGhost:ClearAllPoints()
    -- Keep the dragged player representation centred directly on the cursor.
    SCB.dragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    if SCB.draggedPresetPlayer then
        local i, hovered
        for i = 1, math.ceil(SCB_CurrentPresetSize() / 5) do
            if SCB_FrameContainsCursor(SCB.presetGroupFrames[i]) then hovered = i break end
        end
        SCB.draggedPresetPlayerHoverGroup = hovered
        if hovered then
            SCB_SetPresetGroupDragHighlight(hovered, 0.55 + (0.45 * math.abs(math.sin((GetTime and GetTime() or 0) * 5))))
        else
            SCB_SetPresetGroupDragHighlight(nil)
        end
    end
end

function SCB_ShowDragGhost(info)
    local color
    if not SCB.dragGhost or not info then
        return
    end
    SCB.dragGhost.label:SetText(info.name)
    if SCB.dragGhost.roleIcon then
        local selection = SCB.presetEditorPlayerRoles[info.key]
        local roleInfo = SCB_GetPlayerClassRoleInfo(info, selection)
        if roleInfo then SCB.dragGhost.roleIcon:SetTexture(SCB_RoleTexture(roleInfo)) end
    end
    color = SCB_ClassColor(info.classToken)
    if color then
        SCB.dragGhost.label:SetTextColor(color.r, color.g, color.b, 1)
    else
        SCB.dragGhost.label:SetTextColor(1, 1, 1, 1)
    end
    SCB.dragGhost:Show()
    SCB.dragGhost:SetScript("OnUpdate", SCB_UpdateDragGhost)
    SCB_UpdateDragGhost()
end

function SCB_HideDragGhost()
    if SCB.dragGhost then
        SCB.dragGhost:SetScript("OnUpdate", nil)
        SCB.dragGhost:Hide()
    end
end

function SCB_RevealUnderlyingBot(slotIndex)
    local row, slot, classInfo, roleInfo
    if not slotIndex then
        return
    end
    row = SCB.presetSlotRows[slotIndex]
    slot = SCB.presetEditorSlots[slotIndex]
    if not row or not slot then
        return
    end
    classInfo = SCB_FindClass(slot.class)
    roleInfo = SCB_FindRoleEntry(classInfo, slot.role, slot.extra)
    if row.playerOverlay then
        -- Keep the drag-owner button alive so Vanilla still delivers
        -- OnDragStop; only hide its contents while exposing the bot below.
        row.playerOverlay:SetAlpha(0)
    end
    if row.playerRoleButton then
        row.playerRoleButton:Hide()
    end
    if row.classButton and classInfo then
        SCB_SetArtButtonTexture(row.classButton, SCB.assetRoot .. classInfo.icon, nil)
        row.classButton:Show()
    end
    if row.roleButton and roleInfo then
        SCB_SetArtButtonTexture(row.roleButton, SCB_RoleTexture(roleInfo), SCB_RoleHighlightTexture(roleInfo))
        row.roleButton.scbTooltip = roleInfo.label .. "\nLeft-click next role/spec; right-click previous"
    end
end

function SCB_PresetPlayerDragStart()
    if SCB_StopPresetTutorial then SCB_StopPresetTutorial(true) end
    local present, originSlot
    if SCB_CurrentPresetSize() <= 5 then
        return
    end
    SCB.draggedPresetPlayer = this.scbPlayerKey
    originSlot = SCB.presetEditorPlayers and SCB.presetEditorPlayers[this.scbPlayerKey]
    SCB.draggedPresetPlayerOriginSlot = originSlot
    present = SCB_GetPresentHumanMap()
    if present[this.scbPlayerKey] then
        SCB_ShowDragGhost(present[this.scbPlayerKey])
    end
end

function SCB_FinishPresetPlayerDrag(groupIndex)
    local key = SCB.draggedPresetPlayer
    if not key then
        return false
    end

    SCB.draggedPresetPlayer = nil
    SCB.draggedPresetPlayerOriginSlot = nil
    SCB_HideDragGhost()
    SCB.draggedPresetPlayerHoverGroup = nil
    SCB_SetPresetGroupDragHighlight(nil)

    if groupIndex then
        SCB_AssignPresetPlayer(key, groupIndex)
    end

    SCB_RefreshPresetSlots()
    if SCB_RefreshPresetPlayers then
        SCB_RefreshPresetPlayers()
    end
    return true
end

function SCB_PresetPlayerDragStop()
    local i, groupCount
    if not SCB.draggedPresetPlayer or SCB_CurrentPresetSize() <= 5 then return end
    groupCount = math.ceil(SCB_CurrentPresetSize() / 5)
    for i = 1, groupCount do
        if SCB_FrameContainsCursor(SCB.presetGroupFrames[i]) then
            SCB_FinishPresetPlayerDrag(i)
            return
        end
    end
    -- No valid drop: restore the player overlay and its player-role artwork.
    SCB_FinishPresetPlayerDrag(nil)
end

function SCB_CancelPresetPlayerDrag()
    if not SCB.draggedPresetPlayer then
        SCB_HideDragGhost()
        return
    end
    SCB.draggedPresetPlayer = nil
    SCB.draggedPresetPlayerOriginSlot = nil
    SCB_HideDragGhost()
    SCB.draggedPresetPlayerHoverGroup = nil
    SCB_SetPresetGroupDragHighlight(nil)
    if SCB.presetPanel and SCB.presetPanel:IsShown() then
        SCB_RefreshPresetSlots()
        if SCB_RefreshPresetPlayers then
            SCB_RefreshPresetPlayers()
        end
    end
end

function SCB_PresetPlayerOnClick()
    local roster, i, info, classInfo, roleInfo, groupStart, groupEnd, j, groupSlot, size

    if SCB.draggedPresetPlayer and this.scbSlotIndex then
        SCB_FinishPresetPlayerDrag(math.floor((this.scbSlotIndex - 1) / 5) + 1)
        return
    end

    if IsShiftKeyDown and IsShiftKeyDown() and this.scbPlayerKey and this.scbSlotIndex then
        roster = SCB_GetHumanRoster()
        for i = 1, table.getn(roster) do
            if roster[i].key == this.scbPlayerKey then
                info = roster[i]
                break
            end
        end
        if info and info.classToken then
            classInfo = SCB_FindClass(string.lower(info.classToken))
        end
        if classInfo then
            roleInfo = classInfo.roles[1]
            size = SCB_CurrentPresetSize()
            groupStart = (math.floor((this.scbSlotIndex - 1) / 5) * 5) + 1
            groupEnd = groupStart + 4
            if groupEnd > size then groupEnd = size end
            for j = groupStart, groupEnd do
                groupSlot = SCB.presetEditorSlots[j]
                if groupSlot then
                    groupSlot.class = classInfo.key
                    groupSlot.role = roleInfo.role
                    groupSlot.extra = roleInfo.extra
                end
            end
            SCB_SetPresetDirty(true)
            SCB_RefreshPresetSlots()
            if SCB_RefreshPresetPlayers then
                SCB_RefreshPresetPlayers()
            end
        end
        return
    end

    if arg1 == "RightButton" and SCB_CurrentPresetSize() > 5 and this.scbPlayerKey and this.scbPlayerKey ~= "$self" then
        SCB.presetEditorPlayers[this.scbPlayerKey] = nil
        SCB_SetPresetDirty(true)
        if SCB_RefreshPresetPlayers then
            SCB_RefreshPresetPlayers()
        end
    end
end

function SCB_SetPlayerNameIdentity(button, info, draggable)
    local color
    if not button or not info then
        return
    end
    button.scbPlayerKey = info.key
    if draggable then
        button.scbTooltip = info.name .. "\n" .. SCB_L("TIP_PLAYER_DRAG", "Drag to another raid group")
    else
        button.scbTooltip = info.name
    end
    if button.label then
        button.label:SetText(info.name)
        color = SCB_ClassColor(info.classToken)
        if color then
            button.label:SetTextColor(color.r, color.g, color.b, 1)
        else
            button.label:SetTextColor(1, 1, 1, 1)
        end
    end
end

function SCB_CreatePresetPlayerNameButton(parent, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(width)
    button:SetHeight(height)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", SCB_PresetPlayerDragStart)
    button:SetScript("OnDragStop", SCB_PresetPlayerDragStop)
    button:SetScript("OnClick", SCB_PresetPlayerOnClick)
    button:SetScript("OnEnter", SCB_TooltipOnEnter)
    button:SetScript("OnLeave", SCB_TooltipOnLeave)

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", button, "LEFT", 2, 0)
    label:SetPoint("RIGHT", button, "RIGHT", -2, 0)
    label:SetJustifyH("LEFT")
    button.label = label
    return button
end

function SCB_AutoPartyPlayerSlots(roster)
    local slots = {}
    local i, info, partyIndex
    -- In a five-player party the client fixes self at slot 1 and party1..4
    -- are the actual invite-order positions. Preserve those positions even
    -- when bots are interspersed between human players.
    slots["$self"] = 1
    for i = 1, table.getn(roster) do
        info = roster[i]
        if info.key ~= "$self" and info.unit then
            local _, _, capturedIndex = string.find(info.unit, "party(%d+)")
            partyIndex = tonumber(capturedIndex)
            if partyIndex then
                slots[info.key] = partyIndex + 1
            end
        end
    end
    return slots
end

-- One authoritative map from live human players to the preset rows they cover.
-- The player overlay, hidden bot controls, blessing allocation and spawn occupancy
-- must all agree on this map.  Human placement never mutates the bot assignment
-- stored underneath the covered row.
function SCB_GetPresetHumanLayout()
    local size = SCB_CurrentPresetSize()
    local roster = SCB_GetHumanRoster()
    local present, assignedPresent, playerRows, groupCounts = {}, {}, {}, {}
    local i, info, key, groupIndex, slotIndex

    for i = 1, table.getn(roster) do
        present[roster[i].key] = roster[i]
    end

    if size <= 5 then
        local auto = SCB_AutoPartyPlayerSlots(roster)
        for key, slotIndex in pairs(auto) do
            if present[key] and slotIndex >= 1 and slotIndex <= size then
                playerRows[key] = slotIndex
                assignedPresent[key] = true
            end
        end
    else
        -- Raid presets assign humans to groups, not fixed slots. Render them in
        -- stable live-roster order at the front of each group; those exact rows
        -- are the bot assignments currently covered by humans.
        for i = 1, table.getn(roster) do
            info = roster[i]
            groupIndex = SCB.presetEditorPlayers and SCB.presetEditorPlayers[info.key]
            if groupIndex and groupIndex >= 1 and groupIndex <= math.ceil(size / 5) then
                groupCounts[groupIndex] = (groupCounts[groupIndex] or 0) + 1
                if groupCounts[groupIndex] <= 5 then
                    playerRows[info.key] = ((groupIndex - 1) * 5) + groupCounts[groupIndex]
                    assignedPresent[info.key] = true
                end
            end
        end
    end

    return roster, present, playerRows, assignedPresent
end

SCB_RefreshPresetPlayers = function()
    local size, roster, present, assignedPresent, playerRows
    local i, info, key, slotIndex, row, button, poolIndex, poolRows, draggable

    if not SCB.presetPanel then return end
    size = SCB_CurrentPresetSize()
    roster, present, playerRows, assignedPresent = SCB_GetPresetHumanLayout()

    SCB_RefreshPresetSlots()

    for i = 1, 40 do
        row = SCB.presetSlotRows[i]
        if row then
            row.scbPresentPlayerKey = nil
            if row.playerOverlay then row.playerOverlay:SetAlpha(1); row.playerOverlay:Hide() end
            if row.playerRoleButton then row.playerRoleButton.scbPlayerKey = nil; row.playerRoleButton:Hide() end
            if row.classButton then row.classButton:Show() end
        end
    end

    for key, slotIndex in pairs(playerRows) do
        if present[key] and slotIndex >= 1 and slotIndex <= size then
            row = SCB.presetSlotRows[slotIndex]
            if row then
                row.scbPresentPlayerKey = key
                if not row.playerOverlay then
                    row.playerOverlay = SCB_CreatePresetPlayerNameButton(row, 64, 26)
                    -- Final horizontal origin is applied by SCB_LayoutPresetRowGeometry.
                    row.playerOverlay:SetPoint("LEFT", row.classButton, "LEFT", 0, 0)
                    row.playerOverlay:SetFrameLevel(row:GetFrameLevel() + 4)
                end
                draggable = size > 5
                SCB_SetPlayerNameIdentity(row.playerOverlay, present[key], draggable)
                row.playerOverlay.scbSlotIndex = slotIndex
                row.playerOverlay:SetAlpha(1); row.playerOverlay:Show(); row.classButton:Hide()
                if row.blessingButton then row.blessingButton:Hide() end
                local roleInfo = SCB_GetPlayerClassRoleInfo(present[key], SCB.presetEditorPlayerRoles[key])
                if row.playerRoleButton and roleInfo then
                    row.playerRoleButton.scbPlayerKey = key
                    row.playerRoleButton.scbSlotIndex = slotIndex
                    SCB_SetArtButtonTexture(row.playerRoleButton, SCB_RoleTexture(roleInfo), SCB_RoleHighlightTexture(roleInfo))
                    row.playerRoleButton.scbTooltip = roleInfo.label .. "\nLeft-click next player role; right-click previous"
                    row.playerRoleButton:Show()
                end
            end
        end
    end

    poolIndex = 0
    if size > 5 then
        for i = 1, table.getn(roster) do
            info = roster[i]
            if not assignedPresent[info.key] then
                poolIndex = poolIndex + 1
                button = SCB.presetPlayerPoolButtons[poolIndex]
                if not button then button = SCB_CreatePresetPlayerNameButton(SCB.presetPlayerPool, 108, 22); SCB.presetPlayerPoolButtons[poolIndex] = button end
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", SCB.presetPlayerPool, "TOPLEFT", ((poolIndex - 1) - math.floor((poolIndex - 1) / 2) * 2) * 112, -14 - (math.floor((poolIndex - 1) / 2) * 24))
                SCB_SetPlayerNameIdentity(button, info, true)
                button.scbSlotIndex = nil
                button:Show()
            end
        end
    end
    for i = poolIndex + 1, table.getn(SCB.presetPlayerPoolButtons) do SCB.presetPlayerPoolButtons[i]:Hide() end
    SCB.presetPlayerPoolVisibleCount = poolIndex
    if poolIndex > 0 then
        poolRows = math.floor((poolIndex - 1) / 2) + 1
        SCB.presetPlayerPool:Show(); SCB.presetPlayerPoolLabel:Show(); SCB.presetPlayerPool:SetHeight(16 + (poolRows * 24))
    else
        SCB.presetPlayerPool:Hide(); SCB.presetPlayerPoolLabel:Hide(); SCB.presetPlayerPool:SetHeight(1)
    end
    if SCB_RefreshPresetCounters then SCB_RefreshPresetCounters() end
    if SCB_LayoutPresetGroups then SCB_LayoutPresetGroups() end
end

function SCB_LoadPreset(groupIndex, presetIndex)
    local group, preset, size
    SCB_EnsurePresetDB()
    group = SoloCraftBotsDB.presetGroups[groupIndex]
    if not group then
        return
    end
    SoloCraftBotsDB.currentPresetGroup = groupIndex
    if presetIndex and group.presets[presetIndex] then
        group.currentPreset = presetIndex
    end
    preset = group.currentPreset and group.presets[group.currentPreset] or nil
    size = group.size

    if preset then
        SCB.presetEditorSlots = SCB_NormalizePresetSlots(preset.slots, size)
        SCB.presetEditorPlayers = SCB_CopyPlayerGroups(preset.playerGroups or preset.playerSlots, size, preset.playerGroups == nil)
        SCB.presetEditorPlayerRoles = SCB_CopyPlayerRoles(preset.playerRoles)
        -- Old presets did not necessarily persist self role. Seed it once from
        -- this character's default, then it becomes an ordinary preset value.
        if not SCB.presetEditorPlayerRoles["$self"] then
            SCB.presetEditorPlayerRoles["$self"] = SCB_GetCharacterDefaultRoleTable()
            preset.playerRoles = preset.playerRoles or {}
            preset.playerRoles["$self"] = SCB.presetEditorPlayerRoles["$self"]
        end
    else
        SCB.presetEditorSlots = SCB_DefaultPresetSlots(size)
        SCB.presetEditorPlayers = { ["$self"] = 1 }
        SCB.presetEditorPlayerRoles = { ["$self"] = SCB_GetCharacterDefaultRoleTable() }
    end

    SCB_UpdatePresetSelectorText()
    SCB_RefreshPresetSlots()
    SCB_RefreshPresetPlayers()
    SCB_SetPresetDirty(false)
    if SCB_RefreshPresetSummonWarning then
        SCB_RefreshPresetSummonWarning()
    end
end

function SCB_SaveCurrentPreset()
    local group, preset, size
    SCB_EnsurePresetDB()
    group = SCB_CurrentPresetGroup()
    preset = SCB_CurrentPreset()
    if not group or not preset then
        SCB_Print("No preset selected to save.")
        return
    end
    size = group.size
    preset.slots = SCB_NormalizePresetSlots(SCB.presetEditorSlots, size)
    preset.playerGroups = SCB_CopyPlayerGroups(SCB.presetEditorPlayers, size, false)
    preset.playerSlots = nil
    preset.playerRoles = SCB_CopyPlayerRoles(SCB.presetEditorPlayerRoles)
    SCB_SetPresetDirty(false, true)
end

function SCB_PresetSaveOnClick()
    if SCB.presetDirty then
        SCB_SaveCurrentPreset()
    end
end

function SCB_GetPresetHumanOccupiedSlots()
    local occupied = {}
    local size = SCB_CurrentPresetSize()
    local roster, present, playerRows = SCB_GetPresetHumanLayout()
    local key, slotIndex, i, row

    -- Use the exact same player-to-row mapping as the visible preset editor.
    -- Any bot under any live human is inactive for automatic extras such as
    -- Paladin blessings, but its stored class/role/extra remain untouched.
    for key, slotIndex in pairs(playerRows) do
        if present[key] and slotIndex >= 1 and slotIndex <= size then
            occupied[slotIndex] = true
        end
    end

    -- Preserve the rendered row as a one-frame fallback for Vanilla event/order
    -- races. This is not a separate policy: it only prevents a visibly covered
    -- bot from briefly participating before the shared layout refresh catches up.
    for i = 1, size do
        row = SCB.presetSlotRows and SCB.presetSlotRows[i]
        if row and row.scbPresentPlayerKey then occupied[i] = true end
    end

    return occupied
end

function SCB_IsPresetSlotHumanOccupied(slotIndex)
    local occupied
    if not slotIndex then return false end
    occupied = SCB_GetPresetHumanOccupiedSlots()
    return occupied[slotIndex] == true
end

function SCB_ChoosePresetPaladinBlessing(excludeIndex)
    local counts = {}
    local occupied = SCB_GetPresetHumanOccupiedSlots()
    local i, slot, blessing, bestIndex, bestCount
    for i = 1, table.getn(SCB_PALADIN_BLESSINGS) do counts[i] = 0 end
    for i = 1, SCB_CurrentPresetSize() do
        if i ~= excludeIndex and not occupied[i] then
            slot = SCB.presetEditorSlots[i]
            if slot and slot.class == "paladin" then
                blessing, bestIndex = SCB_FindPaladinBlessing(slot.extra)
                counts[bestIndex] = (counts[bestIndex] or 0) + 1
            end
        end
    end
    bestIndex = 1
    bestCount = counts[1] or 0
    for i = 2, table.getn(SCB_PALADIN_BLESSINGS) do
        if (counts[i] or 0) < bestCount then
            bestIndex = i
            bestCount = counts[i] or 0
        end
    end
    return SCB_PALADIN_BLESSINGS[bestIndex].key
end

function SCB_PresetClassOnClick()
    local slotIndex = this.scbSlotIndex
    if SCB.draggedPresetPlayer then
        SCB_FinishPresetPlayerDrag(slotIndex)
        return
    end
    local slot = SCB.presetEditorSlots[slotIndex]
    local visible = SCB_GetVisibleClasses()
    local currentIndex = 1
    local i, classInfo, newIndex, roleInfo
    if not slot or SCB_IsPresetSlotHumanOccupied(slotIndex) then
        return
    end
    for i = 1, table.getn(visible) do
        if visible[i].key == slot.class then
            currentIndex = i
            break
        end
    end

    if IsShiftKeyDown and IsShiftKeyDown() then
        local groupStart = (math.floor((slotIndex - 1) / 5) * 5) + 1
        local groupEnd = groupStart + 4
        local size = SCB_CurrentPresetSize()
        local allMatch = true
        local j, groupSlot
        if groupEnd > size then groupEnd = size end

        -- First Shift-click on a mixed group adopts the clicked slot's current
        -- class. Once uniform, subsequent Shift-clicks rotate the whole group.
        for j = groupStart, groupEnd do
            groupSlot = SCB.presetEditorSlots[j]
            if not groupSlot or groupSlot.class ~= slot.class then
                allMatch = false
                break
            end
        end

        if allMatch then
            if arg1 == "RightButton" then
                newIndex = currentIndex - 1
                if newIndex < 1 then newIndex = table.getn(visible) end
            else
                newIndex = currentIndex + 1
                if newIndex > table.getn(visible) then newIndex = 1 end
            end
        else
            newIndex = currentIndex
        end

        classInfo = visible[newIndex]
        roleInfo = classInfo.roles[1]
        for j = groupStart, groupEnd do
            groupSlot = SCB.presetEditorSlots[j]
            if groupSlot then
                local wasPaladin = groupSlot.class == "paladin"
                local paladinBlessing
                if classInfo.key == "paladin" and not wasPaladin then
                    paladinBlessing = SCB_ChoosePresetPaladinBlessing(j)
                end
                groupSlot.class = classInfo.key
                groupSlot.role = roleInfo.role
                if classInfo.key == "paladin" then
                    if not wasPaladin then groupSlot.extra = paladinBlessing end
                    if not groupSlot.extra or groupSlot.extra == "" then groupSlot.extra = "BoK" end
                elseif classInfo.key == "shaman" then
                    groupSlot.extra = SCB_DEFAULT_SHAMAN_TOTEMS
                else
                    groupSlot.extra = roleInfo.extra
                end
            end
        end
    else
        if arg1 == "RightButton" then
            newIndex = currentIndex - 1
            if newIndex < 1 then newIndex = table.getn(visible) end
        else
            newIndex = currentIndex + 1
            if newIndex > table.getn(visible) then newIndex = 1 end
        end
        classInfo = visible[newIndex]
        roleInfo = classInfo.roles[1]
        local wasPaladin = slot.class == "paladin"
        local paladinBlessing
        if classInfo.key == "paladin" and not wasPaladin then
            paladinBlessing = SCB_ChoosePresetPaladinBlessing(slotIndex)
        end
        slot.class = classInfo.key
        slot.role = roleInfo.role
        if classInfo.key == "paladin" then
            if not wasPaladin then slot.extra = paladinBlessing end
            if not slot.extra or slot.extra == "" then slot.extra = "BoK" end
        elseif classInfo.key == "shaman" then
            slot.extra = SCB_DEFAULT_SHAMAN_TOTEMS
        else
            slot.extra = roleInfo.extra
        end
    end

    if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() else SCB_RefreshPresetSlots() end
    SCB_SetPresetDirty(true)
end

function SCB_PresetPlayerRoleOnClick()
    local slotIndex = this.scbSlotIndex
    local playerKey = this.scbPlayerKey
    local present, playerInfo, classInfo, currentRole, currentExtra, currentIndex, newIndex, roleInfo
    local _, classToken

    if SCB.draggedPresetPlayer then
        SCB_FinishPresetPlayerDrag(slotIndex)
        return
    end
    if not playerKey then
        return
    end

    present = SCB_GetPresentHumanMap()
    playerInfo = present[playerKey]
    if not playerInfo then
        return
    end

    -- Reuse the same class role list as bot slots. The player's actual class
    -- determines which roles can be selected; there is no separate player-role
    -- ruleset to drift out of sync.
    classToken = playerInfo.classToken
    if not classToken and playerInfo.unit and UnitClass then
        _, classToken = UnitClass(playerInfo.unit)
    end
    classInfo = SCB_FindClass(classToken and string.lower(classToken) or nil)
    if not classInfo or not classInfo.roles or table.getn(classInfo.roles) == 0 then
        return
    end

    if SCB.presetEditorPlayerRoles[playerKey] then
        currentRole, currentExtra = SCB_GetPlayerRoleSelection(SCB.presetEditorPlayerRoles[playerKey])
    elseif playerKey == "$self" then
        currentRole, currentExtra = SCB_GetCharacterDefaultRoleSelection()
    else
        currentRole, currentExtra = classInfo.roles[1].role, classInfo.roles[1].extra
    end
    roleInfo, currentIndex = SCB_FindRoleEntry(classInfo, currentRole, currentExtra)
    currentIndex = currentIndex or 1

    if arg1 == "RightButton" then
        newIndex = currentIndex - 1
        if newIndex < 1 then newIndex = table.getn(classInfo.roles) end
    else
        newIndex = currentIndex + 1
        if newIndex > table.getn(classInfo.roles) then newIndex = 1 end
    end

    roleInfo = classInfo.roles[newIndex]
    SCB.presetEditorPlayerRoles[playerKey] = SCB_MakePlayerRoleSelection(roleInfo.role, roleInfo.extra)
    SCB_SetArtButtonTexture(this, SCB_RoleTexture(roleInfo), SCB_RoleHighlightTexture(roleInfo))
    this.scbTooltip = roleInfo.label .. "\nLeft-click next player role; right-click previous"
    if SCB_RefreshPresetCounters then
        SCB_RefreshPresetCounters()
    end
    SCB_SetPresetDirty(true)
end

function SCB_PresetRoleOnClick()
    local slotIndex = this.scbSlotIndex
    if SCB.draggedPresetPlayer then
        SCB_FinishPresetPlayerDrag(slotIndex)
        return
    end

    -- A live player's role has its own overlay button.  This handler owns
    -- only the underlying bot assignment and must never mutate playerRoles.
    if SCB_IsPresetSlotHumanOccupied(slotIndex) then
        return
    end

    local slot = SCB.presetEditorSlots[slotIndex]
    local currentIndex, newIndex, classInfo, roleInfo
    if not slot then return end
    classInfo = SCB_FindClass(slot.class)
    roleInfo, currentIndex = SCB_FindRoleEntry(classInfo, slot.role, slot.extra)
    if arg1 == "RightButton" then
        newIndex = currentIndex - 1
        if newIndex < 1 then newIndex = table.getn(classInfo.roles) end
    else
        newIndex = currentIndex + 1
        if newIndex > table.getn(classInfo.roles) then newIndex = 1 end
    end
    roleInfo = classInfo.roles[newIndex]
    slot.role = roleInfo.role
    if slot.class == "paladin" then
        if not slot.extra or slot.extra == "" then slot.extra = "BoK" end
    elseif slot.class == "shaman" then
        if not slot.extra or slot.extra == "" then slot.extra = SCB_DEFAULT_SHAMAN_TOTEMS end
    else
        slot.extra = roleInfo.extra
    end
    if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() else SCB_RefreshPresetSlots() end
    SCB_SetPresetDirty(true)
end

function SCB_PresetBlessingOnClick()
    local slotIndex = this.scbSlotIndex
    local slot = SCB.presetEditorSlots[slotIndex]
    local blessing, currentIndex, newIndex

    if SCB.draggedPresetPlayer then
        SCB_FinishPresetPlayerDrag(slotIndex)
        return
    end
    if not slot or slot.class ~= "paladin" then
        return
    end
    if SCB_IsPresetSlotHumanOccupied(slotIndex) then
        return
    end
    if not UnitLevel or UnitLevel("player") ~= 60 then
        if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() else SCB_RefreshPresetSlots() end
        return
    end

    blessing, currentIndex = SCB_FindPaladinBlessing(slot.extra)
    if arg1 == "RightButton" then
        newIndex = currentIndex - 1
        if newIndex < 1 then newIndex = table.getn(SCB_PALADIN_BLESSINGS) end
    else
        newIndex = currentIndex + 1
        if newIndex > table.getn(SCB_PALADIN_BLESSINGS) then newIndex = 1 end
    end

    blessing = SCB_PALADIN_BLESSINGS[newIndex]
    slot.extra = blessing.key
    if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() else SCB_RefreshPresetSlots() end
    SCB_SetPresetDirty(true)
end

function SCB_GetShamanTotemQuadrant(button)
    local x, y, scale, left, right, top, bottom, midX, midY
    if not button or not GetCursorPosition then return "air" end
    x, y = GetCursorPosition()
    scale = button:GetEffectiveScale() or 1
    x, y = x / scale, y / scale
    left, right = button:GetLeft() or 0, button:GetRight() or 0
    top, bottom = button:GetTop() or 0, button:GetBottom() or 0
    midX, midY = (left + right) / 2, (top + bottom) / 2
    if y >= midY then
        if x < midX then return "air" else return "earth" end
    end
    if x < midX then return "fire" else return "water" end
end

function SCB_PresetShamanTotemOnClick()
    local slotIndex = this.scbSlotIndex
    local slot = SCB.presetEditorSlots[slotIndex]
    local groupKey, totems, current, currentIndex, newIndex, list

    if SCB.draggedPresetPlayer then
        SCB_FinishPresetPlayerDrag(slotIndex)
        return
    end
    if not slot or slot.class ~= "shaman" then return end
    if SCB_IsPresetSlotHumanOccupied(slotIndex) then return end

    groupKey = SCB_GetShamanTotemQuadrant(this)
    totems = SCB_ParseShamanTotems(slot.extra)
    current, currentIndex = SCB_FindShamanTotem(groupKey, totems[groupKey])
    list = SCB_SHAMAN_TOTEMS[groupKey]

    if arg1 == "RightButton" then
        newIndex = currentIndex - 1
        if newIndex < 1 then newIndex = table.getn(list) end
    else
        newIndex = currentIndex + 1
        if newIndex > table.getn(list) then newIndex = 1 end
    end

    totems[groupKey] = list[newIndex].key
    slot.extra = SCB_BuildShamanTotemExtra(totems)
    if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() else SCB_RefreshPresetSlots() end
    SCB_SetPresetDirty(true)
end



function SCB_PresetExtraOnClick()
    local slot = SCB.presetEditorSlots[this.scbSlotIndex]
    if not slot then return end
    if slot.class == "paladin" then
        SCB_PresetBlessingOnClick()
    elseif slot.class == "shaman" then
        SCB_PresetShamanTotemOnClick()
    end
end

function SCB_HidePresetMenus()
    if SCB.presetGroupMenu then SCB.presetGroupMenu:Hide() end
    if SCB.presetMenu then SCB.presetMenu:Hide() end
    if SCB_CommsHideTargetMenu then SCB_CommsHideTargetMenu() end
end

function SCB_GetPresetPopupDialog(frame)
    local candidate = frame
    local i, popup
    while candidate do
        if candidate.editBox then return candidate end
        if candidate.GetParent then candidate = candidate:GetParent() else candidate = nil end
    end
    for i = 1, 4 do
        popup = getglobal("StaticPopup" .. i)
        if popup and popup:IsShown() and (popup.which == "SOLOCRAFTBOTS_PRESET_NAME" or popup.which == "SOLOCRAFTBOTS_PRESET_GROUP_NAME" or popup.which == "SOLOCRAFTBOTS_PRESET_RENAME") then
            return popup
        end
    end
    return nil
end

function SCB_GetPopupEditBox(frame)
    local dialog = SCB_GetPresetPopupDialog(frame)
    if not dialog then return nil end
    if dialog.editBox then return dialog.editBox end
    if dialog.GetName then return getglobal(dialog:GetName() .. "EditBox") end
    return nil
end

function SCB_AcceptPresetName(dialog)
    local editBox = SCB_GetPopupEditBox(dialog)
    local name = editBox and editBox:GetText() or ""
    local group = SCB_CurrentPresetGroup()
    local preset
    if not name or name == "" then name = SCB.pendingPresetDefaultName or "Preset" end
    if not group then return end

    SCB.pendingNewPresetPlayerRoles = SCB_CopyPlayerRoles(SCB.presetEditorPlayerRoles)
    SCB.pendingNewPresetPlayerRoles["$self"] = SCB_GetCharacterDefaultRoleTable()
    table.insert(group.presets, {
        name = name,
        slots = SCB_NormalizePresetSlots(SCB.presetEditorSlots, group.size),
        playerGroups = SCB_CopyPlayerGroups(SCB.presetEditorPlayers, group.size, false),
        playerRoles = SCB.pendingNewPresetPlayerRoles,
    })
    SCB.pendingNewPresetPlayerRoles = nil
    group.currentPreset = table.getn(group.presets)
    SCB.pendingPresetDefaultName = nil
    SCB_LoadPreset(SoloCraftBotsDB.currentPresetGroup, group.currentPreset)
end

function SCB_AcceptPresetGroupName(dialog)
    local editBox = SCB_GetPopupEditBox(dialog)
    local name = editBox and editBox:GetText() or ""
    local source = SCB_CurrentPresetGroup()
    local size = (source and source.size) or 5
    if not name or name == "" then name = "New Group" end
    table.insert(SoloCraftBotsDB.presetGroups, {
        name = name,
        size = size,
        isDefault = false,
        presets = {},
        currentPreset = nil,
    })
    SoloCraftBotsDB.currentPresetGroup = table.getn(SoloCraftBotsDB.presetGroups)
    SCB_LoadPreset(SoloCraftBotsDB.currentPresetGroup, nil)
end

function SCB_AcceptPresetRename(dialog)
    local editBox = SCB_GetPopupEditBox(dialog)
    local name = editBox and editBox:GetText() or ""
    local group = SCB_CurrentPresetGroup()
    local index = SCB.presetRenameIndex or (group and group.currentPreset)
    local preset = group and index and group.presets[index]
    if not group or not preset or not name or name == "" then return end
    preset.name = name
    if group.currentPreset == index then SCB_UpdatePresetSelectorText() end
    SCB.presetRenameIndex = nil
end

StaticPopupDialogs["SOLOCRAFTBOTS_PRESET_RENAME"] = {
    text = SCB_L("RENAME_PRESET", "Rename preset"), button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = 1, maxLetters = 32,
    OnAccept = function() SCB_AcceptPresetRename(this) end,
    EditBoxOnEnterPressed = function()
        local dialog = SCB_GetPresetPopupDialog(this)
        if dialog then
            SCB_AcceptPresetRename(dialog)
            dialog:Hide()
        end
    end,
    EditBoxOnEscapePressed = function()
        local dialog = SCB_GetPresetPopupDialog(this)
        if dialog then dialog:Hide() end
    end,
    OnShow = function()
        local editBox = SCB_GetPopupEditBox(this)
        local group = SCB_CurrentPresetGroup()
        local index = SCB.presetRenameIndex or (group and group.currentPreset)
        local preset = group and index and group.presets[index]
        if editBox then editBox:SetText(preset and preset.name or ""); editBox:HighlightText(); editBox:SetFocus() end
    end,
    OnHide = function() SCB.presetRenameIndex = nil end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
}

function SCB_PresetRenameOnClick()
    local group = SCB_CurrentPresetGroup()
    local index = this and this.scbPresetIndex or (group and group.currentPreset)
    if not group or not index or not group.presets[index] then return end
    SCB.presetRenameIndex = index
    SCB_HidePresetMenus()
    StaticPopup_Show("SOLOCRAFTBOTS_PRESET_RENAME")
end

StaticPopupDialogs["SOLOCRAFTBOTS_PRESET_NAME"] = {
    text = "Preset name",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 32,
    OnAccept = function() SCB_AcceptPresetName(this) end,
    EditBoxOnEnterPressed = function()
        local dialog = SCB_GetPresetPopupDialog(this)
        SCB_AcceptPresetName(this)
        if dialog then dialog:Hide() end
    end,
    OnShow = function()
        local editBox = SCB_GetPopupEditBox(this)
        if editBox then
            editBox:SetText(SCB.pendingPresetDefaultName or "Preset")
            editBox:HighlightText()
            editBox:SetFocus()
        end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
}

StaticPopupDialogs["SOLOCRAFTBOTS_PRESET_GROUP_NAME"] = {
    text = "Preset group name",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 32,
    OnAccept = function() SCB_AcceptPresetGroupName(this) end,
    EditBoxOnEnterPressed = function()
        local dialog = SCB_GetPresetPopupDialog(this)
        SCB_AcceptPresetGroupName(this)
        if dialog then dialog:Hide() end
    end,
    OnShow = function()
        local editBox = SCB_GetPopupEditBox(this)
        if editBox then
            editBox:SetText("New Group")
            editBox:HighlightText()
            editBox:SetFocus()
        end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
}

function SCB_PresetGroupChoiceOnClick()
    if this.scbAddNew then
        SCB_HidePresetMenus()
        StaticPopup_Show("SOLOCRAFTBOTS_PRESET_GROUP_NAME")
        return
    end
    if this.scbGroupIndex then
        SCB_LoadPreset(this.scbGroupIndex, SoloCraftBotsDB.presetGroups[this.scbGroupIndex].currentPreset)
    end
    SCB_HidePresetMenus()
end

function SCB_PresetChoiceOnClick()
    local group = SCB_CurrentPresetGroup()
    if this.scbAddNew then
        SCB_HidePresetMenus()
        SCB.pendingPresetDefaultName = "Preset " .. ((group and table.getn(group.presets) or 0) + 1)
        StaticPopup_Show("SOLOCRAFTBOTS_PRESET_NAME")
        return
    end
    if this.scbPresetIndex then
        SCB_LoadPreset(SoloCraftBotsDB.currentPresetGroup, this.scbPresetIndex)
    end
    SCB_HidePresetMenus()
end

function SCB_DeletePresetGroupOnClick()
    local index = this.scbGroupIndex
    local group = index and SoloCraftBotsDB.presetGroups[index]
    if not group or group.isDefault then return end
    table.remove(SoloCraftBotsDB.presetGroups, index)
    if SoloCraftBotsDB.currentPresetGroup > table.getn(SoloCraftBotsDB.presetGroups) then
        SoloCraftBotsDB.currentPresetGroup = table.getn(SoloCraftBotsDB.presetGroups)
    elseif index < SoloCraftBotsDB.currentPresetGroup then
        SoloCraftBotsDB.currentPresetGroup = SoloCraftBotsDB.currentPresetGroup - 1
    end
    SCB_LoadPreset(SoloCraftBotsDB.currentPresetGroup, SCB_CurrentPresetGroup().currentPreset)
    SCB_HidePresetMenus()
end

function SCB_DeletePresetOnClick()
    local group = SCB_CurrentPresetGroup()
    local index = this.scbPresetIndex
    if not group or not index or not group.presets[index] then return end
    table.remove(group.presets, index)
    if table.getn(group.presets) == 0 then
        group.currentPreset = nil
        SCB_LoadPreset(SoloCraftBotsDB.currentPresetGroup, nil)
    else
        if group.currentPreset and group.currentPreset > table.getn(group.presets) then
            group.currentPreset = table.getn(group.presets)
        elseif index < group.currentPreset then
            group.currentPreset = group.currentPreset - 1
        end
        SCB_LoadPreset(SoloCraftBotsDB.currentPresetGroup, group.currentPreset)
    end
    SCB_HidePresetMenus()
end

function SCB_SetMenuDeleteButton(button, show, index, deleteScript)
    if not button.deleteButton then
        local del = CreateFrame("Button", nil, button)
        del:SetWidth(16)
        del:SetHeight(16)
        del:SetPoint("RIGHT", button, "RIGHT", -2, 0)
        local tex = del:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(del)
        tex:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        del.icon = tex
        del:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(SCB_L("TIP_DELETE", "Delete"), 1, 1, 1, 1)
            GameTooltip:Show()
        end)
        del:SetScript("OnLeave", SCB_TooltipOnLeave)
        button.deleteButton = del
    end
    button.deleteButton:SetScript("OnClick", deleteScript)
    if index then
        button.deleteButton.scbGroupIndex = deleteScript == SCB_DeletePresetGroupOnClick and index or nil
        button.deleteButton.scbPresetIndex = deleteScript == SCB_DeletePresetOnClick and index or nil
    end
    if show then button.deleteButton:Show() else button.deleteButton:Hide() end
end

function SCB_SetMenuRenameButton(button, show, index)
    if not button.renameButton then
        local rename = CreateFrame("Button", nil, button)
        rename:SetWidth(16)
        rename:SetHeight(16)
        rename:SetPoint("RIGHT", button, "RIGHT", -20, 0)
        local tex = rename:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(rename)
        tex:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
        rename.icon = tex
        rename.scbTooltip = SCB_L("TIP_RENAME_PRESET", "Rename preset")
        rename:SetScript("OnClick", SCB_PresetRenameOnClick)
        rename:SetScript("OnEnter", SCB_TooltipOnEnter)
        rename:SetScript("OnLeave", SCB_TooltipOnLeave)
        button.renameButton = rename
    end
    button.renameButton.scbPresetIndex = index
    if show then button.renameButton:Show() else button.renameButton:Hide() end
end

local SCB_RebuildPresetMenu

function SCB_MovePresetOnClick()
    local group = SCB_CurrentPresetGroup()
    local index = this.scbPresetIndex
    local direction = this.scbPresetMoveDirection
    local target
    local selected
    if not group or not index or not direction then return end

    target = index + direction
    if target < 1 or target > table.getn(group.presets) then return end

    selected = group.currentPreset
    group.presets[index], group.presets[target] = group.presets[target], group.presets[index]

    -- Keep the same preset selected while its list position changes.
    if selected == index then
        group.currentPreset = target
    elseif selected == target then
        group.currentPreset = index
    end

    SCB_UpdatePresetSelectorText()
    SCB_RebuildPresetMenu()
end

function SCB_SetMenuMoveButtons(button, show, index, count)
    if not button.moveUpButton then
        local up = SCB_CreateArrowButton(button, 14)
        up:SetPoint("RIGHT", button, "RIGHT", -56, 0)
        SCB_SetArrowDirection(up.scbArrowTexture, "up")
        up.scbPresetMoveDirection = -1
        up.scbTooltip = SCB_L("TIP_MOVE_PRESET_UP", "Move preset up")
        up:SetScript("OnClick", SCB_MovePresetOnClick)
        up:SetScript("OnEnter", SCB_TooltipOnEnter)
        up:SetScript("OnLeave", SCB_TooltipOnLeave)
        button.moveUpButton = up

        local down = SCB_CreateArrowButton(button, 14)
        down:SetPoint("RIGHT", button, "RIGHT", -38, 0)
        SCB_SetArrowDirection(down.scbArrowTexture, "down")
        down.scbPresetMoveDirection = 1
        down.scbTooltip = SCB_L("TIP_MOVE_PRESET_DOWN", "Move preset down")
        down:SetScript("OnClick", SCB_MovePresetOnClick)
        down:SetScript("OnEnter", SCB_TooltipOnEnter)
        down:SetScript("OnLeave", SCB_TooltipOnLeave)
        button.moveDownButton = down
    end

    button.moveUpButton.scbPresetIndex = index
    button.moveDownButton.scbPresetIndex = index

    if show and index and index > 1 then button.moveUpButton:Show() else button.moveUpButton:Hide() end
    if show and index and count and index < count then button.moveDownButton:Show() else button.moveDownButton:Hide() end
end

function SCB_RebuildPresetGroupMenu()
    local count = table.getn(SoloCraftBotsDB.presetGroups)
    local total = count + 1
    local i, button, group
    for i = 1, total do
        button = SCB.presetGroupMenuButtons[i]
        if not button then
            button = SCB_CreateTextButton(SCB.presetGroupMenu, nil, math.max(1, SCB.presetGroupMenu:GetWidth() - 8), 20, "")
            button:SetPoint("TOPLEFT", SCB.presetGroupMenu, "TOPLEFT", 4, -4 - ((i - 1) * 20))
            button.label:ClearAllPoints()
            button.label:SetPoint("LEFT", button, "LEFT", 3, 0)
            button.label:SetPoint("RIGHT", button, "RIGHT", -20, 0)
            button.label:SetJustifyH("LEFT")
            button:SetScript("OnClick", SCB_PresetGroupChoiceOnClick)
            SCB.presetGroupMenuButtons[i] = button
        end
        if i == 1 then
            button.label:SetText("<Add New Group>")
            button.label:SetTextColor(0.82, 0.82, 0.82, 1)
            button.scbAddNew = true
            button.scbGroupIndex = nil
            SCB_SetMenuDeleteButton(button, false, nil, SCB_DeletePresetGroupOnClick)
            if button.renameButton then button.renameButton:Hide() end
        else
            group = SoloCraftBotsDB.presetGroups[i - 1]
            button.label:SetText(group.name)
            if group.isDefault then
                button.label:SetTextColor(1, 0.82, 0, 1)
            else
                button.label:SetTextColor(0.82, 0.82, 0.82, 1)
            end
            button.scbAddNew = nil
            button.scbGroupIndex = i - 1
            SCB_SetMenuDeleteButton(button, not group.isDefault, i - 1, SCB_DeletePresetGroupOnClick)
            if button.renameButton then button.renameButton:Hide() end
        end
        button:Show()
    end
    for i = total + 1, table.getn(SCB.presetGroupMenuButtons) do
        SCB.presetGroupMenuButtons[i]:Hide()
    end
    SCB.presetGroupMenu:SetHeight(8 + (total * 20))
end

SCB_RebuildPresetMenu = function()
    local group = SCB_CurrentPresetGroup()
    local count = group and table.getn(group.presets) or 0
    local total = count + 1
    local i, button, preset
    for i = 1, total do
        button = SCB.presetNameMenuButtons[i]
        if not button then
            button = SCB_CreateTextButton(SCB.presetMenu, nil, math.max(1, SCB.presetMenu:GetWidth() - 8), 20, "")
            button:SetPoint("TOPLEFT", SCB.presetMenu, "TOPLEFT", 4, -4 - ((i - 1) * 20))
            button.label:ClearAllPoints()
            button.label:SetPoint("LEFT", button, "LEFT", 3, 0)
            button.label:SetPoint("RIGHT", button, "RIGHT", -74, 0)
            button.label:SetJustifyH("LEFT")
            button:SetScript("OnClick", SCB_PresetChoiceOnClick)
            SCB.presetNameMenuButtons[i] = button
        end
        if i == 1 then
            button.label:SetText("<Add New Preset>")
            button.scbAddNew = true
            button.scbPresetIndex = nil
            SCB_SetMenuDeleteButton(button, false, nil, SCB_DeletePresetOnClick)
            SCB_SetMenuRenameButton(button, false, nil)
            SCB_SetMenuMoveButtons(button, false, nil, count)
        else
            preset = group.presets[i - 1]
            button.label:SetText(preset.name or ("Preset " .. (i - 1)))
            button.scbAddNew = nil
            button.scbPresetIndex = i - 1
            SCB_SetMenuDeleteButton(button, true, i - 1, SCB_DeletePresetOnClick)
            SCB_SetMenuRenameButton(button, true, i - 1)
            SCB_SetMenuMoveButtons(button, true, i - 1, count)
        end
        button:Show()
    end
    for i = total + 1, table.getn(SCB.presetNameMenuButtons) do
        SCB.presetNameMenuButtons[i]:Hide()
    end
    SCB.presetMenu:SetHeight(8 + (total * 20))
end

function SCB_PresetGroupSelectorOnClick()
    SCB_RebuildPresetGroupMenu()
    if SCB.presetGroupMenu:IsShown() then
        SCB.presetGroupMenu:Hide()
    else
        if SCB.presetMenu then SCB.presetMenu:Hide() end
        SCB.presetGroupMenu:Show()
        SCB.presetGroupMenu:Raise()
    end
end

function SCB_PresetSelectorOnClick()
    SCB_RebuildPresetMenu()
    if SCB.presetMenu:IsShown() then
        SCB.presetMenu:Hide()
    else
        if SCB.presetGroupMenu then SCB.presetGroupMenu:Hide() end
        SCB.presetMenu:Show()
        SCB.presetMenu:Raise()
    end
end

local SCB_PRESET_CONVERT_NOW = "__SCB_CONVERT_NOW__"
local SCB_PRESET_WAIT_RAID = "__SCB_WAIT_RAID__"
local SCB_PRESET_WAIT_BOOTSTRAP = "__SCB_WAIT_BOOTSTRAP__"
SCB.PRESET_WAIT_REPLACEMENT = "__SCB_WAIT_REPLACEMENT__"
SCB.PRESET_REMOVE_SURVIVOR = "__SCB_REMOVE_SURVIVOR__"
SCB.PRESET_WAIT_SURVIVOR_GONE = "__SCB_WAIT_SURVIVOR_GONE__"
SCB.PRESET_WAIT_GROUP = "__SCB_WAIT_GROUP__"
SCB.PRESET_WAIT_FINAL_ROSTER = "__SCB_WAIT_FINAL_ROSTER__"
SCB.PRESET_CHECK_COMBAT = "__SCB_CHECK_COMBAT__"
SCB.PRESET_ARRANGE_PLAYERS = "__SCB_ARRANGE_PLAYERS__"
SCB.PRESET_TRACK_ROSTER = "__SCB_TRACK_ROSTER__"

function SCB_PresetGroupHasCombat()
    local count, i, unit, pet
    if not UnitAffectingCombat then return false end

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        count = GetNumRaidMembers()
        for i = 1, count do
            unit = "raid" .. i
            if UnitAffectingCombat(unit) then return true end
            pet = unit .. "pet"
            if (not UnitExists or UnitExists(pet)) and UnitAffectingCombat(pet) then return true end
        end
        return false
    end

    if UnitAffectingCombat("player") then return true end
    if (not UnitExists or UnitExists("pet")) and UnitAffectingCombat("pet") then return true end

    count = GetNumPartyMembers and GetNumPartyMembers() or 0
    for i = 1, count do
        unit = "party" .. i
        if UnitAffectingCombat(unit) then return true end
        pet = unit .. "pet"
        if (not UnitExists or UnitExists(pet)) and UnitAffectingCombat(pet) then return true end
    end

    return false
end

function SCB_ArrangePresetPlayers()
    local desired = SCB.presetHumanGroups or {}
    local key, wantedGroup, wantedName, i, name, _, currentGroup
    if not SetRaidSubgroup or not GetRaidRosterInfo or not GetNumRaidMembers then return true end
    if GetNumRaidMembers() == 0 then return false end

    -- Resolve each human by name immediately before moving them. Raid indices
    -- can change after SetRaidSubgroup(), so never cache an index across moves.
    for key, wantedGroup in pairs(desired) do
        wantedName = SCB_PresetPlayerDisplayName(key)
        if wantedName then
            for i = 1, GetNumRaidMembers() do
                name, _, currentGroup = GetRaidRosterInfo(i)
                if name == wantedName then
                    if currentGroup ~= wantedGroup then
                        SetRaidSubgroup(i, wantedGroup)
                    end
                    break
                end
            end
        end
    end

    -- Verify from a fresh roster snapshot. If the server has not reflected the
    -- moves yet, leave the queue parked here and try again next frame.
    for key, wantedGroup in pairs(desired) do
        wantedName = SCB_PresetPlayerDisplayName(key)
        if wantedName then
            local found = false
            for i = 1, GetNumRaidMembers() do
                name, _, currentGroup = GetRaidRosterInfo(i)
                if name == wantedName then
                    found = true
                    if currentGroup ~= wantedGroup then return false end
                    break
                end
            end
            if not found then return false end
        end
    end
    return true
end

function SCB_ProbeSurvivorWorldPresence(name)
    local hadTarget, oldTargetName, found
    if not name or name == "" or not TargetByName or not UnitName then
        return false
    end

    hadTarget = UnitExists and UnitExists("target")
    oldTargetName = hadTarget and UnitName("target") or nil

    -- Exact matching matters here: a failed lookup must not accept the closest
    -- partial name. TargetByName leaves the current target unchanged on failure.
    TargetByName(name, true)
    found = UnitName("target") == name

    -- Restore the player's previous targeting state only if our successful
    -- probe actually changed it. A failed exact lookup leaves it untouched.
    if found and oldTargetName ~= name then
        if hadTarget then
            if TargetLastTarget then TargetLastTarget() end
        elseif ClearTarget then
            ClearTarget()
        end
    end

    return found
end

-- Authoritative preset role tracking ----------------------------------------------
-- Initial preset spawning establishes bot-relative order in Blizzard's own group
-- roster. Raids use authoritative subgroup order; five-player parties use
-- player/party1..party4 order. Roles still come only from the preset: roster order
-- is used solely to bind each bot name to its logical preset assignment.
function SCB_CreateRaidRoleTracker(slots, size, occupied, group, snapshot)
    local tracker = {
        version = 5,
        mode = size <= 5 and "party" or "raid",
        ready = false,
        allowFinalize = false,
        size = size,
        zone = size > 5 and ((GetRealZoneText and GetRealZoneText()) or "") or "",
        presetGroupID = group and group.id or nil,
        presetGroupName = group and group.name or nil,
        presetName = snapshot and snapshot.presetName or (SCB_CurrentPreset() and SCB_CurrentPreset().name or nil),
        assignments = {},
        players = {},
    }
    local i, slot, g, player

    for i = 1, size do
        slot = slots[i]
        g = math.floor((i - 1) / 5) + 1
        tracker.assignments[i] = {
            slotIndex = i,
            group = g,
            class = slot.class,
            role = slot.role,
            extra = slot.extra,
            command = SCB_BuildSpawnCommand(slot.class, slot.role, slot.extra),
            initialActive = not occupied[i],
            botName = nil,
        }
    end

    if snapshot and snapshot.players then
        for i = 1, table.getn(snapshot.players) do
            player = snapshot.players[i]
            table.insert(tracker.players, {
                key = player.name,
                name = player.name,
                group = player.group or 1,
                slotIndex = player.slotIndex,
                role = player.role,
                extra = player.extra,
            })
        end
    end

    -- Keep the existing SavedVariables field name for migration compatibility.
    SoloCraftBotsCharDB.raidRoleTracker = tracker
    return tracker
end

function SCB_GetRaidBotsByGroup()
    local result = {}
    local count = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local i, name, _, subgroup
    for i = 1, 8 do result[i] = {} end
    for i = 1, count do
        name = UnitName and UnitName("raid" .. i) or nil
        _, _, subgroup = GetRaidRosterInfo(i)
        if name and subgroup and SCB_IsBotName(name) then
            table.insert(result[subgroup], { name = name, raidIndex = i })
        end
    end
    return result
end

-- Apply SCB's known preset tank roles to pfUI when it is available.
-- pfUI does not expose a public ToggleTank function: its own popup toggle writes
-- directly to pfUI.uf.raid.tankrole[name] and shows the raid updater. Mirror that
-- state change, but set an explicit value rather than toggling so repeated tracker
-- refreshes can never accidentally turn a tank off.
function SCB_ApplyTrackedPfUITankRoles(tracker)
    local roles, i, assignment, player, name, frame
    if not tracker or not tracker.ready then return end
    if not pfUI or not pfUI.uf or not pfUI.uf.raid or type(pfUI.uf.raid.tankrole) ~= "table" then return end

    roles = pfUI.uf.raid.tankrole
    SCB.pfuiAutoTanks = SCB.pfuiAutoTanks or {}

    -- Only undo tank flags that SCB itself previously applied. Never sweep pfUI's
    -- whole tank table, because the user may have unrelated manual assignments.
    for name in pairs(SCB.pfuiAutoTanks) do
        roles[name] = nil
    end
    SCB.pfuiAutoTanks = {}

    for i = 1, table.getn(tracker.assignments or {}) do
        assignment = tracker.assignments[i]
        if assignment and assignment.botName and assignment.role == "tank" then
            roles[assignment.botName] = true
            SCB.pfuiAutoTanks[assignment.botName] = true
        end
    end
    for i = 1, table.getn(tracker.players or {}) do
        player = tracker.players[i]
        if player and player.name and player.role == "tank" then
            roles[player.name] = true
            SCB.pfuiAutoTanks[player.name] = true
        end
    end

    -- This is the same refresh trigger used by pfUI's own Toggle as Tank path
    -- while in a raid. Avoid forcing the raid updater visible in a party.
    if GetNumRaidMembers and GetNumRaidMembers() > 0 and pfUI.uf.raid.Show then
        pfUI.uf.raid:Show()
    end

    -- Refresh group/raid unitframes when possible. pfUI_TankIcons hooks
    -- RefreshUnit, so its icon state updates immediately as well.
    if pfUI.uf.RefreshUnit and pfUI.uf.frames then
        for i = 1, table.getn(pfUI.uf.frames) do
            frame = pfUI.uf.frames[i]
            if frame and frame.label and (frame.label == "party" or frame.label == "raid") then
                pfUI.uf:RefreshUnit(frame, "all")
            end
        end
    end
end

function SCB_TryFinalizeRaidRoleTracking()
    local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker
    local botsByGroup, expectedByGroup, g, i, assignment, expected, actual, ordinal, members
    if not tracker or tracker.ready or not tracker.assignments then return tracker and tracker.ready end
    if not tracker.allowFinalize then return false end

    expectedByGroup = {}
    for g = 1, 8 do expectedByGroup[g] = {} end
    for i = 1, table.getn(tracker.assignments) do
        assignment = tracker.assignments[i]
        if assignment.initialActive then table.insert(expectedByGroup[assignment.group], assignment) end
    end

    if tracker.mode == "party" or (tracker.size or 0) <= 5 then
        -- A party has no subgroup API, but player/party1..party4 is still the
        -- authoritative client roster order. Filter humans and ordinal-map the
        -- remaining bot names onto the preset's active bot assignments.
        if GetNumRaidMembers and GetNumRaidMembers() > 0 then return false end
        members = SCB_CollectGroupMembers()
        if table.getn(members) ~= (tracker.size or 0) then
            tracker.partyFullSeenAt = nil
            return false
        end

        actual = {}
        for i = 1, table.getn(members) do
            if members[i].isBot then table.insert(actual, { name = members[i].name }) end
        end
        expected = expectedByGroup[1]
        if table.getn(actual) ~= table.getn(expected) then return false end
        for ordinal = 1, table.getn(expected) do
            expected[ordinal].botName = actual[ordinal].name
        end
    else
        if not GetNumRaidMembers or GetNumRaidMembers() == 0 then return false end
        botsByGroup = SCB_GetRaidBotsByGroup()
        for g = 1, math.ceil((tracker.size or 0) / 5) do
            expected = expectedByGroup[g]
            actual = botsByGroup[g] or {}
            if table.getn(actual) ~= table.getn(expected) then return false end
        end
        for g = 1, math.ceil((tracker.size or 0) / 5) do
            expected = expectedByGroup[g]
            actual = botsByGroup[g] or {}
            for ordinal = 1, table.getn(expected) do
                expected[ordinal].botName = actual[ordinal].name
            end
        end
    end

    tracker.ready = true
    tracker.completedAt = GetTime and GetTime() or 0
    SCB_ApplyTrackedPfUITankRoles(tracker)
    if SCB_DebugLog then SCB_DebugLog("TRACK", "Authoritative preset bot-role map ready (" .. (tracker.mode or "raid") .. ").") end
    if SCB_RefreshRefillButton then SCB_RefreshRefillButton() end
    return true
end

function SCB_GetTrackedHumanCounts(tracker)
    local counts, names, members, i, member, player
    counts = {}
    names = {}
    for i = 1, 8 do counts[i] = 0 end
    members = SCB_CollectGroupMembers()
    for i = 1, table.getn(members) do
        member = members[i]
        if not member.isBot then names[member.name] = true end
    end
    for i = 1, table.getn(tracker.players or {}) do
        player = tracker.players[i]
        if player.name and names[player.name] then
            counts[player.group] = (counts[player.group] or 0) + 1
        end
    end
    return counts
end

function SCB_GetMissingRaidAssignments(ignoredBotName, delayedSlotIndex)
    local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker
    local missing = {}
    local currentNames, humanCounts, subgroupCounts, members, i, member, assignment, localIndex, presentHumans, occupiedSlots
    local raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if not tracker or not tracker.ready or not tracker.assignments then return missing end

    members = SCB_CollectGroupMembers()
    currentNames = {}
    for i = 1, table.getn(members) do
        if members[i].name ~= ignoredBotName then currentNames[members[i].name] = true end
    end

    if tracker.mode == "party" or (tracker.size or 0) <= 5 then
        if raidCount > 0 or table.getn(members) >= (tracker.size or 0) then return missing end

        -- Keep the original logical slots of tracked humans stable even though
        -- WoW renumbers party1..party4 after another member leaves.
        presentHumans = {}
        for i = 1, table.getn(members) do
            member = members[i]
            if not member.isBot then presentHumans[member.name] = true end
        end
        occupiedSlots = {}
        for i = 1, table.getn(tracker.players or {}) do
            if tracker.players[i].name and presentHumans[tracker.players[i].name] and tracker.players[i].slotIndex then
                occupiedSlots[tracker.players[i].slotIndex] = true
            end
        end

        for i = 1, table.getn(tracker.assignments) do
            assignment = tracker.assignments[i]
            if assignment.slotIndex ~= delayedSlotIndex and not occupiedSlots[assignment.slotIndex] and (not assignment.botName or not currentNames[assignment.botName]) then
                if table.getn(members) + table.getn(missing) < (tracker.size or 0) then
                    table.insert(missing, assignment)
                end
            end
        end
        return missing
    end

    if raidCount == 0 or raidCount >= (tracker.size or 0) then return missing end
    if tracker.zone and tracker.zone ~= "" and GetRealZoneText and GetRealZoneText() ~= tracker.zone then return missing end

    subgroupCounts = {}
    for i = 1, 8 do subgroupCounts[i] = 0 end
    for i = 1, table.getn(members) do
        member = members[i]
        if member.subgroup then subgroupCounts[member.subgroup] = (subgroupCounts[member.subgroup] or 0) + 1 end
    end
    humanCounts = SCB_GetTrackedHumanCounts(tracker)

    for i = 1, table.getn(tracker.assignments) do
        assignment = tracker.assignments[i]
        localIndex = math.mod(assignment.slotIndex - 1, 5) + 1
        -- Live assigned humans consume the front N logical rows of their group.
        -- A human leaving therefore exposes the underlying bot assignment again.
        if assignment.slotIndex ~= delayedSlotIndex and localIndex > (humanCounts[assignment.group] or 0) then
            if (not assignment.botName or not currentNames[assignment.botName]) and (subgroupCounts[assignment.group] or 0) < 5 then
                table.insert(missing, assignment)
                subgroupCounts[assignment.group] = subgroupCounts[assignment.group] + 1
            end
        end
    end
    return missing
end

function SCB_RefreshRefillButton()
    local button = SCB.presetRefillButton
    local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker
    local activeRefill = SCB.refillState and SCB.refillState.active and SCB.refillState or nil
    local anchorName = activeRefill and activeRefill.anchorName or SCB_GetKickAllAnchorForFreshBuild()
    local delayed = activeRefill and activeRefill.delayedAssignment or (anchorName and tracker and tracker.assignments and tracker.assignments[5] or nil)
    local missing
    local count
    if not button then return end
    missing = SCB_GetMissingRaidAssignments(anchorName, delayed and delayed.slotIndex or nil)
    count = table.getn(missing) + (delayed and 1 or 0)
    if count > 0 then
        if button.scbPulseMode ~= "greenloop" then SCB_StartPresetButtonPulse(button, "greenloop") end
        button.scbTooltip = string.format(SCB_L("PRESET_REFILL_TOOLTIP_READY", "Refill %d missing preset bot(s)."), count)
    else
        SCB_StopPresetButtonPulse(button)
        button.scbTooltip = SCB_L("PRESET_REFILL_TOOLTIP_EMPTY", "No tracked preset bots are missing.")
    end
end

function SCB_RefillPresetOnClick()
    local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker
    local anchorName = SCB_GetKickAllAnchorForFreshBuild()
    local delayed = anchorName and tracker and tracker.assignments and tracker.assignments[5] or nil
    local missing = SCB_GetMissingRaidAssignments(anchorName, delayed and delayed.slotIndex or nil)
    if table.getn(SCB.presetSpawnQueue) > 0 or (SCB.presetGroupWaitRemaining or 0) > 0 then
        SCB_Print(SCB_L("PRESET_REFILL_SUMMON_BUSY", "Wait for Preset Summon to finish before refilling."))
        return
    end
    if SCB.refillState and SCB.refillState.active then return end
    if table.getn(missing) == 0 and not delayed then return end
    SCB.refillState = {
        active = true,
        phase = "nextgroup",
        cooldown = 0,
        anchorName = anchorName,
        delayedAssignment = delayed,
    }
end

function SCB_GetNewRefillBots(beforeNames)
    local result = {}
    local raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local count, i, name, _, subgroup
    if raidCount > 0 then
        for i = 1, raidCount do
            name = UnitName and UnitName("raid" .. i) or nil
            _, _, subgroup = GetRaidRosterInfo(i)
            if name and SCB_IsBotName(name) and not beforeNames[name] then
                table.insert(result, { name = name, raidIndex = i, subgroup = subgroup })
            end
        end
    else
        count = (GetNumPartyMembers and GetNumPartyMembers()) or 0
        for i = 1, count do
            name = UnitName and UnitName("party" .. i) or nil
            if name and SCB_IsBotName(name) and not beforeNames[name] then
                table.insert(result, { name = name, subgroup = 1 })
            end
        end
    end
    return result
end

function SCB_RefillOnUpdate(elapsed)
    local state = SCB.refillState
    local missing, groupMissing, assignment, members, beforeNames, newBots
    local i, j, group, name, subgroup, allMoved, raidCount, now
    if not state or not state.active then return end

    if state.cooldown and state.cooldown > 0 then
        state.cooldown = state.cooldown - (elapsed or 0)
        if state.cooldown > 0 then return end
        state.cooldown = 0
    end

    if state.phase == "nextgroup" or state.phase == "combat" then
        missing = SCB_GetMissingRaidAssignments(state.anchorName, state.delayedAssignment and state.delayedAssignment.slotIndex or nil)
        if table.getn(missing) == 0 then
            if state.anchorName and state.delayedAssignment then
                state.phase = "removeanchor"
            else
                state.active = false
                state.phase = nil
                SCB_RefreshRefillButton()
            end
            return
        end
        if SCB_PresetGroupHasCombat() then
            state.phase = "combat"
            return
        end

        -- Refill one logical five-slot group per burst. All missing assignments
        -- in that group are sent in the same frame, in reverse preset order,
        -- preserving the same LIFO -> authoritative-order relationship used by
        -- the normal preset summoner. There is never more than one group burst
        -- outstanding at once.
        group = missing[1].group
        groupMissing = {}
        for i = 1, table.getn(missing) do
            if missing[i].group == group then table.insert(groupMissing, missing[i]) end
        end

        beforeNames = {}
        members = SCB_CollectGroupMembers()
        for i = 1, table.getn(members) do
            if members[i].isBot then beforeNames[members[i].name] = true end
        end

        state.group = group
        state.assignments = groupMissing
        state.beforeNames = beforeNames
        state.phase = "waitgroup"
        state.fullSeenAt = nil

        for i = table.getn(groupMissing), 1, -1 do
            assignment = groupMissing[i]
            SCB_SendSpawnCommand(assignment.command)
            if SCB_DebugLog then SCB_DebugLog("REFILL", "Requested preset slot " .. assignment.slotIndex .. " in G" .. assignment.group) end
        end
        return
    end

    if state.phase == "waitgroup" then
        newBots = SCB_GetNewRefillBots(state.beforeNames or {})
        if table.getn(newBots) < table.getn(state.assignments or {}) then
            state.fullSeenAt = nil
            return
        end
        if table.getn(newBots) ~= table.getn(state.assignments or {}) then return end

        raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
        if raidCount > 0 then
            -- All bots in this burst belong to the same logical preset group.
            -- If WoW initially placed one elsewhere, move it before ordinal
            -- mapping; no role knowledge is required to do that because every
            -- new name has the same destination subgroup.
            allMoved = true
            for i = 1, table.getn(newBots) do
                if newBots[i].subgroup ~= state.group then
                    allMoved = false
                    if not SCB_PresetGroupHasCombat() and SetRaidSubgroup and newBots[i].raidIndex then
                        SetRaidSubgroup(newBots[i].raidIndex, state.group)
                    end
                end
            end
            if not allMoved then
                state.fullSeenAt = nil
                return
            end
        end

        -- Once the whole refill burst is present in its final logical group,
        -- wait an exact 1.0 seconds before reading authoritative order. In a
        -- party this also gives the Vanilla party1..party4 ordering time to
        -- resolve after the fifth member joins.
        now = GetTime and GetTime() or 0
        if not state.fullSeenAt then
            state.fullSeenAt = now
            return
        end
        if GetTime and (now - state.fullSeenAt) < 1.0 then return end

        newBots = SCB_GetNewRefillBots(state.beforeNames or {})
        if table.getn(newBots) ~= table.getn(state.assignments or {}) then return end
        if raidCount > 0 then
            for i = 1, table.getn(newBots) do
                if newBots[i].subgroup ~= state.group then
                    state.fullSeenAt = nil
                    return
                end
            end
        end

        -- Only newly joined names participate in this ordinal map. Existing
        -- tracked bots keep their identity->role bindings. The refill burst was
        -- sent LIFO, so authoritative new-bot order maps directly onto the
        -- missing assignments in ascending preset-slot order.
        for i = 1, table.getn(state.assignments) do
            state.assignments[i].botName = newBots[i].name
        end
        SCB_ApplyTrackedPfUITankRoles(SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker)

        state.phase = "nextgroup"
        state.group = nil
        state.assignments = nil
        state.beforeNames = nil
        state.fullSeenAt = nil
        SCB_RefreshRefillButton()
        return
    end

    if state.phase == "removeanchor" then
        if SCB_PresetGroupHasCombat() then return end
        if state.anchorName and SCB_GroupHasName(state.anchorName) and UninviteByName then
            if SCB_DebugLog then SCB_DebugLog("REFILL", "Removing Kick All anchor " .. state.anchorName .. " before delayed G1S5 refill") end
            UninviteByName(state.anchorName)
        end
        state.anchorProbeRemaining = 1.0
        state.phase = "waitanchorgone"
        return
    end

    if state.phase == "waitanchorgone" then
        state.anchorProbeRemaining = (state.anchorProbeRemaining or 0) - (elapsed or 0)
        if state.anchorProbeRemaining > 0 then return end
        if SCB_ProbeSurvivorWorldPresence(state.anchorName) then
            state.anchorProbeRemaining = 1.0
            return
        end
        SCB_ClearKickAllAnchor(state.anchorName)
        state.anchorProbeRemaining = nil
        state.phase = "spawndelayed"
        return
    end

    if state.phase == "spawndelayed" then
        if SCB_PresetGroupHasCombat() then return end
        beforeNames = {}
        members = SCB_CollectGroupMembers()
        for i = 1, table.getn(members) do
            if members[i].isBot then beforeNames[members[i].name] = true end
        end
        state.beforeNames = beforeNames
        state.phase = "waitdelayed"
        state.fullSeenAt = nil
        SCB_SendSpawnCommand(state.delayedAssignment.command)
        if SCB_DebugLog then SCB_DebugLog("REFILL", "Requested delayed preset slot 5 in G1 after anchor removal") end
        return
    end

    if state.phase == "waitdelayed" then
        newBots = SCB_GetNewRefillBots(state.beforeNames or {})
        if table.getn(newBots) ~= 1 then return end
        raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
        if raidCount > 0 and newBots[1].subgroup ~= 1 then
            if not SCB_PresetGroupHasCombat() and SetRaidSubgroup and newBots[1].raidIndex then
                SetRaidSubgroup(newBots[1].raidIndex, 1)
            end
            return
        end
        now = GetTime and GetTime() or 0
        if not state.fullSeenAt then
            state.fullSeenAt = now
            return
        end
        if GetTime and (now - state.fullSeenAt) < 1.0 then return end
        newBots = SCB_GetNewRefillBots(state.beforeNames or {})
        if table.getn(newBots) ~= 1 then return end
        state.delayedAssignment.botName = newBots[1].name
        SCB_ApplyTrackedPfUITankRoles(SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker)
        state.active = false
        state.phase = nil
        state.anchorName = nil
        state.delayedAssignment = nil
        state.beforeNames = nil
        state.fullSeenAt = nil
        SCB_RefreshRefillButton()
        return
    end
end

function SCB_PresetSpawnQueueOnUpdate()
    local nextItem, bootstrapName
    local elapsed = arg1 or 0

    SCB_RefillOnUpdate(elapsed)

    -- A logical preset group is a single same-frame burst. The only timed
    -- spacing in the normal preset scheduler is the tested, exact 1.0 second
    -- boundary between logical five-slot groups.
    if SCB.presetGroupWaitRemaining and SCB.presetGroupWaitRemaining > 0 then
        SCB.presetGroupWaitRemaining = SCB.presetGroupWaitRemaining - elapsed
        if SCB.presetGroupWaitRemaining > 0 then return end
        SCB.presetGroupWaitRemaining = 0
        -- Reaching the end of the normal 1.0-second group boundary without a
        -- server combat rejection confirms that any retried burst made it past
        -- the race window. A later logical group gets a fresh retry ladder.
        if SCB.presetCombatRetryResetPending then
            SCB.presetCombatRetryFailures = 0
            SCB.presetCombatRetryResetPending = nil
        end
    end

    if SCB.presetCombatRetryWaitRemaining and SCB.presetCombatRetryWaitRemaining > 0 then
        SCB.presetCombatRetryWaitRemaining = SCB.presetCombatRetryWaitRemaining - elapsed
        if SCB.presetCombatRetryWaitRemaining > 0 then return end
        SCB.presetCombatRetryWaitRemaining = 0
    end

    while table.getn(SCB.presetSpawnQueue) > 0 do
        nextItem = SCB.presetSpawnQueue[1]

        if nextItem == SCB.PRESET_WAIT_GROUP then
            table.remove(SCB.presetSpawnQueue, 1)
            SCB.presetGroupWaitRemaining = 1.0
            if (SCB.presetCombatRetryFailures or 0) > 0 then
                SCB.presetCombatRetryResetPending = true
            end
            SCB.presetSpawnElapsed = 0
            return
        elseif nextItem == SCB.PRESET_ARRANGE_PLAYERS then
            -- Once the raid exists, put each live human into the logical preset
            -- subgroup they were assigned to before any real bot burst is sent.
            if SCB_ArrangePresetPlayers() then
                table.remove(SCB.presetSpawnQueue, 1)
                SCB.presetSpawnElapsed = 0
            else
                return
            end
        elseif nextItem == SCB.PRESET_TRACK_ROSTER then
            if SoloCraftBotsCharDB.raidRoleTracker then SoloCraftBotsCharDB.raidRoleTracker.allowFinalize = true end
            if SCB_TryFinalizeRaidRoleTracking() then
                SCB.presetCombatRetryFailures = 0
                SCB.presetCombatRetryResetPending = nil
                table.remove(SCB.presetSpawnQueue, 1)
                SCB.presetSpawnElapsed = 0
            else
                return
            end
        elseif nextItem == SCB.PRESET_CHECK_COMBAT then
            -- Gate each logical summon burst on the live combat state of every
            -- group member and pet. Keep the marker at the head of the queue
            -- while blocked; once clear, consume it and release the entire
            -- logical group in the same frame exactly as before.
            SCB.presetCombatPollRemaining = (SCB.presetCombatPollRemaining or 0) - elapsed
            if SCB.presetCombatPollRemaining > 0 then return end
            if SCB_PresetGroupHasCombat() then
                SCB.presetCombatPollRemaining = 0.50
                return
            end
            SCB.presetCombatPollRemaining = nil
            SCB.presetLastBurstCommands = {}
            SCB.presetLastBurstRequeued = nil
            table.remove(SCB.presetSpawnQueue, 1)
            SCB.presetSpawnElapsed = 0
        elseif nextItem == SCB_PRESET_CONVERT_NOW then
            if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                table.remove(SCB.presetSpawnQueue, 1)
                SCB.presetSpawnElapsed = 0
            elseif GetNumPartyMembers and GetNumPartyMembers() > 0 and ConvertToRaid then
                ConvertToRaid()
                SCB.presetSpawnQueue[1] = SCB_PRESET_WAIT_RAID
                SCB.presetSpawnElapsed = 0
                return
            else
                return
            end
        elseif nextItem == SCB_PRESET_WAIT_BOOTSTRAP then
            bootstrapName = SCB_FindFirstGroupBotName()
            if bootstrapName then
                SCB.presetCombatRetryFailures = 0
                SCB.presetCombatRetryResetPending = nil
                SCB.presetBootstrapBotName = bootstrapName
                SCB.presetSurvivorBotName = bootstrapName
                if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                    SCB.presetSpawnQueue[1] = SCB_PRESET_WAIT_RAID
                elseif ConvertToRaid then
                    ConvertToRaid()
                    SCB.presetSpawnQueue[1] = SCB_PRESET_WAIT_RAID
                end
                SCB.presetSpawnElapsed = 0
            end
            return
        elseif nextItem == SCB_PRESET_WAIT_RAID then
            if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                table.remove(SCB.presetSpawnQueue, 1)
                SCB.presetSpawnElapsed = 0
            else
                return
            end
        elseif nextItem == SCB.PRESET_WAIT_REPLACEMENT then
            -- Legacy barrier retained for compatibility with an in-flight queue
            -- created by an older build. New queues use WAIT_FINAL_ROSTER.
            if SCB_CountGroupBots() >= 2 then
                table.remove(SCB.presetSpawnQueue, 1)
                SCB.presetSpawnElapsed = 0
            else
                return
            end
        elseif nextItem == SCB.PRESET_WAIT_FINAL_ROSTER then
            -- For the new Group 1 hand-off, keep the temporary survivor until
            -- every other requested preset bot is actually visible in roster.
            -- The survivor itself occupies the held bot's place, so the target
            -- bot count equals the preset's final required bot count.
            if SCB_CountGroupBots() >= (SCB.presetExpectedBotCountBeforeHandoff or 0) then
                SCB.presetCombatRetryFailures = 0
                SCB.presetCombatRetryResetPending = nil
                table.remove(SCB.presetSpawnQueue, 1)
                SCB.presetSpawnElapsed = 0
            else
                return
            end
        elseif nextItem == SCB.PRESET_REMOVE_SURVIVOR then
            if SCB.presetSurvivorBotName and UninviteByName then
                if SCB_DebugLog then
                    SCB_DebugLog("SURVIVOR", string.format(SCB_L("DEBUG_SURVIVOR_KICK"), SCB.presetSurvivorBotName))
                end
                UninviteByName(SCB.presetSurvivorBotName)
            end
            SCB.presetSurvivorProbeRemaining = 1.0
            table.remove(SCB.presetSpawnQueue, 1)
            SCB.presetSpawnElapsed = 0
            return
        elseif nextItem == SCB.PRESET_WAIT_SURVIVOR_GONE then
            -- Leaving the raid roster is not enough: SoloCraft can keep the
            -- kicked bot physically alive in the instance for another server
            -- tick or two. Poll the exact bot name once per second and do not
            -- send the held Group 1 replacement until the world unit is gone.
            SCB.presetSurvivorProbeRemaining = (SCB.presetSurvivorProbeRemaining or 0) - elapsed
            if SCB.presetSurvivorProbeRemaining > 0 then
                return
            end

            if SCB_ProbeSurvivorWorldPresence(SCB.presetSurvivorBotName) then
                if SCB_DebugLog then
                    SCB_DebugLog("SURVIVOR", string.format(SCB_L("DEBUG_SURVIVOR_PRESENT"), SCB.presetSurvivorBotName))
                end
                SCB.presetSurvivorProbeRemaining = 1.0
                return
            end

            if SCB_DebugLog then
                SCB_DebugLog("SURVIVOR", string.format(SCB_L("DEBUG_SURVIVOR_GONE"), SCB.presetSurvivorBotName or "?"))
            end
            SCB.presetSurvivorProbeRemaining = nil
            SCB_ClearKickAllAnchor(SCB.presetSurvivorBotName)
            SCB.presetSurvivorBotName = nil
            SCB.presetBootstrapBotName = nil
            SCB.presetExpectedBotCountBeforeHandoff = nil
            table.remove(SCB.presetSpawnQueue, 1)
            SCB.presetSpawnElapsed = 0
        else
            -- Normal preset spawn commands are intentionally consumed without
            -- a per-command throttle. This makes each logical group a true
            -- same-frame burst; SCB.PRESET_WAIT_GROUP supplies the 1.0s gap.
            SCB.presetLastBurstCommands = SCB.presetLastBurstCommands or {}
            table.insert(SCB.presetLastBurstCommands, nextItem)
            SCB_SendSpawnCommand(nextItem)
            table.remove(SCB.presetSpawnQueue, 1)
        end
    end

    SCB.presetSpawnElapsed = 0
end


function SCB_QueuePresetSpawn(commands)
    local i
    if not commands or table.getn(commands) == 0 then return end
    for i = 1, table.getn(commands) do
        table.insert(SCB.presetSpawnQueue, commands[i])
    end
end


local SCB_RAID_ZONE_BY_GROUP = {
    ubrs = "Blackrock Spire",
    zg = "Zul'Gurub",
    aq20 = "Ruins of Ahn'Qiraj",
    mc = "Molten Core",
    onyxia = "Onyxia's Lair",
    bwl = "Blackwing Lair",
    aq40 = "Temple of Ahn'Qiraj",
    naxx = "Naxxramas",
}

function SCB_PresetExpectedToSummon()
    local group = SCB_CurrentPresetGroup()
    local zone = (GetRealZoneText and GetRealZoneText()) or ""
    local inInstance = false
    if IsInInstance then inInstance = IsInInstance() == 1 end
    if not group then return true end
    if (group.size or 0) <= 5 or group.id == "5man" then return true end
    if group.id == "10man" then return inInstance end
    if group.id == "worldboss" then return false end
    if SCB_RAID_ZONE_BY_GROUP[group.id] then
        return inInstance and zone == SCB_RAID_ZONE_BY_GROUP[group.id]
    end
    -- Custom groups have no authoritative location rule.
    return false
end

SCB_RefreshPresetSummonWarning = function()
    local button = SCB.presetSummonButton
    if not button or not button.label then return end
    if SCB_PresetExpectedToSummon() then
        SCB_StopPresetButtonPulse(button)
        button.scbTooltip = SCB_L("PRESET_SUMMON_TOOLTIP", "Summon this preset.")
    else
        SCB_StartPresetButtonPulse(button, "redloop")
        button.scbTooltip = SCB_L("PRESET_SUMMON_WARNING", "Raid may not be available here. Summoning could fail.")
    end
end

function SCB_GetSnapshotOccupiedSlots(snapshot)
    local occupied = {}
    local groupCounts = {}
    local i, player, groupIndex
    if not snapshot or not snapshot.players then return occupied end

    if (snapshot.size or 0) <= 5 then
        for i = 1, table.getn(snapshot.players) do
            player = snapshot.players[i]
            if player.slotIndex then occupied[player.slotIndex] = true end
        end
    else
        for i = 1, table.getn(snapshot.players) do
            player = snapshot.players[i]
            groupIndex = player.group
            groupCounts[groupIndex] = (groupCounts[groupIndex] or 0) + 1
            if groupCounts[groupIndex] <= 5 then
                occupied[((groupIndex - 1) * 5) + groupCounts[groupIndex]] = true
            end
        end
    end
    return occupied
end

function SCB_CalculateSnapshotRoleCounts(snapshot)
    local counts = { tank = 0, healer = 0, meleedps = 0, rangedps = 0 }
    local occupied = SCB_GetSnapshotOccupiedSlots(snapshot)
    local i, player, slot, role
    for i = 1, table.getn(snapshot.players or {}) do
        player = snapshot.players[i]
        role = player.role
        if counts[role] ~= nil then counts[role] = counts[role] + 1 end
    end
    for i = 1, snapshot.size or 0 do
        if not occupied[i] then
            slot = snapshot.slots and snapshot.slots[i]
            role = slot and slot.role
            if counts[role] ~= nil then counts[role] = counts[role] + 1 end
        end
    end
    return counts
end

function SCB_ValidatePresetExecutionSnapshot(snapshot, requireCurrentRoster)
    local validSizes = { [5] = true, [10] = true, [15] = true, [20] = true, [40] = true }
    local seenPlayers, groupCounts, seenPartySlots = {}, {}, {}
    local currentNames, roster = {}, nil
    local i, slot, player, role, expected, actual, name

    if type(snapshot) ~= "table" or not validSizes[snapshot.size] then
        return false, "Preset snapshot has an unsupported size."
    end
    if type(snapshot.slots) ~= "table" or table.getn(snapshot.slots) ~= snapshot.size then
        return false, "Preset snapshot is incomplete."
    end
    for i = 1, snapshot.size do
        slot = snapshot.slots[i]
        if type(slot) ~= "table" or not SCB_IsValidSpawnAssignment(slot.class, slot.role, slot.extra) then
            return false, "Preset snapshot contains an invalid bot assignment."
        end
    end

    for i = 1, table.getn(snapshot.players or {}) do
        player = snapshot.players[i]
        if type(player) ~= "table" or type(player.name) ~= "string" or player.name == "" or seenPlayers[player.name] then
            return false, "Preset snapshot contains invalid player assignments."
        end
        seenPlayers[player.name] = true
        role = player.role
        if role ~= "tank" and role ~= "healer" and role ~= "meleedps" and role ~= "rangedps" then
            return false, "Preset snapshot contains an invalid player role."
        end
        if snapshot.size <= 5 then
            if type(player.slotIndex) ~= "number" or player.slotIndex < 1 or player.slotIndex > snapshot.size or seenPartySlots[player.slotIndex] then
                return false, "Preset snapshot contains invalid party player slots."
            end
            seenPartySlots[player.slotIndex] = true
        else
            if type(player.group) ~= "number" or player.group < 1 or player.group > math.ceil(snapshot.size / 5) then
                return false, "Preset snapshot contains an invalid raid group."
            end
            groupCounts[player.group] = (groupCounts[player.group] or 0) + 1
            if groupCounts[player.group] > 5 then
                return false, "Preset snapshot assigns more than five players to one raid group."
            end
        end
    end

    actual = SCB_CalculateSnapshotRoleCounts(snapshot)
    expected = snapshot.roleCounts
    if expected then
        if tonumber(expected.tank or -1) ~= actual.tank
            or tonumber(expected.healer or -1) ~= actual.healer
            or tonumber(expected.meleedps or -1) ~= actual.meleedps
            or tonumber(expected.rangedps or -1) ~= actual.rangedps then
            return false, "Preset snapshot role counts do not match its assignments."
        end
    end

    if requireCurrentRoster then
        roster = SCB_GetHumanRoster()
        if table.getn(roster) ~= table.getn(snapshot.players or {}) then
            return false, "The human roster changed after this preset snapshot was created."
        end
        for i = 1, table.getn(roster) do currentNames[roster[i].name] = true end
        for name in pairs(seenPlayers) do
            if not currentNames[name] then
                return false, "The human roster changed after this preset snapshot was created."
            end
        end
    end
    return true
end

function SCB_BuildPresetExecutionSnapshot()
    local group = SCB_CurrentPresetGroup()
    local preset = SCB_CurrentPreset()
    local size = SCB_CurrentPresetSize()
    local slots, roster, partySlots, players, groupCounts = {}, {}, {}, {}, {}
    local i, info, assignedGroup, role, extra, fallbackRole, fallbackExtra
    local snapshot, valid, errorText

    if not group or not preset then
        return nil, "Add or select a preset first."
    end

    slots = SCB_NormalizePresetSlots(SCB.presetEditorSlots, size)
    for i = 1, size do
        if not SCB_IsValidSpawnAssignment(slots[i].class, slots[i].role, slots[i].extra) then
            return nil, "Preset contains an invalid bot assignment."
        end
    end

    roster = SCB_GetHumanRoster()
    if size <= 5 then partySlots = SCB_AutoPartyPlayerSlots(roster) end

    for i = 1, table.getn(roster) do
        info = roster[i]
        if size > 5 then
            assignedGroup = SCB.presetEditorPlayers and SCB.presetEditorPlayers[info.key]
            if not assignedGroup then
                return nil, "Assign " .. info.name .. " to a preset group first."
            end
            if assignedGroup < 1 or assignedGroup > math.ceil(size / 5) then
                return nil, "Preset contains an invalid player group assignment."
            end
            groupCounts[assignedGroup] = (groupCounts[assignedGroup] or 0) + 1
            if groupCounts[assignedGroup] > 5 then
                return nil, "Preset Group " .. assignedGroup .. " has more than five players assigned."
            end
        else
            assignedGroup = 1
            if not partySlots[info.key] then
                return nil, "Preset could not resolve the current party layout."
            end
        end

        if info.key == "$self" then
            fallbackRole, fallbackExtra = SCB_GetCharacterDefaultRoleSelection()
        else
            fallbackRole = SCB_DefaultPlayerRole(info)
            fallbackExtra = nil
        end
        role, extra = SCB_GetPlayerRoleSelection(SCB.presetEditorPlayerRoles and SCB.presetEditorPlayerRoles[info.key] or nil, fallbackRole, fallbackExtra)
        table.insert(players, {
            name = info.name,
            group = assignedGroup,
            slotIndex = size <= 5 and partySlots[info.key] or nil,
            role = role,
            extra = extra,
        })
    end

    snapshot = {
        protocol = 1,
        groupID = group.id,
        groupName = group.name or "Preset Group",
        size = size,
        presetName = preset.name or "Preset",
        slots = slots,
        players = players,
        roleCounts = SCB_CalculatePresetRoleCounts(),
    }
    valid, errorText = SCB_ValidatePresetExecutionSnapshot(snapshot, true)
    if not valid then return nil, errorText end
    return snapshot
end

function SCB_StartPresetSummonSnapshot(snapshot)
    local valid, errorText = SCB_ValidatePresetExecutionSnapshot(snapshot, true)
    local group, size, slots, commands, occupied, startBotState, survivorName
    local groupCommands, groupCount, g, i, slot, heldG1Command, hasLater, expectedBotCount
    local kickAllAnchorName, useKickAllAnchor, player

    if not valid then return false, errorText end
    if table.getn(SCB.presetSpawnQueue) > 0 or (SCB.presetGroupWaitRemaining or 0) > 0 or (SCB.presetCombatRetryWaitRemaining or 0) > 0 then
        return false, "Preset Summon is already in progress."
    end

    group = { id = snapshot.groupID, name = snapshot.groupName, size = snapshot.size }
    size = snapshot.size
    slots = SCB_CopySlots(snapshot.slots)
    commands = {}
    occupied = SCB_GetSnapshotOccupiedSlots(snapshot)
    groupCommands = {}
    groupCount = math.ceil(size / 5)

    SCB.presetCombatRetryWaitRemaining = 0
    SCB.presetCombatRetryFailures = 0
    SCB.presetCombatRetryResetPending = nil
    SCB.presetLastBurstCommands = nil
    SCB.presetLastBurstRequeued = nil

    -- Empty gate. The only permitted existing bot is the deliberate safety
    -- survivor: exactly one bot while the player is the only human.
    startBotState, survivorName = SCB_GetPresetStartBotState()
    if startBotState == "blocked" then
        return false, "Preset Summon requires an empty group, or one safety survivor with no other players."
    end
    SCB.presetSurvivorBotName = survivorName
    kickAllAnchorName = SCB_GetKickAllAnchorForFreshBuild()
    useKickAllAnchor = startBotState == "survivor" and kickAllAnchorName and survivorName == kickAllAnchorName

    SCB_CreateRaidRoleTracker(slots, size, occupied, group, snapshot)
    if SCB_RefreshRefillButton then SCB_RefreshRefillButton() end

    for g = 1, groupCount do groupCommands[g] = {} end
    for i = 1, size do
        if not occupied[i] then
            slot = slots[i]
            g = math.floor((i - 1) / 5) + 1
            table.insert(groupCommands[g], SCB_BuildSpawnCommand(slot.class, slot.role, slot.extra))
        end
    end

    if size > 5 then
        if startBotState == "survivor" then
            if not (GetNumRaidMembers and GetNumRaidMembers() > 0) then
                table.insert(commands, SCB_PRESET_CONVERT_NOW)
            end
        elseif GetNumRaidMembers and GetNumRaidMembers() > 0 then
            -- Already a raid.
        elseif ((GetNumPartyMembers and GetNumPartyMembers()) or 0) > 0 then
            table.insert(commands, SCB_PRESET_CONVERT_NOW)
        else
            SCB.presetBootstrapBotName = nil
            SCB.presetSurvivorBotName = nil
            table.insert(commands, SCB.PRESET_CHECK_COMBAT)
            table.insert(commands, SCB_BuildSpawnCommand("warrior", "tank", nil))
            table.insert(commands, SCB_PRESET_WAIT_BOOTSTRAP)
            startBotState = "survivor"
        end
    end

    if size > 5 then
        SCB.presetHumanGroups = {}
        for i = 1, table.getn(snapshot.players or {}) do
            player = snapshot.players[i]
            if player.group and player.group >= 1 and player.group <= groupCount then
                SCB.presetHumanGroups[player.name] = player.group
            end
        end
        table.insert(commands, SCB.PRESET_ARRANGE_PLAYERS)
    else
        SCB.presetHumanGroups = nil
    end

    expectedBotCount = 0
    for g = 1, groupCount do expectedBotCount = expectedBotCount + table.getn(groupCommands[g]) end

    if startBotState == "survivor" then
        if table.getn(groupCommands[1]) == 0 then
            return false, "Preset Group 1 has no bot slot available to replace the safety survivor."
        end
        if useKickAllAnchor then
            heldG1Command = groupCommands[1][table.getn(groupCommands[1])]
            table.remove(groupCommands[1], table.getn(groupCommands[1]))
        else
            heldG1Command = groupCommands[1][1]
            table.remove(groupCommands[1], 1)
        end
        SCB.presetExpectedBotCountBeforeHandoff = expectedBotCount
    else
        SCB.presetExpectedBotCountBeforeHandoff = nil
    end

    for g = 1, groupCount do
        if table.getn(groupCommands[g]) > 0 then table.insert(commands, SCB.PRESET_CHECK_COMBAT) end
        for i = table.getn(groupCommands[g]), 1, -1 do table.insert(commands, groupCommands[g][i]) end

        hasLater = false
        if g < groupCount then
            local gg
            for gg = g + 1, groupCount do
                if table.getn(groupCommands[gg]) > 0 then hasLater = true break end
            end
        end
        if hasLater then table.insert(commands, SCB.PRESET_WAIT_GROUP) end
    end

    if heldG1Command then
        table.insert(commands, SCB.PRESET_WAIT_FINAL_ROSTER)
        table.insert(commands, SCB.PRESET_REMOVE_SURVIVOR)
        table.insert(commands, SCB.PRESET_WAIT_SURVIVOR_GONE)
        table.insert(commands, SCB.PRESET_CHECK_COMBAT)
        table.insert(commands, heldG1Command)
    end

    table.insert(commands, SCB.PRESET_TRACK_ROSTER)
    SCB_QueuePresetSpawn(commands)
    return true
end

function SCB_PresetSummonOnClick()
    local snapshot, errorText = SCB_BuildPresetExecutionSnapshot()
    local ok
    if not snapshot then
        SCB_Print(errorText)
        return
    end

    -- Preserve the old normalization side effect for the visible local editor.
    SCB.presetEditorSlots = SCB_CopySlots(snapshot.slots)
    SCB_RefreshPresetPlayers()

    ok, errorText = SCB_StartPresetSummonSnapshot(snapshot)
    if not ok and errorText then SCB_Print(errorText) end
end


function SCB_StopPresetTutorial(markSeen)
    if not SCB.presetTutorial then return end
    SCB.presetTutorial:SetScript("OnUpdate", nil)
    SCB.presetTutorial:Hide()
    if SCB.presetTutorial.scbHiddenTargetRow then
        SCB.presetTutorial.scbHiddenTargetRow:Show()
        SCB.presetTutorial.scbHiddenTargetRow = nil
    end
    if SCB.presetTutorialFlash then SCB.presetTutorialFlash:Hide() end
    SCB_SetPresetGroupDragHighlight(nil)
    if markSeen then
        SoloCraftBotsCharDB.helpers = SoloCraftBotsCharDB.helpers or {}
        SoloCraftBotsCharDB.helpers.presetPlayerDrag = true
    end
end

function SCB_PresetTutorialOnUpdate()
    local f = this
    f.elapsed = (f.elapsed or 0) + arg1
    if f.elapsed < 0.50 then
        if SCB.presetTutorialFlash then
            local pulse = math.abs(math.sin((f.elapsed / 0.50) * 3 * math.pi))
            SCB.presetTutorialFlash:SetAlpha(0.12 + (pulse * 0.43)); SCB.presetTutorialFlash:Show()
        end
        f:SetAlpha(0); return
    end
    if SCB.presetTutorialFlash then SCB.presetTutorialFlash:Hide() end
    f:SetAlpha(1)
    local t = (f.elapsed - 0.50) / 2.0
    if t >= 1 then SCB_SetPresetGroupDragHighlight(nil); SCB_StopPresetTutorial(true); return end
    local x, y
    if t < 0.18 then
        x, y = f.sx, f.sy
    elseif t < 0.70 then
        local p = (t - 0.18) / 0.52
        x = f.sx + ((f.cx - f.sx) * p); y = f.sy + ((f.cy - f.sy) * p)
    else
        -- This is the tutorial's mouse-up moment. Keep the fake cursor exactly
        -- where the user released it, but snap the player representation to
        -- the first logical player row just like a real group-level drop.
        if not f.released then
            local cursorLeft, cursorTop = f.cursor:GetLeft(), f.cursor:GetTop()
            f.cursor:ClearAllPoints()
            if cursorLeft and cursorTop then
                f.cursor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorLeft, cursorTop)
            else
                f.cursor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", f.cx + 10, f.cy + 3)
            end
            if f.targetRow and f.targetRow:IsShown() then
                f.targetRow:Hide()
                f.scbHiddenTargetRow = f.targetRow
            end
            f.released = true
        end
        x, y = f.ex, f.ey
    end
    -- Match the real drag hover feedback: the destination group itself pulses
    -- gold as the cursor enters it, and remains highlighted through the drop.
    if t >= 0.64 then
        SCB_SetPresetGroupDragHighlight(f.targetGroup, 0.55 + (0.45 * math.abs(math.sin(f.elapsed * 5))))
    else
        SCB_SetPresetGroupDragHighlight(nil)
    end
    f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
end

function SCB_StartPresetTutorial()
    local source = SCB.presetSlotRows[1]
    local targetGroup = SCB.presetGroupFrames[2]
    local targetTop = SCB.presetSlotRows[6]
    local f = SCB.presetTutorial
    if not f or not source or not targetGroup or not targetTop or not source:IsShown() or not targetGroup:IsShown() then return end
    -- The tutorial ghost uses the same 84px width as a real preset row.
    -- Centre it on the row/group itself so its backdrop edges line up exactly.
    f.sx = ((source:GetLeft() + source:GetRight()) / 2)
    f.sy = ((source:GetTop() + source:GetBottom()) / 2)
    f.cx = ((targetGroup:GetLeft() + targetGroup:GetRight()) / 2)
    f.cy = ((targetGroup:GetTop() + targetGroup:GetBottom()) / 2)
    f.ex = ((targetTop:GetLeft() + targetTop:GetRight()) / 2)
    f.ey = ((targetTop:GetTop() + targetTop:GetBottom()) / 2)
    f.targetGroup = 2; f.targetRow = targetTop; f.scbHiddenTargetRow = nil; f.elapsed = 0; f.released = false; f:SetAlpha(0)
    -- SCB_PresetTutorialOnUpdate detaches the cursor from the player on the
    -- simulated mouse-up, so always restore the normal drag anchor on start.
    f.cursor:ClearAllPoints(); f.cursor:SetPoint("TOPLEFT", f.label, "CENTER", -3, 3)
    if SCB.presetTutorialFlash then
        SCB.presetTutorialFlash:ClearAllPoints(); SCB.presetTutorialFlash:SetPoint("TOPLEFT", source, "TOPLEFT", -2, 2); SCB.presetTutorialFlash:SetPoint("BOTTOMRIGHT", source, "BOTTOMRIGHT", 2, -2); SCB.presetTutorialFlash:SetAlpha(0.12); SCB.presetTutorialFlash:Show()
    end
    f.label:SetText(SCB_PresetPlayerDisplayName("$self"))
    local info = SCB_GetPresentHumanMap()["$self"]
    if info then
        local c = SCB_ClassColor(info.classToken); if c then f.label:SetTextColor(c.r, c.g, c.b, 1) end
        local role = SCB_GetPlayerClassRoleInfo(info, SCB.presetEditorPlayerRoles["$self"]); if role then f.roleIcon:SetTexture(SCB_RoleTexture(role)) end
    end
    f:Show(); f:SetScript("OnUpdate", SCB_PresetTutorialOnUpdate)
end

function SCB_MaybeStartPresetTutorial()
    SoloCraftBotsCharDB = SoloCraftBotsCharDB or {}
    SoloCraftBotsCharDB.helpers = SoloCraftBotsCharDB.helpers or {}
    if SoloCraftBotsCharDB.helpers.presetPlayerDrag then return end
    if SCB_CurrentPresetSize() < 10 then return end
    SCB_StartPresetTutorial()
end

function SCB_SetPresetToggleDirection(open)
    if not SCB.presetToggle or not SCB.presetToggle.scbArrowTexture then return end
    if open then
        SCB_SetArrowDirection(SCB.presetToggle.scbArrowTexture, "right")
    else
        SCB_SetArrowDirection(SCB.presetToggle.scbArrowTexture, "left")
    end
end

function SCB_SetPresetPanelShown(show)
    if not SCB.presetPanel then return end

    -- Presets is an attached drawer, but visibility is intentionally instant.
    -- Keeping this stateless avoids animation/toggle lock edge cases.
    SCB.presetPanel:SetScript("OnUpdate", nil)

    if show then
        SCB.presetPanel:ClearAllPoints()
        SCB.presetPanel:SetPoint("TOPRIGHT", SCB.frame, "TOPLEFT", -2, 0)
        SCB_RefreshPresetPlayers()
        SCB_RefreshPresetSummonWarning()
        SCB.presetPanel:Show()
        SCB_SetPresetToggleDirection(true)
        if SCB_MaybeStartPresetTutorial then SCB_MaybeStartPresetTutorial() end
    else
        if SCB_StopPresetTutorial then SCB_StopPresetTutorial(true) end
        SCB_CancelPresetPlayerDrag()
        SCB_HidePresetMenus()
        SCB.presetPanel:Hide()
        SCB_SetPresetToggleDirection(false)
    end

    -- Defensive: older slide builds could leave this button disabled.
    if SCB.presetToggle then SCB.presetToggle:Enable() end
    SCB.presetSlideAnimating = nil
end

function SCB_PresetToggleOnClick()
    if not SCB.presetPanel then return end
    SCB_SetPresetPanelShown(not SCB.presetPanel:IsShown())
end

function SCB_ResetTutorialHelpers()
    -- Closing Presets first mirrors what the user would do manually and also
    -- stops any running helper cleanly.  Reset afterwards so reopening the
    -- drawer can immediately demonstrate the tutorial again.
    if SCB.presetPanel and SCB.presetPanel:IsShown() then
        SCB_SetPresetPanelShown(false)
    else
        SCB_StopPresetTutorial(false)
    end
    SoloCraftBotsCharDB = SoloCraftBotsCharDB or {}
    SoloCraftBotsCharDB.helpers = {}
    SCB_Print(SCB_L("HELPERS_RESET", "Tutorial helpers reset for this character."))
end

function SCB_ResetTutorialsOnClick()
    SCB_ResetTutorialHelpers()
end

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
            local blessingButton = SCB_CreateArtButton(content, "SoloCraftBotsMainPaladinBlessing", roleSize, SCB_PALADIN_BLESSINGS[1].texture, true)
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
            roleButton.scbTooltip = classInfo.name .. " - " .. roleInfo.label .. "\nClick to spawn"
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
    -- Refill shares the removal row with Kick Dead / Kick All. Keep the three
    -- utility buttons equal-width and centred as one compact strip.
    local utilityWidth = 72
    local utilityGap = 6
    local utilityTotal = (3 * utilityWidth) + (2 * utilityGap)
    local utilityLeft = math.floor((SCB.frame:GetWidth() - utilityTotal) / 2)

    layout.refill:ClearAllPoints()
    layout.refill:SetWidth(utilityWidth)
    layout.refill:SetPoint("TOPLEFT", layout.content, "TOPLEFT", utilityLeft, y)
    layout.kickDead:ClearAllPoints()
    layout.kickDead:SetWidth(utilityWidth)
    layout.kickDead:SetPoint("LEFT", layout.refill, "RIGHT", utilityGap, 0)
    layout.kickAll:ClearAllPoints()
    layout.kickAll:SetWidth(utilityWidth)
    layout.kickAll:SetPoint("LEFT", layout.kickDead, "RIGHT", utilityGap, 0)

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
    local i, r, row, recipient, commandKey, commandInfo, button, layoutRow

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
        button.scbTooltip = recipient.label .. " - " .. SCB.commands.come.label .. "\n" .. SCB_L("TIP_CTRL_COME", "Ctrl-click: Move, then Come")
        button:SetScript("OnClick", SCB_DirectCommandOnClick)
        button:SetScript("OnEnter", SCB_TooltipOnEnter)
        button:SetScript("OnLeave", SCB_TooltipOnLeave)
        layoutRow.recipientButton = button

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
            button.scbTooltip = recipient.label .. " - " .. commandInfo.label
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
        button.scbRecipientLabel = "All"
        button.scbTooltip = commandInfo.label .. " (All)"
        button:SetScript("OnClick", SCB_DirectCommandOnClick)
        button:SetScript("OnEnter", SCB_TooltipOnEnter)
        button:SetScript("OnLeave", SCB_TooltipOnLeave)
        table.insert(standaloneButtons, button)
    end

    -- Refill belongs with the raid-maintenance actions rather than inside the
    -- Presets drawer. Its tracker/state remains preset-backed; this is only a
    -- UI relocation.
    local refill = SCB_CreateTextButton(content, "SoloCraftBotsPresetRefill", 72, 24, SCB_L("PRESET_REFILL", "Refill"))
    refill.scbTooltip = SCB_L("PRESET_REFILL_TOOLTIP_EMPTY", "No tracked preset bots are missing.")
    refill:SetScript("OnClick", SCB_RefillPresetOnClick)
    refill:SetScript("OnEnter", SCB_TooltipOnEnter)
    refill:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.presetRefillButton = refill
    SCB_SetPresetButtonGrey(refill)

    -- Native removals deliberately do not use .partybot remove. Both routes
    -- share survivor safety so the last bot is retained when the player is
    -- the only human in the group.
    local kickDead = SCB_CreateTextButton(content, "SoloCraftBotsKickDead", 72, 24, "Kick Dead")
    kickDead.scbTooltip = "Remove dead bots\nKeeps one survivor if you are the only human"
    kickDead:SetScript("OnClick", SCB_KickDeadOnClick)
    kickDead:SetScript("OnEnter", SCB_TooltipOnEnter)
    kickDead:SetScript("OnLeave", SCB_TooltipOnLeave)

    local kickAll = SCB_CreateTextButton(content, "SoloCraftBotsKickAll", 72, 24, "Kick All")
    kickAll.scbTooltip = "Remove all bots\nKeeps one survivor if you are the only human"
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
        refill = refill,
        kickDead = kickDead,
        kickAll = kickAll,
    }
    SCB_LayoutCommandUI()
end

function SCB_CreateRaidmarkUI(frame)
    local section, content = SCB_CreateCollapsibleSection(frame, "assignments", SCB_L("SECTION_ASSIGNMENTS"), 34)
    local toggleSize = 22

    -- One always-highlighted state button. Focus is the default; clicking it
    -- swaps between Focus and CC assignment modes.
    local clearMarks = SCB_CreateArtButton(section, nil, toggleSize, SCB.assetRoot .. "bin.tga")
    clearMarks:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, -2)
    clearMarks.scbTooltip = SCB_L("TIP_CLEAR_MARKS", "Clear Focus/CC marks\nTarget a party bot: clear that bot\nOtherwise: clear all bots")
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
        button.scbTooltip = mark.name .. " (uses current Focus/CC assignment mode)"
        button:SetScript("OnClick", SCB_RaidMarkOnClick)
        button:SetScript("OnEnter", SCB_TooltipOnEnter)
        button:SetScript("OnLeave", SCB_TooltipOnLeave)
    end
end

function SCB_CreateDropdownArrow(parent)
    local arrow = CreateFrame("Button", nil, parent)
    arrow:SetWidth(18)
    arrow:SetHeight(18)
    arrow:SetPoint("RIGHT", parent, "RIGHT", -2, 0)
    arrow:EnableMouse(false)
    local texture = arrow:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(arrow)
    texture:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    parent.arrow = arrow
end

function SCB_CreatePresetDropdown(parent, name, width, text, clickScript)
    local button = SCB_CreateTextButton(parent, name, width, 24, text)
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", button, "LEFT", 7, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -22, 0)
    button.label:SetJustifyH("LEFT")
    SCB_CreateDropdownArrow(button)
    button:SetScript("OnClick", clickScript)
    return button
end

function SCB_CalculatePresetRoleCounts()
    local counts = { tank = 0, healer = 0, meleedps = 0, rangedps = 0 }
    local size = SCB_CurrentPresetSize()
    local present = SCB_GetPresentHumanMap()
    local playersPerGroup = {}
    local key, groupIndex, i, g, slot, role, info

    if size > 5 then
        for key, groupIndex in pairs(SCB.presetEditorPlayers or {}) do
            if present[key] and groupIndex >= 1 and groupIndex <= math.ceil(size / 5) then
                playersPerGroup[groupIndex] = (playersPerGroup[groupIndex] or 0) + 1
                info = present[key]
                role = SCB_GetPlayerRoleSelection(SCB.presetEditorPlayerRoles[key], key == "$self" and SCB_GetCharacterDefaultRole() or SCB_DefaultPlayerRole(info))
                if counts[role] ~= nil then counts[role] = counts[role] + 1 end
            end
        end
        for i = 1, size do
            g = math.floor((i - 1) / 5) + 1
            if math.mod(i - 1, 5) + 1 > (playersPerGroup[g] or 0) then
                slot = SCB.presetEditorSlots[i]
                role = slot and slot.role
                if counts[role] ~= nil then counts[role] = counts[role] + 1 end
            end
        end
    else
        for i = 1, size do
            slot = SCB.presetEditorSlots[i]
            role = slot and slot.role
            if counts[role] ~= nil then counts[role] = counts[role] + 1 end
        end
    end
    return counts
end

SCB_RefreshPresetCounters = function()
    local counts = SCB_CalculatePresetRoleCounts()
    local key, info
    for key, info in pairs(SCB.presetCounterLabels or {}) do
        info:SetText(tostring(counts[key] or 0))
    end
end

function SCB_LayoutPresetRowGeometry()
    local groupWidth = SCB_GetLayoutValue("preset", "groupWidth")
    local groupHeight = SCB_GetLayoutValue("preset", "groupHeight")
    local roleSize = SCB_GetLayoutValue("preset", "roleSize")
    local classSize = SCB_GetLayoutValue("preset", "classSize")
    local buffSize = SCB_GetLayoutValue("preset", "buffSize")
    local borderH = SCB_GetLayoutValue("preset", "borderHorizontal")
    local borderV = SCB_GetLayoutValue("preset", "borderVertical")
    local iconH = SCB_GetLayoutValue("preset", "iconHorizontal")
    local iconV = SCB_GetLayoutValue("preset", "iconVertical")
    local rowWidth, rowHeight, roleX, classX, buffX, groupIndex, localIndex, slotIndex, groupFrame, row, totemSize, totemIndex

    if groupWidth < 1 then groupWidth = 1 end
    if groupHeight < 1 then groupHeight = 1 end
    if roleSize < 1 then roleSize = 1 end
    if classSize < 1 then classSize = 1 end
    if buffSize < 1 then buffSize = 1 end

    rowWidth = groupWidth - (2 * borderH)
    if rowWidth < 1 then rowWidth = 1 end
    rowHeight = math.max(roleSize, classSize, buffSize) + 2

    -- Preserve the current hand-tuned baseline exactly: Role x=2, Class x=29,
    -- Buff x=57 at 24px icons.  Horizontal spacing then expands/contracts both
    -- inter-icon gaps from that baseline without changing the row inset.
    roleX = 2
    classX = roleX + roleSize + 3 + iconH
    buffX = classX + classSize + 4 + iconH

    for groupIndex = 1, 8 do
        groupFrame = SCB.presetGroupFrames and SCB.presetGroupFrames[groupIndex]
        if groupFrame then
            groupFrame:SetWidth(groupWidth)
            groupFrame:SetHeight(groupHeight)
        end
        for localIndex = 1, 5 do
            slotIndex = ((groupIndex - 1) * 5) + localIndex
            row = SCB.presetSlotRows and SCB.presetSlotRows[slotIndex]
            if row and groupFrame then
                row:ClearAllPoints()
                row:SetWidth(rowWidth)
                row:SetHeight(rowHeight)
                row:SetPoint("TOPLEFT", groupFrame, "TOPLEFT", borderH, -borderV - ((localIndex - 1) * (rowHeight + iconV)))

                row.roleButton:ClearAllPoints()
                row.roleButton:SetWidth(roleSize)
                row.roleButton:SetHeight(roleSize)
                row.roleButton:SetPoint("LEFT", row, "LEFT", roleX, 0)

                row.classButton:ClearAllPoints()
                row.classButton:SetWidth(classSize)
                row.classButton:SetHeight(classSize)
                row.classButton:SetPoint("LEFT", row, "LEFT", classX, 0)

                row.blessingButton:ClearAllPoints()
                row.blessingButton:SetWidth(buffSize)
                row.blessingButton:SetHeight(buffSize)
                row.blessingButton:SetPoint("LEFT", row, "LEFT", buffX, 0)

                if row.playerRoleButton then
                    row.playerRoleButton:ClearAllPoints()
                    row.playerRoleButton:SetWidth(roleSize)
                    row.playerRoleButton:SetHeight(roleSize)
                    row.playerRoleButton:SetPoint("CENTER", row.roleButton, "CENTER", 0, 0)
                end
                if row.playerOverlay then
                    row.playerOverlay:ClearAllPoints()
                    row.playerOverlay:SetPoint("LEFT", row, "LEFT", classX, 0)
                end

                if row.blessingButton.totemIcons then
                    totemSize = math.floor((buffSize - 4) / 2)
                    if totemSize < 1 then totemSize = 1 end
                    for totemIndex = 1, 4 do
                        row.blessingButton.totemIcons[totemIndex]:SetWidth(totemSize)
                        row.blessingButton.totemIcons[totemIndex]:SetHeight(totemSize)
                    end
                end
            end
        end
    end
end

SCB_LayoutPresetGroups = function()
    local size = SCB_CurrentPresetSize()
    local groupCount = math.floor((size + 4) / 5)
    local columns = 2
    local rows, panelWidth, panelHeight, groupFrame, title
    local groupWidth, groupHeight, gapX, gapY, i, col, row, poolRows, poolExtra
    local headerHeight, twoGroupWidth, contentWidth, menuWidth

    if groupCount == 1 then
        columns = 1
    elseif groupCount > 4 then
        columns = 4
    end
    rows = math.floor((groupCount + columns - 1) / columns)

    groupWidth = SCB_GetLayoutValue("preset", "groupWidth")
    groupHeight = SCB_GetLayoutValue("preset", "groupHeight")
    SCB_LayoutPresetRowGeometry()

    -- Bordered controls use 6 frame units for the intended visible 12px gap.
    -- The Group-title row clearance stays at the existing 20 units.
    gapX = 6
    gapY = 20

    twoGroupWidth = (2 * groupWidth) + gapX
    contentWidth = (columns * groupWidth) + ((columns - 1) * gapX)
    if contentWidth < twoGroupWidth then contentWidth = twoGroupWidth end
    panelWidth = contentWidth + 24

    poolExtra = 0
    if SCB.presetPlayerPool and SCB.presetPlayerPool:IsShown() then
        poolRows = math.floor(((SCB.presetPlayerPoolVisibleCount or 0) + 1) / 2)
        poolExtra = 18 + (poolRows * 24)
    end

    headerHeight = 20
    if SCB.presetConfigurationHeading and SCB.presetConfigurationHeading.GetHeight then
        headerHeight = SCB.presetConfigurationHeading:GetHeight()
        if not headerHeight or headerHeight <= 0 then headerHeight = 20 end
    end

    -- Fixed vertical chain:
    -- 12 top inset + header + 12 + dropdown(24) + 6 + action(24)
    -- + 6 + counter(34) + 20 title clearance + groups + 12 bottom inset.
    panelHeight = 12 + headerHeight + 12 + 24 + 6 + 24 + 6 + 34 + 20
        + (rows * groupHeight) + ((rows - 1) * gapY) + 12 + poolExtra

    SCB.presetPanel:SetWidth(panelWidth)
    SCB.presetPanel:SetHeight(panelHeight)

    -- Header furniture follows the group geometry. Selectors/actions remain a
    -- two-column strip; the role counter expands to the live group-grid width.
    if SCB.presetGroupSelector then SCB.presetGroupSelector:SetWidth(groupWidth) end
    if SCB.presetSelector then SCB.presetSelector:SetWidth(groupWidth) end
    local actionGap = 3
    local actionWidth = (twoGroupWidth - (3 * actionGap)) / 4
    if SCB.presetSaveButton then SCB.presetSaveButton:SetWidth(actionWidth) end
    if SCB.presetSummonButton then SCB.presetSummonButton:SetWidth(actionWidth) end
    if SCB.presetSendButton then SCB.presetSendButton:SetWidth(actionWidth) end
    if SCB.presetRequestButton then SCB.presetRequestButton:SetWidth(actionWidth) end
    if SCB.presetSaveButton and SCB.presetGroupSelector then
        SCB.presetSaveButton:ClearAllPoints()
        SCB.presetSaveButton:SetPoint("TOPLEFT", SCB.presetGroupSelector, "BOTTOMLEFT", 0, -6)
        SCB.presetSummonButton:ClearAllPoints()
        SCB.presetSummonButton:SetPoint("LEFT", SCB.presetSaveButton, "RIGHT", actionGap, 0)
        SCB.presetSendButton:ClearAllPoints()
        SCB.presetSendButton:SetPoint("LEFT", SCB.presetSummonButton, "RIGHT", actionGap, 0)
        SCB.presetRequestButton:ClearAllPoints()
        SCB.presetRequestButton:SetPoint("LEFT", SCB.presetSendButton, "RIGHT", actionGap, 0)
    end
    if SCB.presetCounterBox then SCB.presetCounterBox:SetWidth(contentWidth) end

    -- Open dropdown menus deliberately use the two-group span, independent of
    -- whether this preset currently renders one, two or four group columns.
    menuWidth = twoGroupWidth
    if SCB.presetGroupMenu then
        SCB.presetGroupMenu:SetWidth(menuWidth)
        SCB.presetGroupMenu:ClearAllPoints()
        SCB.presetGroupMenu:SetPoint("TOPLEFT", SCB.presetGroupSelector, "BOTTOMLEFT", 0, -1)
    end
    if SCB.presetMenu then
        SCB.presetMenu:SetWidth(menuWidth)
        SCB.presetMenu:ClearAllPoints()
        SCB.presetMenu:SetPoint("TOPLEFT", SCB.presetGroupSelector, "BOTTOMLEFT", 0, -1)
    end
    for i = 1, table.getn(SCB.presetGroupMenuButtons or {}) do SCB.presetGroupMenuButtons[i]:SetWidth(menuWidth - 8) end
    for i = 1, table.getn(SCB.presetNameMenuButtons or {}) do SCB.presetNameMenuButtons[i]:SetWidth(menuWidth - 8) end

    for i = 1, 8 do
        groupFrame = SCB.presetGroupFrames[i]
        title = SCB.presetGroupTitles[i]
        if i <= groupCount then
            col = math.mod(i - 1, columns)
            row = math.floor((i - 1) / columns)

            groupFrame:ClearAllPoints()
            groupFrame:SetPoint(
                "TOPLEFT",
                SCB.presetCounterBox,
                "BOTTOMLEFT",
                col * (groupWidth + gapX),
                -20 - (row * (groupHeight + gapY))
            )
            groupFrame:Show()

            title:ClearAllPoints()
            title:SetPoint("BOTTOMLEFT", groupFrame, "TOPLEFT", 8, 2)
            title:Show()
        else
            groupFrame:Hide()
            title:Hide()
        end
    end

    if SCB.presetPlayerPool then
        SCB.presetPlayerPool:ClearAllPoints()
        SCB.presetPlayerPool:SetPoint(
            "TOPLEFT",
            SCB.presetCounterBox,
            "BOTTOMLEFT",
            3,
            -20 - (rows * groupHeight) - ((rows - 1) * gapY) - 8
        )
    end
    SCB_UpdateLayoutDebugBorders()
end
function SCB_CreatePresetUI(frame)
    local toggle = SCB_CreateArrowButton(frame, 18)
    toggle:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -41)
    toggle:SetScript("OnClick", SCB_PresetToggleOnClick)
    toggle.scbTooltip = SCB_L("TIP_PRESETS", "Open/close group presets")
    toggle:SetScript("OnEnter", SCB_TooltipOnEnter)
    toggle:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB_SetArrowDirection(toggle.scbArrowTexture, "left")
    SCB.presetToggle = toggle
    SCB.presetHeading = SCB_CreateSectionTitle(frame, SCB_L("SECTION_PRESETS"), 36, -42)

    local panel = CreateFrame("Frame", "SoloCraftBotsPresetPanel", UIParent)
    panel:SetWidth(302)
    panel:SetHeight(272)
    panel:SetPoint("TOPRIGHT", frame, "TOPLEFT", -2, 0)
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
    SCB.presetPanel = panel

    local presetHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    presetHeader:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -12)
    presetHeader:SetText(SCB_L("PRESET_CONFIGURATION"))
    presetHeader:SetTextColor(1, 0.82, 0, 1)
    SCB.presetConfigurationHeading = presetHeader

    -- Per-character preset identity: actual class is read-only; role is this
    -- character's default used only to seed newly-created presets.
    SCB.presetSelfClassFrame = CreateFrame("Frame", nil, panel)
    SCB.presetSelfClassFrame:SetWidth(20)
    SCB.presetSelfClassFrame:SetHeight(20)
    SCB.presetSelfClassFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    SCB.presetSelfClassFrame:EnableMouse(true)
    SCB.presetSelfClassFrame:SetScript("OnEnter", SCB_TooltipOnEnter)
    SCB.presetSelfClassFrame:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.presetSelfClassIcon = SCB.presetSelfClassFrame:CreateTexture(nil, "ARTWORK")
    SCB.presetSelfClassIcon:SetAllPoints(SCB.presetSelfClassFrame)

    SCB.presetSelfRoleButton = SCB_CreateArtButton(panel, nil, 20, SCB.assetRoot .. "melee.tga", true, SCB.assetRoot .. "melee_h.tga")
    SCB.presetSelfRoleButton:SetPoint("LEFT", SCB.presetSelfClassFrame, "RIGHT", 4, 0)
    SCB.presetSelfRoleButton:SetScript("OnClick", SCB_CharacterPresetRoleOnClick)
    SCB.presetSelfRoleButton:SetScript("OnEnter", SCB_TooltipOnEnter)
    SCB.presetSelfRoleButton:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB_RefreshCharacterPresetIdentity()

    local groupSelector = SCB_CreatePresetDropdown(panel, "SoloCraftBotsPresetGroupSelector", 92, "Preset Group", SCB_PresetGroupSelectorOnClick)
    groupSelector.scbTooltip = SCB_L("TIP_PRESET_GROUP", "Choose preset group")
    groupSelector:SetScript("OnEnter", SCB_TooltipOnEnter)
    groupSelector:SetScript("OnLeave", SCB_TooltipOnLeave)
    groupSelector:ClearAllPoints()
    SCB.presetGroupSelector = groupSelector

    local selector = SCB_CreatePresetDropdown(panel, "SoloCraftBotsPresetSelector", 92, "Preset", SCB_PresetSelectorOnClick)
    selector.scbTooltip = SCB_L("TIP_PRESET", "Choose preset")
    selector:SetScript("OnEnter", SCB_TooltipOnEnter)
    selector:SetScript("OnLeave", SCB_TooltipOnLeave)
    selector:ClearAllPoints()
    selector:SetPoint("TOPRIGHT", presetHeader, "BOTTOMRIGHT", 0, -12)
    SCB.presetSelector = selector

    -- Group selector depends on the Preset selector, so anchor it only after
    -- both controls exist. This keeps the right-aligned two-column grid intact.
    groupSelector:SetPoint("RIGHT", selector, "LEFT", -6, 0)


    local save = SCB_CreateTextButton(panel, "SoloCraftBotsPresetSave", 42, 24, SCB_L("SAVED", "Saved"))
    save:ClearAllPoints()
    save:SetPoint("TOPLEFT", groupSelector, "BOTTOMLEFT", 0, -6)
    save.scbTooltip = SCB_L("TIP_SAVE", "Saved when the editor matches the selected preset\nClick Unsaved to save changes")
    save:SetScript("OnClick", SCB_PresetSaveOnClick)
    save:SetScript("OnEnter", SCB_TooltipOnEnter)
    save:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.presetSaveButton = save
    SCB_SetPresetButtonGrey(save)

    local groupMenu = CreateFrame("Frame", "SoloCraftBotsPresetGroupMenu", panel)
    groupMenu:SetWidth(134)
    groupMenu:SetHeight(28)
    groupMenu:SetPoint("TOPLEFT", groupSelector, "BOTTOMLEFT", 0, -1)
    groupMenu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    groupMenu:SetBackdropColor(0.03, 0.03, 0.03, 0.98)
    groupMenu:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
    groupMenu:SetFrameStrata("DIALOG")
    groupMenu:Hide()
    SCB.presetGroupMenu = groupMenu

    local menu = CreateFrame("Frame", "SoloCraftBotsPresetMenu", panel)
    menu:SetWidth(134)
    menu:SetHeight(28)
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
    SCB.presetMenu = menu

    local groupWidth, groupHeight = 92, 158
    local g, groupFrame, groupTitle, i, localIndex, row, classButton, roleButton
    for g = 1, 8 do
        groupTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        groupTitle:SetText("Group " .. g)
        groupTitle:SetTextColor(1, 0.82, 0, 1)
        SCB.presetGroupTitles[g] = groupTitle

        groupFrame = CreateFrame("Frame", nil, panel)
        groupFrame:SetWidth(groupWidth)
        groupFrame:SetHeight(groupHeight)
        groupFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        groupFrame:SetBackdropColor(0.02, 0.02, 0.02, 0.45)
        groupFrame:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)
        SCB.presetGroupFrames[g] = groupFrame

        for localIndex = 1, 5 do
            i = ((g - 1) * 5) + localIndex
            row = CreateFrame("Frame", nil, groupFrame)
            row:SetWidth(84)
            row:SetHeight(26)
            row:SetPoint("TOPLEFT", groupFrame, "TOPLEFT", 4, -8 - ((localIndex - 1) * 29))
            row.scbSlotIndex = i

            -- Consistent grammar: [Role] [Class] for bots, [Role] [PlayerName]
            -- for live players. Player names use class colour, not class icons.
            roleButton = SCB_CreateArtButton(row, nil, 24, SCB.assetRoot .. "tank.tga", true, SCB.assetRoot .. "tank_h.tga")
            roleButton:SetPoint("LEFT", row, "LEFT", 2, 0)
            roleButton.scbSlotIndex = i
            roleButton:SetScript("OnClick", SCB_PresetRoleOnClick)
            roleButton:SetScript("OnEnter", SCB_TooltipOnEnter)
            roleButton:SetScript("OnLeave", SCB_TooltipOnLeave)

            classButton = SCB_CreateArtButton(row, nil, 24, SCB.assetRoot .. "warrior.tga", true)
            classButton:SetPoint("LEFT", row, "LEFT", 29, 0)
            classButton.scbSlotIndex = i
            classButton:SetScript("OnClick", SCB_PresetClassOnClick)
            classButton:SetScript("OnEnter", SCB_TooltipOnEnter)
            classButton:SetScript("OnLeave", SCB_TooltipOnLeave)

            row.classButton = classButton
            row.roleButton = roleButton

            local blessingButton = SCB_CreateArtButton(row, nil, 24, SCB_PALADIN_BLESSINGS[1].texture, true)
            blessingButton:SetPoint("LEFT", row, "LEFT", 57, 0)
            blessingButton.scbSlotIndex = i
            blessingButton:SetScript("OnClick", SCB_PresetExtraOnClick)
            blessingButton:SetScript("OnEnter", SCB_TooltipOnEnter)
            blessingButton:SetScript("OnLeave", SCB_TooltipOnLeave)

            -- Shaman uses this same reserved class-extra button as a compact
            -- 2x2 Air/Earth/Fire/Water selector.
            blessingButton.totemIcons = {}
            local totemPositions = {
                { "TOPLEFT", 1, -1 },
                { "TOPRIGHT", -1, -1 },
                { "BOTTOMLEFT", 1, 1 },
                { "BOTTOMRIGHT", -1, 1 },
            }
            local totemIndex, totemTexture
            for totemIndex = 1, 4 do
                totemTexture = blessingButton:CreateTexture(nil, "ARTWORK")
                totemTexture:SetWidth(10)
                totemTexture:SetHeight(10)
                totemTexture:SetPoint(totemPositions[totemIndex][1], blessingButton, totemPositions[totemIndex][1], totemPositions[totemIndex][2], totemPositions[totemIndex][3])
                totemTexture:Hide()
                blessingButton.totemIcons[totemIndex] = totemTexture
            end

            blessingButton:Hide()
            row.blessingButton = blessingButton

            -- Player role is a fully independent clickable button layered
            -- over the bot role.  The bot assignment therefore stays intact
            -- while a player's displayed/saved role is edited.
            local playerRoleButton = SCB_CreateArtButton(row, nil, 24, SCB.assetRoot .. "melee.tga", true, SCB.assetRoot .. "melee_h.tga")
            playerRoleButton:SetPoint("CENTER", roleButton, "CENTER", 0, 0)
            playerRoleButton:SetFrameLevel(row:GetFrameLevel() + 5)
            playerRoleButton.scbSlotIndex = i
            playerRoleButton:SetScript("OnClick", SCB_PresetPlayerRoleOnClick)
            playerRoleButton:SetScript("OnEnter", SCB_TooltipOnEnter)
            playerRoleButton:SetScript("OnLeave", SCB_TooltipOnLeave)
            playerRoleButton:Hide()
            row.playerRoleButton = playerRoleButton

            SCB.presetSlotRows[i] = row
            SCB.presetDropTargets[i] = row
            SCB.presetSlotButtons[i] = { classButton = classButton, roleButton = roleButton }
        end
    end

    SCB_LayoutPresetRowGeometry()
    SCB_UpdateLayoutDebugBorders()

    local playerPool = CreateFrame("Frame", nil, panel)
    playerPool:SetWidth(224)
    playerPool:SetHeight(1)
    playerPool:Hide()
    SCB.presetPlayerPool = playerPool

    local playerPoolLabel = playerPool:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playerPoolLabel:SetPoint("TOPLEFT", playerPool, "TOPLEFT", 2, 0)
    playerPoolLabel:SetText("Players")
    playerPoolLabel:SetTextColor(0.72, 0.72, 0.72, 1)
    playerPoolLabel:Hide()
    SCB.presetPlayerPoolLabel = playerPoolLabel

    local summon = SCB_CreateTextButton(panel, "SoloCraftBotsPresetSummon", 42, 24, SCB_L("PRESET_SUMMON", "Summon"))
    summon:ClearAllPoints()
    summon:SetPoint("LEFT", save, "RIGHT", 3, 0)
    summon.scbTooltip = SCB_L("PRESET_SUMMON_TOOLTIP", "Summon this preset.")
    summon:SetScript("OnClick", SCB_PresetSummonOnClick)
    summon:SetScript("OnEnter", SCB_TooltipOnEnter)
    summon:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.presetSummonButton = summon
    SCB_SetPresetButtonGrey(summon)

    local send = SCB_CreateTextButton(panel, "SoloCraftBotsPresetSend", 42, 24, SCB_L("PRESET_SEND", "Send"))
    send:SetPoint("LEFT", summon, "RIGHT", 3, 0)
    send.scbTooltip = SCB_L("PRESET_SEND_TOOLTIP", "Send this complete preset snapshot to another player.")
    send:SetScript("OnClick", SCB_CommsSendOnClick)
    send:SetScript("OnEnter", SCB_TooltipOnEnter)
    send:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.presetSendButton = send
    SCB_SetPresetButtonGrey(send)

    local request = SCB_CreateTextButton(panel, "SoloCraftBotsPresetRequest", 42, 24, SCB_L("PRESET_REQUEST", "Request"))
    request:SetPoint("LEFT", send, "RIGHT", 3, 0)
    request.scbTooltip = SCB_L("PRESET_REQUEST_TOOLTIP", "Ask another SCB player to summon this complete preset snapshot.")
    request:SetScript("OnClick", SCB_CommsRequestOnClick)
    request:SetScript("OnEnter", SCB_TooltipOnEnter)
    request:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.presetRequestButton = request
    SCB_SetPresetButtonGrey(request)

    local counterBox = CreateFrame("Frame", nil, panel)
    counterBox:SetHeight(34)
    counterBox:SetPoint("TOPRIGHT", request, "BOTTOMRIGHT", 0, -6)
    counterBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    counterBox:SetBackdropColor(0.02, 0.02, 0.02, 0.45)
    counterBox:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)
    SCB.presetCounterBox = counterBox
    SCB.presetCounterLabels = {}

    local counterRoles = {
        { key = "tank", icon = "tank.tga" },
        { key = "healer", icon = "healer.tga" },
        { key = "meleedps", icon = "melee.tga" },
        { key = "rangedps", icon = "ranged.tga" },
    }
    local counterX = 0
    local counterIndex, counterInfo, counterIcon, counterText
    local counterStripWidth = (4 * 40) + (3 * 4)
    for counterIndex = 1, 4 do
        counterInfo = counterRoles[counterIndex]
        counterIcon = counterBox:CreateTexture(nil, "ARTWORK")
        counterIcon:SetWidth(24)
        counterIcon:SetHeight(24)
        counterIcon:SetPoint("LEFT", counterBox, "CENTER", -(counterStripWidth / 2) + counterX, 0)
        counterIcon:SetTexture(SCB.assetRoot .. counterInfo.icon)

        counterText = counterBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        counterText:SetWidth(14)
        counterText:SetPoint("LEFT", counterBox, "CENTER", -(counterStripWidth / 2) + counterX + 26, 0)
        counterText:SetJustifyH("CENTER")
        counterText:SetText("0")
        SCB.presetCounterLabels[counterInfo.key] = counterText

        counterX = counterX + 44
    end

    local dragGhost = CreateFrame("Frame", "SoloCraftBotsPresetDragGhost", UIParent)
    dragGhost:SetWidth(84)
    dragGhost:SetHeight(22)
    dragGhost:SetFrameStrata("TOOLTIP")
    dragGhost:EnableMouse(false)
    local ghostBg = dragGhost:CreateTexture(nil, "BACKGROUND")
    ghostBg:SetAllPoints(dragGhost)
    ghostBg:SetTexture(0, 0, 0, 0.65)
    local ghostRole = dragGhost:CreateTexture(nil, "ARTWORK")
    ghostRole:SetWidth(18)
    ghostRole:SetHeight(18)
    ghostRole:SetPoint("LEFT", dragGhost, "LEFT", 2, 0)
    dragGhost.roleIcon = ghostRole
    local ghostLabel = dragGhost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ghostLabel:SetPoint("LEFT", dragGhost, "LEFT", 24, 0)
    ghostLabel:SetPoint("RIGHT", dragGhost, "RIGHT", -4, 0)
    ghostLabel:SetJustifyH("LEFT")
    dragGhost.label = ghostLabel
    dragGhost:Hide()
    SCB.dragGhost = dragGhost

    local tutorial = CreateFrame("Frame", "SoloCraftBotsPresetTutorial", UIParent)
    tutorial:SetWidth(84)
    tutorial:SetHeight(26)
    tutorial:SetFrameStrata("TOOLTIP")
    tutorial:EnableMouse(false)
    local tutorialBg = tutorial:CreateTexture(nil, "BACKGROUND")
    tutorialBg:SetAllPoints(tutorial)
    tutorialBg:SetTexture(0, 0, 0, 0.72)
    local tutorialRole = tutorial:CreateTexture(nil, "ARTWORK")
    tutorialRole:SetWidth(24)
    tutorialRole:SetHeight(24)
    tutorialRole:SetPoint("LEFT", tutorial, "LEFT", 1, 0)
    tutorial.roleIcon = tutorialRole
    local tutorialLabel = tutorial:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tutorialLabel:SetPoint("LEFT", tutorial, "LEFT", 29, 0)
    tutorialLabel:SetPoint("RIGHT", tutorial, "RIGHT", -3, 0)
    tutorialLabel:SetJustifyH("LEFT")
    tutorial.label = tutorialLabel
    local cursor = tutorial:CreateTexture(nil, "OVERLAY")
    cursor:SetWidth(24)
    cursor:SetHeight(24)
    cursor:SetPoint("TOPLEFT", tutorialLabel, "CENTER", -3, 3)
    cursor:SetTexture("Interface\\CURSOR\\Point")
    tutorial.cursor = cursor
    tutorial:Hide()
    SCB.presetTutorial = tutorial

    local tutorialFlash = CreateFrame("Frame", nil, UIParent)
    tutorialFlash:SetFrameStrata("TOOLTIP")
    tutorialFlash:EnableMouse(false)
    local tutorialFlashTexture = tutorialFlash:CreateTexture(nil, "OVERLAY")
    tutorialFlashTexture:SetAllPoints(tutorialFlash)
    tutorialFlashTexture:SetTexture(1, 0.82, 0.08, 1)
    tutorialFlash:Hide()
    SCB.presetTutorialFlash = tutorialFlash

    panel:Hide()
    SCB_SetPresetToggleDirection(false)
    SCB_EnsurePresetDB()
    local group = SCB_CurrentPresetGroup()
    SCB_LoadPreset(SoloCraftBotsDB.currentPresetGroup, group and group.currentPreset or nil)
    SCB_TryFinalizeRaidRoleTracking()
    SCB_RefreshRefillButton()
end


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
    title:SetText(SCB_L("ADDON_TITLE") .. " [DEV]")

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
    if command == "tutorialreset" then
        SCB_ResetTutorialHelpers()
        return
    elseif command == "debug" then
        SCB_SetDeveloperDebugEnabled(not SCB.developerDebugEnabled)
        return
    elseif command == "debugroster" then
        if not SCB.developerDebugEnabled then
            SCB_Print(SCB_L("DEBUG_MODE_REQUIRED", "Debug mode is disabled. Use /scb debug first."))
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
        if RequestRaidInfo then RequestRaidInfo() end
        SCB_RefreshMainPaladinBlessingButton()
        if SCB.presetPanel then SCB_RefreshPresetPlayers() end
        SCB_TryFinalizeRaidRoleTracking()
        SCB_ApplyTrackedPfUITankRoles(SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker)
        SCB_RefreshRefillButton()
        if SCB.initialSessionValidationPending then
            SCB.initialSessionValidationPending = false
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
                SCB_Print(SCB_L("PRESET_SUMMON_COMBAT_ABORT", "Preset Summon stopped: the server still reports a party member in combat."))
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
            SCB_DebugLog("SYSTEM", arg1 or "")
        end
    elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_SAY" then
        if SCB.developerDebugEnabled and SCB.debugServerCheck and SCB.debugServerCheck:GetChecked() then
            local sender = arg2 or ""
            local message = arg1 or ""
            if sender == "" or sender ~= UnitName("player") then
                SCB_DebugLog("CHAT", (sender ~= "" and (sender .. ": ") or "") .. message)
            end
        end
    elseif event == "PLAYER_LOGOUT" then
        SCB_SavePosition()
    end
end)
