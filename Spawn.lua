-- SoloCraft Bots - authoritative summon runtime.
--
-- 0.7.3 moves preset summon scheduling fully onto the explicit raid system.
-- RoleTracking may still provide role/name state and compatibility helpers, but
-- it no longer owns the active preset summon lifecycle. All outbound spawn
-- commands pass through one validated sender so internal scheduler markers can
-- never reach SoloCraft's .partybot parser.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local SCB_CONVERT_NOW = "__SCB_CONVERT_NOW__"
local SCB_WAIT_RAID = "__SCB_WAIT_RAID__"
local SCB_WAIT_BOOTSTRAP = "__SCB_WAIT_BOOTSTRAP__"
local SCB_WAIT_REAL_RAID_START = SCB.PRESET_WAIT_REAL_RAID_START or "__SCB_WAIT_REAL_RAID_START__"

SCB.PRESET_WAIT_REAL_RAID_START = SCB_WAIT_REAL_RAID_START

local function SCB_IsSpawnCommandString(value)
    return type(value) == "string" and string.find(value, "^add%s+") ~= nil
end

local function SCB_ParseSpawnCommand(command)
    local _, _, classKey, role, extra
    if type(command) ~= "string" then return nil end
    _, _, classKey, role, extra = string.find(command, "^add%s+(%S+)%s+(%S+)%s*(.*)$")
    if not classKey or not role then return nil end
    if extra == "" then extra = nil end
    return classKey, role, extra
end

local function SCB_IsValidatedSpawnCommand(command)
    local classKey, role, extra = SCB_ParseSpawnCommand(command)
    if not classKey or not role then return false end
    if not SCB_IsValidSpawnAssignment then return false end
    return SCB_IsValidSpawnAssignment(classKey, role, extra)
end

local function SCB_SpawnDebug(text)
    if SCB_DebugLog then SCB_DebugLog("Spawn", text) end
end

-- One hard outbound gate for manual, preset and maintenance spawns.
-- Scheduler markers and malformed PartyBot payloads stop here instead of being
-- echoed by SoloCraft's command parser into the player's chat window.
function SCB_SendSpawnCommand(command)
    if not SCB_IsValidatedSpawnCommand(command) then
        SCB_SpawnDebug("Blocked invalid spawn payload: " .. tostring(command))
        return false
    end
    if SCB_RegisterSpawnIntent then SCB_RegisterSpawnIntent() end
    SendChatMessage(".partybot " .. command, "SAY")
    return true
end

local function SCB_GetSpawnLabels(classKey, role, extra)
    local classInfo = SCB_FindClass and SCB_FindClass(classKey) or nil
    local roleInfo = SCB_FindRoleEntry and SCB_FindRoleEntry(classInfo, role, extra) or nil
    local classLabel = classInfo and classInfo.name or tostring(classKey or "Bot")
    local roleLabel = roleInfo and roleInfo.label or tostring(role or "")
    return classLabel, roleLabel
end

function SCB_SpawnOnClick()
    local extra, command, classLabel, roleLabel
    if not this.scbClass or not this.scbRole then return end

    extra = this.scbExtra
    if this.scbClass == "paladin" then
        extra = SCB.mainPaladinBlessing or "BoK"
    end

    command = SCB_BuildSpawnCommand(this.scbClass, this.scbRole, extra)
    if not SCB_IsValidatedSpawnCommand(command) then
        SCB_SpawnDebug("Manual summon rejected before send: " .. tostring(command))
        return
    end

    if SCB_AllowActiveRosterAdoption then SCB_AllowActiveRosterAdoption() end
    if SCB_SendSpawnCommand(command) then
        classLabel, roleLabel = SCB_GetSpawnLabels(this.scbClass, this.scbRole, extra)
        SCB_Print("Summoning a " .. classLabel .. " " .. roleLabel .. ".")
    end
end

local function SCB_CopyBurstAssignment(entry)
    if not entry then return nil end
    return {
        slotIndex = entry.slotIndex,
        group = entry.group,
        command = entry.command,
        class = entry.class,
        role = entry.role,
        extra = entry.extra,
    }
end

