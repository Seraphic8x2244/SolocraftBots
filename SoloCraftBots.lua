-- SoloCraft Bots
-- Clean-sheet SoloCraft PartyBot controller for WoW 1.12.1.
-- Version is sourced from SoloCraftBots.toc.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

-- SavedVariables are loaded before addon Lua files. Initialize the table
-- defensively here as well as during login so startup does not depend on the
-- addon folder name matching an ADDON_LOADED string literal.
SoloCraftBotsDB = SoloCraftBotsDB or {}

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
SCB.initialSessionValidationPending = false
SCB.lastRoster = nil

BINDING_HEADER_SOLOCRAFTBOTS = "SoloCraft Bots"
BINDING_NAME_SOLOCRAFTBOTS_TOGGLE = "Toggle SoloCraft Bots"

local function SCB_Print(text)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(SCB.prefix .. text)
    end
end

local function SCB_SendCommand(command)
    if not command or command == "" then
        return
    end
    -- Control commands use party chat so they can still be issued while dead.
    -- Bot spawning is intentionally handled separately and always uses SAY.
    SendChatMessage(".partybot " .. command, "PARTY")
end

local function SCB_ButtonBackdrop(button)
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

local function SCB_CreateTextButton(parent, name, width, height, text, allowRightClick)
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

local function SCB_CreateArtButton(parent, name, size, texturePath, allowRightClick, highlightTexturePath)
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

local function SCB_SetArtButtonTexture(button, texturePath, highlightTexturePath)
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

local function SCB_SetArtButtonAvailable(button, available)
    if not button or not button.icon then
        return
    end
    button.scbAvailable = available
    if available then
        button.icon:SetVertexColor(1, 1, 1, 1)
        button:SetAlpha(1)
    else
        button.icon:SetVertexColor(0.45, 0.45, 0.45, 1)
        button:SetAlpha(0.52)
    end
end

