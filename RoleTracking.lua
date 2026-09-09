-- SoloCraft Bots - live role identity and pfUI tank-role integration.
--
-- Spawn ordering and preset scheduling are owned by the explicit Spawn/Raid
-- runtime. This module only consumes already-planned spawn identities, enriches
-- the live roster, and exposes resolved role state to pfUI/maintenance.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

SCB.pendingAssumedSpawns = SCB.pendingAssumedSpawns or {}
SCB.assumedRolesByName = SCB.assumedRolesByName or {}
SCB.PRESET_WAIT_REAL_RAID_START = "__SCB_WAIT_REAL_RAID_START__"

-- SoloCraft upgrades newly-spawned bots to T3 only when both conditions are
-- already true: the player is inside one of these 20/40-player raid zones and
-- the player is already in a raid group. A temporary bootstrap is therefore
-- useful only for a solo start in these locations.
local SCB_T3_RAID_GROUPS = {
    zg = true,
    aq20 = true,
    mc = true,
    onyxia = true,
    bwl = true,
    aq40 = true,
    naxx = true,
}

function SCB_IsT3RaidLocation()
    local context = SCB_GetLocationContext and SCB_GetLocationContext() or nil
    return context and context.inInstance and SCB_T3_RAID_GROUPS[context.groupID] == true
end

function SCB_ClearPendingAssumedSpawns()
    SCB.pendingAssumedSpawns = {}
end

function SCB_GetResolvedLiveRole(member)
    if not member then return nil end
    return member.confirmedRole or member.assumedRole
end

local function SCB_BindAssumedSpawnName(name, intent)
    if not name or not intent then return false end
    intent.name = name
    intent.boundAt = GetTime and GetTime() or 0
    SCB.assumedRolesByName[name] = intent
    return true
end

function SCB_BindNextAssumedSpawnName(name)
    local intent
    if not name or SCB.assumedRolesByName[name] then return false end
    if table.getn(SCB.pendingAssumedSpawns or {}) == 0 then return false end
    intent = table.remove(SCB.pendingAssumedSpawns, 1)
    return SCB_BindAssumedSpawnName(name, intent)
end

-- Keep name-linked assumptions session-local and live-only. A kicked bot can be
-- given the same random name by a later summon, and that later spawn must be free
-- to acquire a new assumed role rather than inheriting stale identity.
local function SCB_PruneAssumedRolesToCurrentRoster()
    local current = SCB_GetRosterNames and SCB_GetRosterNames() or {}
    local name
    for name in pairs(SCB.assumedRolesByName or {}) do
        if not current[name] then SCB.assumedRolesByName[name] = nil end
    end
end

-- Primary identity path: the explicit summon runtime preloads
-- SCB.pendingAssumedSpawns in the exact expected SoloCraft receive sequence.
-- Each membership message consumes one planned logical assignment.
function SCB_HandleAssumedRoleSystemMessage(text)
    local _, _, name
    if not text or text == "" then return false end

    _, _, name = string.find(text, "^([^%s]+%*) joins the party%.$")
    if not name then
        _, _, name = string.find(text, "^([^%s]+%*) has joined the raid group%.?$")
    end
    if not name then return false end

    -- Conversion/duplicate membership messages for a bot already linked must
    -- never consume the next pending spawn intent.
    if SCB.assumedRolesByName[name] then return false end
    return SCB_BindNextAssumedSpawnName(name)
end

