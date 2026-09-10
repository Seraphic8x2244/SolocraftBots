-- SoloCraft Bots - exact logical human-slot ownership and execution snapshots.
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

local SCB_PreLogicalGetSnapshotOccupiedSlots = SCB_GetSnapshotOccupiedSlots
function SCB_GetSnapshotOccupiedSlots(snapshot)
    local occupied, groupNext = {}, {}
    local i, player, groupIndex, slotIndex, groupStart, groupEnd

    if not snapshot or (snapshot.size or 0) <= 5 then
        return SCB_PreLogicalGetSnapshotOccupiedSlots(snapshot)
    end

    -- Exact logical human slots win. Compatibility snapshots that provide only
    -- a subgroup retain the old group-front occupancy behavior; new local raid
    -- snapshots always carry an exact logical slot.
    for i = 1, table.getn(snapshot.players or {}) do
        player = snapshot.players[i]
        slotIndex = player and player.slotIndex or nil
        if slotIndex and slotIndex >= 1 and slotIndex <= snapshot.size then
            occupied[slotIndex] = true
        end
    end

    for i = 1, table.getn(snapshot.players or {}) do
        player = snapshot.players[i]
        if player and not player.slotIndex then
            groupIndex = player.group
            if groupIndex then
                groupStart = ((groupIndex - 1) * 5) + 1
                groupEnd = math.min(groupStart + 4, snapshot.size)
                slotIndex = groupNext[groupIndex] or groupStart
                while slotIndex <= groupEnd and occupied[slotIndex] do
                    slotIndex = slotIndex + 1
                end
                if slotIndex <= groupEnd then
                    occupied[slotIndex] = true
                    groupNext[groupIndex] = slotIndex + 1
                end
            end
        end
    end
    return occupied
end

local SCB_PreLogicalValidatePresetExecutionSnapshot = SCB_ValidatePresetExecutionSnapshot
if SCB_PreLogicalValidatePresetExecutionSnapshot then
    function SCB_ValidatePresetExecutionSnapshot(snapshot, requireCurrentRoster)
        local valid, errorText = SCB_PreLogicalValidatePresetExecutionSnapshot(snapshot, requireCurrentRoster)
        local seenSlots = {}
        local i, player, slotIndex, expectedGroup
        if not valid then return valid, errorText end
        if not snapshot or (snapshot.size or 0) <= 5 then return valid, errorText end

        for i = 1, table.getn(snapshot.players or {}) do
            player = snapshot.players[i]
            slotIndex = player and player.slotIndex or nil
            if slotIndex ~= nil then
                if type(slotIndex) ~= "number"
                    or slotIndex < 1 or slotIndex > snapshot.size
                    or seenSlots[slotIndex] then
                    return false, SCB_L("ERR_SNAPSHOT_PLAYERS")
                end
                expectedGroup = SCB_PlayerSlotGroup(slotIndex)
                if expectedGroup ~= player.group then
                    return false, SCB_L("ERR_SNAPSHOT_RAID_GROUP")
                end
                seenSlots[slotIndex] = true
            end
        end
        return true
    end
end

function SCB_BuildPresetExecutionSnapshot()
    local group = SCB_CurrentPresetGroup()
    local preset = SCB_CurrentPreset()
    local size = SCB_CurrentPresetSize()
    local slots, roster, present, playerRows, players, groupCounts = {}, {}, {}, {}, {}, {}
    local i, info, assignedGroup, slotIndex, role, extra, fallbackRole, fallbackExtra
    local snapshot, valid, errorText

    if not group or not preset then
        return nil, SCB_L("ERR_SELECT_PRESET")
    end

    slots = SCB_NormalizePresetSlots(SCB.presetEditorSlots, size)
    for i = 1, size do
        if not SCB_IsValidSpawnAssignment(slots[i].class, slots[i].role, slots[i].extra) then
            return nil, SCB_L("ERR_PRESET_BOT")
        end
    end

    roster, present, playerRows = SCB_GetPresetHumanLayout()

    for i = 1, table.getn(roster) do
        info = roster[i]
        if size > 5 then
            assignedGroup = SCB.presetEditorPlayers and SCB.presetEditorPlayers[info.key]
            slotIndex = playerRows and playerRows[info.key] or nil
            if not assignedGroup then
                return nil, string.format(SCB_L("ERR_ASSIGN_PLAYER"), info.name)
            end
            if assignedGroup < 1 or assignedGroup > math.ceil(size / 5) then
                return nil, SCB_L("ERR_PRESET_PLAYER_GROUP")
            end
            if not slotIndex or SCB_PlayerSlotGroup(slotIndex) ~= assignedGroup then
                return nil, SCB_L("ERR_PARTY_LAYOUT")
            end
            groupCounts[assignedGroup] = (groupCounts[assignedGroup] or 0) + 1
            if groupCounts[assignedGroup] > 5 then
                return nil, string.format(SCB_L("ERR_PRESET_GROUP_FULL"), assignedGroup)
            end
        else
            assignedGroup = 1
            slotIndex = playerRows and playerRows[info.key] or nil
            if not slotIndex then
                return nil, SCB_L("ERR_PARTY_LAYOUT")
            end
        end

        if info.key == "$self" then
            fallbackRole, fallbackExtra = SCB_GetCharacterDefaultRoleSelection()
        else
            fallbackRole = SCB_DefaultPlayerRole(info)
            fallbackExtra = nil
        end
        role, extra = SCB_GetPlayerRoleSelection(
            SCB.presetEditorPlayerRoles and SCB.presetEditorPlayerRoles[info.key] or nil,
            fallbackRole,
            fallbackExtra
        )
        table.insert(players, {
            name = info.name,
            group = assignedGroup,
            slotIndex = slotIndex,
            role = role,
            extra = extra,
        })
    end

    snapshot = {
        protocol = 1,
        groupID = group.id,
        groupName = group.name or SCB_L("PRESET_GROUP_PLACEHOLDER"),
        size = size,
        presetName = preset.name or SCB_L("PRESET_PLACEHOLDER"),
        presetGroupIndex = SoloCraftBotsDB and SoloCraftBotsDB.currentPresetGroup or nil,
        presetIndex = group.currentPreset,
        slots = slots,
        players = players,
        roleCounts = SCB_CalculatePresetRoleCounts(),
    }
    valid, errorText = SCB_ValidatePresetExecutionSnapshot(snapshot, true)
    if not valid then return nil, errorText end
    return snapshot
end

local SCB_PreLogicalCreateRaidRoleTracker = SCB_CreateRaidRoleTracker
if SCB_PreLogicalCreateRaidRoleTracker then
    function SCB_CreateRaidRoleTracker(slots, size, occupied, group, snapshot)
        local tracker = SCB_PreLogicalCreateRaidRoleTracker(slots, size, occupied, group, snapshot)
        if tracker and snapshot then
            tracker.presetGroupIndex = snapshot.presetGroupIndex
            tracker.presetIndex = snapshot.presetIndex
        end
        return tracker
    end
end
