-- SoloCraft Bots - explicit spawn identity and live raid-layout reconciliation.
--
-- 0.7.2 replaces the 0.7.1 same-timestamp burst inference with explicit
-- burst plans. The preset/refill scheduler already knows every logical slot it
-- is requesting, so identity follows that plan instead of GetTime() equality.
-- Timestamps remain diagnostics only.
--
-- This module also treats Blizzard's final raid ordering as the live working
-- layout. Saved presets remain untouched until Save is clicked.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

SCB.presetEditorPlayerSlots = SCB.presetEditorPlayerSlots or {}
SCB.scbPresetBurstPlans = SCB.scbPresetBurstPlans or {}
SCB.scbNextBurstID = SCB.scbNextBurstID or 0


local function SCB_GroupLocalSlot(slotIndex)
    if not slotIndex then return nil end
    return math.mod(slotIndex - 1, 5) + 1
end

local function SCB_BurstDebug(text)
    if SCB_DebugLog then SCB_DebugLog("Burst", text) end
end

-- RoleTracking.lua's 0.7.1 wrapper inferred a burst by comparing GetTime()
-- values at each individual send. Bypass that wrapper completely: managed
-- operations now preload SCB.pendingAssumedSpawns from an explicit burst plan.
-- Preserve the original low-level spawn behavior from SoloCraftBots.lua.
function SCB_SendSpawnCommand(command)
    if not command or command == "" then return end
    if SCB_RegisterSpawnIntent then SCB_RegisterSpawnIntent() end
    SendChatMessage(".partybot " .. command, "SAY")
end

function SCB_BeginAssumedSpawnBurst(plan)
    local i, entry, intent, groupLabel, localSlot
    if not plan or not plan.assignments or table.getn(plan.assignments) == 0 then
        return false
    end

    SCB.pendingAssumedSpawns = SCB.pendingAssumedSpawns or {}
    SCB.scbNextBurstID = (SCB.scbNextBurstID or 0) + 1
    plan.burstID = SCB.scbNextBurstID

    for i = 1, table.getn(plan.assignments) do
        entry = plan.assignments[i]
        if entry then
            intent = {
                command = entry.command,
                class = entry.class,
                role = entry.role,
                extra = entry.extra,
                spawnKind = plan.kind or "preset",
                slotIndex = entry.slotIndex,
                group = entry.group or plan.group,
                burstID = plan.burstID,
                -- Diagnostic metadata only. It never defines burst membership
                -- or ordering.
                queuedAt = GetTime and GetTime() or 0,
            }
            table.insert(SCB.pendingAssumedSpawns, intent)

            localSlot = SCB_GroupLocalSlot(intent.slotIndex)
            if intent.slotIndex and intent.group then
                groupLabel = "G" .. tostring(intent.group) .. "S" .. tostring(localSlot)
            else
                groupLabel = tostring(plan.kind or "spawn")
            end
            SCB_BurstDebug(
                "Burst " .. tostring(plan.burstID)
                .. " expect " .. groupLabel
                .. " " .. tostring(intent.class or "?")
                .. " " .. tostring(intent.role or "?")
            )
        end
    end
    return true
end

-- Primary binding remains the SoloCraft membership message, but it now consumes
-- an explicit logical receive sequence instead of a timestamp-derived queue.
function SCB_HandleAssumedRoleSystemMessage(text)
    local _, _, name
    local intent, localSlot, label
    if not text or text == "" then return false end

    _, _, name = string.find(text, "^([^%s]+%*) joins the party%.$")
    if not name then
        _, _, name = string.find(text, "^([^%s]+%*) has joined the raid group%.?$")
    end
    if not name then return false end

    SCB.assumedRolesByName = SCB.assumedRolesByName or {}
    if SCB.assumedRolesByName[name] then return false end
    if table.getn(SCB.pendingAssumedSpawns or {}) == 0 then return false end

    intent = table.remove(SCB.pendingAssumedSpawns, 1)
    intent.name = name
    intent.boundAt = GetTime and GetTime() or 0
    SCB.assumedRolesByName[name] = intent

    localSlot = SCB_GroupLocalSlot(intent.slotIndex)
    if intent.slotIndex and intent.group then
        label = "G" .. tostring(intent.group) .. "S" .. tostring(localSlot)
    else
        label = tostring(intent.spawnKind or "spawn")
    end
    SCB_BurstDebug(
        "Burst " .. tostring(intent.burstID or "?")
        .. " joined " .. tostring(name)
        .. " -> " .. label
        .. " " .. tostring(intent.class or "?")
        .. " " .. tostring(intent.role or "?")
    )
    return true