local function SCB_GetActiveTrackerAssignmentsByGroup(tracker)
    local groups = {}
    local i, assignment
    for i = 1, 8 do groups[i] = {} end
    for i = 1, table.getn(tracker and tracker.assignments or {}) do
        assignment = tracker.assignments[i]
        if assignment and assignment.initialActive and assignment.group then
            table.insert(groups[assignment.group], assignment)
        end
    end
    return groups
end

local function SCB_QueuePlannedBurst(queue, plans, kind, groupIndex, assignments)
    local plan, i
    if not assignments or table.getn(assignments) == 0 then return false end

    plan = { kind = kind or "preset", group = groupIndex, assignments = {} }
    for i = 1, table.getn(assignments) do
        table.insert(plan.assignments, SCB_CopyBurstAssignment(assignments[i]))
    end

    table.insert(queue, SCB.PRESET_CHECK_COMBAT)
    for i = table.getn(assignments), 1, -1 do
        table.insert(queue, assignments[i].command)
    end
    table.insert(plans, plan)
    return true
end

local function SCB_QueueBootstrapBurst(queue, plans)
    local command = SCB_BuildSpawnCommand("warrior", "tank", nil)
    local plan = {
        kind = "bootstrap",
        group = nil,
        assignments = {
            {
                command = command,
                class = "warrior",
                role = "tank",
                extra = nil,
            },
        },
    }
    table.insert(queue, SCB.PRESET_CHECK_COMBAT)
    table.insert(queue, command)
    table.insert(queue, SCB_WAIT_BOOTSTRAP)
    table.insert(plans, plan)
end

local function SCB_HasLaterAssignments(groups, currentGroup, maxGroup)
    local g
    for g = currentGroup + 1, maxGroup do
        if table.getn(groups[g] or {}) > 0 then return true end
    end
    return false
end

local function SCB_ResetSpawnRuntimeState()
    SCB.scbExplicitPresetOperation = nil
    SCB.scbPresetBurstPlans = {}
    SCB.scbCheckPlanArmed = nil
    SCB.scbArmedPresetPlan = nil
    SCB.scbParkSurvivorBeforeArrange = nil
    SCB.scbRemoveSurvivorAfterG1 = nil
    SCB.scbSurvivorRemovalWaiting = nil
    SCB.scbSurvivorRemovalName = nil
    SCB.scbPartySurvivorGoneAt = nil
end

local SCB_073PreviousAbortBotSpawnOperations = SCB_AbortBotSpawnOperations
if SCB_073PreviousAbortBotSpawnOperations then
    function SCB_AbortBotSpawnOperations()
        -- Preserve the old late RaidIdentity cleanup ordering while making Spawn
        -- the owner: clear scheduler state before the inherited abort chain and
        -- again afterward in case an older layer mutates it while unwinding.
        SCB_ResetSpawnRuntimeState()
        local result = SCB_073PreviousAbortBotSpawnOperations()
        SCB_ResetSpawnRuntimeState()
        if SCB_ClearPendingAssumedSpawns then SCB_ClearPendingAssumedSpawns() end
        return result
    end
end

-- Session reset used to receive the same scheduler cleanup from late-loaded
-- RaidIdentity. Keep that behaviour here so RaidIdentity no longer needs to
-- load after Spawn merely to intercept this function.
local SCB_0816PreviousResetSessionState = SCB_ResetSessionState
if SCB_0816PreviousResetSessionState then
    function SCB_ResetSessionState()
        SCB_ResetSpawnRuntimeState()
        return SCB_0816PreviousResetSessionState()
    end
end