local function SCB_TooltipOnEnter()
    if not this or not this.scbTooltip then
        return
    end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(this.scbTooltip, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function SCB_TooltipOnLeave()
    GameTooltip:Hide()
end

local function SCB_CreateSectionTitle(parent, text, x, y)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    title:SetText(text)
    title:SetTextColor(1, 0.82, 0, 1)
    return title
end

SCB.sections = SCB.sections or {}
SCB.sectionOrder = { "commands", "assignments", "summon" }
local SCB_LayoutSections

local function SCB_EnsureSectionDB()
    SoloCraftBotsDB.sections = SoloCraftBotsDB.sections or {}
end

local function SCB_SectionToggleOnClick()
    if not this or not this.scbSectionKey then
        return
    end
    SCB_EnsureSectionDB()
    SoloCraftBotsDB.sections[this.scbSectionKey] = not SoloCraftBotsDB.sections[this.scbSectionKey]
    if SCB_LayoutSections then
        SCB_LayoutSections()
    end
end

local function SCB_CreateCollapsibleSection(parent, key, titleText, contentHeight)
    local section = CreateFrame("Frame", nil, parent)
    section:SetWidth(parent:GetWidth())
    section:SetHeight(26 + contentHeight)
    section.scbKey = key
    section.scbExpandedHeight = 26 + contentHeight
    section.scbCollapsedHeight = 26

    local toggle = SCB_CreateTextButton(section, nil, 18, 18, "-")
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

local function SCB_GetPlayerFaction()
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

local function SCB_GetVisibleClasses()
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

local function SCB_FindClass(classKey)
    local i
    for i = 1, table.getn(SCB.classes) do
        if SCB.classes[i].key == classKey then
            return SCB.classes[i]
        end
    end
    return nil
end

local function SCB_GetPlayerClassInfo()
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

local function SCB_FindRoleEntry(classInfo, role, extra)
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

local function SCB_RoleTexture(roleInfo)
    if not roleInfo then
        return nil
    end
    if roleInfo.texture then
        return roleInfo.texture
    end
    return SCB.assetRoot .. roleInfo.icon
end

local function SCB_RoleHighlightTexture(roleInfo)
    if not roleInfo or roleInfo.texture or not roleInfo.icon then
        return nil
    end
    return SCB.assetRoot .. string.gsub(roleInfo.icon, "%.tga$", "_h.tga")
end

-- -------------------------------------------------------------------------
-- Session state / bot identity
-- -------------------------------------------------------------------------

local function SCB_GetRosterNames()
    local names = {}
    local i, name

    name = UnitName("player")
    if name then
        names[name] = true
    end

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            name = UnitName("raid" .. i)
            if name then
                names[name] = true
            end
        end
    elseif GetNumPartyMembers then
        for i = 1, GetNumPartyMembers() do
            name = UnitName("party" .. i)
            if name then
                names[name] = true
            end
        end
    end
    return names
end

local function SCB_EnsureSessionDB()
    SoloCraftBotsDB.session = SoloCraftBotsDB.session or {}
    SoloCraftBotsDB.session.knownBots = SoloCraftBotsDB.session.knownBots or {}
    SoloCraftBotsDB.session.state = SoloCraftBotsDB.session.state or {}
    if not SoloCraftBotsDB.session.state.distance then
        SoloCraftBotsDB.session.state.distance = "near"
    end
end

local function SCB_ResetSessionState()
    SCB_EnsureSessionDB()
    SoloCraftBotsDB.session.knownBots = {}
    SoloCraftBotsDB.session.state = { distance = "near" }
end

local function SCB_RefreshDistanceButtons()
    if not SCB.distanceButton then
        return
    end
    SCB_EnsureSessionDB()
    local state = SoloCraftBotsDB.session.state.distance
    if state == "far" then
        SCB_SetArtButtonTexture(SCB.distanceButton, SCB.assetRoot .. "distance.tga", nil)
        SCB.distanceButton.scbTooltip = "Spawn Far\n.partybot distance on\nClick to switch to Spawn Near"
    else
        SCB_SetArtButtonTexture(SCB.distanceButton, SCB.assetRoot .. "distance_off.tga", nil)
        SCB.distanceButton.scbTooltip = "Spawn Near\n.partybot distance off\nClick to switch to Spawn Far"
    end
end

local function SCB_ValidateSavedSession()
    SCB_EnsureSessionDB()
    local roster = SCB_GetRosterNames()
    local known = SoloCraftBotsDB.session.knownBots
    local retained = {}
    local hasKnown = false
    local name

    for name in pairs(known) do
        if roster[name] then
            retained[name] = true
            hasKnown = true
        end
    end

    if hasKnown then
        SoloCraftBotsDB.session.knownBots = retained
    else
        SCB_ResetSessionState()
    end

    SCB.lastRoster = roster
    SCB.pendingBotAdds = 0
    SCB.pendingBotAddsExpires = 0
    SCB_RefreshDistanceButtons()
end

local function SCB_RegisterSpawnIntent()
    SCB.pendingBotAdds = SCB.pendingBotAdds + 1
    if GetTime then
        SCB.pendingBotAddsExpires = GetTime() + 5
    end
end

local function SCB_HandleRosterChange()
    local current = SCB_GetRosterNames()
    local name

    SCB_EnsureSessionDB()

    if SCB.pendingBotAdds > 0 and GetTime and SCB.pendingBotAddsExpires > 0 and GetTime() > SCB.pendingBotAddsExpires then
        SCB.pendingBotAdds = 0
        SCB.pendingBotAddsExpires = 0
    end

    if SCB.lastRoster and SCB.pendingBotAdds > 0 then
        for name in pairs(current) do
            if SCB.pendingBotAdds <= 0 then
                break
            end
            if not SCB.lastRoster[name] and name ~= UnitName("player") then
                SoloCraftBotsDB.session.knownBots[name] = true
                SCB.pendingBotAdds = SCB.pendingBotAdds - 1
            end
        end
    end

    SCB.lastRoster = current
end

-- -------------------------------------------------------------------------
-- Spawning
-- -------------------------------------------------------------------------

local function SCB_BuildSpawnCommand(classKey, role, extra)
    local command = "add " .. classKey .. " " .. role
    if extra and extra ~= "" then
        command = command .. " " .. extra
    end
    return command
end

local function SCB_SendSpawnCommand(command)
    if not command or command == "" then
        return
    end
    SCB_RegisterSpawnIntent()
    SendChatMessage(".partybot " .. command, "SAY")
end

local function SCB_SpawnOnClick()
    if not this.scbClass or not this.scbRole then
        return
    end
    SCB_SendSpawnCommand(SCB_BuildSpawnCommand(this.scbClass, this.scbRole, this.scbExtra))
end

local function SCB_DistanceOnClick()
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
-- Direct command matrix
-- -------------------------------------------------------------------------

SCB.recipients = {
    { key = "all", label = "All", icon = "all.tga", highlightIcon = "all_h.tga" },
    { key = "target", label = "Target", icon = "one.tga", highlightIcon = "one_h.tga" },
    { key = "tank", label = "Tanks", icon = "tank.tga", highlightIcon = "tank_h.tga" },
    { key = "healer", label = "Healers", icon = "healer.tga", highlightIcon = "healer_h.tga" },
    { key = "melee", label = "Melee", icon = "melee.tga", highlightIcon = "melee_h.tga" },
    { key = "ranged", label = "Ranged", icon = "ranged.tga", highlightIcon = "ranged_h.tga" },
}

SCB.commandOrder = {
    "play", "move", "come", "stay", "pause",
    "pull", "spread", "hug", "object", "aoe", "attackstart", "attackstop",
}

SCB.commands = {
    play = {
        label = "Play",
        icon = "unpause.tga",
        highlightIcon = "unpause_h.tga",
        routes = {
            all = { "unpause all" },
            target = { "unpause" },
        },
    },
    move = {
        label = "Move",
        icon = "move.tga",
        highlightIcon = "move_h.tga",
        routes = {
            all = { "moveall" },
            target = { "move" },
            tank = { "movetank" },
            healer = { "moveheal" },
            melee = { "movemelee" },
            ranged = { "moverange" },
        },
    },
    come = {
        label = "Come",
        icon = "come.tga",
        highlightIcon = "come_h.tga",
        routes = {
            all = { "cometome" },
            target = { "come" },
            tank = { "cometank" },
            healer = { "comeheal" },
            melee = { "comemelee" },
            ranged = { "comerange" },
        },
    },
    stay = {
        label = "Stay",
        icon = "stay.tga",
        highlightIcon = "stay_h.tga",
        routes = {
            all = { "stayall" },
            target = { "stay" },
            tank = { "staytank" },
            healer = { "stayheal" },
            melee = { "staymelee" },
            ranged = { "stayrange" },
        },
    },
    pause = {
        label = "Pause",
        icon = "pause.tga",
        highlightIcon = "pause_h.tga",
        routes = {
            all = { "pause all" },
            target = { "pause" },
        },
    },
    pull = {
        label = "Pull",
        icon = "pull.tga",
        highlightIcon = "pull_h.tga",
        routes = { tank = { "pull" } },
    },
    spread = {
        label = "Spread",
        icon = "spread.tga",
        highlightIcon = "spread_h.tga",
        routes = { ranged = { "spread" } },
    },
    hug = {
        label = "Hug",
        icon = "unspread.tga",
        highlightIcon = "unspread_h.tga",
        routes = { ranged = { "spreadoff" } },
    },
    object = {
        label = "Object",
        icon = "object.tga",
        highlightIcon = "object_h.tga",
        routes = { all = { "usegobject" } },
    },
    aoe = {
        label = "AoE",
        icon = "aoe.tga",
        highlightIcon = "aoe_h.tga",
        routes = { all = { "aoe" } },
    },
    attackstart = {
        label = "Attack Start",
        icon = "attackstart.tga",
        highlightIcon = "attackstart_h.tga",
        routes = { all = { "attackstart" } },
    },
    attackstop = {
        label = "Attack Stop",
        icon = "attackstop.tga",
        highlightIcon = "attackstop_h.tga",
        routes = { all = { "attackstop" } },
    },
}

local function SCB_DirectCommandOnClick()
    local commandInfo = SCB.commands[this.scbCommandKey]
    local route
    local moveRoute
    local i

    if not commandInfo then
        return
    end

    route = commandInfo.routes[this.scbRecipientKey]
    if not route then
        SCB_Print(commandInfo.label .. " is not available for " .. this.scbRecipientLabel .. ".")
        return
    end

    -- Ctrl-click Come replaces the old ForceMove button: issue Move first to
    -- clear Stay, then immediately issue the matching Come command.
    if this.scbCommandKey == "come" and IsControlKeyDown and IsControlKeyDown() then
        moveRoute = SCB.commands.move.routes[this.scbRecipientKey]
        if moveRoute then
            for i = 1, table.getn(moveRoute) do
                SCB_SendCommand(moveRoute[i])
            end
        end
    end

    for i = 1, table.getn(route) do
        SCB_SendCommand(route[i])
    end
end

-- -------------------------------------------------------------------------
-- Raidmarks
-- -------------------------------------------------------------------------

SCB.raidMarks = {
    { key = "skull", name = "Skull" },
    { key = "cross", name = "Cross" },
    { key = "square", name = "Square" },
    { key = "moon", name = "Moon" },
    { key = "triangle", name = "Triangle" },
    { key = "diamond", name = "Diamond" },
    { key = "circle", name = "Circle" },
    { key = "star", name = "Star" },
}

local function SCB_RefreshRaidmarkModeButton()
    if not SCB.assignmentModeButton then
        return
    end
    if SCB.raidMarkMode == "cc" then
        SCB_SetArtButtonTexture(SCB.assignmentModeButton, SCB.assetRoot .. "cc_h.tga", nil)
        SCB.assignmentModeButton.scbTooltip = "CC assignments\nClick to switch to Focus assignments"
    else
        SCB.raidMarkMode = "focus"
        SCB_SetArtButtonTexture(SCB.assignmentModeButton, SCB.assetRoot .. "focus_h.tga", nil)
        SCB.assignmentModeButton.scbTooltip = "Focus assignments\nClick to switch to CC assignments"
    end
end

local function SCB_RaidmarkModeOnClick()
    if SCB.raidMarkMode == "focus" then
        SCB.raidMarkMode = "cc"
    else
        SCB.raidMarkMode = "focus"
    end
    SCB_RefreshRaidmarkModeButton()
end

local function SCB_RaidMarkOnClick()
    if not this.scbMark or not SCB.raidMarkMode then
        return
    end
    SCB_SendCommand(SCB.raidMarkMode .. "mark " .. this.scbMark)
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
    { id = "5man", name = "5 Man", size = 5 },
    { id = "10man", name = "10 Man", size = 10 },
    { id = "ubrs", name = "UBRS", size = 15 },
    { id = "zg", name = "ZG", size = 20 },
    { id = "aq20", name = "AQ20", size = 20 },
    { id = "mc", name = "MC", size = 40 },
    { id = "onyxia", name = "Onyxia", size = 40 },
    { id = "bwl", name = "BWL", size = 40 },
    { id = "aq40", name = "AQ40", size = 40 },
    { id = "naxx", name = "Naxx", size = 40 },
    { id = "worldboss", name = "WorldBoss", size = 40 },
}

local SCB_PLAYER_ROLES = {
    { role = "tank", label = "Tank", icon = "tank.tga" },
    { role = "healer", label = "Healer", icon = "healer.tga" },
    { role = "meleedps", label = "Melee", icon = "melee.tga" },
    { role = "rangedps", label = "Ranged", icon = "ranged.tga" },
}

local function SCB_CopySlot(slot)
    return {
        class = slot.class,
        role = slot.role,
        extra = slot.extra,
    }
