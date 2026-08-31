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

local function SCB_GetChatChannel()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        return "RAID"
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        return "PARTY"
    end
    return "SAY"
end

local function SCB_SendCommand(command)
    if not command or command == "" then
        return
    end
    SendChatMessage(".partybot " .. command, SCB_GetChatChannel())
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

local function SCB_AddForceMoveOverlay(button)
    if not button or button.scbForceMoveBang then
        return
    end
    local bang = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bang:SetPoint("TOPRIGHT", button, "TOPRIGHT", -3, -2)
    bang:SetText("!")
    bang:SetTextColor(1, 0.05, 0.05, 1)
    if bang.SetShadowColor then
        bang:SetShadowColor(0, 0, 0, 1)
        bang:SetShadowOffset(1, -1)
    end
    button.scbForceMoveBang = bang
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
    "play", "forcemove", "move", "come", "stay", "pause",
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
    forcemove = {
        label = "Force Move",
        icon = "move.tga",
        highlightIcon = "move_h.tga",
        routes = {
            all = { "moveall", "cometome" },
            target = { "move", "come" },
            tank = { "movetank", "cometank" },
            healer = { "moveheal", "comeheal" },
            melee = { "movemelee", "comemelee" },
            ranged = { "moverange", "comerange" },
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
    local i

    if not commandInfo then
        return
    end

    route = commandInfo.routes[this.scbRecipientKey]
    if not route then
        SCB_Print(commandInfo.label .. " is not available for " .. this.scbRecipientLabel .. ".")
        return
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
    for i = 1, table.getn(slots) do
        copy[i] = SCB_CopySlot(slots[i])
    end
    return copy
end

local function SCB_DefaultPresetSlots()
    return {
        -- Every raid position owns a bot assignment. Human players temporarily
        -- overlay one of these positions and sacrifice that bot while present.
        { class = "warrior", role = "tank" },
        { class = "warrior", role = "tank" },
        { class = "priest", role = "healer" },
        { class = "rogue", role = "meleedps" },
        { class = "mage", role = "rangedps" },

        { class = "warrior", role = "tank" },
        { class = "priest", role = "healer" },
        { class = "rogue", role = "meleedps" },
        { class = "mage", role = "rangedps" },
        { class = "hunter", role = "rangedps" },
    }
end

local function SCB_NormalizePresetSlots(slots)
    local defaults = SCB_DefaultPresetSlots()
    local normalized = {}
    local i, slot

    -- 0.2.3 and earlier stored only the nine bot positions because the player
    -- was hard-coded into Group 1 / Slot 1. Migrate that shape losslessly by
    -- inserting a new underlying bot assignment at slot 1.
    if slots and table.getn(slots) == 9 then
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

    for i = 1, 10 do
        slot = slots and slots[i] or nil
        if slot and slot.class and slot.role then
            normalized[i] = SCB_CopySlot(slot)
        else
            normalized[i] = SCB_CopySlot(defaults[i])
        end
    end
    return normalized
end

local function SCB_PresetSlotLabel(index)
    if index <= 5 then
        return "Group 1 / Slot " .. index
    end
    return "Group 2 / Slot " .. (index - 5)
end

local function SCB_CopyPlayerSlots(playerSlots)
    local copy = {}
    local key, slot
    if playerSlots then
        for key, slot in pairs(playerSlots) do
            if type(key) == "string" and type(slot) == "number" and slot >= 1 and slot <= 10 then
                copy[key] = slot
            end
        end
    end
    if not copy["$self"] then
        copy["$self"] = 1
    end
    return copy
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

local function SCB_PlayerAtPresetSlot(slotIndex)
    local key, assigned
    for key, assigned in pairs(SCB.presetEditorPlayers or {}) do
        if assigned == slotIndex then
            return key
        end
    end
    return nil
end

local SCB_SetPresetDirty

local function SCB_AssignPresetPlayer(key, slotIndex)
    if not key or not slotIndex or slotIndex < 1 or slotIndex > 10 then
        return
    end
    SCB.presetEditorPlayers = SCB.presetEditorPlayers or {}
    local otherKey = SCB_PlayerAtPresetSlot(slotIndex)
    local oldSlot = SCB.presetEditorPlayers[key]
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

local function SCB_EnsurePresetDB()
    -- Create one starter preset only when presets have never existed. If the
    -- player deliberately deletes every preset, keep the list empty.
    if SoloCraftBotsDB.presets == nil then
        SoloCraftBotsDB.presets = {
            { name = "Preset 1", slots = SCB_DefaultPresetSlots(), playerSlots = { ["$self"] = 1 } },
        }
        SoloCraftBotsDB.currentPreset = 1
        return
    end

    if table.getn(SoloCraftBotsDB.presets) == 0 then
        SoloCraftBotsDB.currentPreset = nil
        return
    end

    if not SoloCraftBotsDB.currentPreset or not SoloCraftBotsDB.presets[SoloCraftBotsDB.currentPreset] then
        SoloCraftBotsDB.currentPreset = 1
    end
end

SCB_SetPresetDirty = function(dirty)
    SCB.presetDirty = dirty == true
    if not SCB.presetSaveButton then
        return
    end

    if SCB.presetDirty then
        SCB.presetSaveButton.scbPulseTime = 0
        SCB.presetSaveButton:SetScript("OnUpdate", SCB_PresetSavePulseOnUpdate)
    else
        SCB.presetSaveButton:SetScript("OnUpdate", nil)
        SCB.presetSaveButton:SetBackdropColor(0.04, 0.04, 0.04, 0.90)
        SCB.presetSaveButton:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        if SCB.presetSaveButton.label then
            SCB.presetSaveButton.label:SetTextColor(1, 1, 1, 1)
        end
    end
end

function SCB_PresetSavePulseOnUpdate()
    if not SCB.presetDirty then
        return
    end
    this.scbPulseTime = (this.scbPulseTime or 0) + (arg1 or 0)
    local pulse = 0.5 + (0.5 * math.sin(this.scbPulseTime * 3.2))
    local green = 0.52 + (0.28 * pulse)
    this:SetBackdropColor(0.16 + (0.06 * pulse), 0.10 + (0.05 * pulse), 0.01, 0.94)
    this:SetBackdropBorderColor(1, green, 0, 1)
    if this.label then
        this.label:SetTextColor(1, 0.78 + (0.18 * pulse), 0.12, 1)
    end
end

local function SCB_UpdatePresetSelectorText()
    if not SCB.presetSelector then
        return
    end
    SCB_EnsurePresetDB()
    local preset = SoloCraftBotsDB.currentPreset and SoloCraftBotsDB.presets[SoloCraftBotsDB.currentPreset]
    if preset then
        SCB.presetSelector.label:SetText(preset.name or ("Preset " .. SoloCraftBotsDB.currentPreset))
    else
        SCB.presetSelector.label:SetText("No Preset")
    end
end

local function SCB_RefreshPresetSlots()
    local i, slot, classInfo, roleInfo
    local classButton, roleButton

    for i = 1, 10 do
        slot = SCB.presetEditorSlots[i]
        classButton = SCB.presetSlotButtons[i] and SCB.presetSlotButtons[i].classButton
        roleButton = SCB.presetSlotButtons[i] and SCB.presetSlotButtons[i].roleButton

        if slot and classButton and roleButton then
            classInfo = SCB_FindClass(slot.class)
            roleInfo = SCB_FindRoleEntry(classInfo, slot.role, slot.extra)

            SCB_SetArtButtonTexture(classButton, SCB.assetRoot .. classInfo.icon, nil)
            classButton.scbTooltip = SCB_PresetSlotLabel(i) .. ": " .. classInfo.name .. "\nLeft-click next class; right-click previous"

            SCB_SetArtButtonTexture(roleButton, SCB_RoleTexture(roleInfo), SCB_RoleHighlightTexture(roleInfo))
            roleButton.scbTooltip = roleInfo.label .. "\nLeft-click next role/spec; right-click previous"
        end
    end
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

local function SCB_PresetPlayerDragStart()
    SCB.draggedPresetPlayer = this.scbPlayerKey
end

local function SCB_PresetPlayerDragStop()
    local key = SCB.draggedPresetPlayer or this.scbPlayerKey
    local i
    SCB.draggedPresetPlayer = nil
    if not key then
        return
    end
    for i = 1, 10 do
        if SCB_FrameContainsCursor(SCB.presetDropTargets[i]) then
            SCB_AssignPresetPlayer(key, i)
            SCB_RefreshPresetSlots()
            if SCB_RefreshPresetPlayers then
                SCB_RefreshPresetPlayers()
            end
            return
        end
    end
end

local function SCB_PresetPlayerOnClick()
    if arg1 == "RightButton" and this.scbPlayerKey and this.scbPlayerKey ~= "$self" then
        SCB.presetEditorPlayers[this.scbPlayerKey] = nil
        SCB_SetPresetDirty(true)
        if SCB_RefreshPresetPlayers then
            SCB_RefreshPresetPlayers()
        end
    end
end

local function SCB_SetPlayerButtonIdentity(button, info)
    local color, classInfo
    if not button or not info then
        return
    end
    button.scbPlayerKey = info.key
    button.scbTooltip = info.name .. "\nDrag onto a preset slot"
    if info.key ~= "$self" then
        button.scbTooltip = button.scbTooltip .. "\nRight-click to unassign"
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
    if button.icon then
        classInfo = info.classToken and SCB_FindClass(string.lower(info.classToken)) or nil
        if classInfo then
            button.icon:SetTexture(SCB.assetRoot .. classInfo.icon)
            button.icon:Show()
        else
            button.icon:Hide()
        end
    end
end

local function SCB_CreatePresetPlayerButton(parent, width, height)
    local button = SCB_CreateTextButton(parent, nil, width, height, "", true)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", SCB_PresetPlayerDragStart)
    button:SetScript("OnDragStop", SCB_PresetPlayerDragStop)
    button:SetScript("OnClick", SCB_PresetPlayerOnClick)
    button:SetScript("OnEnter", SCB_TooltipOnEnter)
    button:SetScript("OnLeave", SCB_TooltipOnLeave)
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", button, "LEFT", 25, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    button.label:SetJustifyH("LEFT")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(18)
    icon:SetHeight(18)
    icon:SetPoint("LEFT", button, "LEFT", 4, 0)
    button.icon = icon
    return button
end

function SCB_RefreshPresetPlayers()
    if not SCB.presetPanel then
        return
    end
    local roster = SCB_GetHumanRoster()
    local present = {}
    local assignedPresent = {}
    local i, info, slotIndex, row, button

    for i = 1, table.getn(roster) do
        present[roster[i].key] = roster[i]
    end

    -- Hide previous overlays and return all bot rows to full strength first.
    for i = 1, 10 do
        row = SCB.presetSlotRows[i]
        if row then
            if row.playerOverlay then
                row.playerOverlay:Hide()
            end
            if row.classButton then row.classButton:SetAlpha(1) end
            if row.roleButton then row.roleButton:SetAlpha(1) end
        end
    end

    for info, slotIndex in pairs(SCB.presetEditorPlayers or {}) do
        if present[info] and slotIndex >= 1 and slotIndex <= 10 then
            assignedPresent[info] = true
            row = SCB.presetSlotRows[slotIndex]
            if row then
                if not row.playerOverlay then
                    row.playerOverlay = SCB_CreatePresetPlayerButton(row, 94, 26)
                    row.playerOverlay:SetPoint("LEFT", row, "LEFT", 0, 0)
                    row.playerOverlay:SetFrameLevel(row:GetFrameLevel() + 4)
                end
                SCB_SetPlayerButtonIdentity(row.playerOverlay, present[info])
                row.playerOverlay:Show()
                if row.classButton then row.classButton:SetAlpha(0.22) end
                if row.roleButton then row.roleButton:SetAlpha(0.22) end
            end
        end
    end

    -- Unassigned live players remain available in the small player pool.
    local poolIndex = 0
    for i = 1, table.getn(roster) do
        info = roster[i]
        if not assignedPresent[info.key] then
            poolIndex = poolIndex + 1
            button = SCB.presetPlayerPoolButtons[poolIndex]
            if not button then
                button = SCB_CreatePresetPlayerButton(SCB.presetPlayerPool, 108, 22)
                SCB.presetPlayerPoolButtons[poolIndex] = button
            end
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", SCB.presetPlayerPool, "TOPLEFT", ((poolIndex - 1) - math.floor((poolIndex - 1) / 2) * 2) * 112, -14 - (math.floor((poolIndex - 1) / 2) * 24))
            SCB_SetPlayerButtonIdentity(button, info)
            button:Show()
        end
    end
    for i = poolIndex + 1, table.getn(SCB.presetPlayerPoolButtons) do
        SCB.presetPlayerPoolButtons[i]:Hide()
    end

    if poolIndex > 0 then
        local poolRows = math.floor((poolIndex - 1) / 2) + 1
        SCB.presetPlayerPool:Show()
        if SCB.presetPlayerPoolLabel then SCB.presetPlayerPoolLabel:Show() end
        SCB.presetPlayerPool:SetHeight(16 + (poolRows * 24))
        SCB.presetPanel:SetHeight(286 + (poolRows * 24))
    else
        SCB.presetPlayerPool:Hide()
        if SCB.presetPlayerPoolLabel then SCB.presetPlayerPoolLabel:Hide() end
        SCB.presetPlayerPool:SetHeight(1)
        SCB.presetPanel:SetHeight(272)
    end
end

local function SCB_LoadPreset(index)
    SCB_EnsurePresetDB()
    local preset = SoloCraftBotsDB.presets[index]
    if not preset then
        return
    end

    SoloCraftBotsDB.currentPreset = index
    SCB.presetEditorSlots = SCB_NormalizePresetSlots(preset.slots)
    SCB.presetEditorPlayers = SCB_CopyPlayerSlots(preset.playerSlots)
    SCB_UpdatePresetSelectorText()
    SCB_RefreshPresetSlots()
    SCB_RefreshPresetPlayers()
    SCB_SetPresetDirty(false)
end

local function SCB_SaveCurrentPreset()
    SCB_EnsurePresetDB()
    local preset = SoloCraftBotsDB.currentPreset and SoloCraftBotsDB.presets[SoloCraftBotsDB.currentPreset]
    if not preset then
        SCB_Print("No preset selected to save.")
        return
    end
    preset.slots = SCB_NormalizePresetSlots(SCB.presetEditorSlots)
    preset.playerSlots = SCB_CopyPlayerSlots(SCB.presetEditorPlayers)
    SCB_SetPresetDirty(false)
end

local function SCB_PresetSaveOnClick()
    SCB_SaveCurrentPreset()
end

local function SCB_PresetClassOnClick()
    local slotIndex = this.scbSlotIndex
    local slot = SCB.presetEditorSlots[slotIndex]
    local visible = SCB_GetVisibleClasses()
    local i, currentIndex, nextIndex, classInfo, roleInfo
    local direction = 1

    if arg1 == "RightButton" then
        direction = -1
    end
    if not slot or table.getn(visible) == 0 then
        return
    end

    currentIndex = 0
    for i = 1, table.getn(visible) do
        if visible[i].key == slot.class then
            currentIndex = i
            break
        end
    end

    if currentIndex == 0 then
        nextIndex = 1
    else
        nextIndex = currentIndex + direction
        if nextIndex < 1 then
            nextIndex = table.getn(visible)
        elseif nextIndex > table.getn(visible) then
            nextIndex = 1
        end
    end

    classInfo = visible[nextIndex]
    roleInfo = SCB_FindRoleEntry(classInfo, slot.role, slot.extra)
    slot.class = classInfo.key
    slot.role = roleInfo.role
    slot.extra = roleInfo.extra
    SCB_RefreshPresetSlots()
    SCB_SetPresetDirty(true)
end

local function SCB_PresetRoleOnClick()
    local slotIndex = this.scbSlotIndex
    local slot = SCB.presetEditorSlots[slotIndex]
    local classInfo, currentRoleInfo, currentIndex
    local nextIndex, direction

    if not slot then
        return
    end
    classInfo = SCB_FindClass(slot.class)
    if not classInfo or table.getn(classInfo.roles) == 0 then
        return
    end

    direction = 1
    if arg1 == "RightButton" then
        direction = -1
    end

    currentRoleInfo, currentIndex = SCB_FindRoleEntry(classInfo, slot.role, slot.extra)
    nextIndex = currentIndex + direction
    if nextIndex < 1 then
        nextIndex = table.getn(classInfo.roles)
    elseif nextIndex > table.getn(classInfo.roles) then
        nextIndex = 1
    end

    currentRoleInfo = classInfo.roles[nextIndex]
    slot.role = currentRoleInfo.role
    slot.extra = currentRoleInfo.extra
    SCB_RefreshPresetSlots()
    SCB_SetPresetDirty(true)
end

local function SCB_HidePresetMenu()
    if SCB.presetMenu then
        SCB.presetMenu:Hide()
    end
end

local function SCB_PresetMenuChoiceOnClick()
    if this.scbPresetIndex then
        SCB_LoadPreset(this.scbPresetIndex)
    end
    SCB_HidePresetMenu()
end

local function SCB_RebuildPresetMenu()
    if not SCB.presetMenu then
        return
    end

    SCB_EnsurePresetDB()
    local count = table.getn(SoloCraftBotsDB.presets)
    local i, preset, button
    local maxVisible = 10
    local visibleCount = math.min(count, maxVisible)

    for i = 1, maxVisible do
        button = SCB.presetMenuButtons[i]
        if not button then
            button = SCB_CreateTextButton(SCB.presetMenu, nil, 96, 20, "")
            button:SetPoint("TOPLEFT", SCB.presetMenu, "TOPLEFT", 4, -4 - ((i - 1) * 20))
            button:SetScript("OnClick", SCB_PresetMenuChoiceOnClick)
            SCB.presetMenuButtons[i] = button
        end

        if i <= visibleCount then
            preset = SoloCraftBotsDB.presets[i]
            button.label:SetText(preset.name or ("Preset " .. i))
            button.scbPresetIndex = i
            button:Show()
        else
            button:Hide()
            button.scbPresetIndex = nil
        end
    end

    SCB.presetMenu:SetHeight(8 + (visibleCount * 20))
end

local function SCB_PresetSelectorOnClick()
    if arg1 == "RightButton" then
        local preset = SoloCraftBotsDB.currentPreset and SoloCraftBotsDB.presets[SoloCraftBotsDB.currentPreset]
        if not preset then
            SCB_Print("No preset selected to rename.")
            return
        end
        SCB.pendingPresetNameMode = "rename"
        SCB.pendingPresetDefaultName = preset.name or "Preset"
        StaticPopup_Show("SOLOCRAFTBOTS_PRESET_NAME")
        return
    end

    SCB_RebuildPresetMenu()
    if SCB.presetMenu:IsShown() then
        SCB.presetMenu:Hide()
    else
        SCB.presetMenu:Show()
        SCB.presetMenu:Raise()
    end
end

local function SCB_PresetAddOnClick()
    SCB_EnsurePresetDB()
    SCB.pendingPresetNameMode = "add"
    SCB.pendingPresetDefaultName = "Preset " .. (table.getn(SoloCraftBotsDB.presets) + 1)
    StaticPopup_Show("SOLOCRAFTBOTS_PRESET_NAME")
end

local function SCB_PresetRemoveOnClick()
    SCB_EnsurePresetDB()
    local count = table.getn(SoloCraftBotsDB.presets)
    local index = SoloCraftBotsDB.currentPreset

    if count == 0 or not index then
        return
    end

    table.remove(SoloCraftBotsDB.presets, index)
    count = table.getn(SoloCraftBotsDB.presets)

    if count == 0 then
        SoloCraftBotsDB.currentPreset = nil
        SCB.presetEditorSlots = SCB_NormalizePresetSlots(nil)
        SCB.presetEditorPlayers = { ["$self"] = 1 }
        SCB_UpdatePresetSelectorText()
        SCB_RefreshPresetSlots()
        SCB_RefreshPresetPlayers()
        SCB_SetPresetDirty(false)
        SCB_HidePresetMenu()
        return
    end

    if index > count then
        index = count
    end
    SCB_LoadPreset(index)
end

local function SCB_GetPresetPopupDialog(frame)
    local candidate = frame
    local i, popup

    while candidate do
        if candidate.editBox then
            return candidate
        end
        if candidate.GetParent then
            candidate = candidate:GetParent()
        else
            candidate = nil
        end
    end

    for i = 1, 4 do
        popup = getglobal("StaticPopup" .. i)
        if popup and popup:IsShown() and popup.which == "SOLOCRAFTBOTS_PRESET_NAME" then
            return popup
        end
    end
    return nil
end

local function SCB_GetPopupEditBox(frame)
    local dialog = SCB_GetPresetPopupDialog(frame)
    if not dialog then
        return nil
    end
    if dialog.editBox then
        return dialog.editBox
    end
    if dialog.GetName then
        return getglobal(dialog:GetName() .. "EditBox")
    end
    return nil
end

local function SCB_AcceptPresetName(dialog)
    local editBox = SCB_GetPopupEditBox(dialog)
    local name = editBox and editBox:GetText() or ""
    if not name or name == "" then
        name = SCB.pendingPresetDefaultName or "Preset"
    end

    SCB_EnsurePresetDB()

    if SCB.pendingPresetNameMode == "rename" then
        local preset = SoloCraftBotsDB.currentPreset and SoloCraftBotsDB.presets[SoloCraftBotsDB.currentPreset]
        if preset then
            preset.name = name
            SCB_UpdatePresetSelectorText()
        end
    else
        local sourceSlots = SCB.presetEditorSlots
        if not sourceSlots or table.getn(sourceSlots) == 0 then
            sourceSlots = SCB_DefaultPresetSlots()
        end
        table.insert(SoloCraftBotsDB.presets, {
            name = name,
            slots = SCB_NormalizePresetSlots(sourceSlots),
            playerSlots = SCB_CopyPlayerSlots(SCB.presetEditorPlayers),
        })
        SCB_LoadPreset(table.getn(SoloCraftBotsDB.presets))
    end

    SCB.pendingPresetNameMode = nil
    SCB.pendingPresetDefaultName = nil
end

StaticPopupDialogs["SOLOCRAFTBOTS_PRESET_NAME"] = {
    text = "Preset name",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 32,
    OnAccept = function()
        SCB_AcceptPresetName(this)
    end,
    OnCancel = function()
        SCB.pendingPresetNameMode = nil
        SCB.pendingPresetDefaultName = nil
    end,
    EditBoxOnEnterPressed = function()
        local dialog = SCB_GetPresetPopupDialog(this)
        SCB_AcceptPresetName(this)
        if dialog then
            dialog:Hide()
        end
    end,
    OnShow = function()
        local editBox = SCB_GetPopupEditBox(this)
        if editBox then
            editBox:SetText(SCB.pendingPresetDefaultName or "Preset")
            editBox:HighlightText()
            editBox:SetFocus()
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    exclusive = 1,
}

local SCB_PRESET_RAID_BARRIER = "__SCB_RAID_BARRIER__"
local SCB_PRESET_CONVERT_NOW = "__SCB_CONVERT_NOW__"
local SCB_PRESET_WAIT_RAID = "__SCB_WAIT_RAID__"

local function SCB_PresetSpawnQueueOnUpdate()
    local nextItem

    if table.getn(SCB.presetSpawnQueue) == 0 then
        SCB.presetSpawnElapsed = 0
        return
    end

    nextItem = SCB.presetSpawnQueue[1]

    -- Normally Group 1 fills the five-player party before conversion. If live
    -- human placement means Group 1 needs more bot positions than the party can
    -- physically hold, convert as soon as a party exists and continue in raid.
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
    elseif nextItem == SCB_PRESET_RAID_BARRIER then
        if GetNumRaidMembers and GetNumRaidMembers() > 0 then
            table.remove(SCB.presetSpawnQueue, 1)
            SCB.presetSpawnElapsed = 0
        elseif GetNumPartyMembers and GetNumPartyMembers() >= 4 and ConvertToRaid then
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
    if SCB.presetSpawnElapsed < SCB.presetSpawnInterval then
        return
    end

    SCB.presetSpawnElapsed = SCB.presetSpawnElapsed - SCB.presetSpawnInterval
    SCB_SendSpawnCommand(nextItem)
    table.remove(SCB.presetSpawnQueue, 1)
end

local function SCB_QueuePresetSpawn(commands)
    local i

    if not commands or table.getn(commands) == 0 then
        return
    end

    -- Add commands stay on the persistent FIFO and are always sent through SAY.
    -- Special queue barriers pause a 10-player preset for party-to-raid conversion.
    for i = 1, table.getn(commands) do
        table.insert(SCB.presetSpawnQueue, commands[i])
    end
end

local function SCB_PresetSummonOnClick()
    local commands = {}
    local slots = SCB_NormalizePresetSlots(SCB.presetEditorSlots)
    local present = SCB_GetPresentHumanMap()
    local occupied = {}
    local key, slotIndex, i, slot
    local group1Commands = {}
    local group2Commands = {}
    local existingParty = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    local availableBeforeRaid = 4 - existingParty

    SCB.presetEditorSlots = slots
    SCB_RefreshPresetSlots()
    SCB_RefreshPresetPlayers()

    -- Only live assigned humans sacrifice their underlying bot. Saved player
    -- assignments that are currently absent leave the bot slot active.
    for key, slotIndex in pairs(SCB.presetEditorPlayers or {}) do
        if present[key] and slotIndex >= 1 and slotIndex <= 10 then
            occupied[slotIndex] = true
        end
    end

    -- A live human without a preset slot would make a 10-player composition
    -- ambiguous: SCB would have to guess which bot to sacrifice. Require the
    -- user to make that choice instead.
    local humanKey
    for humanKey in pairs(present) do
        if not SCB.presetEditorPlayers[humanKey] then
            SCB_Print("Assign " .. SCB_PresetPlayerDisplayName(humanKey) .. " to a preset slot before Summon.")
            return
        end
    end

    for i = 1, 5 do
        if not occupied[i] then
            slot = slots[i]
            table.insert(group1Commands, SCB_BuildSpawnCommand(slot.class, slot.role, slot.extra))
        end
    end
    for i = 6, 10 do
        if not occupied[i] then
            slot = slots[i]
            table.insert(group2Commands, SCB_BuildSpawnCommand(slot.class, slot.role, slot.extra))
        end
    end

    if availableBeforeRaid < 0 then
        availableBeforeRaid = 0
    end

    -- Preserve strict Group 1 spawn order while respecting the five-player
    -- party ceiling. If Group 1 still has bots left when the party will fill,
    -- pause, convert, then finish Group 1 before proceeding to Group 2.
    for i = 1, table.getn(group1Commands) do
        if i == availableBeforeRaid + 1 then
            table.insert(commands, SCB_PRESET_CONVERT_NOW)
        end
        table.insert(commands, group1Commands[i])
    end

    if table.getn(group1Commands) <= availableBeforeRaid then
        table.insert(commands, SCB_PRESET_RAID_BARRIER)
    elseif availableBeforeRaid == 0 and (not GetNumRaidMembers or GetNumRaidMembers() == 0) then
        -- With a full existing party the conversion barrier must precede the
        -- first Group 1 bot rather than waiting for another spawn command.
        if commands[1] ~= SCB_PRESET_CONVERT_NOW then
            table.insert(commands, 1, SCB_PRESET_CONVERT_NOW)
        end
    end

    for i = 1, table.getn(group2Commands) do
        table.insert(commands, group2Commands[i])
    end

    SCB_QueuePresetSpawn(commands)
end

local function SCB_SetPresetPanelShown(show)
    if not SCB.presetPanel then
        return
    end
    if show then
        SCB.presetPanel:Show()
        SCB.presetPanel:Raise()
    else
        SCB.presetPanel:Hide()
        SCB_HidePresetMenu()
    end
end

local function SCB_PresetToggleOnClick()
    if not SCB.presetPanel then
        return
    end
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
    local maxColumns = 8
    local maxRowWidth = (maxColumns * buttonSize) + ((maxColumns - 1) * gap)
    local left = math.floor((frame:GetWidth() - maxRowWidth) / 2)
    local top = -2

    local rows = {
        { recipient = "all", indent = 0, commands = { "play", "forcemove", "move", "come", "stay", "pause" } },
        { recipient = "target", indent = 0, commands = { "play", "forcemove", "move", "come", "stay", "pause" } },
        { gapBefore = true, recipient = "tank", indent = 1, commands = { "forcemove", "move", "come", "stay", "pull" } },
        { recipient = "healer", indent = 1, commands = { "forcemove", "move", "come", "stay" } },
        { recipient = "melee", indent = 1, commands = { "forcemove", "move", "come", "stay" } },
        { recipient = "ranged", indent = 1, commands = { "forcemove", "move", "come", "stay", "spread", "hug" } },
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
            if commandKey == "forcemove" then
                button.scbTooltip = button.scbTooltip .. "\nSends Move, then Come"
                SCB_AddForceMoveOverlay(button)
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

local function SCB_CreatePresetUI(frame)
    local toggle = SCB_CreateTextButton(frame, "SoloCraftBotsPresetToggle", 64, 20, "Presets")
    toggle:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
    toggle:SetScript("OnClick", SCB_PresetToggleOnClick)
    toggle.scbTooltip = "Open/close group presets"
    toggle:SetScript("OnEnter", SCB_TooltipOnEnter)
    toggle:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.presetToggle = toggle

    local panel = CreateFrame("Frame", "SoloCraftBotsPresetPanel", frame)
    panel:SetWidth(254)
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

    local add = SCB_CreateTextButton(panel, "SoloCraftBotsPresetAdd", 22, 22, "+")
    add:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -31)
    add.scbTooltip = "Add preset"
    add:SetScript("OnClick", SCB_PresetAddOnClick)
    add:SetScript("OnEnter", SCB_TooltipOnEnter)
    add:SetScript("OnLeave", SCB_TooltipOnLeave)

    local remove = SCB_CreateTextButton(panel, "SoloCraftBotsPresetRemove", 22, 22, "-")
    remove:SetPoint("LEFT", add, "RIGHT", 2, 0)
    remove.scbTooltip = "Remove current preset"
    remove:SetScript("OnClick", SCB_PresetRemoveOnClick)
    remove:SetScript("OnEnter", SCB_TooltipOnEnter)
    remove:SetScript("OnLeave", SCB_TooltipOnLeave)

    local save = SCB_CreateTextButton(panel, "SoloCraftBotsPresetSave", 22, 22, "S")
    save:SetPoint("LEFT", remove, "RIGHT", 2, 0)
    save.scbTooltip = "Save current composition"
    save:SetScript("OnClick", SCB_PresetSaveOnClick)
    save:SetScript("OnEnter", SCB_TooltipOnEnter)
    save:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.presetSaveButton = save

    local selector = SCB_CreateTextButton(panel, "SoloCraftBotsPresetSelector", 104, 22, "Preset", true)
    selector:SetPoint("LEFT", save, "RIGHT", 2, 0)
    selector.label:ClearAllPoints()
    selector.label:SetPoint("LEFT", selector, "LEFT", 7, 0)
    selector.label:SetPoint("RIGHT", selector, "RIGHT", -22, 0)
    selector.label:SetJustifyH("LEFT")

    -- Use Blizzard's familiar dropdown arrow artwork so this still remains our
    -- compact selector while reading immediately as a dropdown control.
    local selectorArrow = CreateFrame("Button", nil, selector)
    selectorArrow:SetWidth(18)
    selectorArrow:SetHeight(18)
    selectorArrow:SetPoint("RIGHT", selector, "RIGHT", -2, 0)
    selectorArrow:EnableMouse(false)
    local selectorArrowTexture = selectorArrow:CreateTexture(nil, "ARTWORK")
    selectorArrowTexture:SetAllPoints(selectorArrow)
    selectorArrowTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    selector.arrow = selectorArrow
    selector.scbTooltip = "Left-click: choose preset\nRight-click: rename current preset"
    selector:SetScript("OnClick", SCB_PresetSelectorOnClick)
    selector:SetScript("OnEnter", SCB_TooltipOnEnter)
    selector:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.presetSelector = selector

    local menu = CreateFrame("Frame", "SoloCraftBotsPresetMenu", panel)
    menu:SetWidth(104)
    menu:SetHeight(28)
    menu:SetPoint("TOPRIGHT", selector, "BOTTOMRIGHT", 0, -1)
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    menu:SetBackdropColor(0.03, 0.03, 0.03, 0.98)
    menu:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
    menu:SetFrameStrata("DIALOG")
    menu:Hide()
    SCB.presetMenu = menu

    -- Ten-player presets are authored as two explicit five-player groups.
    -- All ten positions retain bot assignments; live human players are dragged
    -- onto positions as overlays and temporarily sacrifice the bot underneath.
    local groupTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    groupTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -65)
    groupTitle:SetText("Group 1")
    groupTitle:SetTextColor(1, 0.82, 0, 1)

    local groupFrame = CreateFrame("Frame", nil, panel)
    groupFrame:SetWidth(112)
    groupFrame:SetHeight(158)
    groupFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -74)
    groupFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    groupFrame:SetBackdropColor(0.02, 0.02, 0.02, 0.45)
    groupFrame:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)

    local group2Title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    group2Title:SetPoint("TOPLEFT", panel, "TOPLEFT", 140, -65)
    group2Title:SetText("Group 2")
    group2Title:SetTextColor(1, 0.82, 0, 1)

    local group2Frame = CreateFrame("Frame", nil, panel)
    group2Frame:SetWidth(112)
    group2Frame:SetHeight(158)
    group2Frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 132, -74)
    group2Frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    group2Frame:SetBackdropColor(0.02, 0.02, 0.02, 0.45)
    group2Frame:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)

    local i, localIndex, parentFrame, row, classButton, roleButton
    for i = 1, 10 do
        if i <= 5 then
            parentFrame = groupFrame
            localIndex = i
        else
            parentFrame = group2Frame
            localIndex = i - 5
        end

        row = CreateFrame("Frame", nil, parentFrame)
        row:SetWidth(94)
        row:SetHeight(26)
        row:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 9, -8 - ((localIndex - 1) * 29))
        row.scbSlotIndex = i

        classButton = SCB_CreateArtButton(row, nil, 26, SCB.assetRoot .. "warrior.tga", true)
        classButton:SetPoint("LEFT", row, "LEFT", 0, 0)
        classButton.scbSlotIndex = i
        classButton:SetScript("OnClick", SCB_PresetClassOnClick)
        classButton:SetScript("OnEnter", SCB_TooltipOnEnter)
        classButton:SetScript("OnLeave", SCB_TooltipOnLeave)

        roleButton = SCB_CreateArtButton(row, nil, 22, SCB.assetRoot .. "tank.tga", true, SCB.assetRoot .. "tank_h.tga")
        roleButton:SetPoint("LEFT", classButton, "RIGHT", 8, 0)
        roleButton.scbSlotIndex = i
        roleButton:SetScript("OnClick", SCB_PresetRoleOnClick)
        roleButton:SetScript("OnEnter", SCB_TooltipOnEnter)
        roleButton:SetScript("OnLeave", SCB_TooltipOnLeave)

        row.classButton = classButton
        row.roleButton = roleButton
        SCB.presetSlotRows[i] = row
        SCB.presetDropTargets[i] = row
        SCB.presetSlotButtons[i] = {
            classButton = classButton,
            roleButton = roleButton,
        }
    end

    local playerPool = CreateFrame("Frame", nil, panel)
    playerPool:SetWidth(224)
    playerPool:SetHeight(1)
    playerPool:SetPoint("TOPLEFT", panel, "TOPLEFT", 15, -238)
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
    summon.scbTooltip = "Summon this 10-player preset in group order\nUses the current editor state, saved or unsaved"
    summon:SetScript("OnClick", SCB_PresetSummonOnClick)
    summon:SetScript("OnEnter", SCB_TooltipOnEnter)
    summon:SetScript("OnLeave", SCB_TooltipOnLeave)

    panel:Hide()
    SCB_EnsurePresetDB()
    if SoloCraftBotsDB.currentPreset then
        SCB_LoadPreset(SoloCraftBotsDB.currentPreset)
    else
        SCB.presetEditorSlots = SCB_NormalizePresetSlots(nil)
        SCB.presetEditorPlayers = { ["$self"] = 1 }
        SCB_UpdatePresetSelectorText()
        SCB_RefreshPresetSlots()
        SCB_RefreshPresetPlayers()
        SCB_SetPresetDirty(false)
    end
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
