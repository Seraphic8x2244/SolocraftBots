-- SoloCraft Bots - transitional bootstrap removal-overlap gate.
--
-- 0.8.23 refines the shared removal-settle rule for the temporary raid
-- bootstrap only. The bootstrap is extra capacity, so unrelated preset bursts
-- may continue while its roster disappearance + 3-second accounting window
-- resolves. The final preset bot burst (or final roster tracking) still waits
-- until that window is complete.
--
-- This file is intentionally one-gate transitional code loaded immediately
-- after Spawn.lua. Once runtime-proven, absorb it into Spawn's coordinator
-- before further scheduler-file retirement.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local function SCB_0823BootstrapSafety()
    local safety = SCB_GetBotOperationSafety and SCB_GetBotOperationSafety(false) or nil
    if not safety or not safety.bootstrapName or not safety.removeAfterGroupOne then
        return nil
    end
    return safety
end

local function SCB_0823HasRealGroupOneBot(bootstrapName)
    local i, name, _, subgroup, assumption
    if not bootstrapName or not GetNumRaidMembers or not GetRaidRosterInfo then return false end

    for i = 1, GetNumRaidMembers() do
        name = UnitName and UnitName("raid" .. i) or nil
        _, _, subgroup = GetRaidRosterInfo(i)
        if name and subgroup == 1 and name ~= bootstrapName
            and SCB_IsBotName and SCB_IsBotName(name) then
            assumption = SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil
            if not assumption or assumption.spawnKind ~= "bootstrap" then
                return true
            end
        end
    end
    return false
end

local function SCB_0823FinishBootstrapRemoval(safety, name)
    if SCB_ClearKickAllAnchor then SCB_ClearKickAllAnchor(name) end
    safety.survivorName = nil
    safety.bootstrapName = nil
    safety.removeAfterGroupOne = nil
    safety.removalWaiting = nil
    safety.removalName = nil
    safety.removalGoneAt = nil
    if SCB_DebugLog then
        SCB_DebugLog("Spawn", "Bootstrap " .. tostring(name) .. " removal settle completed in parallel with preset bursts")
    end
end

local function SCB_0823PollBootstrapRemoval()
    local safety = SCB_0823BootstrapSafety()
    local name, now, settleDelay

    if not safety then return true end
    name = safety.removalName or safety.bootstrapName
    if not name then
        safety.removeAfterGroupOne = nil
        return true
    end

    if safety.removalWaiting then
        if SCB_GroupHasName and SCB_GroupHasName(name) then
            safety.removalGoneAt = nil
            return false
        end

        now = GetTime and GetTime() or 0
        if not safety.removalGoneAt then
            safety.removalGoneAt = now
            return false
        end

        settleDelay = SCB.REPLACE_REMOVAL_SETTLE_DELAY or 3.0
        if not GetTime or (now - safety.removalGoneAt) >= settleDelay then
            SCB_0823FinishBootstrapRemoval(safety, name)
            return true
        end
        return false
    end

    if not SCB_0823HasRealGroupOneBot(name) then return false end
    if SCB_PresetGroupHasCombat and SCB_PresetGroupHasCombat() then return false end

    if UninviteByName then
        UninviteByName(name)
        safety.removalWaiting = true
        safety.removalName = name
        safety.removalGoneAt = nil
        if SCB_DebugLog then
            SCB_DebugLog("Spawn", "Bootstrap " .. tostring(name) .. " removal requested; unrelated preset bursts may continue")
        end
    end
    return false
end

local function SCB_0823CurrentBurstNeedsFreedCapacity()
    local plans = SCB.scbPresetBurstPlans or {}
    local current = plans[1]
    local i, plan

    if not current or current.kind ~= "preset" then return false end
    for i = 2, table.getn(plans) do
        plan = plans[i]
        if plan and plan.kind == "preset" then return false end
    end
    return true
end

-- Spawn's proven scheduler asks the RaidBurst helper whether it may advance
-- after G1. For ordinary survivors retain the old strict next-add barrier. For
-- the temporary bootstrap, keep polling removal in the coordinator state but
-- only block the final capacity-filling bot burst (or final roster tracking).
local SCB_0823PreviousTryRemoveParkedSurvivor = SCB.scb072TryRemoveParkedSurvivor
if SCB_0823PreviousTryRemoveParkedSurvivor then
    SCB.scb072TryRemoveParkedSurvivor = function()
        local safety = SCB_0823BootstrapSafety()
        local queue, head

        if not safety then
            return SCB_0823PreviousTryRemoveParkedSurvivor()
        end

        SCB_0823PollBootstrapRemoval()
        safety = SCB_0823BootstrapSafety()
        if not safety then return true end

        queue = SCB.presetSpawnQueue or {}
        head = queue[1]

        if head == SCB.PRESET_TRACK_ROSTER then
            return false
        end

        if head == SCB.PRESET_CHECK_COMBAT
            and not SCB.presetLastBurstRequeued
            and SCB_0823CurrentBurstNeedsFreedCapacity() then
            return false
        end

        return true
    end
end

-- Poll before the authoritative Spawn scheduler each frame. This lets roster
-- disappearance and the settle clock advance during ordinary one-second group
-- waits instead of only being observed when the next burst reaches a gate.
local SCB_0823PreviousPresetSpawnQueueOnUpdate = SCB_PresetSpawnQueueOnUpdate
if SCB_0823PreviousPresetSpawnQueueOnUpdate then
    function SCB_PresetSpawnQueueOnUpdate()
        SCB_0823PollBootstrapRemoval()
        return SCB_0823PreviousPresetSpawnQueueOnUpdate()
    end
end