end

local function SCB_CopySlots(slots)
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

local function SCB_DefaultPlayerRoleForClass(classInfo)
    if classInfo and classInfo.roles and classInfo.roles[1] then
        return classInfo.roles[1].role
    end
    return "meleedps"
end

local function SCB_DefaultPresetSlots(size)
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

local function SCB_NormalizePresetSlots(slots, size)
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

local function SCB_CopyPlayerSlots(playerSlots, size)
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

local function SCB_CopyPlayerRoles(playerRoles)
    local copy = {}
    local key, role
    if playerRoles then
        for key, role in pairs(playerRoles) do
            if type(key) == "string" and type(role) == "string" then
                copy[key] = role
            end
        end
    end
    return copy
end

local function SCB_GetDefaultPresetGroups()
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

local function SCB_CurrentPresetGroup()
    if not SoloCraftBotsDB.presetGroups then
        return nil
    end
    return SoloCraftBotsDB.presetGroups[SoloCraftBotsDB.currentPresetGroup or 1]
end

local function SCB_CurrentPreset()
    local group = SCB_CurrentPresetGroup()
    if not group or not group.currentPreset then
        return nil
    end
    return group.presets and group.presets[group.currentPreset] or nil
end

local function SCB_CurrentPresetSize()
    local group = SCB_CurrentPresetGroup()
    return (group and group.size) or 10
end

local function SCB_CurrentGroupCount()
    return math.floor((SCB_CurrentPresetSize() + 4) / 5)
end

local function SCB_PresetSlotLabel(index)
    local group = math.floor((index - 1) / 5) + 1
    local slot = math.mod(index - 1, 5) + 1
    return "Group " .. group .. " / Slot " .. slot
end

local function SCB_PresetPlayerDisplayName(key)
    if key == "$self" then
        return (UnitName and UnitName("player")) or "YOU"
    end
    return key
end

local function SCB_IsKnownBotName(name)
    if not name then
        return false
    end
    SCB_EnsureSessionDB()
    if SoloCraftBotsDB.session.knownBots[name] then
        return true
    end
    return string.find(name, "%*", 1) ~= nil
end

local function SCB_GetHumanRoster()
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

local function SCB_GetPresentHumanMap()
    local map = {}
    local roster = SCB_GetHumanRoster()
    local i
    for i = 1, table.getn(roster) do
        map[roster[i].key] = roster[i]
    end
    return map
end

local function SCB_ClassColor(classToken)
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

local function SCB_PlayerRoleInfo(role)
    local i
    for i = 1, table.getn(SCB_PLAYER_ROLES) do
        if SCB_PLAYER_ROLES[i].role == role then
            return SCB_PLAYER_ROLES[i], i
        end
    end
    return SCB_PLAYER_ROLES[3], 3
end

local function SCB_DefaultPlayerRole(info)
    local classInfo
    if info and info.classToken then
        classInfo = SCB_FindClass(string.lower(info.classToken))
    end
    return SCB_DefaultPlayerRoleForClass(classInfo)
end

local function SCB_EnsurePresetDB()
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
                playerRoles = {},
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

SCB_SetPresetDirty = function(dirty)
    SCB.presetDirty = dirty == true
    if not SCB.presetSaveButton or not SCB.presetSaveButton.label then
        return
    end
    SCB.presetSaveButton:SetScript("OnUpdate", nil)
    if SCB.presetDirty then
        SCB.presetSaveButton.label:SetText("Unsaved")
        SCB.presetSaveButton.label:SetTextColor(1, 0.58, 0.10, 1)
        SCB.presetSaveButton:SetBackdropBorderColor(0.95, 0.48, 0.08, 1)
    else
        SCB.presetSaveButton.label:SetText("Saved")
        SCB.presetSaveButton.label:SetTextColor(0.25, 1, 0.35, 1)
        SCB.presetSaveButton:SetBackdropBorderColor(0.20, 0.65, 0.28, 1)
    end
end

local function SCB_UpdatePresetSelectorText()
    local group, preset
    if not SCB.presetGroupSelector or not SCB.presetSelector then
        return
    end
    SCB_EnsurePresetDB()
    group = SCB_CurrentPresetGroup()
    preset = SCB_CurrentPreset()
    SCB.presetGroupSelector.label:SetText(group and group.name or "No Group")
    SCB.presetSelector.label:SetText(preset and preset.name or "No Preset")
end

local function SCB_RefreshPresetSlots()
    local size = SCB_CurrentPresetSize()
    local present = SCB_GetPresentHumanMap()
    local i, slot, classInfo, roleInfo, row, playerKey, playerInfo, playerRole

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
                    row.classButton.scbTooltip = SCB_PresetSlotLabel(i) .. ": " .. classInfo.name .. "\nLeft-click next class; right-click previous"
                    SCB_SetArtButtonTexture(row.roleButton, SCB_RoleTexture(roleInfo), SCB_RoleHighlightTexture(roleInfo))
                    row.roleButton.scbTooltip = roleInfo.label .. "\nLeft-click next role/spec; right-click previous"
                end
            else
                row:Hide()
            end
        end
    end

    -- Player role artwork is a separate button layered above the bot role
    -- button.  Keep the underlying bot role completely untouched here.
    for playerKey, i in pairs(SCB.presetEditorPlayers or {}) do
        playerInfo = present[playerKey]
        row = i and SCB.presetSlotRows[i]
        if playerInfo and row and i <= size and row.playerRoleButton then
            playerRole = SCB_PlayerRoleInfo(SCB.presetEditorPlayerRoles[playerKey] or SCB_DefaultPlayerRole(playerInfo))
            SCB_SetArtButtonTexture(row.playerRoleButton, SCB.assetRoot .. playerRole.icon, SCB.assetRoot .. string.gsub(playerRole.icon, "%.tga$", "_h.tga"))
        end
    end
end

local function SCB_FrameContainsCursor(frame)
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

local function SCB_PlayerAtPresetSlot(slotIndex)
    local key, assigned
    for key, assigned in pairs(SCB.presetEditorPlayers or {}) do
        if assigned == slotIndex then
            return key
        end
    end
    return nil
end

local function SCB_AssignPresetPlayer(key, slotIndex)
    local size = SCB_CurrentPresetSize()
    local otherKey, oldSlot
    if size <= 5 or not key or not slotIndex or slotIndex < 1 or slotIndex > size then
        return
    end
    SCB.presetEditorPlayers = SCB.presetEditorPlayers or {}
    otherKey = SCB_PlayerAtPresetSlot(slotIndex)
    oldSlot = SCB.presetEditorPlayers[key]
    if otherKey and otherKey ~= key then
        if oldSlot then
            SCB.presetEditorPlayers[otherKey] = oldSlot
        else
            SCB.presetEditorPlayers[otherKey] = nil
        end
    end
    SCB.presetEditorPlayers[key] = slotIndex
    SCB_SetPresetDirty(true)
end

local function SCB_UpdateDragGhost()
    local x, y, scale
    if not SCB.dragGhost or not SCB.dragGhost:IsShown() or not GetCursorPosition then
        return
    end
    x, y = GetCursorPosition()
    scale = UIParent:GetEffectiveScale() or 1
    SCB.dragGhost:ClearAllPoints()
    -- Keep the dragged player representation centred directly on the cursor.
    SCB.dragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

local function SCB_ShowDragGhost(info)
    local color
    if not SCB.dragGhost or not info then
        return
    end
    SCB.dragGhost.label:SetText(info.name)
    if SCB.dragGhost.roleIcon then
        local roleInfo = SCB_PlayerRoleInfo(SCB.presetEditorPlayerRoles[info.key] or SCB_DefaultPlayerRole(info))
        SCB.dragGhost.roleIcon:SetTexture(SCB.assetRoot .. roleInfo.icon)
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

