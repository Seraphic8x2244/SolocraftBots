-- SoloCraft Bots - observe Blizzard raid layout without rewriting logical preset identity.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local function SCB_BurstDebug(text)
    if SCB_DebugLog then SCB_DebugLog("Burst", text) end
end

local function SCB_BuildLiveRaidPositions()
    local result, groupRows = {}, {}
    local raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local i, name, _, subgroup
    for i = 1, 8 do groupRows[i] = 0 end
    for i = 1, raidCount do
        name = UnitName and UnitName("raid" .. i) or nil
        _, _, subgroup = GetRaidRosterInfo(i)
        if name and subgroup and subgroup >= 1 and subgroup <= 8 then
            groupRows[subgroup] = groupRows[subgroup] + 1
            result[name] = {
                raidIndex = i,
                group = subgroup,
                groupRow = groupRows[subgroup],
            }
        end
    end
    return result
end

-- Logical slot/group remain preset intent. These current* fields are observation
-- only and may change whenever Blizzard reorders the raid.
local function SCB_RefreshTrackerLiveLayout()
    local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil
    local positions, changed = SCB_BuildLiveRaidPositions(), false
    local i, player, assignment, name, live, assumption
    if not tracker or not tracker.ready or tracker.mode ~= "raid" then return false end

    for i = 1, table.getn(tracker.players or {}) do
        player = tracker.players[i]
        live = player and player.name and positions[player.name] or nil
        if live then
            if player.currentGroup ~= live.group or player.currentGroupRow ~= live.groupRow
                or player.currentRaidIndex ~= live.raidIndex then changed = true end
            player.currentGroup = live.group
            player.currentGroupRow = live.groupRow
            player.currentRaidIndex = live.raidIndex
        end
    end

    for i = 1, table.getn(tracker.assignments or {}) do
        assignment = tracker.assignments[i]
        name = assignment and (assignment.botName or assignment.scbAssumedName) or nil
        live = name and positions[name] or nil
        if live then
            if assignment.currentGroup ~= live.group or assignment.currentGroupRow ~= live.groupRow
                or assignment.currentRaidIndex ~= live.raidIndex then changed = true end
            assignment.currentGroup = live.group
            assignment.currentGroupRow = live.groupRow
            assignment.currentRaidIndex = live.raidIndex
            assumption = SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil
            if assumption then
                assumption.currentGroup = live.group
                assumption.currentGroupRow = live.groupRow
                assumption.currentRaidIndex = live.raidIndex
            end
        end
    end

    if changed then
        tracker.layoutRevision = (tracker.layoutRevision or 0) + 1
        tracker.layoutUpdatedAt = GetTime and GetTime() or 0
        SCB_BurstDebug("Observed Blizzard raid layout revision " .. tostring(tracker.layoutRevision))
    end
    return changed
end

local SCB_PreviousTryFinalizeRaidRoleTracking_Layout = SCB_TryFinalizeRaidRoleTracking
if SCB_PreviousTryFinalizeRaidRoleTracking_Layout then
    function SCB_TryFinalizeRaidRoleTracking()
        local ready = SCB_PreviousTryFinalizeRaidRoleTracking_Layout()
        if ready then SCB_RefreshTrackerLiveLayout() end
        return ready
    end
end

local SCB_PreviousHandleRosterChange_Layout = SCB_HandleRosterChange
if SCB_PreviousHandleRosterChange_Layout then
    function SCB_HandleRosterChange()
        local result = SCB_PreviousHandleRosterChange_Layout()
        SCB_RefreshTrackerLiveLayout()
        return result
    end
end

-- Temporary scheduler-state cleanup remains here until Spawn consolidation.
local SCB_PreviousAbortBotSpawnOperations_Layout = SCB_AbortBotSpawnOperations
if SCB_PreviousAbortBotSpawnOperations_Layout then
    function SCB_AbortBotSpawnOperations()
        SCB.scbPresetBurstPlans = {}
        SCB.scbExplicitPresetOperation = nil
        SCB.scbCheckPlanArmed = nil
        SCB.scbArmedPresetPlan = nil
        SCB.scbParkSurvivorBeforeArrange = nil
        SCB.scbRemoveSurvivorAfterG1 = nil
        SCB.scbSurvivorRemovalWaiting = nil
        SCB.scbSurvivorRemovalName = nil
        return SCB_PreviousAbortBotSpawnOperations_Layout()
    end
end

local SCB_PreviousResetSessionState_Layout = SCB_ResetSessionState
if SCB_PreviousResetSessionState_Layout then
    function SCB_ResetSessionState()
        SCB.scbPresetBurstPlans = {}
        SCB.scbExplicitPresetOperation = nil
        SCB.scbCheckPlanArmed = nil
        SCB.scbArmedPresetPlan = nil
        SCB.scbParkSurvivorBeforeArrange = nil
        SCB.scbRemoveSurvivorAfterG1 = nil
        SCB.scbSurvivorRemovalWaiting = nil
        SCB.scbSurvivorRemovalName = nil
        return SCB_PreviousResetSessionState_Layout()
    end
end