-- Fallback for server builds that do not emit one of the membership strings
-- above. Most roster events expose one newly-added bot; if several arrive in
-- one event, match requested class first, then preserve live roster order only
-- for genuinely ambiguous same-class additions. Class is identity evidence
-- here, never a restriction on which role a class is allowed to have.
local function SCB_BindAssumptionsFromRosterDelta(previousNames)
    local newMembers, used, consumed = {}, {}, {}
    local members = SCB_CollectGroupMembers and SCB_CollectGroupMembers() or {}
    local qi, mi, intent, member, _, classFile, wantedClass, chosen

    if not previousNames or table.getn(SCB.pendingAssumedSpawns or {}) == 0 then return end

    for mi = 1, table.getn(members) do
        member = members[mi]
        if member and member.isBot and member.name and not previousNames[member.name]
            and not SCB.assumedRolesByName[member.name] then
            _, classFile = UnitClass and UnitClass(member.unit)
            table.insert(newMembers, {
                name = member.name,
                class = classFile and string.lower(classFile) or nil,
            })
        end
    end
    if table.getn(newMembers) == 0 then return end

    for qi = 1, table.getn(SCB.pendingAssumedSpawns) do
        if table.getn(consumed) >= table.getn(newMembers) then break end
        intent = SCB.pendingAssumedSpawns[qi]
        wantedClass = intent.class and string.lower(intent.class) or nil
        chosen = nil

        if wantedClass then
            for mi = 1, table.getn(newMembers) do
                if not used[mi] and newMembers[mi].class == wantedClass then
                    chosen = mi
                    break
                end
            end
        end
        if not chosen then
            for mi = 1, table.getn(newMembers) do
                if not used[mi] then chosen = mi break end
            end
        end

        if chosen then
            used[chosen] = true
            SCB_BindAssumedSpawnName(newMembers[chosen].name, intent)
            table.insert(consumed, qi)
        end
    end

    for qi = table.getn(consumed), 1, -1 do
        table.remove(SCB.pendingAssumedSpawns, consumed[qi])
    end
end

-- Enrich the canonical Live Roster. A fresh name-linked spawn assumption wins
-- over the legacy preset ordinal association. Once the Active Roster exists,
-- its maintained role is the durable fallback across zoning/reload boundaries.
local SCB_OriginalBuildLiveRoster = SCB_BuildLiveRoster
if SCB_OriginalBuildLiveRoster then
    function SCB_BuildLiveRoster()
        local roster = SCB_OriginalBuildLiveRoster()
        local i, member, assumption, slot

        for i = 1, table.getn(roster and roster.members or {}) do
            member = roster.members[i]
            assumption = member and SCB.assumedRolesByName[member.name] or nil

            if assumption then
                member.assumedRole = assumption.role
                member.assumedExtra = assumption.extra
                member.assumedClass = assumption.class or member.assumedClass
                member.assumedRoleSource = "spawn"
                member.spawnKind = assumption.spawnKind
            elseif member and member.isBot and SCB_GetActiveSlotByName then
                slot = SCB_GetActiveSlotByName(member.name)
                if slot and slot.role then
                    member.assumedRole = slot.role
                    member.assumedExtra = slot.extra
                    member.assumedRoleSource = "active"
                end
            elseif member and member.assumedRole then
                member.assumedRoleSource = member.assumedRoleSource or "preset"
            end

            if member then member.resolvedRole = SCB_GetResolvedLiveRole(member) end
        end
        return roster
    end
end

-- The Live Roster is the one controller of SCB-applied pfUI tank flags.
-- Manual pfUI tank assignments remain untouched because we remove only names
-- previously written by SCB itself. Bootstrap is lifecycle infrastructure, not
-- a real preset member, so it never receives a persistent SCB tank mark.
function SCB_ApplyLivePfUITankRoles()
    local roles, roster, i, member, name, frame
    if not pfUI or not pfUI.uf or not pfUI.uf.raid
        or type(pfUI.uf.raid.tankrole) ~= "table" then return end

    roles = pfUI.uf.raid.tankrole
    roster = SCB_GetLiveRoster and SCB_GetLiveRoster(true) or nil
    SCB.pfuiAutoTanks = SCB.pfuiAutoTanks or {}

    for name in pairs(SCB.pfuiAutoTanks) do roles[name] = nil end
    SCB.pfuiAutoTanks = {}

    for i = 1, table.getn(roster and roster.members or {}) do
        member = roster.members[i]
        if member and member.name and member.spawnKind ~= "bootstrap"
            and SCB_GetResolvedLiveRole(member) == "tank" then
            roles[member.name] = true
            SCB.pfuiAutoTanks[member.name] = true
        end
    end

    if GetNumRaidMembers and GetNumRaidMembers() > 0 and pfUI.uf.raid.Show then
        pfUI.uf.raid:Show()
    end

    if pfUI.uf.RefreshUnit and pfUI.uf.frames then
        for i = 1, table.getn(pfUI.uf.frames) do
            frame = pfUI.uf.frames[i]
            if frame and frame.label and (frame.label == "party" or frame.label == "raid") then
                pfUI.uf:RefreshUnit(frame, "all")
            end
        end
    end