local function SCB_HideDragGhost()
    if SCB.dragGhost then
        SCB.dragGhost:SetScript("OnUpdate", nil)
        SCB.dragGhost:Hide()
    end
end

local function SCB_RevealUnderlyingBot(slotIndex)
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

local function SCB_PresetPlayerDragStart()
    local present, originSlot
    if SCB_CurrentPresetSize() <= 5 then
        return
    end
    SCB.draggedPresetPlayer = this.scbPlayerKey
    originSlot = SCB.presetEditorPlayers and SCB.presetEditorPlayers[this.scbPlayerKey]
    SCB.draggedPresetPlayerOriginSlot = originSlot
    present = SCB_GetPresentHumanMap()
    if present[this.scbPlayerKey] then
        -- Reveal the bot assignment being sacrificed as soon as the player
        -- leaves the slot, rather than waiting until the drop completes.
        SCB_RevealUnderlyingBot(originSlot)
        SCB_ShowDragGhost(present[this.scbPlayerKey])
    end
end

local function SCB_FinishPresetPlayerDrag(slotIndex)
    local key = SCB.draggedPresetPlayer
    if not key then
        return false
    end

    SCB.draggedPresetPlayer = nil
    SCB.draggedPresetPlayerOriginSlot = nil
    SCB_HideDragGhost()

    if slotIndex then
        SCB_AssignPresetPlayer(key, slotIndex)
    end

    SCB_RefreshPresetSlots()
    if SCB_RefreshPresetPlayers then
        SCB_RefreshPresetPlayers()
    end
    return true
end

local function SCB_PresetPlayerDragStop()
    local i, size
    if not SCB.draggedPresetPlayer or SCB_CurrentPresetSize() <= 5 then
        return
    end
    size = SCB_CurrentPresetSize()
    for i = 1, size do
        if SCB_FrameContainsCursor(SCB.presetDropTargets[i]) then
            SCB_FinishPresetPlayerDrag(i)
            return
        end
    end
    -- No valid drop: restore the player overlay and its player-role artwork.
    SCB_FinishPresetPlayerDrag(nil)
end

local function SCB_CancelPresetPlayerDrag()
    if not SCB.draggedPresetPlayer then
        SCB_HideDragGhost()
        return
    end
    SCB.draggedPresetPlayer = nil
    SCB.draggedPresetPlayerOriginSlot = nil
    SCB_HideDragGhost()
    if SCB.presetPanel and SCB.presetPanel:IsShown() then
        SCB_RefreshPresetSlots()
        if SCB_RefreshPresetPlayers then
            SCB_RefreshPresetPlayers()
        end
    end
end

local function SCB_PresetPlayerOnClick()
    if SCB.draggedPresetPlayer and this.scbSlotIndex then
        SCB_FinishPresetPlayerDrag(this.scbSlotIndex)
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

local function SCB_SetPlayerNameIdentity(button, info, draggable)
    local color
    if not button or not info then
        return
    end
    button.scbPlayerKey = info.key
    if draggable then
        button.scbTooltip = info.name .. "\nDrag to another raid slot"
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

local function SCB_CreatePresetPlayerNameButton(parent, width, height)
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

local function SCB_AutoPartyPlayerSlots(roster)
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

SCB_RefreshPresetPlayers = function()
    local size, roster, present, activeAssignments, assignedPresent
    local i, info, slotIndex, row, button, poolIndex, poolRows, draggable

    if not SCB.presetPanel then
        return
    end
    size = SCB_CurrentPresetSize()
    roster = SCB_GetHumanRoster()
    present = {}
    assignedPresent = {}
    for i = 1, table.getn(roster) do
        present[roster[i].key] = roster[i]
    end

    if size <= 5 then
        activeAssignments = SCB_AutoPartyPlayerSlots(roster)
    else
        activeAssignments = SCB.presetEditorPlayers or {}
    end

    for i = 1, 40 do
        row = SCB.presetSlotRows[i]
        if row then
            row.scbPresentPlayerKey = nil
            if row.playerOverlay then
                row.playerOverlay:SetAlpha(1)
                row.playerOverlay:Hide()
            end
            if row.playerRoleButton then
                row.playerRoleButton.scbPlayerKey = nil
                row.playerRoleButton:Hide()
            end
            if row.classButton then row.classButton:Show() end
        end
    end

    for info, slotIndex in pairs(activeAssignments) do
        if present[info] and slotIndex >= 1 and slotIndex <= size then
            assignedPresent[info] = true
            row = SCB.presetSlotRows[slotIndex]
            if row then
                row.scbPresentPlayerKey = info
                if not row.playerOverlay then
                    row.playerOverlay = SCB_CreatePresetPlayerNameButton(row, 64, 26)
                    row.playerOverlay:SetPoint("LEFT", row.roleButton, "RIGHT", 8, 0)
                    row.playerOverlay:SetFrameLevel(row:GetFrameLevel() + 4)
                end
                draggable = size > 5
                SCB_SetPlayerNameIdentity(row.playerOverlay, present[info], draggable)
                row.playerOverlay.scbSlotIndex = slotIndex
                row.playerOverlay:SetAlpha(1)
                row.playerOverlay:Show()
                row.classButton:Hide()

                local roleInfo = SCB_PlayerRoleInfo(SCB.presetEditorPlayerRoles[info] or SCB_DefaultPlayerRole(present[info]))
                if row.playerRoleButton then
                    row.playerRoleButton.scbPlayerKey = info
                    row.playerRoleButton.scbSlotIndex = slotIndex
                    SCB_SetArtButtonTexture(row.playerRoleButton, SCB.assetRoot .. roleInfo.icon, SCB.assetRoot .. string.gsub(roleInfo.icon, "%.tga$", "_h.tga"))
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
                if not button then
                    button = SCB_CreatePresetPlayerNameButton(SCB.presetPlayerPool, 108, 22)
                    SCB.presetPlayerPoolButtons[poolIndex] = button
                end
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", SCB.presetPlayerPool, "TOPLEFT", ((poolIndex - 1) - math.floor((poolIndex - 1) / 2) * 2) * 112, -14 - (math.floor((poolIndex - 1) / 2) * 24))
                SCB_SetPlayerNameIdentity(button, info, true)
                button.scbSlotIndex = nil
                button:Show()
            end
        end
    end

    for i = poolIndex + 1, table.getn(SCB.presetPlayerPoolButtons) do
        SCB.presetPlayerPoolButtons[i]:Hide()
    end

    SCB.presetPlayerPoolVisibleCount = poolIndex
    if poolIndex > 0 then
        poolRows = math.floor((poolIndex - 1) / 2) + 1
        SCB.presetPlayerPool:Show()
        SCB.presetPlayerPoolLabel:Show()
        SCB.presetPlayerPool:SetHeight(16 + (poolRows * 24))
    else
        SCB.presetPlayerPool:Hide()
        SCB.presetPlayerPoolLabel:Hide()
        SCB.presetPlayerPool:SetHeight(1)
    end

    SCB_RefreshPresetSlots()
    if SCB_LayoutPresetGroups then
        SCB_LayoutPresetGroups()
    end
end

local function SCB_LoadPreset(groupIndex, presetIndex)
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
        SCB.presetEditorPlayers = SCB_CopyPlayerSlots(preset.playerSlots, size)
        SCB.presetEditorPlayerRoles = SCB_CopyPlayerRoles(preset.playerRoles)
    else
        SCB.presetEditorSlots = SCB_DefaultPresetSlots(size)
        SCB.presetEditorPlayers = { ["$self"] = 1 }
        SCB.presetEditorPlayerRoles = {}
    end

    SCB_UpdatePresetSelectorText()
    SCB_RefreshPresetSlots()
    SCB_RefreshPresetPlayers()
    SCB_SetPresetDirty(false)
end

