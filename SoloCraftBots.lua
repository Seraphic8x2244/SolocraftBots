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

local function SCB_CreateArtButton(parent, name, size, texturePath, allowRightClick)
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
    highlight:SetTexture(texturePath)
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.28)
    button.highlight = highlight

    local selected = button:CreateTexture(nil, "OVERLAY")
    selected:SetTexture(texturePath)
    selected:SetBlendMode("ADD")
    selected:SetAlpha(0.42)
    selected:SetWidth(size + 5)
    selected:SetHeight(size + 5)
    selected:SetPoint("CENTER", button, "CENTER", 0, 0)
    selected:Hide()
    button.selectedGlow = selected

    return button
end

local function SCB_SetArtButtonSelected(button, selected)
    if not button or not button.selectedGlow then
        return
    end
    if selected then
        button.selectedGlow:Show()
    else
        button.selectedGlow:Hide()
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
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    title:SetText(text)
    title:SetTextColor(1, 0.82, 0, 1)
    return title
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
    if not SCB.distanceFarButton or not SCB.distanceNearButton then
        return
    end
    SCB_EnsureSessionDB()
    local state = SoloCraftBotsDB.session.state.distance
    SCB_SetArtButtonSelected(SCB.distanceFarButton, state == "far")
    SCB_SetArtButtonSelected(SCB.distanceNearButton, state == "near")
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
    if this.scbDistanceMode == "far" then
        SCB_SendCommand("distance on")
        SoloCraftBotsDB.session.state.distance = "far"
    else
        SCB_SendCommand("distance off")
        SoloCraftBotsDB.session.state.distance = "near"
    end
    SCB_RefreshDistanceButtons()
end

-- -------------------------------------------------------------------------
-- Direct command matrix
-- -------------------------------------------------------------------------

SCB.recipients = {
    { key = "all", label = "All", icon = "all.tga" },
    { key = "target", label = "Target", icon = "target.tga" },
    { key = "tank", label = "Tanks", icon = "tank.tga" },
    { key = "healer", label = "Healers", icon = "healer.tga" },
    { key = "melee", label = "Melee", icon = "melee.tga" },
    { key = "ranged", label = "Ranged", icon = "ranged.tga" },
}

SCB.commandOrder = {
    "heel", "forceheel", "move", "stay", "attack", "passive",
    "spread", "object", "hug", "pause", "unpause", "pull", "aoe",
}