-- Build the complete summon queue and identity plans together. No queue rewrite
-- or timestamp inference follows this point: the scheduler knows which logical
-- slot every requested bot belongs to before any command is sent.
function SCB_StartPresetSummonSnapshot(snapshot)
    local valid, errorText = SCB_ValidatePresetExecutionSnapshot(snapshot, true)
    local group, size, slots, occupied, tracker, groups
    local queue, plans, groupCount, startBotState, survivorName
    local raidCount, partyCount, needsT3Bootstrap, g, i, player
    local firstAssignment, heldAssignment, expectedBotCount, hasLater
    local kickAllAnchorName

    if not valid then return false, errorText end
    if table.getn(SCB.presetSpawnQueue or {}) > 0
        or (SCB.presetGroupWaitRemaining or 0) > 0
        or (SCB.presetCombatRetryWaitRemaining or 0) > 0 then
        return false, SCB_L("ERR_SUMMON_BUSY")
    end

    startBotState, survivorName = SCB_GetPresetStartBotState()
    if startBotState == "blocked" then
        return false, SCB_L("ERR_SUMMON_GROUP_NOT_EMPTY")
    end

    size = snapshot.size
    group = { id = snapshot.groupID, name = snapshot.groupName, size = size }
    slots = SCB_CopySlots(snapshot.slots)
    occupied = SCB_GetSnapshotOccupiedSlots(snapshot)
    groupCount = math.ceil(size / 5)
    queue, plans = {}, {}

    SCB.presetSpawnQueue = {}
    SCB.presetSpawnElapsed = 0
    SCB.presetGroupWaitRemaining = 0
    SCB.presetCombatRetryWaitRemaining = 0
    SCB.presetCombatPollRemaining = nil
    SCB.presetCombatRetryFailures = 0
    SCB.presetCombatRetryResetPending = nil
    SCB.presetLastBurstCommands = nil
    SCB.presetLastBurstRequeued = nil
    SCB.presetExpectedBotCountBeforeHandoff = nil
    SCB.presetSurvivorProbeRemaining = nil
    SCB.presetBootstrapBotName = nil
    SCB.presetSurvivorBotName = survivorName
    SCB_ResetSpawnRuntimeState()
    if SCB_ClearPendingAssumedSpawns then SCB_ClearPendingAssumedSpawns() end

    tracker = SCB_CreateRaidRoleTracker(slots, size, occupied, group, snapshot)
    if not tracker then return false, SCB_L("ERR_SUMMON_BUSY") end
    groups = SCB_GetActiveTrackerAssignmentsByGroup(tracker)

    if tracker.presetGroupIndex and tracker.presetIndex
        and SoloCraftBotsDB.currentPresetGroup == tracker.presetGroupIndex
        and SCB_CurrentPresetGroup()
        and SCB_CurrentPresetGroup().currentPreset == tracker.presetIndex then
        SCB.scbEditorLayoutTrackerRevision = tracker.layoutRevision or 0
    end

    expectedBotCount = 0
    for g = 1, groupCount do expectedBotCount = expectedBotCount + table.getn(groups[g] or {}) end

    raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    partyCount = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    needsT3Bootstrap = size > 5 and startBotState == "empty"
        and raidCount == 0 and partyCount == 0
        and SCB_IsT3RaidLocation and SCB_IsT3RaidLocation()

    if size > 5 then
        SCB.presetHumanGroups = {}
        for i = 1, table.getn(snapshot.players or {}) do
            player = snapshot.players[i]
            if player.group and player.group >= 1 and player.group <= groupCount then
                SCB.presetHumanGroups[player.name] = player.group
            end
        end

        if startBotState == "survivor" then
            if table.getn(groups[1] or {}) == 0 then
                return false, SCB_L("ERR_SURVIVOR_NO_SLOT")
            end
            if raidCount == 0 then table.insert(queue, SCB_CONVERT_NOW) end
            SCB.scbParkSurvivorBeforeArrange = true
            SCB.scbRemoveSurvivorAfterG1 = true
        elseif raidCount > 0 then
            -- Existing raid: arrange humans, then send normal explicit bursts.
        elseif partyCount > 0 then
            table.insert(queue, SCB_CONVERT_NOW)
        elseif needsT3Bootstrap then
            SCB_QueueBootstrapBurst(queue, plans)
            SCB.scbParkSurvivorBeforeArrange = true
            SCB.scbRemoveSurvivorAfterG1 = true
        else
            -- Ordinary dungeon/raid conversion: the first REAL G1 bot creates
            -- the party. Its exact slot identity is known before the send.
            firstAssignment = groups[1] and groups[1][1] or nil
            if not firstAssignment then
                return false, SCB_L("ERR_SURVIVOR_NO_SLOT")
            end
            SCB_QueuePlannedBurst(queue, plans, "preset", 1, { firstAssignment })
            table.remove(groups[1], 1)
            table.insert(queue, SCB_WAIT_REAL_RAID_START)
        end

        table.insert(queue, SCB.PRESET_ARRANGE_PLAYERS)
    else
        SCB.presetHumanGroups = nil

        -- Five-player groups have no spare subgroup to park the safety anchor.
        -- Preserve it until the other desired bots are present, then replace it
        -- after a roster-only settle delay. No hidden targeting probe is used.
        if startBotState == "survivor" then
            if table.getn(groups[1] or {}) == 0 then
                return false, SCB_L("ERR_SURVIVOR_NO_SLOT")
            end
            kickAllAnchorName = SCB_GetKickAllAnchorForFreshBuild and SCB_GetKickAllAnchorForFreshBuild() or nil
            if kickAllAnchorName and kickAllAnchorName == survivorName then
                heldAssignment = groups[1][table.getn(groups[1])]
                table.remove(groups[1], table.getn(groups[1]))
            else
                heldAssignment = groups[1][1]
                table.remove(groups[1], 1)
            end
            SCB.presetExpectedBotCountBeforeHandoff = expectedBotCount
        end
    end

    for g = 1, groupCount do
        if table.getn(groups[g] or {}) > 0 then
            SCB_QueuePlannedBurst(queue, plans, "preset", g, groups[g])
            hasLater = SCB_HasLaterAssignments(groups, g, groupCount)
            if hasLater then table.insert(queue, SCB.PRESET_WAIT_GROUP) end
        end
    end

    if heldAssignment then
        table.insert(queue, SCB.PRESET_WAIT_FINAL_ROSTER)
        table.insert(queue, SCB.PRESET_REMOVE_SURVIVOR)
        table.insert(queue, SCB.PRESET_WAIT_SURVIVOR_GONE)
        SCB_QueuePlannedBurst(queue, plans, "preset", heldAssignment.group or 1, { heldAssignment })
    end

    table.insert(queue, SCB.PRESET_TRACK_ROSTER)

    SCB.presetSpawnQueue = queue
    SCB.scbPresetBurstPlans = plans
    SCB.scbExplicitPresetOperation = true
    SCB.scbCheckPlanArmed = nil
    SCB.scbArmedPresetPlan = nil
    if SCB_RefreshRefillButton then SCB_RefreshRefillButton() end
    return true