local function SCB_SaveCurrentPreset()
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
    preset.playerSlots = SCB_CopyPlayerSlots(SCB.presetEditorPlayers, size)
    preset.playerRoles = SCB_CopyPlayerRoles(SCB.presetEditorPlayerRoles)
    SCB_SetPresetDirty(false)
end

local function SCB_PresetSaveOnClick()
    if SCB.presetDirty then
        SCB_SaveCurrentPreset()
    end
end

local function SCB_PresetClassOnClick()
    local slotIndex = this.scbSlotIndex
    if SCB.draggedPresetPlayer then
        SCB_FinishPresetPlayerDrag(slotIndex)
        return
    end
    local slot = SCB.presetEditorSlots[slotIndex]
    local visible = SCB_GetVisibleClasses()
    local currentIndex = 1
    local i, classInfo, newIndex, roleInfo
    if not slot or (SCB.presetSlotRows[slotIndex] and SCB.presetSlotRows[slotIndex].scbPresentPlayerKey) then
        return
    end
    for i = 1, table.getn(visible) do
        if visible[i].key == slot.class then
            currentIndex = i
            break
        end
    end
    if arg1 == "RightButton" then
        newIndex = currentIndex - 1
        if newIndex < 1 then newIndex = table.getn(visible) end
    else
        newIndex = currentIndex + 1
        if newIndex > table.getn(visible) then newIndex = 1 end
    end
    classInfo = visible[newIndex]
    roleInfo = classInfo.roles[1]
    slot.class = classInfo.key
    slot.role = roleInfo.role
    slot.extra = roleInfo.extra
    SCB_RefreshPresetSlots()
    SCB_SetPresetDirty(true)
end

local function SCB_PresetPlayerRoleOnClick()
    local slotIndex = this.scbSlotIndex
    local playerKey = this.scbPlayerKey
    local present, current, currentIndex, newIndex, roleInfo

    if SCB.draggedPresetPlayer then
        SCB_FinishPresetPlayerDrag(slotIndex)
        return
    end
    if not playerKey then
        return
    end

    present = SCB_GetPresentHumanMap()
    current, currentIndex = SCB_PlayerRoleInfo(SCB.presetEditorPlayerRoles[playerKey] or SCB_DefaultPlayerRole(present[playerKey]))
    if arg1 == "RightButton" then
        newIndex = currentIndex - 1
        if newIndex < 1 then newIndex = table.getn(SCB_PLAYER_ROLES) end
    else
        newIndex = currentIndex + 1
        if newIndex > table.getn(SCB_PLAYER_ROLES) then newIndex = 1 end
    end

    roleInfo = SCB_PLAYER_ROLES[newIndex]
    SCB.presetEditorPlayerRoles[playerKey] = roleInfo.role
    SCB_SetArtButtonTexture(this, SCB.assetRoot .. roleInfo.icon, SCB.assetRoot .. string.gsub(roleInfo.icon, "%.tga$", "_h.tga"))
    this.scbTooltip = roleInfo.label .. "\nLeft-click next player role; right-click previous"
    SCB_SetPresetDirty(true)
end

local function SCB_PresetRoleOnClick()
    local slotIndex = this.scbSlotIndex
    if SCB.draggedPresetPlayer then
        SCB_FinishPresetPlayerDrag(slotIndex)
        return
    end

    -- A live player's role has its own overlay button.  This handler owns
    -- only the underlying bot assignment and must never mutate playerRoles.
    local row = SCB.presetSlotRows[slotIndex]
    if row and row.scbPresentPlayerKey then
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
    slot.extra = roleInfo.extra
    SCB_RefreshPresetSlots()
    SCB_SetPresetDirty(true)
end

local function SCB_HidePresetMenus()
    if SCB.presetGroupMenu then SCB.presetGroupMenu:Hide() end
    if SCB.presetMenu then SCB.presetMenu:Hide() end
end

local function SCB_GetPresetPopupDialog(frame)
    local candidate = frame
    local i, popup
    while candidate do
        if candidate.editBox then return candidate end
        if candidate.GetParent then candidate = candidate:GetParent() else candidate = nil end
    end
    for i = 1, 4 do
        popup = getglobal("StaticPopup" .. i)
        if popup and popup:IsShown() and (popup.which == "SOLOCRAFTBOTS_PRESET_NAME" or popup.which == "SOLOCRAFTBOTS_PRESET_GROUP_NAME") then
            return popup
        end
    end
    return nil
end

local function SCB_GetPopupEditBox(frame)
    local dialog = SCB_GetPresetPopupDialog(frame)
    if not dialog then return nil end
    if dialog.editBox then return dialog.editBox end
    if dialog.GetName then return getglobal(dialog:GetName() .. "EditBox") end
    return nil
end

local function SCB_AcceptPresetName(dialog)
    local editBox = SCB_GetPopupEditBox(dialog)
    local name = editBox and editBox:GetText() or ""
    local group = SCB_CurrentPresetGroup()
    local preset
    if not name or name == "" then name = SCB.pendingPresetDefaultName or "Preset" end
    if not group then return end

    table.insert(group.presets, {
        name = name,
        slots = SCB_NormalizePresetSlots(SCB.presetEditorSlots, group.size),
        playerSlots = SCB_CopyPlayerSlots(SCB.presetEditorPlayers, group.size),
        playerRoles = SCB_CopyPlayerRoles(SCB.presetEditorPlayerRoles),
    })
    group.currentPreset = table.getn(group.presets)
    SCB.pendingPresetDefaultName = nil
    SCB_LoadPreset(SoloCraftBotsDB.currentPresetGroup, group.currentPreset)
end

local function SCB_AcceptPresetGroupName(dialog)
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

local function SCB_PresetGroupChoiceOnClick()
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

local function SCB_PresetChoiceOnClick()
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

local function SCB_DeletePresetGroupOnClick()
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

local function SCB_DeletePresetOnClick()
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

local function SCB_SetMenuDeleteButton(button, show, index, deleteScript)
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
            GameTooltip:SetText("Delete", 1, 1, 1, 1)
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

local function SCB_RebuildPresetGroupMenu()
    local count = table.getn(SoloCraftBotsDB.presetGroups)
    local total = count + 1
    local i, button, group
    for i = 1, total do
        button = SCB.presetGroupMenuButtons[i]
        if not button then
            button = SCB_CreateTextButton(SCB.presetGroupMenu, nil, 126, 20, "")
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
            button.scbAddNew = true
            button.scbGroupIndex = nil
            SCB_SetMenuDeleteButton(button, false, nil, SCB_DeletePresetGroupOnClick)
        else
            group = SoloCraftBotsDB.presetGroups[i - 1]
            button.label:SetText(group.name)
            button.scbAddNew = nil
            button.scbGroupIndex = i - 1
            SCB_SetMenuDeleteButton(button, not group.isDefault, i - 1, SCB_DeletePresetGroupOnClick)
        end
        button:Show()
    end
    for i = total + 1, table.getn(SCB.presetGroupMenuButtons) do
        SCB.presetGroupMenuButtons[i]:Hide()
    end
    SCB.presetGroupMenu:SetHeight(8 + (total * 20))
end

local function SCB_RebuildPresetMenu()
    local group = SCB_CurrentPresetGroup()
    local count = group and table.getn(group.presets) or 0
    local total = count + 1
    local i, button, preset
    for i = 1, total do
        button = SCB.presetNameMenuButtons[i]
        if not button then
            button = SCB_CreateTextButton(SCB.presetMenu, nil, 126, 20, "")
            button:SetPoint("TOPLEFT", SCB.presetMenu, "TOPLEFT", 4, -4 - ((i - 1) * 20))
            button.label:ClearAllPoints()
            button.label:SetPoint("LEFT", button, "LEFT", 3, 0)
            button.label:SetPoint("RIGHT", button, "RIGHT", -20, 0)
            button.label:SetJustifyH("LEFT")
            button:SetScript("OnClick", SCB_PresetChoiceOnClick)
            SCB.presetNameMenuButtons[i] = button
        end
        if i == 1 then
            button.label:SetText("<Add New Preset>")
            button.scbAddNew = true
            button.scbPresetIndex = nil
            SCB_SetMenuDeleteButton(button, false, nil, SCB_DeletePresetOnClick)
        else
            preset = group.presets[i - 1]
            button.label:SetText(preset.name or ("Preset " .. (i - 1)))
            button.scbAddNew = nil
            button.scbPresetIndex = i - 1
            SCB_SetMenuDeleteButton(button, true, i - 1, SCB_DeletePresetOnClick)
        end
        button:Show()
    end
    for i = total + 1, table.getn(SCB.presetNameMenuButtons) do
        SCB.presetNameMenuButtons[i]:Hide()
    end
    SCB.presetMenu:SetHeight(8 + (total * 20))