end

-- Retain the old public/internal name so older call sites and in-flight state
-- continue to work, but the tracker is no longer the tank-mark controller.
function SCB_ApplyTrackedPfUITankRoles(tracker)
    SCB_ApplyLivePfUITankRoles()
end

-- Compatibility reconciliation for trackers created before exact slot metadata.
-- RaidIdentity.lua replaces this with the explicit slotIndex path later in load.
function SCB_ReconcileTrackerFromAssumedRoles(tracker)
    local roster, used, replacements = nil, {}, {}
    local i, j, assignment, member, assumption, wantedGroup, matchedName

    if not tracker or not tracker.ready or tracker.scbRoleIdentityReconciled then
        return tracker and tracker.scbRoleIdentityReconciled or false
    end

    roster = SCB_GetLiveRoster and SCB_GetLiveRoster(true) or nil
    if not roster then return false end

    for i = 1, table.getn(tracker.assignments or {}) do
        assignment = tracker.assignments[i]
        if assignment and assignment.initialActive then
            wantedGroup = assignment.group or 1
            matchedName = nil

            for j = 1, table.getn(roster.members or {}) do
                member = roster.members[j]
                assumption = member and SCB.assumedRolesByName[member.name] or nil
                if member and member.isBot and member.name and not used[member.name]
                    and (member.currentGroup or 1) == wantedGroup
                    and assumption and assumption.spawnKind ~= "bootstrap"
                    and assumption.command == assignment.command then
                    matchedName = member.name
                    break
                end
            end

            if not matchedName then return false end
            replacements[i] = matchedName
            used[matchedName] = true
        end
    end

    for i = 1, table.getn(tracker.assignments or {}) do
        if replacements[i] then tracker.assignments[i].botName = replacements[i] end
    end
    tracker.scbRoleIdentityReconciled = true
    return true
end

local SCB_OriginalTryFinalizeRaidRoleTracking = SCB_TryFinalizeRaidRoleTracking
if SCB_OriginalTryFinalizeRaidRoleTracking then
    function SCB_TryFinalizeRaidRoleTracking()
        local ready = SCB_OriginalTryFinalizeRaidRoleTracking()
        local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil

        if ready and tracker and SCB_ReconcileTrackerFromAssumedRoles(tracker) then
            if SCB_EstablishActiveRosterFromTracker then
                SCB_EstablishActiveRosterFromTracker(tracker)
            end
            if SCB_RefreshLiveRoster then SCB_RefreshLiveRoster() end
        end
        if ready then SCB_ApplyLivePfUITankRoles() end
        return ready
    end
end

-- A bootstrap should never be adopted as a desired maintained slot.
local SCB_OriginalAdoptObservedBotIntoActiveRoster = SCB_AdoptObservedBotIntoActiveRoster
if SCB_OriginalAdoptObservedBotIntoActiveRoster then
    function SCB_AdoptObservedBotIntoActiveRoster(member, roster)
        local assumption = member and member.name and SCB.assumedRolesByName[member.name] or nil
        if assumption and assumption.spawnKind == "bootstrap" then return nil end
        return SCB_OriginalAdoptObservedBotIntoActiveRoster(member, roster)
    end
end