SCB.commands = {
    heel = {
        label = "Heel",
        icon = "come.tga",
        routes = {
            all = { "cometome" },
            target = { "come" },
            tank = { "cometank" },
            healer = { "comeheal" },
            melee = { "comemelee" },
            ranged = { "comerange" },
        },
    },
    forceheel = {
        label = "Force Heel",
        icon = "forcecome.tga",
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
        routes = {
            all = { "moveall" },
            target = { "move" },
            tank = { "movetank" },
            healer = { "moveheal" },
            melee = { "movemelee" },
            ranged = { "moverange" },
        },
    },
    stay = {
        label = "Stay",
        icon = "stay.tga",
        routes = {
            all = { "stayall" },
            target = { "stay" },
            tank = { "staytank" },
            healer = { "stayheal" },
            melee = { "staymelee" },
            ranged = { "stayrange" },
        },
    },
    attack = {
        label = "Attack",
        icon = "attack.tga",
        routes = { all = { "attackstart" } },
    },
    passive = {
        label = "Passive",
        icon = "stopattack2.tga",
        routes = { all = { "attackstop" } },
    },
    spread = {
        label = "Spread",
        icon = "spread.tga",
        routes = { ranged = { "spread" } },
    },
    object = {
        label = "Object",
        icon = "gobject.tga",
        routes = { all = { "usegobject" } },
    },
    hug = {
        label = "Hug",
        icon = "spreadoff.tga",
        routes = { ranged = { "spreadoff" } },
    },
    pause = {
        label = "Pause",
        icon = "pause.tga",
        routes = {
            all = { "pause all" },
            target = { "pause" },
        },
    },
    unpause = {
        label = "Unpause",
        icon = "unpause.tga",
        routes = {
            all = { "unpause all" },
            target = { "unpause" },
        },
    },
    pull = {
        label = "Pull",
        icon = "pull.tga",
        routes = { tank = { "pull" } },
    },
    aoe = {
        label = "AoE",
        icon = "aoe.tga",
        routes = { all = { "aoe" } },
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

local function SCB_RefreshRaidmarkModeButtons()
    if not SCB.focusModeButton or not SCB.ccModeButton then
        return
    end
    SCB_SetArtButtonSelected(SCB.focusModeButton, SCB.raidMarkMode == "focus")
    SCB_SetArtButtonSelected(SCB.ccModeButton, SCB.raidMarkMode == "cc")
end

local function SCB_RaidmarkModeOnClick()
    if this.scbMarkMode == "focus" or this.scbMarkMode == "cc" then
        SCB.raidMarkMode = this.scbMarkMode
        SCB_RefreshRaidmarkModeButtons()
    end
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
        { class = "warrior", role = "tank" },
        { class = "priest", role = "healer" },
        { class = "rogue", role = "meleedps" },
        { class = "mage", role = "rangedps" }, -- Frost: no extra arg
    }
end

local function SCB_NormalizePresetSlots(slots)
    local defaults = SCB_DefaultPresetSlots()
    local normalized = {}
    local i, slot
    for i = 1, 4 do
        slot = slots and slots[i] or nil
        if slot and slot.class and slot.role then
            normalized[i] = SCB_CopySlot(slot)
        else
            normalized[i] = SCB_CopySlot(defaults[i])
        end
    end
    return normalized
end

local function SCB_EnsurePresetDB()
    -- Create one starter preset only when presets have never existed. If the
    -- player deliberately deletes every preset, keep the list empty.
    if SoloCraftBotsDB.presets == nil then
        SoloCraftBotsDB.presets = {
            { name = "Preset 1", slots = SCB_DefaultPresetSlots() },
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

local function SCB_SetPresetDirty(dirty)
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

    for i = 1, 4 do
        slot = SCB.presetEditorSlots[i]
        classButton = SCB.presetSlotButtons[i] and SCB.presetSlotButtons[i].classButton
        roleButton = SCB.presetSlotButtons[i] and SCB.presetSlotButtons[i].roleButton

        if slot and classButton and roleButton then
            classInfo = SCB_FindClass(slot.class)
            roleInfo = SCB_FindRoleEntry(classInfo, slot.role, slot.extra)

            classButton.icon:SetTexture(SCB.assetRoot .. classInfo.icon)
            classButton.scbTooltip = "Bot " .. (i + 1) .. ": " .. classInfo.name .. "\nLeft-click next class; right-click previous"

            roleButton.icon:SetTexture(SCB_RoleTexture(roleInfo))
            roleButton.scbTooltip = roleInfo.label .. "\nLeft-click next role/spec; right-click previous"
        end
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
    SCB_UpdatePresetSelectorText()
    SCB_RefreshPresetSlots()
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
            button = SCB_CreateTextButton(SCB.presetMenu, nil, 126, 20, "")
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
        SCB_UpdatePresetSelectorText()
        SCB_RefreshPresetSlots()
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

local function SCB_PresetSpawnQueueOnUpdate()
    if table.getn(SCB.presetSpawnQueue) == 0 then
        SCB.presetSpawnElapsed = 0
        return
    end

    SCB.presetSpawnElapsed = SCB.presetSpawnElapsed + (arg1 or 0)
    if SCB.presetSpawnElapsed < SCB.presetSpawnInterval then
        return
    end

    SCB.presetSpawnElapsed = SCB.presetSpawnElapsed - SCB.presetSpawnInterval
    SCB_SendSpawnCommand(SCB.presetSpawnQueue[1])
    table.remove(SCB.presetSpawnQueue, 1)
end

local function SCB_QueuePresetSpawn(commands)
    local i

    if not commands or table.getn(commands) == 0 then
        return
    end

    -- Preset spawning deliberately mirrors FillRaidBots' simple FIFO model:
    -- every add command is queued and sent through SAY at a fixed 0.1s cadence.
    -- No raid conversion, roster-dependent channel switching, or per-batch state.
    for i = 1, table.getn(commands) do
        table.insert(SCB.presetSpawnQueue, commands[i])
    end
end

local function SCB_PresetSummonOnClick()
    local commands = {}
    local slots = SCB_NormalizePresetSlots(SCB.presetEditorSlots)
    local i, slot

    -- Keep the editor canonical before sending so every selected preset uses
    -- exactly the four visible bot slots, regardless of preset index/history.
    SCB.presetEditorSlots = slots
    SCB_RefreshPresetSlots()

    for i = 1, 4 do
        slot = slots[i]
        table.insert(commands, SCB_BuildSpawnCommand(slot.class, slot.role, slot.extra))
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
    SCB_CreateSectionTitle(frame, "Summon", 16, -42)

    local far = SCB_CreateArtButton(frame, "SoloCraftBotsDistanceFar", 22, SCB.assetRoot .. "distance.tga")
    far:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -44, -38)
    far.scbDistanceMode = "far"
    far.scbTooltip = "Spawn Far\n.partybot distance on\nRemains clickable even when highlighted"
    far:SetScript("OnClick", SCB_DistanceOnClick)
    far:SetScript("OnEnter", SCB_TooltipOnEnter)
    far:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.distanceFarButton = far

    local near = SCB_CreateArtButton(frame, "SoloCraftBotsDistanceNear", 22, SCB.assetRoot .. "distanceoff.tga")
    near:SetPoint("LEFT", far, "RIGHT", 3, 0)
    near.scbDistanceMode = "near"
    near.scbTooltip = "Spawn Near\n.partybot distance off\nRemains clickable even when highlighted"
    near:SetScript("OnClick", SCB_DistanceOnClick)
    near:SetScript("OnEnter", SCB_TooltipOnEnter)
    near:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.distanceNearButton = near

    local visibleClasses = SCB_GetVisibleClasses()
    local gridLeft = 16
    local gridTop = -66
    local cellWidth = 72
    local cellHeight = 100
    local classSize = 42
    local roleSize = 18
    local roleGap = 3
    local i, j, classInfo, roleInfo, row, col
    local cellX, cellY, classFrame, classTexture, roleButton, roleTexture
    local roleCount, roleRow, roleCol, rolesThisRow, rowStartX, roleX, roleY

    for i = 1, table.getn(visibleClasses) do
        classInfo = visibleClasses[i]
        row = math.floor((i - 1) / 4)
        col = math.mod(i - 1, 4)
        cellX = gridLeft + (col * cellWidth)
        cellY = gridTop - (row * cellHeight)

        classFrame = CreateFrame("Frame", nil, frame)
        classFrame:SetWidth(classSize)
        classFrame:SetHeight(classSize)
        classFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", cellX + ((cellWidth - classSize) / 2), cellY)
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
            roleButton = SCB_CreateArtButton(frame, nil, roleSize, roleTexture)
            roleButton:SetPoint("TOPLEFT", frame, "TOPLEFT", roleX, roleY)
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
    SCB_CreateSectionTitle(frame, "Commands", 16, -258)

    local buttonSize = 31
    local gap = 3
    local rowGap = 1
    local groupGap = 10
    local maxColumns = 7
    local maxRowWidth = (maxColumns * buttonSize) + ((maxColumns - 1) * gap)
    local left = math.floor((frame:GetWidth() - maxRowWidth) / 2)
    local top = -278

    local rows = {
        { recipient = "all", commands = { "heel", "move", "stay", "forceheel", "pause", "unpause" } },
        { recipient = "target", commands = { "heel", "move", "stay", "forceheel", "pause", "unpause" } },
        { gapBefore = true, recipient = "tank", commands = { "heel", "move", "stay", "forceheel", "pull" } },
        { recipient = "healer", commands = { "heel", "move", "stay", "forceheel" } },
        { recipient = "melee", commands = { "heel", "move", "stay", "forceheel" } },
        { recipient = "ranged", commands = { "heel", "move", "stay", "forceheel", "spread", "hug" } },
    }

    local recipientByKey = {}
    local i, r, row, recipient, commandKey, commandInfo, route, button
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

        button = SCB_CreateArtButton(frame, nil, buttonSize, SCB.assetRoot .. recipient.icon)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", left, y)
        button.scbTooltip = recipient.label
        button:SetScript("OnEnter", SCB_TooltipOnEnter)
        button:SetScript("OnLeave", SCB_TooltipOnLeave)

        for i = 1, table.getn(row.commands) do
            commandKey = row.commands[i]
            commandInfo = SCB.commands[commandKey]
            route = commandInfo.routes[row.recipient]
            button = SCB_CreateArtButton(frame, nil, buttonSize, SCB.assetRoot .. commandInfo.icon)
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", left + (i * (buttonSize + gap)), y)
            button.scbCommandKey = commandKey
            button.scbRecipientKey = row.recipient
            button.scbRecipientLabel = recipient.label
            button.scbTooltip = recipient.label .. " - " .. commandInfo.label
            if commandKey == "forceheel" then
                button.scbTooltip = button.scbTooltip .. "\nSends Move, then Heel"
            end
            if not route then
                button.scbTooltip = button.scbTooltip .. "\nUnavailable for this recipient"
            end
            button:SetScript("OnClick", SCB_DirectCommandOnClick)
            button:SetScript("OnEnter", SCB_TooltipOnEnter)
            button:SetScript("OnLeave", SCB_TooltipOnLeave)
            SCB_SetArtButtonAvailable(button, route ~= nil)
        end

        y = y - buttonSize - rowGap
    end

    -- Object and AoE have fixed natural scope and therefore do not need a
    -- recipient icon. Keep them separate from the recipient rows.
    y = y - 10
    local standalone = { "object", "aoe" }
    local standaloneWidth = (2 * buttonSize) + gap
    local standaloneLeft = math.floor((frame:GetWidth() - standaloneWidth) / 2)
    for i = 1, table.getn(standalone) do
        commandKey = standalone[i]
        commandInfo = SCB.commands[commandKey]
        button = SCB_CreateArtButton(frame, nil, buttonSize, SCB.assetRoot .. commandInfo.icon)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", standaloneLeft + ((i - 1) * (buttonSize + gap)), y)
        button.scbCommandKey = commandKey
        button.scbRecipientKey = "all"
        button.scbRecipientLabel = "All"
        button.scbTooltip = commandInfo.label
        button:SetScript("OnClick", SCB_DirectCommandOnClick)
        button:SetScript("OnEnter", SCB_TooltipOnEnter)
        button:SetScript("OnLeave", SCB_TooltipOnLeave)
    end

    SCB.commandBottomY = y - buttonSize
end

local function SCB_CreateRaidmarkUI(frame)
    local titleY = (SCB.commandBottomY or -465) - 24
    local title = SCB_CreateSectionTitle(frame, "Raidmarks", 16, titleY)
    local toggleSize = 22
    local toggleGap = 3

    local focus = SCB_CreateArtButton(frame, nil, toggleSize, SCB.assetRoot .. "focus.tga")
    focus:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -44, titleY + 4)
    focus.scbMarkMode = "focus"
    focus.scbTooltip = "Focus marks"
    focus:SetScript("OnClick", SCB_RaidmarkModeOnClick)
    focus:SetScript("OnEnter", SCB_TooltipOnEnter)
    focus:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.focusModeButton = focus

    local cc = SCB_CreateArtButton(frame, nil, toggleSize, SCB.assetRoot .. "cc.tga")
    cc:SetPoint("LEFT", focus, "RIGHT", toggleGap, 0)
    cc.scbMarkMode = "cc"
    cc.scbTooltip = "CC marks"
    cc:SetScript("OnClick", SCB_RaidmarkModeOnClick)
    cc:SetScript("OnEnter", SCB_TooltipOnEnter)
    cc:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.ccModeButton = cc

    SCB.raidMarkMode = "focus"
    SCB_RefreshRaidmarkModeButtons()

    local markSize = 24
    local gap = 2
    local totalWidth = (8 * markSize) + (7 * gap)
    local left = math.floor((frame:GetWidth() - totalWidth) / 2)
    local y = titleY - 25
    local i, mark, button

    for i = 1, table.getn(SCB.raidMarks) do
        mark = SCB.raidMarks[i]
        button = SCB_CreateArtButton(frame, nil, markSize, SCB.assetRoot .. mark.key .. ".tga")
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", left + ((i - 1) * (markSize + gap)), y)
        button.scbMark = mark.key
        button.scbTooltip = mark.name .. " (uses selected Focus/CC mode)"
        button:SetScript("OnClick", SCB_RaidMarkOnClick)
        button:SetScript("OnEnter", SCB_TooltipOnEnter)
        button:SetScript("OnLeave", SCB_TooltipOnLeave)
    end

    SCB.raidmarkBottomY = y - markSize
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
    panel:SetWidth(190)
    panel:SetHeight(226)
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

    local selector = SCB_CreateTextButton(panel, "SoloCraftBotsPresetSelector", 98, 22, "Preset", true)
    selector:SetPoint("LEFT", save, "RIGHT", 2, 0)
    selector.scbTooltip = "Left-click: choose preset\nRight-click: rename current preset"
    selector:SetScript("OnClick", SCB_PresetSelectorOnClick)
    selector:SetScript("OnEnter", SCB_TooltipOnEnter)
    selector:SetScript("OnLeave", SCB_TooltipOnLeave)
    SCB.presetSelector = selector

    local menu = CreateFrame("Frame", "SoloCraftBotsPresetMenu", panel)
    menu:SetWidth(134)
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

    local playerNum = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playerNum:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -66)
    playerNum:SetText("1")
    local playerText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playerText:SetPoint("LEFT", playerNum, "RIGHT", 13, 0)
    playerText:SetText("Player")
    playerText:SetTextColor(1, 1, 1, 1)

    local i, num, classButton, roleButton
    for i = 1, 4 do
        num = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        num:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -89 - ((i - 1) * 30))
        num:SetText(i + 1)

        classButton = SCB_CreateArtButton(panel, nil, 26, SCB.assetRoot .. "warrior.tga", true)
        classButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 47, -83 - ((i - 1) * 30))
        classButton.scbSlotIndex = i
        classButton:SetScript("OnClick", SCB_PresetClassOnClick)
        classButton:SetScript("OnEnter", SCB_TooltipOnEnter)
        classButton:SetScript("OnLeave", SCB_TooltipOnLeave)

        roleButton = SCB_CreateArtButton(panel, nil, 22, SCB.assetRoot .. "tank.tga", true)
        roleButton:SetPoint("LEFT", classButton, "RIGHT", 8, 0)
        roleButton.scbSlotIndex = i
        roleButton:SetScript("OnClick", SCB_PresetRoleOnClick)
        roleButton:SetScript("OnEnter", SCB_TooltipOnEnter)
        roleButton:SetScript("OnLeave", SCB_TooltipOnLeave)

        SCB.presetSlotButtons[i] = {
            classButton = classButton,
            roleButton = roleButton,
        }
    end

    local summon = SCB_CreateTextButton(panel, "SoloCraftBotsPresetSummon", 88, 24, "Summon")
    summon:SetPoint("BOTTOM", panel, "BOTTOM", 0, 13)
    summon.scbTooltip = "Summon the four bot slots shown above\nUses the current editor state, saved or unsaved"
    summon:SetScript("OnClick", SCB_PresetSummonOnClick)
    summon:SetScript("OnEnter", SCB_TooltipOnEnter)
    summon:SetScript("OnLeave", SCB_TooltipOnLeave)

    panel:Hide()
    SCB_EnsurePresetDB()
    if SoloCraftBotsDB.currentPreset then
        SCB_LoadPreset(SoloCraftBotsDB.currentPreset)
    else
        SCB.presetEditorSlots = SCB_NormalizePresetSlots(nil)
        SCB_UpdatePresetSelectorText()
        SCB_RefreshPresetSlots()
        SCB_SetPresetDirty(false)
    end
end

local function SCB_CreateUI()
    local frame = CreateFrame("Frame", "SoloCraftBotsFrame", UIParent)
    SCB.frame = frame
    frame:SetWidth(320)
    frame:SetHeight(620)
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

    SCB_CreateSummonUI(frame)
    SCB_CreateCommandUI(frame)
    SCB_CreateRaidmarkUI(frame)
    SCB_CreatePresetUI(frame)

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
    elseif event == "PLAYER_LOGIN" then
        -- Do not rely on ADDON_LOADED having matched a hard-coded folder name.
        -- This also makes first-run SavedVariables initialization explicit.
        SoloCraftBotsDB = SoloCraftBotsDB or {}
        SCB_EnsureSessionDB()
        SCB_EnsurePresetDB()
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
    elseif event == "PLAYER_LOGOUT" then
        SCB_SavePosition()
    end
end)
