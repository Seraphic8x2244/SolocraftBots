-- SoloCraft Bots - preset execution snapshots with exact raid rows.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local SCB_072PreviousGetSnapshotOccupiedSlots = SCB_GetSnapshotOccupiedSlots
function SCB_GetSnapshotOccupiedSlots(snapshot)
    local occupied, groupNext = {}, {}
    local i, player, groupIndex, slotIndex, groupStart, groupEnd

    if not snapshot or (snapshot.size or 0) <= 5 then
        return SCB_072PreviousGetSnapshotOccupiedSlots(snapshot)
    end

    -- Exact live rows win. Old snapshots without them retain group-front
    -- compatibility by taking the first remaining row in their assigned group.
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

local SCB_072PreviousValidatePresetExecutionSnapshot = SCB_ValidatePresetExecutionSnapshot
if SCB_072PreviousValidatePresetExecutionSnapshot then
    function SCB_ValidatePresetExecutionSnapshot(snapshot, requireCurrentRoster)
        local valid, errorText = SCB_072PreviousValidatePresetExecutionSnapshot(snapshot, requireCurrentRoster)
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
                expectedGroup = math.floor((slotIndex - 1) / 5) + 1
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
            if not slotIndex
                or math.floor((slotIndex - 1) / 5) + 1 ~= assignedGroup then
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

local SCB_072PreviousCreateRaidRoleTracker = SCB_CreateRaidRoleTracker
if SCB_072PreviousCreateRaidRoleTracker then
    function SCB_CreateRaidRoleTracker(slots, size, occupied, group, snapshot)
        local tracker = SCB_072PreviousCreateRaidRoleTracker(slots, size, occupied, group, snapshot)
        if tracker and snapshot then
            tracker.presetGroupIndex = snapshot.presetGroupIndex
            tracker.presetIndex = snapshot.presetIndex
        end
        return tracker
    end
end
