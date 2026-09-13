-- SoloCraft Bots - transitional bootstrap continuity gate.
--
-- 0.8.23 refines the shared removal-settle rule for the temporary raid
-- bootstrap only. The bootstrap is extra capacity, so unrelated preset bursts
-- may continue while its roster disappearance + 3-second accounting window
-- resolves. The final preset bot burst (or final roster tracking) still waits
-- until that window is complete.
--
-- 0.8.24 extends the same bootstrap concept to retained preset-rebuild anchors.
-- When continuity needs one and no other human already preserves the group,
-- reuse an existing bot instead of destroying the group and manufacturing a
-- fresh temporary member. Five-player targets keep the existing strict party
-- handoff; raid-sized targets use the 0.8.23 overlapping bootstrap removal.
--
-- This remains a one-gate transitional layer. It now loads after Commands.lua
-- so it can extend the existing safe Kick All policy without duplicating that
-- implementation. Once runtime-proven, absorb it into the final Spawn/Commands
-- owners before retiring more scheduler scaffolding.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local function SCB_0824ActivePresetRebuildSnapshot()
    local operation = SCB_GetActiveBotOperation and SCB_GetActiveBotOperation() or nil
    local intent = operation and operation.desiredIntent or nil
    local snapshot = intent and intent.snapshot or nil

    if not operation or operation.kind ~= "preset" or not operation.rebuild or not snapshot then
        return nil
    end
    return snapshot
end

local function SCB_0824PresetNeedsRetainedBootstrap()
    local snapshot = SCB_0824ActivePresetRebuildSnapshot()
    local size, context, raidCount

    if not snapshot then return false, nil end
    size = tonumber(snapshot.size) or 0

    -- Raid-sized rebuilds can reuse one existing bot as the temporary raid
    -- bootstrap instead of dropping to an empty bot roster first. Commands.lua
    -- still suppresses this when another human is present, because humans then
    -- preserve the group topology themselves.
    if size > 5 then return true, "raid" end

    -- Five-player continuity matters inside instances, but must remain party
    -- topology. Do not introduce a new raid conversion merely because the
    -- generic bootstrap role is active. Existing 5-man handoff code already
    -- reserves exactly one final logical bot assignment dynamically.
    context = SCB_GetLocationContext and SCB_GetLocationContext() or nil
    raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if size > 0 and size <= 5 and context and context.inInstance and raidCount == 0 then
        return true, "party"
    end

    return false, nil
end

-- Commands owns the physical Kick All implementation. Extend only its safety
-- decision while a preset rebuild is active; manual Kick All and non-preset
-- removals retain the original policy.
local SCB_0824PreviousSurvivorSafetyRequired = SCB_SurvivorSafetyRequired
if SCB_0824PreviousSurvivorSafetyRequired then
    function SCB_SurvivorSafetyRequired()
        local retain = SCB_0824PresetNeedsRetainedBootstrap()
        if retain then return true end
        return SCB_0824PreviousSurvivorSafetyRequired()
    end
end

-- A retained rebuild anchor historically entered Spawn as survivorName. After
-- the proven snapshot builder has created fresh operation safety state, classify
-- that same named bot as the unified bootstrap as well. Five-player queues keep
-- their strict final-slot handoff because they never set removeAfterGroupOne;
-- raid-sized queues therefore fall naturally into the 0.8.23 overlap path.
local SCB_0824PreviousStartPresetSummonSnapshot = SCB_StartPresetSummonSnapshot
if SCB_0824PreviousStartPresetSummonSnapshot then
    function SCB_StartPresetSummonSnapshot(snapshot)
        local ok, errorText = SCB_0824PreviousStartPresetSummonSnapshot(snapshot)
        local safety, anchorName, size

        if not ok then return ok, errorText end

        safety = SCB_GetBotOperationSafety and SCB_GetBotOperationSafety(false) or nil
        anchorName = SCB_GetKickAllAnchorForFreshBuild
            and SCB_GetKickAllAnchorForFreshBuild() or nil
        size = tonumber(snapshot and snapshot.size) or 0

        if safety and anchorName and safety.survivorName == anchorName then
            safety.bootstrapName = anchorName
            safety.bootstrapTopology = size > 5 and "raid" or "party"
            safety.bootstrapOrigin = "retained"
            if SCB_DebugLog then
                SCB_DebugLog(
                    "Spawn",
                    "Retained " .. tostring(anchorName)
                    .. " as " .. tostring(safety.bootstrapTopology)
                    .. " bootstrap for preset rebuild"
                )
            end
        end

        return ok, errorText
    end
end

local function SCB_0823BootstrapSafety()
    local safety = SCB_GetBotOperationSafety and SCB_GetBotOperationSafety(false) or nil
    if not safety or not safety.bootstrapName or not safety.removeAfterGroupOne then
        return nil
    end

    -- Fresh T3 bootstrap learns its random bot name only after joining. Retained
    -- rebuild anchors are tagged above. Keep both origins on the same state.
    if not safety.bootstrapTopology then safety.bootstrapTopology = "raid" end
    if not safety.bootstrapOrigin then safety.bootstrapOrigin = "created" end
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
    safety.bootstrapTopology = nil
    safety.bootstrapOrigin = nil
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
        safety.bootstrapTopology = nil
        safety.bootstrapOrigin = nil
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
-- after G1. For ordinary strict handoffs retain the old next-add barrier. For
-- a raid bootstrap, keep polling removal in coordinator state but only block
-- the final capacity-filling bot burst (or final roster tracking).
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
