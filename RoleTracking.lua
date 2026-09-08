-- SoloCraft Bots - live role identity and pfUI tank-role integration.
--
-- 0.6.x has one reliable role source immediately after an SCB spawn: the role
-- SCB itself requested. Keep that as assumedRole on the named live member.
-- confirmedRole is deliberately a separate, higher-priority observation layer;
-- 0.7.0 can populate it without changing the consumers defined here.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

SCB.pendingAssumedSpawns = SCB.pendingAssumedSpawns or {}
SCB.assumedRolesByName = SCB.assumedRolesByName or {}

local function SCB_ParseSpawnAssumption(command)
    local _, _, classKey, role, extra
    if not command or command == "" then return nil end
    _, _, classKey, role, extra = string.find(command, "^add%s+(%S+)%s+(%S+)%s*(.*)$")
    if not classKey or not role then return nil end
    if extra == "" then extra = nil end
    return {
        command = command,
        class = classKey,
        role = role,
        extra = extra,
        queuedAt = GetTime and GetTime() or 0,
    }
end

function SCB_ClearPendingAssumedSpawns()
    SCB.pendingAssumedSpawns = {}
end

function SCB_GetResolvedLiveRole(member)
    if not member then return nil end
    return member.confirmedRole or member.assumedRole
end

local function SCB_QueueAssumedSpawn(command)
    local intent

    -- Manual one-off spawns are intentionally left for the future detector.
    -- The automated preset/refill machinery is the authoritative source of an
    -- assumed role because SCB owns both the requested command and its lifecycle.
    if not SCB_HasBotSpawnOperation or not SCB_HasBotSpawnOperation() then return end

    -- A server combat rejection re-sends the exact same burst. The original
    -- unmatched intents already describe that retry, so do not enqueue copies.
    if (SCB.presetCombatRetryFailures or 0) > 0
        and table.getn(SCB.pendingAssumedSpawns or {}) > 0 then
        return
    end

    intent = SCB_ParseSpawnAssumption(command)
    if not intent then return end
    table.insert(SCB.pendingAssumedSpawns, intent)
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

-- Primary identity path: SoloCraft's membership messages arrive in the same
-- server processing order as the add commands. This preserves the summoner's
-- role identity even when Blizzard later presents the subgroup in another order.
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

-- The Live Roster is now the one controller of SCB-applied pfUI tank flags.
-- Manual pfUI tank assignments remain untouched because we remove only names
-- previously written by SCB itself.
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
        if member and member.name and SCB_GetResolvedLiveRole(member) == "tank" then
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

-- Reconcile the legacy preset tracker after it reaches its normal full-roster
-- barrier. The old ordinal map may have been wrong; exact spawn-command identity
-- plus the live subgroup lets us replace it with the summoner-linked name.
-- Identical requests are interchangeable by definition.
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
                    and assumption and assumption.command == assignment.command then
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
            -- The original finalizer may already have built the Active Roster
            -- from its ordinal guess. Rebuild it once from the corrected tracker
            -- so Replace Dead/Missing inherits the same identity truth.
            if SCB_EstablishActiveRosterFromTracker then
                SCB_EstablishActiveRosterFromTracker(tracker)
            end
            if SCB_RefreshLiveRoster then SCB_RefreshLiveRoster() end
        end
        if ready then SCB_ApplyLivePfUITankRoles() end
        return ready
    end
end

-- Capture automated spawn intent at the exact point the command is sent.
local SCB_OriginalSendSpawnCommand = SCB_SendSpawnCommand
if SCB_OriginalSendSpawnCommand then
    function SCB_SendSpawnCommand(command)
        SCB_QueueAssumedSpawn(command)
        return SCB_OriginalSendSpawnCommand(command)
    end
end

-- Bind a roster-delta fallback before the normal roster handler overwrites
-- SCB.lastRoster, then let the canonical handler refresh Live/Active Roster.
-- Finally prune departed names and apply tank flags from settled live role state.
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

-- Fresh preset and refill operations must never inherit an unmatched intent from
-- an aborted earlier operation.
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