end

local function SCB_PresetBotCount(snapshot)
    local humans = table.getn(snapshot and snapshot.players or {})
    local count = (snapshot and snapshot.size or 0) - humans
    if count < 0 then count = 0 end
    return count
end

function SCB_PresetSummonOnClick()
    local snapshot, errorText, ok, botCount, suffix

    if IsControlKeyDown and IsControlKeyDown() and SCB_HasBotSpawnOperation() then
        SCB_AbortBotSpawnOperations()
    end

    snapshot, errorText = SCB_BuildPresetExecutionSnapshot()
    if not snapshot then
        SCB_Print(errorText)
        return
    end

    SCB.presetEditorSlots = SCB_CopySlots(snapshot.slots)
    SCB_RefreshPresetPlayers()

    ok, errorText = SCB_StartPresetRebuild(snapshot)
    if not ok then
        if errorText then SCB_Print(errorText) end
        return
    end

    botCount = SCB_PresetBotCount(snapshot)
    suffix = botCount == 1 and " bot" or " bots"
    SCB_Print("Summoning Preset " .. tostring(snapshot.presetName or "Preset")
        .. " with " .. tostring(botCount) .. suffix .. ".")
end

local function SCB_ShouldRemoveParkedSurvivor(head)
    local plan
    if not SCB.scbRemoveSurvivorAfterG1 then return false end
    if head == SCB.PRESET_TRACK_ROSTER then return true end
    if head ~= SCB.PRESET_CHECK_COMBAT then return false end
    plan = SCB.scbPresetBurstPlans and SCB.scbPresetBurstPlans[1] or nil
    return plan and plan.kind == "preset" and plan.group and plan.group > 1
end

local function SCB_AbortInvalidSchedulerItem(item)
    SCB_SpawnDebug("Aborting on invalid scheduler item: " .. tostring(item))
    if SCB_AbortBotSpawnOperations then SCB_AbortBotSpawnOperations() end
    SCB_Print("Summon aborted because the internal summon queue was invalid.")
end