end

-- Exact logical slot identity is authoritative when available. Command+group is
-- retained only as a compatibility fallback for an in-flight/legacy tracker.
function SCB_ReconcileTrackerFromAssumedRoles(tracker)
    local roster, used, replacements = nil, {}, {}
    local i, j, assignment, member, assumption, matchedName

    if not tracker or not tracker.ready or tracker.scbRoleIdentityReconciled then
        return tracker and tracker.scbRoleIdentityReconciled or false
    end

    roster = SCB_GetLiveRoster and SCB_GetLiveRoster(true) or nil
    if not roster then return false end

    for i = 1, table.getn(tracker.assignments or {}) do
        assignment = tracker.assignments[i]
        if assignment and assignment.initialActive then
            matchedName = nil

            -- Preferred 0.7.2 identity path: the summoner already told us the
            -- exact logical slot this name belongs to.
            for j = 1, table.getn(roster.members or {}) do
                member = roster.members[j]
                assumption = member and SCB.assumedRolesByName[member.name] or nil
                if member and member.isBot and member.name and not used[member.name]
                    and assumption and assumption.spawnKind ~= "bootstrap"
                    and assumption.slotIndex == assignment.slotIndex then
                    matchedName = member.name
                    break
                end
            end

            -- Legacy fallback for assumptions created without slot metadata.
            if not matchedName then
                for j = 1, table.getn(roster.members or {}) do
                    member = roster.members[j]
                    assumption = member and SCB.assumedRolesByName[member.name] or nil
                    if member and member.isBot and member.name and not used[member.name]
                        and (member.currentGroup or 1) == (assignment.group or 1)
                        and assumption and assumption.spawnKind ~= "bootstrap"
                        and not assumption.slotIndex
                        and assumption.command == assignment.command then
                        matchedName = member.name
                        break
                    end
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

-- Detection.lua uses this public linker for the preset status ticks. Give it
-- the same exact slot identity as the live-role/tank controller; command-only
-- matching remains only for legacy assumptions without slot metadata.
function SCB_LinkAssumptionsToTrackerSlots()
    local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil
    local used = {}
    local i, assignment, name, intent, chosenName, chosenAt

    if not tracker or not tracker.assignments then return end

    for i = 1, table.getn(tracker.assignments) do
        assignment = tracker.assignments[i]
        name = assignment and assignment.scbAssumedName or nil
        intent = name and SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil

        if assignment and assignment.initialActive and intent
            and intent.spawnKind ~= "bootstrap"
            and ((intent.slotIndex and intent.slotIndex == assignment.slotIndex)
                or (not intent.slotIndex and intent.command == assignment.command)) then
            used[name] = true
        elseif assignment then
            assignment.scbAssumedName = nil
        end
    end

    for i = 1, table.getn(tracker.assignments) do
        assignment = tracker.assignments[i]
        if assignment and assignment.initialActive and not assignment.scbAssumedName then
            chosenName, chosenAt = nil, nil

            -- Exact 0.7.2 slot identity first.
            for name, intent in pairs(SCB.assumedRolesByName or {}) do
                if not used[name] and intent and intent.spawnKind ~= "bootstrap"
                    and intent.slotIndex == assignment.slotIndex then
                    chosenName = name
                    break
                end
            end

            -- Compatibility fallback for assumptions created before explicit
            -- slot metadata existed.
            if not chosenName then
                for name, intent in pairs(SCB.assumedRolesByName or {}) do
                    if not used[name] and intent and intent.spawnKind ~= "bootstrap"
                        and not intent.slotIndex and intent.command == assignment.command then
                        if not chosenAt or (intent.boundAt or 0) < chosenAt then
                            chosenName = name
                            chosenAt = intent.boundAt or 0
                        end
                    end
                end
            end

            if chosenName then
                assignment.scbAssumedName = chosenName
                used[chosenName] = true
            end
        end
    end
end