end

local function SCB_PresetGroupSelectorOnClick()
    SCB_RebuildPresetGroupMenu()
    if SCB.presetGroupMenu:IsShown() then
        SCB.presetGroupMenu:Hide()
    else
        if SCB.presetMenu then SCB.presetMenu:Hide() end
        SCB.presetGroupMenu:Show()
        SCB.presetGroupMenu:Raise()
    end
end

local function SCB_PresetSelectorOnClick()
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

local function SCB_PresetSpawnQueueOnUpdate()
    local nextItem
    if table.getn(SCB.presetSpawnQueue) == 0 then
        SCB.presetSpawnElapsed = 0
        return
    end
    nextItem = SCB.presetSpawnQueue[1]
    if nextItem == SCB_PRESET_CONVERT_NOW then
        if GetNumRaidMembers and GetNumRaidMembers() > 0 then
            table.remove(SCB.presetSpawnQueue, 1)
            SCB.presetSpawnElapsed = 0
        elseif GetNumPartyMembers and GetNumPartyMembers() > 0 and ConvertToRaid then
            ConvertToRaid()
            SCB.presetSpawnQueue[1] = SCB_PRESET_WAIT_RAID
            SCB.presetSpawnElapsed = 0
        end
        return
    elseif nextItem == SCB_PRESET_WAIT_RAID then
        if GetNumRaidMembers and GetNumRaidMembers() > 0 then
            table.remove(SCB.presetSpawnQueue, 1)
            SCB.presetSpawnElapsed = 0
        end
        return
    end

    SCB.presetSpawnElapsed = SCB.presetSpawnElapsed + (arg1 or 0)
    if SCB.presetSpawnElapsed < SCB.presetSpawnInterval then return end
    SCB.presetSpawnElapsed = SCB.presetSpawnElapsed - SCB.presetSpawnInterval
    SCB_SendSpawnCommand(nextItem)
    table.remove(SCB.presetSpawnQueue, 1)
end

local function SCB_QueuePresetSpawn(commands)
    local i
    if not commands or table.getn(commands) == 0 then return end
    for i = 1, table.getn(commands) do
        table.insert(SCB.presetSpawnQueue, commands[i])
    end
end

local function SCB_PresetSummonOnClick()
    local group = SCB_CurrentPresetGroup()
    local size = SCB_CurrentPresetSize()
    local commands, slots, present, occupied = {}, SCB_NormalizePresetSlots(SCB.presetEditorSlots, size), SCB_GetPresentHumanMap(), {}
    local roster, activeAssignments, key, slotIndex, i, slot, existingParty, availableBeforeRaid, sentBeforeConvert

    if not group or not SCB_CurrentPreset() then
        SCB_Print("Add or select a preset before Summon.")
        return
    end
    if size > 20 then
        SCB_Print("40-player preset spawning is reserved for the tracked queue revision.")
        return
    end

    SCB.presetEditorSlots = slots
    SCB_RefreshPresetPlayers()

    if size <= 5 then
        roster = SCB_GetHumanRoster()
        activeAssignments = SCB_AutoPartyPlayerSlots(roster)
        -- Every existing party position is occupied, whether human or bot.
        -- Five-man order cannot be reorganised, so fill only the remaining
        -- invite-order positions.
        local partyMembers = (GetNumPartyMembers and GetNumPartyMembers()) or 0
        for i = 1, math.min(5, partyMembers + 1) do occupied[i] = true end
        for i = 1, 5 do
            if not occupied[i] then
                slot = slots[i]
                table.insert(commands, SCB_BuildSpawnCommand(slot.class, slot.role, slot.extra))
            end
        end
        SCB_QueuePresetSpawn(commands)
        return
    end

    for key, slotIndex in pairs(SCB.presetEditorPlayers or {}) do
        if present[key] and slotIndex >= 1 and slotIndex <= size then occupied[slotIndex] = true end
    end
    for key in pairs(present) do
        if not SCB.presetEditorPlayers[key] then
            SCB_Print("Assign " .. SCB_PresetPlayerDisplayName(key) .. " to a preset slot before Summon.")
            return
        end
    end

    existingParty = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    availableBeforeRaid = 4 - existingParty
    if availableBeforeRaid < 0 then availableBeforeRaid = 0 end
    sentBeforeConvert = 0

    for i = 1, size do
        if not occupied[i] then
            if (not GetNumRaidMembers or GetNumRaidMembers() == 0) and sentBeforeConvert >= availableBeforeRaid then
                if table.getn(commands) == 0 or commands[table.getn(commands)] ~= SCB_PRESET_CONVERT_NOW then
                    table.insert(commands, SCB_PRESET_CONVERT_NOW)
                end
                sentBeforeConvert = -1000
            end
            slot = slots[i]
            table.insert(commands, SCB_BuildSpawnCommand(slot.class, slot.role, slot.extra))
            if sentBeforeConvert >= 0 then sentBeforeConvert = sentBeforeConvert + 1 end
        end
    end

    -- If the first group exactly fills a party, conversion must happen before
    -- any later raid-only additions. This barrier remains deliberately simple
    -- until the acknowledged queue arrives in 0.3.0.
    if size > 5 and (not GetNumRaidMembers or GetNumRaidMembers() == 0) then
        local commandCount = table.getn(commands)
        if commandCount > availableBeforeRaid and availableBeforeRaid > 0 then
            local converted = false
            for i = 1, commandCount do
                if commands[i] == SCB_PRESET_CONVERT_NOW then converted = true break end
            end
            if not converted then table.insert(commands, availableBeforeRaid + 1, SCB_PRESET_CONVERT_NOW) end
        end
    end
    SCB_QueuePresetSpawn(commands)
end

local function SCB_SetPresetPanelShown(show)
    if not SCB.presetPanel then return end
    if show then
        SCB.presetPanel:Show()
        SCB.presetPanel:Raise()
        SCB_RefreshPresetPlayers()
    else
        -- Closing Presets is also an explicit drag cancel. Never leave a
        -- stale dragged player key behind after Escape or the close toggle.
        SCB_CancelPresetPlayerDrag()
        SCB.presetPanel:Hide()
        SCB_HidePresetMenus()
    end
end

local function SCB_PresetToggleOnClick()
    if not SCB.presetPanel then return end
    SCB_SetPresetPanelShown(not SCB.presetPanel:IsShown())
end


-- -------------------------------------------------------------------------
-- Escape / top-level visibility
-- -------------------------------------------------------------------------

local function SCB_SetEscapeProxyShown(show)
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

local function SCB_EscapeProxyOnHide()
    if SCB.ignoreEscapeProxyHide then
        return
    end
    if not SCB.frame or not SCB.frame:IsShown() then
        return
    end

    -- First Escape closes the preset side panel; the next closes SCB.
    if SCB.presetPanel and SCB.presetPanel:IsShown() then
        SCB_SetPresetPanelShown(false)
        this:Show()
        return
    end

    SCB.frame:Hide()
end

local function SCB_MainFrameOnShow()
    SCB_SetEscapeProxyShown(true)
end

