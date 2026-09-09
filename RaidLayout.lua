-- SoloCraft Bots - live Blizzard raid-layout reconciliation.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local function SCB_BurstDebug(text)
    if SCB_DebugLog then SCB_DebugLog("Burst", text) end
end

-- Blizzard raid order -> active tracker / visible working preset
-- -------------------------------------------------------------------------

local function SCB_MarkWorkingPresetDirty()
    SCB.presetDirty = true
    if SCB.presetSaveButton and SCB.presetSaveButton.label then
        SCB.presetSaveButton.label:SetText(SCB_L("UNSAVED"))
        if SCB_StartPresetButtonPulse then
            SCB_StartPresetButtonPulse(SCB.presetSaveButton, "redloop")
        end
    end
end

local function SCB_IsTrackerPresetSelected(tracker)
    local group = SCB_CurrentPresetGroup()
    if not tracker or not group then return false end
    return tracker.presetGroupIndex
        and tracker.presetIndex
        and SoloCraftBotsDB.currentPresetGroup == tracker.presetGroupIndex
        and group.currentPreset == tracker.presetIndex
end

local function SCB_SyncTrackerToRaidOrder()
    local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil
    local raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local size, groupCount
    local sourceByName, playerBySource = {}, {}
    local targetToSource, seenSource, groupOrdinals = {}, {}, {}
    local oldAssignments, newAssignments, newPlayers = {}, {}, {}
    local i, name, _, subgroup, targetSlot, sourceSlot, assignment, player
    local changed = false
    local oldRevision, editorAligned

    if not tracker or not tracker.ready or tracker.mode ~= "raid" then return false end
    oldRevision = tracker.layoutRevision or 0
    editorAligned = SCB.scbEditorLayoutTrackerRevision == oldRevision
    size = tonumber(tracker.size) or 0
    if size <= 5 or raidCount ~= size then return false end
    groupCount = math.ceil(size / 5)

    -- A row identity always includes its underlying bot assignment. A live
    -- human occupying that row or its live bot name identifies which source row
    -- Blizzard has displayed at each target row.
    for i = 1, table.getn(tracker.assignments or {}) do
        assignment = tracker.assignments[i]
        if assignment then
            oldAssignments[assignment.slotIndex] = assignment
            if assignment.botName then sourceByName[assignment.botName] = assignment.slotIndex end
        end
    end
    for i = 1, table.getn(tracker.players or {}) do
        player = tracker.players[i]
        if not player or not player.name or not player.slotIndex then return false end
        sourceByName[player.name] = player.slotIndex
        playerBySource[player.slotIndex] = player
    end

    -- Fresh explicit assumptions can repair identity even before a legacy
    -- tracker botName has caught up.
    for name, assignment in pairs(SCB.assumedRolesByName or {}) do
        if assignment and assignment.spawnKind ~= "bootstrap" and assignment.slotIndex then
            sourceByName[name] = assignment.slotIndex
        end
    end

    for i = 1, 8 do groupOrdinals[i] = 0 end
    for i = 1, raidCount do
        name = UnitName and UnitName("raid" .. i) or nil
        _, _, subgroup = GetRaidRosterInfo(i)
        if not name or not subgroup or subgroup < 1 or subgroup > groupCount then return false end

        groupOrdinals[subgroup] = groupOrdinals[subgroup] + 1
        if groupOrdinals[subgroup] > 5 then return false end
        targetSlot = ((subgroup - 1) * 5) + groupOrdinals[subgroup]
        sourceSlot = sourceByName[name]
        if not sourceSlot or seenSource[sourceSlot] or targetToSource[targetSlot] then return false end
        targetToSource[targetSlot] = sourceSlot
        seenSource[sourceSlot] = true
    end

    for i = 1, size do
        if not targetToSource[i] or not seenSource[i] or not oldAssignments[i] then return false end
        if targetToSource[i] ~= i then changed = true end
    end
    if not changed then return false end

    for targetSlot = 1, size do
        sourceSlot = targetToSource[targetSlot]
        assignment = oldAssignments[sourceSlot]
        newAssignments[targetSlot] = assignment
        assignment.slotIndex = targetSlot
        assignment.group = math.floor((targetSlot - 1) / 5) + 1

        if assignment.botName and SCB.assumedRolesByName[assignment.botName] then
            SCB.assumedRolesByName[assignment.botName].slotIndex = targetSlot
            SCB.assumedRolesByName[assignment.botName].group = assignment.group
        end

        player = playerBySource[sourceSlot]
        if player then
            player.slotIndex = targetSlot
            player.group = assignment.group
            table.insert(newPlayers, player)
        end
    end

    tracker.assignments = newAssignments
    tracker.players = newPlayers
    tracker.layoutRevision = (tracker.layoutRevision or 0) + 1
    tracker.layoutUpdatedAt = GetTime and GetTime() or 0

    -- If the active preset is what the editor currently shows, permute its row
    -- records by the same identity mapping and expose Blizzard's exact human
    -- rows. Selecting/reselecting a preset later still deliberately reloads its
    -- saved state, as before.
    if SCB_IsTrackerPresetSelected(tracker) then
        local oldEditorSlots = SCB_CopySlots(SCB.presetEditorSlots or {})
        local newEditorSlots = {}
        local roster = SCB_GetHumanRoster()
        local keyByName = {}
        local key, slot

        for i = 1, table.getn(roster) do
            if roster[i].name then keyByName[roster[i].name] = roster[i].key end
        end

        for targetSlot = 1, size do
            sourceSlot = targetToSource[targetSlot]
            if editorAligned and oldEditorSlots[sourceSlot] then
                -- Preserve unsaved editor changes when the editor was already
                -- following this exact active-layout revision.
                newEditorSlots[targetSlot] = SCB_CopySlot(oldEditorSlots[sourceSlot])
            elseif oldAssignments[sourceSlot] then
                -- A preset reload/selection may intentionally show saved data
                -- that no longer matches the active raid. On the next real raid
                -- move, rebuild from tracker identity instead of permuting that
                -- unrelated view.
                newEditorSlots[targetSlot] = {
                    class = oldAssignments[sourceSlot].class,
                    role = oldAssignments[sourceSlot].role,
                    extra = oldAssignments[sourceSlot].extra,
                }
            end
        end
        SCB.presetEditorSlots = newEditorSlots
        SCB.presetEditorPlayerSlots = SCB.presetEditorPlayerSlots or {}

        -- Clear exact rows for currently tracked humans, then write their new
        -- Blizzard positions.
        for i = 1, table.getn(tracker.players or {}) do
            player = tracker.players[i]
            key = keyByName[player.name] or player.name
            SCB.presetEditorPlayers[key] = player.group
            SCB.presetEditorPlayerSlots[key] = player.slotIndex
        end

        SCB.scbEditorLayoutTrackerRevision = tracker.layoutRevision
        SCB_MarkWorkingPresetDirty()
        if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() end
        if SCB_RefreshPresetRoleIndicators then SCB_RefreshPresetRoleIndicators() end
        SCB_BurstDebug("Live raid order changed working preset -> Unsaved")
    end

    -- Maintenance and pfUI must inherit the same reordered identity truth.
    if SCB_EstablishActiveRosterFromTracker then
        SCB_EstablishActiveRosterFromTracker(tracker)
    end
    if SCB_RefreshLiveRoster then SCB_RefreshLiveRoster() end
    if SCB_ApplyLivePfUITankRoles then SCB_ApplyLivePfUITankRoles() end
    if SCB_RefreshRefillButton then SCB_RefreshRefillButton() end
    return true