-- Authoritative preset scheduler. It deliberately does not call the previous
-- RoleTracking/Presets/RaidRefill scheduler wrapper chain.
function SCB_PresetSpawnQueueOnUpdate()
    local elapsed = arg1 or 0
    local queue = SCB.presetSpawnQueue or {}
    local head, plan, retry, bootstrapName
    local now, settleDelay

    if SCB_PresetRebuildOnUpdate then SCB_PresetRebuildOnUpdate() end
    if SCB_MaintenanceReplaceOnUpdate then SCB_MaintenanceReplaceOnUpdate() end
    if SCB_RefillOnUpdate then SCB_RefillOnUpdate(elapsed) end

    if not SCB.scbExplicitPresetOperation then return end

    if SCB.presetGroupWaitRemaining and SCB.presetGroupWaitRemaining > 0 then
        SCB.presetGroupWaitRemaining = SCB.presetGroupWaitRemaining - elapsed
        if SCB.presetGroupWaitRemaining > 0 then return end
        SCB.presetGroupWaitRemaining = 0
        if SCB.presetCombatRetryResetPending then
            SCB.presetCombatRetryFailures = 0
            SCB.presetCombatRetryResetPending = nil
        end
        return
    end

    if SCB.presetCombatRetryWaitRemaining and SCB.presetCombatRetryWaitRemaining > 0 then
        SCB.presetCombatRetryWaitRemaining = SCB.presetCombatRetryWaitRemaining - elapsed
        if SCB.presetCombatRetryWaitRemaining > 0 then return end
        SCB.presetCombatRetryWaitRemaining = 0
        return
    end

    while table.getn(queue) > 0 do
        head = queue[1]

        if SCB_ShouldRemoveParkedSurvivor(head) and not SCB.presetLastBurstRequeued then
            if not SCB.scb072TryRemoveParkedSurvivor
                or not SCB.scb072TryRemoveParkedSurvivor() then
                return
            end
            head = queue[1]
        end

        if head == SCB.PRESET_WAIT_GROUP then
            table.remove(queue, 1)
            SCB.presetGroupWaitRemaining = 1.0
            if (SCB.presetCombatRetryFailures or 0) > 0 then
                SCB.presetCombatRetryResetPending = true
            end
            SCB.presetSpawnElapsed = 0
            return

        elseif head == SCB.PRESET_ARRANGE_PLAYERS then
            if SCB.scbParkSurvivorBeforeArrange then
                if not SCB.scb072TryParkSurvivorInGroupEight
                    or not SCB.scb072TryParkSurvivorInGroupEight() then
                    return
                end
                SCB.scbParkSurvivorBeforeArrange = nil
            end
            if SCB_ArrangePresetPlayers and SCB_ArrangePresetPlayers() then
                table.remove(queue, 1)
                SCB.presetSpawnElapsed = 0
            else
                return
            end

        elseif head == SCB.PRESET_TRACK_ROSTER then
            if SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker then
                SoloCraftBotsCharDB.raidRoleTracker.allowFinalize = true
            end
            if SCB_TryFinalizeRaidRoleTracking and SCB_TryFinalizeRaidRoleTracking() then
                SCB.presetCombatRetryFailures = 0
                SCB.presetCombatRetryResetPending = nil
                table.remove(queue, 1)
                SCB.presetSpawnElapsed = 0
            else
                return
            end

        elseif head == SCB.PRESET_CHECK_COMBAT then
            SCB.presetCombatPollRemaining = (SCB.presetCombatPollRemaining or 0) - elapsed
            if SCB.presetCombatPollRemaining > 0 then return end
            if SCB_PresetGroupHasCombat and SCB_PresetGroupHasCombat() then
                SCB.presetCombatPollRemaining = 0.50
                return
            end
            SCB.presetCombatPollRemaining = nil

            retry = SCB.presetLastBurstRequeued == true
            if not retry then
                plan = table.remove(SCB.scbPresetBurstPlans, 1)
                if not plan or not SCB_BeginAssumedSpawnBurst
                    or not SCB_BeginAssumedSpawnBurst(plan) then
                    SCB_AbortInvalidSchedulerItem("missing explicit burst plan")
                    return
                end
                SCB.scbArmedPresetPlan = plan
            else
                SCB.scbArmedPresetPlan = nil
            end

            SCB.presetLastBurstCommands = {}
            SCB.presetLastBurstRequeued = nil
            table.remove(queue, 1)
            SCB.presetSpawnElapsed = 0

        elseif head == SCB_CONVERT_NOW then
            if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                table.remove(queue, 1)
            elseif GetNumPartyMembers and GetNumPartyMembers() > 0 and ConvertToRaid then
                ConvertToRaid()
                queue[1] = SCB_WAIT_RAID
                return
            else
                return
            end

        elseif head == SCB_WAIT_BOOTSTRAP then
            bootstrapName = SCB_FindFirstGroupBotName and SCB_FindFirstGroupBotName() or nil
            if not bootstrapName then return end

            SCB.presetCombatRetryFailures = 0
            SCB.presetCombatRetryResetPending = nil
            SCB.presetBootstrapBotName = bootstrapName
            SCB.presetSurvivorBotName = bootstrapName
            if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                queue[1] = SCB_WAIT_RAID
            elseif ConvertToRaid then
                ConvertToRaid()
                queue[1] = SCB_WAIT_RAID
            else
                return
            end
            return

        elseif head == SCB_WAIT_REAL_RAID_START then
            if not SCB_FindFirstGroupBotName or not SCB_FindFirstGroupBotName() then return end

            if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                table.remove(queue, 1)
            elseif GetNumPartyMembers and GetNumPartyMembers() > 0 and ConvertToRaid then
                ConvertToRaid()
                queue[1] = SCB_WAIT_RAID
                return
            else
                return
            end

        elseif head == SCB_WAIT_RAID then
            if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                table.remove(queue, 1)
            else
                return
            end

        elseif head == SCB.PRESET_WAIT_FINAL_ROSTER then
            if SCB_CountGroupBots and SCB_CountGroupBots() >= (SCB.presetExpectedBotCountBeforeHandoff or 0) then
                table.remove(queue, 1)
            else
                return
            end

        elseif head == SCB.PRESET_REMOVE_SURVIVOR then
            if SCB.presetSurvivorBotName and UninviteByName then
                UninviteByName(SCB.presetSurvivorBotName)
            end
            SCB.scbPartySurvivorGoneAt = nil
            table.remove(queue, 1)
            return

        elseif head == SCB.PRESET_WAIT_SURVIVOR_GONE then
            if SCB.presetSurvivorBotName and SCB_GroupHasName
                and SCB_GroupHasName(SCB.presetSurvivorBotName) then
                SCB.scbPartySurvivorGoneAt = nil
                return
            end

            now = GetTime and GetTime() or 0
            if not SCB.scbPartySurvivorGoneAt then
                SCB.scbPartySurvivorGoneAt = now
                return
            end
            settleDelay = SCB.REPLACE_REMOVAL_SETTLE_DELAY or 3.0
            if GetTime and (now - SCB.scbPartySurvivorGoneAt) < settleDelay then return end

            if SCB_ClearKickAllAnchor then SCB_ClearKickAllAnchor(SCB.presetSurvivorBotName) end
            SCB.presetSurvivorBotName = nil
            SCB.presetExpectedBotCountBeforeHandoff = nil
            SCB.scbPartySurvivorGoneAt = nil
            table.remove(queue, 1)

        elseif SCB_IsSpawnCommandString(head) then
            if not SCB_SendSpawnCommand(head) then
                SCB_AbortInvalidSchedulerItem(head)
                return
            end
            SCB.presetLastBurstCommands = SCB.presetLastBurstCommands or {}
            table.insert(SCB.presetLastBurstCommands, head)
            table.remove(queue, 1)
            -- A plan is considered released only after at least one validated
            -- command actually left the client, never when CHECK_COMBAT merely
            -- armed it.
            if SCB.scbArmedPresetPlan then
                SCB.scbArmedPresetPlan.released = true
            end

        elseif type(head) == "string" and string.find(head, "^__SCB_") then
            SCB_AbortInvalidSchedulerItem(head)
            return

        else
            SCB_AbortInvalidSchedulerItem(head)
            return
        end
    end

    if table.getn(queue) == 0
        and (SCB.presetGroupWaitRemaining or 0) <= 0
        and (SCB.presetCombatRetryWaitRemaining or 0) <= 0 then
        SCB_ResetSpawnRuntimeState()
    end
end