local function SCB_MainFrameOnHide()
    SCB_SetPresetPanelShown(false)
    SCB_SetEscapeProxyShown(false)
end

-- -------------------------------------------------------------------------
-- Frame position / top-level UI
-- -------------------------------------------------------------------------

local function SCB_SavePosition()
    if not SoloCraftBotsDB or not SCB.frame then
        return
    end
    local point, relativeTo, relativePoint, x, y = SCB.frame:GetPoint()
    SoloCraftBotsDB.point = point or "CENTER"
    SoloCraftBotsDB.relativePoint = relativePoint or point or "CENTER"
    SoloCraftBotsDB.x = x or 0
    SoloCraftBotsDB.y = y or 0
end

local function SCB_RestorePosition()
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

local function SCB_FrameDragStart()
    this:StartMoving()
end

local function SCB_FrameDragStop()
    this:StopMovingOrSizing()
    SCB_SavePosition()
end

local function SCB_CloseOnClick()
    if SCB.frame then
        SCB.frame:Hide()
    end
end

local function SCB_CreateSummonUI(frame)
    local section, content = SCB_CreateCollapsibleSection(frame, "summon", "Summon Bots", 196)

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
    local cellWidth = 72
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

local function SCB_CreateCommandUI(frame)
    local section, content = SCB_CreateCollapsibleSection(frame, "commands", "Command Bots", 276)

    local buttonSize = 32
    local gap = 3
    local rowGap = 1
    local groupGap = 20
    -- ALL and TARGET start immediately after the recipient icon. Role rows
    -- reserve the Play column because those recipients have no Play command.
    local maxColumns = 6
    local maxRowWidth = (maxColumns * buttonSize) + ((maxColumns - 1) * gap)
    local left = math.floor((frame:GetWidth() - maxRowWidth) / 2)
    local top = -2

    local rows = {
        { recipient = "all", indent = 0, commands = { "play", "move", "come", "stay", "pause" } },
        { recipient = "target", indent = 0, commands = { "play", "move", "come", "stay", "pause" } },
        { gapBefore = true, recipient = "tank", indent = 1, commands = { "move", "come", "stay", "pull" } },
        { recipient = "healer", indent = 1, commands = { "move", "come", "stay" } },
        { recipient = "melee", indent = 1, commands = { "move", "come", "stay" } },
        { recipient = "ranged", indent = 1, commands = { "move", "come", "stay", "spread", "hug" } },
    }

    local recipientByKey = {}
    local i, r, row, recipient, commandKey, commandInfo, button
    local y = top

    for i = 1, table.getn(SCB.recipients) do
        recipientByKey[SCB.recipients[i].key] = SCB.recipients[i]
    end

    for r = 1, table.getn(rows) do
        row = rows[r]
        if row.gapBefore then
            y = y - groupGap
        end
        recipient = recipientByKey[row.recipient]

        button = SCB_CreateArtButton(
            content, nil, buttonSize,
            SCB.assetRoot .. recipient.icon,
            nil,
            SCB.assetRoot .. recipient.highlightIcon
        )
        button:SetPoint("TOPLEFT", content, "TOPLEFT", left, y)
        button.scbTooltip = recipient.label
        button:SetScript("OnEnter", SCB_TooltipOnEnter)
        button:SetScript("OnLeave", SCB_TooltipOnLeave)

        for i = 1, table.getn(row.commands) do
            commandKey = row.commands[i]
            commandInfo = SCB.commands[commandKey]
            button = SCB_CreateArtButton(
                content, nil, buttonSize,
                SCB.assetRoot .. commandInfo.icon,
                nil,
                SCB.assetRoot .. commandInfo.highlightIcon
            )
            button:SetPoint(
                "TOPLEFT", content, "TOPLEFT",
                left + ((i + (row.indent or 0)) * (buttonSize + gap)), y
            )
            button.scbCommandKey = commandKey
            button.scbRecipientKey = row.recipient
            button.scbRecipientLabel = recipient.label
            button.scbTooltip = recipient.label .. " - " .. commandInfo.label
            if commandKey == "come" then
                button.scbTooltip = button.scbTooltip .. "\nCtrl-click: Move, then Come"
            end
            button:SetScript("OnClick", SCB_DirectCommandOnClick)
            button:SetScript("OnEnter", SCB_TooltipOnEnter)
            button:SetScript("OnLeave", SCB_TooltipOnLeave)
        end

        y = y - buttonSize - rowGap
    end

    -- All-only / unique actions sit outside the recipient matrix.
    y = y - groupGap
    local standalone = { "aoe", "object", "attackstart", "attackstop" }
    local standaloneWidth = (4 * buttonSize) + (3 * gap)
    local standaloneLeft = math.floor((frame:GetWidth() - standaloneWidth) / 2)
    for i = 1, table.getn(standalone) do
        commandKey = standalone[i]
        commandInfo = SCB.commands[commandKey]
        button = SCB_CreateArtButton(
            content, nil, buttonSize,
            SCB.assetRoot .. commandInfo.icon,
            nil,
            SCB.assetRoot .. commandInfo.highlightIcon
        )
        button:SetPoint("TOPLEFT", content, "TOPLEFT", standaloneLeft + ((i - 1) * (buttonSize + gap)), y)
        button.scbCommandKey = commandKey
        button.scbRecipientKey = "all"
        button.scbRecipientLabel = "All"
        button.scbTooltip = commandInfo.label .. " (All)"
        button:SetScript("OnClick", SCB_DirectCommandOnClick)
        button:SetScript("OnEnter", SCB_TooltipOnEnter)
        button:SetScript("OnLeave", SCB_TooltipOnLeave)
    end
end

local function SCB_CreateRaidmarkUI(frame)
    local section, content = SCB_CreateCollapsibleSection(frame, "assignments", "Assignments", 34)
    local toggleSize = 22

    -- One always-highlighted state button. Focus is the default; clicking it
    -- swaps between Focus and CC assignment modes.
    local mode = SCB_CreateArtButton(section, nil, toggleSize, SCB.assetRoot .. "focus_h.tga")
    mode:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, -2)
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

local function SCB_CreateDropdownArrow(parent)
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

local function SCB_CreatePresetDropdown(parent, name, width, text, clickScript)
    local button = SCB_CreateTextButton(parent, name, width, 22, text)
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", button, "LEFT", 7, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -22, 0)
    button.label:SetJustifyH("LEFT")
    SCB_CreateDropdownArrow(button)
    button:SetScript("OnClick", clickScript)
    return button
end

SCB_LayoutPresetGroups = function()
    local size = SCB_CurrentPresetSize()
    local groupCount = math.floor((size + 4) / 5)
    local columns = 2
    local rows, panelWidth, panelHeight, groupX, groupY, groupFrame, title
    local groupWidth, groupHeight, gapX, gapY, topY, i, col, row, poolRows, poolExtra

    if groupCount == 1 then
        columns = 1
    elseif groupCount > 4 then
        columns = 4
    end
    rows = math.floor((groupCount + columns - 1) / columns)

    groupWidth = 102
    groupHeight = 158
    gapX = 10
    gapY = 20
    topY = 78
    panelWidth = (columns * groupWidth) + ((columns - 1) * gapX) + 20
    if panelWidth < 294 then panelWidth = 294 end

    poolExtra = 0
    if SCB.presetPlayerPool and SCB.presetPlayerPool:IsShown() then
        poolRows = math.floor(((SCB.presetPlayerPoolVisibleCount or 0) + 1) / 2)
        poolExtra = 18 + (poolRows * 24)
    end
    panelHeight = topY + (rows * groupHeight) + ((rows - 1) * gapY) + 56 + poolExtra

    SCB.presetPanel:SetWidth(panelWidth)
    SCB.presetPanel:SetHeight(panelHeight)

    for i = 1, 8 do
        groupFrame = SCB.presetGroupFrames[i]
        title = SCB.presetGroupTitles[i]
        if i <= groupCount then
            col = math.mod(i - 1, columns)
            row = math.floor((i - 1) / columns)
            groupX = 10 + (col * (groupWidth + gapX))
            groupY = -topY - (row * (groupHeight + gapY))
            groupFrame:ClearAllPoints()
            groupFrame:SetPoint("TOPLEFT", SCB.presetPanel, "TOPLEFT", groupX, groupY)
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
        SCB.presetPlayerPool:SetPoint("TOPLEFT", SCB.presetPanel, "TOPLEFT", 15, -(topY + (rows * groupHeight) + ((rows - 1) * gapY) + 8))
    end
