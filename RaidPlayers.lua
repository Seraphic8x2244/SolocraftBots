-- SoloCraft Bots - exact logical human-slot ownership for raid presets.
--
-- A preset slot is composition intent. Blizzard's physical raid row is live
-- observation only and must never decide which bot a human suppresses.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

SCB.presetEditorPlayerSlots = SCB.presetEditorPlayerSlots or {}

local function SCB_CopyExactPlayerSlots(source, size)
    local copy = {}
    local key, slot
    size = tonumber(size) or 0
    for key, slot in pairs(source or {}) do
        if type(key) == "string" and type(slot) == "number"
            and slot >= 1 and slot <= size then
            copy[key] = slot
        end
    end
    return copy
end

local function SCB_PlayerSlotGroup(slotIndex)
    if not slotIndex then return nil end
    return math.floor((slotIndex - 1) / 5) + 1
end

local function SCB_FindPlayerKeyByName(name)
    local roster = SCB_GetHumanRoster and SCB_GetHumanRoster() or {}
    local i
    for i = 1, table.getn(roster) do
        if roster[i].name == name then return roster[i].key end
    end
    return nil
end

-- -------------------------------------------------------------------------
-- Logical human layout
-- -------------------------------------------------------------------------

function SCB_GetPresetHumanLayout()
    local size = SCB_CurrentPresetSize()
    local roster = SCB_GetHumanRoster()
    local present, assignedPresent, playerRows = {}, {}, {}
    local used = {}
    local i, info, key, slotIndex

    for i = 1, table.getn(roster) do present[roster[i].key] = roster[i] end

    if size <= 5 then
        local auto = SCB_AutoPartyPlayerSlots(roster)
        for key, slotIndex in pairs(auto) do
            if present[key] and slotIndex >= 1 and slotIndex <= size then
                playerRows[key] = slotIndex
                assignedPresent[key] = true
            end
        end
        return roster, present, playerRows, assignedPresent
    end

    -- Raid presets render only explicit logical assignments. Present humans with
    -- no exact saved/working slot remain in Other Players until the user assigns
    -- them. Blizzard's current subgroup row never fills this table.
    for i = 1, table.getn(roster) do
        info = roster[i]
        slotIndex = SCB.presetEditorPlayerSlots and SCB.presetEditorPlayerSlots[info.key] or nil
        if slotIndex and slotIndex >= 1 and slotIndex <= size and not used[slotIndex] then
            playerRows[info.key] = slotIndex
            assignedPresent[info.key] = true
            used[slotIndex] = true
        end
    end

    return roster, present, playerRows, assignedPresent
end

local SCB_PreviousAssignPresetPlayer_Logical = SCB_AssignPresetPlayer
function SCB_AssignPresetPlayer(key, slotIndex)
    local size = SCB_CurrentPresetSize()
    local groupIndex, otherKey, otherSlot
    if size <= 5 or not key or not slotIndex or slotIndex < 1 or slotIndex > size then return false end

    SCB.presetEditorPlayerSlots = SCB.presetEditorPlayerSlots or {}
    SCB.presetEditorPlayers = SCB.presetEditorPlayers or {}

    -- Never silently displace another saved human assignment. The user can
    -- explicitly remove/move that player first.
    for otherKey, otherSlot in pairs(SCB.presetEditorPlayerSlots) do
        if otherKey ~= key and otherSlot == slotIndex then return false end
    end

    groupIndex = SCB_PlayerSlotGroup(slotIndex)
    SCB.presetEditorPlayerSlots[key] = slotIndex
    SCB.presetEditorPlayers[key] = groupIndex
    if SCB_SetPresetDirty then SCB_SetPresetDirty(true) else SCB.presetDirty = true end
    return true
end

-- Exact slot drops replace the old group-frame drop semantics for raids.
function SCB_FinishPresetPlayerDrag(slotIndex)
    local key = SCB.draggedPresetPlayer
    if not key then return false end

    SCB.draggedPresetPlayer = nil
    SCB.draggedPresetPlayerOriginSlot = nil
    SCB_HideDragGhost()
    SCB.draggedPresetPlayerHoverGroup = nil
    SCB_SetPresetGroupDragHighlight(nil)

    if slotIndex then SCB_AssignPresetPlayer(key, slotIndex) end

    SCB_RefreshPresetSlots()
    if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() end
    return true
end

-- Mouse-up resolves the exact preset row beneath the cursor. Dropping onto the
-- group background alone is intentionally not enough: a human must replace one
-- specific logical bot slot.
function SCB_PresetPlayerDragStop()
    local i, row
    if not SCB.draggedPresetPlayer or SCB_CurrentPresetSize() <= 5 then return end
    for i = 1, SCB_CurrentPresetSize() do
        row = SCB.presetDropTargets and SCB.presetDropTargets[i] or nil
        if row and SCB_FrameContainsCursor(row) then
            SCB_FinishPresetPlayerDrag(i)
            return
        end
    end
    SCB_FinishPresetPlayerDrag(nil)
end