-- Bind a roster-delta fallback before the normal roster handler overwrites
-- SCB.lastRoster, then let the canonical handler refresh Live/Active Roster.
local SCB_OriginalHandleRosterChange = SCB_HandleRosterChange
if SCB_OriginalHandleRosterChange then
    function SCB_HandleRosterChange()
        local previousNames = SCB.lastRoster
        SCB_BindAssumptionsFromRosterDelta(previousNames)
        SCB_OriginalHandleRosterChange()
        SCB_PruneAssumedRolesToCurrentRoster()
        SCB_ApplyLivePfUITankRoles()
    end
end

-- Replace Dead removes exact bot names, but SoloCraft can continue to count a
-- departed bot against the instance cap briefly after Blizzard drops it from the
-- group roster. Wait three full seconds from the first observed roster absence
-- before starting the replacement summon chain. Combat remains a hard gate.
SCB.REPLACE_REMOVAL_SETTLE_DELAY = 3.0
local SCB_OriginalMaintenanceReplaceOnUpdate = SCB_MaintenanceReplaceOnUpdate
if SCB_OriginalMaintenanceReplaceOnUpdate then
    function SCB_MaintenanceReplaceOnUpdate()
        local state = SCB.replaceDeadState
        local now = GetTime and GetTime() or 0
        local waitForDeparture = state and state.active
            and (state.phase == "waitremoved" or state.phase == "waitsurvivorremoved")
            and state.removedNames and next(state.removedNames) ~= nil

        if waitForDeparture then
            if state.scbRemovalDelayPhase ~= state.phase then
                state.scbRemovalDelayPhase = state.phase
                state.scbRemovalGoneAt = nil
            end

            if not SCB_ReplaceDeadNamesGone or not SCB_ReplaceDeadNamesGone(state.removedNames) then
                state.scbRemovalGoneAt = nil
                return
            end

            if not state.scbRemovalGoneAt then
                state.scbRemovalGoneAt = now
                return
            end

            if (now - state.scbRemovalGoneAt) < SCB.REPLACE_REMOVAL_SETTLE_DELAY then return end
            if SCB_PresetGroupHasCombat and SCB_PresetGroupHasCombat() then return end
        end

        return SCB_OriginalMaintenanceReplaceOnUpdate()
    end
end

-- Fresh preset/refill operations never inherit unmatched intents from an
-- aborted earlier operation.
local SCB_OriginalCreateRaidRoleTracker = SCB_CreateRaidRoleTracker
if SCB_OriginalCreateRaidRoleTracker then
    function SCB_CreateRaidRoleTracker(slots, size, occupied, group, snapshot)
        SCB_ClearPendingAssumedSpawns()
        return SCB_OriginalCreateRaidRoleTracker(slots, size, occupied, group, snapshot)
    end
end

local SCB_OriginalStartRefillAssignments = SCB_StartRefillAssignments
if SCB_OriginalStartRefillAssignments then
    function SCB_StartRefillAssignments(assignments)
        SCB_ClearPendingAssumedSpawns()
        return SCB_OriginalStartRefillAssignments(assignments)
    end
end

local SCB_OriginalAbortBotSpawnOperations = SCB_AbortBotSpawnOperations
if SCB_OriginalAbortBotSpawnOperations then
    function SCB_AbortBotSpawnOperations()
        SCB_ClearPendingAssumedSpawns()
        return SCB_OriginalAbortBotSpawnOperations()
    end
end

local SCB_OriginalResetSessionState = SCB_ResetSessionState
if SCB_OriginalResetSessionState then
    function SCB_ResetSessionState()
        SCB_ClearPendingAssumedSpawns()
        SCB.assumedRolesByName = {}
        return SCB_OriginalResetSessionState()
    end
end

-- Listen directly to the underlying system event; ChatFilter only affects
-- presentation and therefore cannot hide these role-identity messages from us.
local roleEventFrame = CreateFrame("Frame", "SoloCraftBotsRoleTrackingEventFrame", UIParent)
roleEventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
roleEventFrame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_SYSTEM" then SCB_HandleAssumedRoleSystemMessage(arg1) end
end)