end

local function SCB_CreatePresetUI(frame)
    local toggle = SCB_CreateTextButton(frame, "SoloCraftBotsPresetToggle", 64, 20, "Presets")
    toggle:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
    toggle:SetScript("OnClick", SCB_PresetToggleOnClick)
    toggle.scbTooltip = "Open/close group presets"
    toggle:SetScript("OnEnter", SCB_TooltipOnEnter)
    toggle:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.presetToggle = toggle

    local panel = CreateFrame("Frame", "SoloCraftBotsPresetPanel", frame)
    panel:SetWidth(294)
    panel:SetHeight(272)
    panel:SetPoint("TOPRIGHT", frame, "TOPLEFT", -2, -39)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 24,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.96)
    panel:SetFrameLevel(frame:GetFrameLevel() + 5)
    SCB.presetPanel = panel

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 13, -12)
    title:SetText("Presets")
    title:SetTextColor(1, 0.82, 0, 1)

    local groupSelector = SCB_CreatePresetDropdown(panel, "SoloCraftBotsPresetGroupSelector", 102, "Preset Group", SCB_PresetGroupSelectorOnClick)
    groupSelector:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -31)
    groupSelector.scbTooltip = "Choose preset group"
    groupSelector:SetScript("OnEnter", SCB_TooltipOnEnter)
    groupSelector:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.presetGroupSelector = groupSelector

    local selector = SCB_CreatePresetDropdown(panel, "SoloCraftBotsPresetSelector", 104, "Preset", SCB_PresetSelectorOnClick)
    selector:SetPoint("LEFT", groupSelector, "RIGHT", 4, 0)
    selector.scbTooltip = "Choose preset"
    selector:SetScript("OnEnter", SCB_TooltipOnEnter)
    selector:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.presetSelector = selector

    local save = SCB_CreateTextButton(panel, "SoloCraftBotsPresetSave", 58, 22, "Saved")
    save:SetPoint("LEFT", selector, "RIGHT", 4, 0)
    save.scbTooltip = "Saved when the editor matches the selected preset\nClick Unsaved to save changes"
    save:SetScript("OnClick", SCB_PresetSaveOnClick)
    save:SetScript("OnEnter", SCB_TooltipOnEnter)
    save:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.presetSaveButton = save

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

    local groupWidth, groupHeight = 102, 158
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
            row:SetPoint("TOPLEFT", groupFrame, "TOPLEFT", 9, -8 - ((localIndex - 1) * 29))
            row.scbSlotIndex = i

            -- Consistent grammar: [Role] [Class] for bots, [Role] [PlayerName]
            -- for live players. Player names use class colour, not class icons.
            roleButton = SCB_CreateArtButton(row, nil, 24, SCB.assetRoot .. "tank.tga", true, SCB.assetRoot .. "tank_h.tga")
            roleButton:SetPoint("LEFT", row, "LEFT", 0, 0)
            roleButton.scbSlotIndex = i
            roleButton:SetScript("OnClick", SCB_PresetRoleOnClick)
            roleButton:SetScript("OnEnter", SCB_TooltipOnEnter)
            roleButton:SetScript("OnLeave", SCB_TooltipOnLeave)

            classButton = SCB_CreateArtButton(row, nil, 24, SCB.assetRoot .. "warrior.tga", true)
            classButton:SetPoint("LEFT", roleButton, "RIGHT", 8, 0)
            classButton.scbSlotIndex = i
            classButton:SetScript("OnClick", SCB_PresetClassOnClick)
            classButton:SetScript("OnEnter", SCB_TooltipOnEnter)
            classButton:SetScript("OnLeave", SCB_TooltipOnLeave)

            row.classButton = classButton
            row.roleButton = roleButton

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

    local summon = SCB_CreateTextButton(panel, "SoloCraftBotsPresetSummon", 88, 24, "Summon")
    summon:SetPoint("BOTTOM", panel, "BOTTOM", 0, 13)
    summon.scbTooltip = "Summon the selected preset in authored order\n5 Man remains a party; raid presets convert only when required"
    summon:SetScript("OnClick", SCB_PresetSummonOnClick)
    summon:SetScript("OnEnter", SCB_TooltipOnEnter)
    summon:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.presetSummonButton = summon

    local dragGhost = CreateFrame("Frame", "SoloCraftBotsPresetDragGhost", UIParent)
    dragGhost:SetWidth(94)
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

    panel:Hide()
    SCB_EnsurePresetDB()
    local group = SCB_CurrentPresetGroup()
    SCB_LoadPreset(SoloCraftBotsDB.currentPresetGroup, group and group.currentPreset or nil)
end


SCB_LayoutSections = function()
    if not SCB.frame then
        return
    end
    SCB_EnsureSectionDB()

    local y = -38
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
                section.scbToggle.label:SetText("+")
            else
                section:SetHeight(section.scbExpandedHeight)
                section.scbContent:Show()
                section.scbToggle.label:SetText("-")
            end

            y = y - section:GetHeight() - sectionGap
        end
    end

    SCB.frame:SetHeight((-y) + 8)
end

local function SCB_CreateUI()
    local frame = CreateFrame("Frame", "SoloCraftBotsFrame", UIParent)
    SCB.frame = frame
    frame:SetWidth(320)
    frame:SetHeight(640)
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
    title:SetText("SoloCraft Bots")

    local close = CreateFrame("Button", "SoloCraftBotsCloseButton", frame, "UIPanelButtonTemplate")
    close:SetWidth(22)
    close:SetHeight(20)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -11, -10)
    close:SetText("X")
    close:SetScript("OnClick", SCB_CloseOnClick)

    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    version:SetPoint("RIGHT", close, "LEFT", -5, 0)
    version:SetText(SCB.version)
    version:SetTextColor(0.6, 0.6, 0.6, 1)

    SCB_CreateCommandUI(frame)
    SCB_CreateRaidmarkUI(frame)
    SCB_CreateSummonUI(frame)
    SCB_CreatePresetUI(frame)
    SCB_LayoutSections()

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
    SoloCraftBots_Toggle()
end

local eventFrame = CreateFrame("Frame", "SoloCraftBotsEventFrame", UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "SoloCraftBots" then
        SoloCraftBotsDB = SoloCraftBotsDB or {}
        SCB_EnsureSessionDB()
        SCB_EnsurePresetDB()
        SCB_EnsureSectionDB()
    elseif event == "PLAYER_LOGIN" then
        -- Do not rely on ADDON_LOADED having matched a hard-coded folder name.
        -- This also makes first-run SavedVariables initialization explicit.
        SoloCraftBotsDB = SoloCraftBotsDB or {}
        SCB_EnsureSessionDB()
        SCB_EnsurePresetDB()
        SCB_EnsureSectionDB()
        if not SCB.frame then
            SCB_CreateUI()
        end
        SCB.initialSessionValidationPending = true
    elseif event == "PLAYER_ENTERING_WORLD" then
        if SCB.initialSessionValidationPending then
            SCB.initialSessionValidationPending = false
            SCB_ValidateSavedSession()
        end
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        SCB_HandleRosterChange()
        if SCB.presetPanel then
            SCB_RefreshPresetPlayers()
        end
    elseif event == "PLAYER_LOGOUT" then
        SCB_SavePosition()
    end
end)