end

local SCB_072PreviousTryFinalizeRaidRoleTracking = SCB_TryFinalizeRaidRoleTracking
if SCB_072PreviousTryFinalizeRaidRoleTracking then
    function SCB_TryFinalizeRaidRoleTracking()
        local ready = SCB_072PreviousTryFinalizeRaidRoleTracking()
        if ready then SCB_SyncTrackerToRaidOrder() end
        return ready
    end
end

local SCB_072PreviousHandleRosterChange = SCB_HandleRosterChange
if SCB_072PreviousHandleRosterChange then
    function SCB_HandleRosterChange()
        local result = SCB_072PreviousHandleRosterChange()
        SCB_SyncTrackerToRaidOrder()
        return result
    end
end

-- Clear every 0.7.2 parallel scheduler state along with the canonical operation.
local SCB_072PreviousAbortBotSpawnOperations = SCB_AbortBotSpawnOperations
if SCB_072PreviousAbortBotSpawnOperations then
    function SCB_AbortBotSpawnOperations()
        SCB.scbPresetBurstPlans = {}
        SCB.scbExplicitPresetOperation = nil
        SCB.scbCheckPlanArmed = nil
        SCB.scbArmedPresetPlan = nil
        SCB.scbParkSurvivorBeforeArrange = nil
        SCB.scbRemoveSurvivorAfterG1 = nil
        SCB.scbSurvivorRemovalWaiting = nil
        SCB.scbSurvivorRemovalName = nil
        return SCB_072PreviousAbortBotSpawnOperations()
    end
end

local SCB_072PreviousResetSessionState = SCB_ResetSessionState
if SCB_072PreviousResetSessionState then
    function SCB_ResetSessionState()
        SCB.scbPresetBurstPlans = {}
        SCB.scbExplicitPresetOperation = nil
        SCB.scbCheckPlanArmed = nil
        SCB.scbArmedPresetPlan = nil
        SCB.scbParkSurvivorBeforeArrange = nil
        SCB.scbRemoveSurvivorAfterG1 = nil
        SCB.scbSurvivorRemovalWaiting = nil
        SCB.scbSurvivorRemovalName = nil
        return SCB_072PreviousResetSessionState()
    end
end