local SCB_PreviousPresetPlayerOnClick_Logical = SCB_PresetPlayerOnClick
if SCB_PreviousPresetPlayerOnClick_Logical then
    function SCB_PresetPlayerOnClick()
        local key = this and this.scbPlayerKey or nil
        local slotIndex = this and this.scbSlotIndex or nil
        local remove = arg1 == "RightButton" and key and key ~= "$self"
            and SCB_CurrentPresetSize() > 5

        if SCB.draggedPresetPlayer and slotIndex then
            SCB_FinishPresetPlayerDrag(slotIndex)
            return
        end

        local result = SCB_PreviousPresetPlayerOnClick_Logical()
        if remove and SCB.presetEditorPlayers and not SCB.presetEditorPlayers[key] then
            SCB.presetEditorPlayerSlots = SCB.presetEditorPlayerSlots or {}
            SCB.presetEditorPlayerSlots[key] = nil
        end
        return result
    end
end

-- -------------------------------------------------------------------------
-- Preset persistence
-- -------------------------------------------------------------------------

local SCB_PreviousLoadPreset_Logical = SCB_LoadPreset
if SCB_PreviousLoadPreset_Logical then
    function SCB_LoadPreset(groupIndex, presetIndex)
        local group, preset, size, key, slotIndex
        SCB.presetEditorPlayerSlots = {}
        SCB_PreviousLoadPreset_Logical(groupIndex, presetIndex)

        group = SCB_CurrentPresetGroup()
        preset = SCB_CurrentPreset()
        size = group and group.size or SCB_CurrentPresetSize()
        SCB.presetEditorPlayerSlots = SCB_CopyExactPlayerSlots(preset and preset.playerSlots or nil, size)

        -- Exact slot is authoritative; group is retained as derived compatibility
        -- data for existing arrangement/snapshot code during consolidation.
        SCB.presetEditorPlayers = SCB.presetEditorPlayers or {}
        for key, slotIndex in pairs(SCB.presetEditorPlayerSlots) do
            SCB.presetEditorPlayers[key] = SCB_PlayerSlotGroup(slotIndex)
        end
        if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() end
    end
end

local SCB_PreviousSaveCurrentPreset_Logical = SCB_SaveCurrentPreset
if SCB_PreviousSaveCurrentPreset_Logical then
    function SCB_SaveCurrentPreset()
        local exact = SCB_CopyExactPlayerSlots(SCB.presetEditorPlayerSlots, SCB_CurrentPresetSize())
        local result = SCB_PreviousSaveCurrentPreset_Logical()
        local preset = SCB_CurrentPreset()
        if preset then
            preset.playerSlots = exact
            SCB.presetEditorPlayerSlots = SCB_CopyExactPlayerSlots(exact, SCB_CurrentPresetSize())
        end
        return result
    end
end

local SCB_PreviousAcceptPresetName_Logical = SCB_AcceptPresetName
if SCB_PreviousAcceptPresetName_Logical then
    function SCB_AcceptPresetName(dialog)
        local exact = SCB_CopyExactPlayerSlots(SCB.presetEditorPlayerSlots, SCB_CurrentPresetSize())
        local result = SCB_PreviousAcceptPresetName_Logical(dialog)
        local preset = SCB_CurrentPreset()
        if preset then
            preset.playerSlots = SCB_CopyExactPlayerSlots(exact, SCB_CurrentPresetSize())
            SCB.presetEditorPlayerSlots = SCB_CopyExactPlayerSlots(exact, SCB_CurrentPresetSize())
            if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() end
        end
        return result
    end
end

-- -------------------------------------------------------------------------
-- Execution snapshots
-- -------------------------------------------------------------------------

local SCB_PreviousBuildPresetExecutionSnapshot_Logical = SCB_BuildPresetExecutionSnapshot
if SCB_PreviousBuildPresetExecutionSnapshot_Logical then
    function SCB_BuildPresetExecutionSnapshot()
        local snapshot, errorText = SCB_PreviousBuildPresetExecutionSnapshot_Logical()
        local used, i, player, key, slotIndex
        if not snapshot then return nil, errorText end
        if (snapshot.size or 0) <= 5 then return snapshot, errorText end

        used = {}
        for i = 1, table.getn(snapshot.players or {}) do
            player = snapshot.players[i]
            key = SCB_FindPlayerKeyByName(player.name)
            slotIndex = key and SCB.presetEditorPlayerSlots and SCB.presetEditorPlayerSlots[key] or nil
            if not slotIndex then
                return nil, string.format(SCB_L("ERR_ASSIGN_PLAYER"), player.name)
            end
            if slotIndex < 1 or slotIndex > snapshot.size or used[slotIndex] then
                return nil, SCB_L("ERR_PARTY_LAYOUT")
            end
            used[slotIndex] = true
            player.slotIndex = slotIndex
            player.group = SCB_PlayerSlotGroup(slotIndex)
        end
        return snapshot, errorText
    end
end

-- Raid human occupancy is exact logical-slot occupancy. Humans are not packed
-- into the first N slots of their Blizzard subgroup.
function SCB_GetSnapshotOccupiedSlots(snapshot)
    local occupied = {}
    local i, player
    if not snapshot or not snapshot.players then return occupied end
    for i = 1, table.getn(snapshot.players) do
        player = snapshot.players[i]
        if player.slotIndex and player.slotIndex >= 1 and player.slotIndex <= (snapshot.size or 0) then
            occupied[player.slotIndex] = true
        end
    end
    return occupied
end
