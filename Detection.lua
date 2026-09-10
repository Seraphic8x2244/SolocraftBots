-- SoloCraft Bots - combat role evidence and preset role-status indicators.
--
-- Vanilla 1.12 has no modern combat-log API.  FillRaidBots demonstrates the
-- reliable old-client pattern: listen to CHAT_MSG_SPELL_* combat text, extract
-- the acting group member from arg1, and classify recognised spell names.  SCB
-- keeps that proven transport but treats each observation as one evidence step.
-- Two observations are required before confirmedRole is set.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

SCB.roleEvidenceByName = SCB.roleEvidenceByName or {}
SCB.roleEvidenceRecent = SCB.roleEvidenceRecent or {}
SCB.ROLE_CONFIRM_THRESHOLD = 2

-- Vanilla-only subset of FRB's spell/role catalogue.  Later-expansion entries
-- (for example Lava Lash, Crusader Strike, Steady Shot, Incinerate) are
-- deliberately excluded.  These are evidence, not class locks: every role keeps
-- its own score and the strongest score wins once it reaches the threshold.
local SCB_ROLE_SPELLS = {
    warrior = {
        { "Defensive Stance", "tank" },
        { "Sunder Armor", "tank" },
        { "Taunt", "tank" },
        { "Revenge", "tank" },
        { "Shield Wall", "tank" },
        { "Last Stand", "tank" },
        { "Shield Block", "tank" },
        { "Mocking Blow", "tank" },
        { "Mortal Strike", "meleedps" },
        { "Bloodthirst", "meleedps" },
        { "Whirlwind", "meleedps" },
    },
    priest = {
        { "Greater Heal", "healer" },
        { "Prayer of Healing", "healer" },
        { "Flash Heal", "healer" },
        { "Power Word: Shield", "healer" },
        { "Holy Nova", "healer" },
        { "Heal", "healer" },
        { "Shadow Word: Pain", "rangedps" },
        { "Mind Blast", "rangedps" },
        { "Mind Flay", "rangedps" },
        { "Shadowform", "rangedps" },
        { "Vampiric Embrace", "rangedps" },
    },
    druid = {
        { "Dire Bear Form", "tank" },
        { "Bear Form", "tank" },
        { "Maul", "tank" },
        { "Growl", "tank" },
        { "Swipe", "tank" },
        { "Cat Form", "meleedps" },
        { "Rake", "meleedps" },
        { "Ferocious Bite", "meleedps" },
        { "Shred", "meleedps" },
        { "Healing Touch", "healer" },
        { "Regrowth", "healer" },
        { "Rejuvenation", "healer" },
        { "Tranquility", "healer" },
        { "Swiftmend", "healer" },
        { "Starfire", "rangedps" },
        { "Moonfire", "rangedps" },
        { "Hurricane", "rangedps" },
        { "Wrath", "rangedps" },
    },
    shaman = {
        { "Healing Wave", "healer" },
        { "Chain Heal", "healer" },
        { "Lesser Healing Wave", "healer" },
        { "Lightning Bolt", "rangedps" },
        { "Chain Lightning", "rangedps" },
        { "Earth Shock", "rangedps" },
        { "Flame Shock", "rangedps" },
        { "Stormstrike", "meleedps" },
        { "Windfury Weapon", "meleedps" },
    },
    paladin = {
        { "Holy Light", "healer" },
        { "Flash of Light", "healer" },
        { "Holy Shock", "healer" },
        { "Righteous Fury", "tank" },
        { "Holy Shield", "tank" },
        { "Seal of Righteousness", "tank" },
        { "Consecration", "tank" },
        { "Blessing of Sanctuary", "tank" },
        { "Seal of Command", "meleedps" },
        { "Judgement of Command", "meleedps" },
    },
    mage = {
        { "Arcane Missiles", "rangedps" },
        { "Arcane Power", "rangedps" },
        { "Arcane Explosion", "rangedps" },
        { "Fireball", "rangedps" },
        { "Frostbolt", "rangedps" },
        { "Ice Armor", "rangedps" },
        { "Blizzard", "rangedps" },
        { "Pyroblast", "rangedps" },
        { "Frost Nova", "rangedps" },
        { "Cone of Cold", "rangedps" },
        { "Scorch", "rangedps" },
        { "Flamestrike", "rangedps" },
        { "Fire Blast", "rangedps" },
        { "Ice Block", "rangedps" },
    },
    warlock = {
        { "Shadow Bolt", "rangedps" },
        { "Corruption", "rangedps" },
        { "Immolate", "rangedps" },
        { "Siphon Life", "rangedps" },
        { "Curse of Agony", "rangedps" },
        { "Curse of Doom", "rangedps" },
        { "Rain of Fire", "rangedps" },
        { "Life Tap", "rangedps" },
        { "Hellfire", "rangedps" },
        { "Shadowburn", "rangedps" },
        { "Death Coil", "rangedps" },
        { "Drain Soul", "rangedps" },
        { "Drain Life", "rangedps" },
    },
    rogue = {
        { "Stealth", "meleedps" },
        { "Backstab", "meleedps" },
        { "Sinister Strike", "meleedps" },
        { "Eviscerate", "meleedps" },
        { "Ambush", "meleedps" },
        { "Slice and Dice", "meleedps" },
        { "Gouge", "meleedps" },
        { "Hemorrhage", "meleedps" },
        { "Rupture", "meleedps" },
        { "Kidney Shot", "meleedps" },
        { "Expose Armor", "meleedps" },
        { "Sprint", "meleedps" },
        { "Vanish", "meleedps" },
        { "Distract", "meleedps" },
        { "Preparation", "meleedps" },
        { "Blind", "meleedps" },
    },
    hunter = {
        { "Aimed Shot", "rangedps" },
        { "Multi-Shot", "rangedps" },
        { "Arcane Shot", "rangedps" },
        { "Serpent Sting", "rangedps" },
        { "Scatter Shot", "rangedps" },
        { "Feign Death", "rangedps" },
        { "Rapid Fire", "rangedps" },
        { "Viper Sting", "rangedps" },
        { "Hunter's Mark", "rangedps" },
        { "Volley", "rangedps" },
    },
}

local SCB_COMBAT_SOURCE_PATTERNS = {
    "^(.-) begins to cast",
    "^(.-) casts",
    "^(.-)'s ",
    "^(.-) gains",
    "^(.-) deals",
    "^(.-) hits",
    "^(.-) heals",
    "^(.-) crits",
}

local function SCB_NormalizeCombatName(name)
    local result, i, char
    if type(name) ~= "string" then return nil end
    result = ""
    for i = 1, string.len(name) do
        char = string.sub(name, i, i)
        if (char >= "a" and char <= "z") or (char >= "A" and char <= "Z")
            or (char >= "0" and char <= "9") or char == "*" then
            result = result .. string.lower(char)
        end
    end
    if result == "" then return nil end
    return result
end

local function SCB_ExtractCombatSource(text)
    local i, _, _, name
    if type(text) ~= "string" then return nil end
    for i = 1, table.getn(SCB_COMBAT_SOURCE_PATTERNS) do
        _, _, name = string.find(text, SCB_COMBAT_SOURCE_PATTERNS[i])
        if name and name ~= "" then return name end
    end
    return nil
end

local function SCB_FindLiveBotForCombatSource(sourceName)
    local wanted = SCB_NormalizeCombatName(sourceName)
    local members = SCB_CollectGroupMembers and SCB_CollectGroupMembers() or {}
    local i, member, _, classFile
    if not wanted then return nil, nil end

    for i = 1, table.getn(members) do
        member = members[i]
        if member and member.isBot and member.name
            and SCB_NormalizeCombatName(member.name) == wanted then
            if UnitClass and member.unit then _, classFile = UnitClass(member.unit) end
            return member.name, classFile and string.lower(classFile) or nil
        end
    end
    return nil, nil
end

local function SCB_FindRoleSpell(classKey, text)
    local list = classKey and SCB_ROLE_SPELLS[classKey] or nil
    local i, entry
    if not list or type(text) ~= "string" then return nil, nil end
    for i = 1, table.getn(list) do
        entry = list[i]
        if string.find(text, entry[1], 1, true) then return entry[1], entry[2] end
    end
    return nil, nil
end

local function SCB_CopyRoleScores(scores)
    local copy, role = {}, nil
    for role, value in pairs(scores or {}) do copy[role] = value end
    return copy
end

local function SCB_GetAssumedRoleForName(name)
    local assumption = SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil
    local slot
    if assumption and assumption.spawnKind ~= "bootstrap" and assumption.role then
        return assumption.role
    end
    if SCB_GetActiveSlotByName then
        slot = SCB_GetActiveSlotByName(name)
        if slot then return slot.assumedRole or slot.role end
    end
    return nil
end

local function SCB_ResolveEvidenceCandidate(name, state)
    local assumedRole = SCB_GetAssumedRoleForName(name)
    local bestRole, bestScore, role, score = nil, -1, nil, 0

    for role, score in pairs(state.byRole or {}) do
        if score > bestScore then
            bestRole, bestScore = role, score
        elseif score == bestScore and role == assumedRole then
            -- Assumption is a tie-breaker only; it never prevents another role
            -- from winning once the observed evidence is stronger.
            bestRole = role
        end
    end

    state.candidateRole = bestRole
    state.candidateScore = bestScore > 0 and bestScore or 0
    if bestRole and bestScore >= SCB.ROLE_CONFIRM_THRESHOLD then
        state.confirmedRole = bestRole
    end
end

function SCB_GetBotRoleEvidence(name)
    return name and SCB.roleEvidenceByName[name] or nil
end

function SCB_GetBotRoleEvidenceStage(name, role)
    local state = SCB_GetBotRoleEvidence(name)
    local score
    if not state or not role then return 0 end
    if state.confirmedRole == role then return SCB.ROLE_CONFIRM_THRESHOLD end
    score = state.byRole and state.byRole[role] or 0
    if score > SCB.ROLE_CONFIRM_THRESHOLD then score = SCB.ROLE_CONFIRM_THRESHOLD end
    return score
end

local function SCB_SyncEvidenceToActiveSlot(name, state)
    local slot = SCB_GetActiveSlotByName and SCB_GetActiveSlotByName(name) or nil
    if not slot then return end
    slot.roleEvidence = SCB_CopyRoleScores(state.byRole)
    slot.confirmedRole = state.confirmedRole
    if state.confirmedRole then slot.role = state.confirmedRole end
    slot.detected = state.confirmedRole and true or nil
    slot.updatedAt = GetTime and GetTime() or 0
end

local function SCB_IsDuplicateRoleObservation(name, spell)
    local now = GetTime and GetTime() or 0
    local key = tostring(name) .. "\031" .. tostring(spell)
    local previous = SCB.roleEvidenceRecent[key]
    SCB.roleEvidenceRecent[key] = now
    return previous and (now - previous) < 0.30
end

function SCB_AddBotRoleEvidence(name, classKey, role, spell, eventName)
    local state, oldConfirmed, score
    if not name or not classKey or not role or not spell then return false end
    if SCB_IsDuplicateRoleObservation(name, spell) then return false end

    state = SCB.roleEvidenceByName[name]
    if not state then
        state = { class = classKey, byRole = {}, observations = 0 }
        SCB.roleEvidenceByName[name] = state
    end

    -- Actual UnitClass is authoritative for identity. If a stale text parse ever
    -- points at the wrong unit, do not let a spell from another class contaminate
    -- that bot's role evidence.
    if state.class and state.class ~= classKey then return false end

    oldConfirmed = state.confirmedRole
    state.class = classKey
    state.byRole[role] = (state.byRole[role] or 0) + 1
    state.observations = (state.observations or 0) + 1
    state.lastSpell = spell
    state.lastEvent = eventName
    state.updatedAt = GetTime and GetTime() or 0
    SCB_ResolveEvidenceCandidate(name, state)
    SCB_SyncEvidenceToActiveSlot(name, state)

    score = state.byRole[role] or 0
    if SCB_DebugLog then
        SCB_DebugLog("Detection", name .. " " .. classKey .. " " .. role
            .. " " .. spell .. " evidence=" .. tostring(score)
            .. " candidate=" .. tostring(state.candidateRole or "?")
            .. " confirmed=" .. tostring(state.confirmedRole or "?"))
    end

    if SCB_RefreshLiveRoster then SCB_RefreshLiveRoster() end
    if SCB_ApplyLivePfUITankRoles then SCB_ApplyLivePfUITankRoles() end
    if SCB_RefreshPresetRoleIndicators then SCB_RefreshPresetRoleIndicators() end

    return oldConfirmed ~= state.confirmedRole
end

function SCB_HandleRoleCombatText(text, eventName)
    local source, name, classKey, spell, role
    if type(text) ~= "string" or text == "" then return false end

    -- Resource gain lines are noisy and can contain recognised words without a
    -- meaningful cast. FRB filters these too.
    if string.find(text, "gains %d+ Mana") or string.find(text, "gains %d+ Rage")
        or string.find(text, "gains %d+ Energy") then
        return false
    end

    source = SCB_ExtractCombatSource(text)
    if not source then return false end
    name, classKey = SCB_FindLiveBotForCombatSource(source)
    if not name or not classKey then return false end

    spell, role = SCB_FindRoleSpell(classKey, text)
    if not spell or not role then return false end
    SCB_AddBotRoleEvidence(name, classKey, role, spell, eventName)
    return true
end

-- -------------------------------------------------------------------------
-- Active Roster role semantics
-- -------------------------------------------------------------------------
-- Active slots keep the requested role and the observed role separately.  The
-- legacy slot.role field remains the resolved/desirable replacement role so the
-- existing Replace Missing machinery does not need a parallel command path.

local SCB_OriginalEstablishActiveRosterFromTracker_Detection = SCB_EstablishActiveRosterFromTracker
if SCB_OriginalEstablishActiveRosterFromTracker_Detection then
    function SCB_EstablishActiveRosterFromTracker(tracker)
        local ok = SCB_OriginalEstablishActiveRosterFromTracker_Detection(tracker)
        local roster, id, slot
        if not ok then return ok end
        roster = SCB_GetActiveRoster and SCB_GetActiveRoster() or nil
        for id, slot in pairs(roster and roster.slots or {}) do
            if slot and slot.expected then
                slot.assumedRole = slot.assumedRole or slot.role
                slot.confirmedRole = nil
                slot.roleEvidence = nil
                slot.detected = nil
            end
        end
        return ok
    end
end

-- Replace the old scaffold semantics: confirmed observation no longer destroys
-- the requested/assumed role.  Consumers can resolve confirmedRole first while
-- the original intent remains available for diagnostics and future replacement.
function SCB_UpdateActiveBotDetection(name, role, extra, extraKnown)
    local slot = SCB_GetActiveSlotByName and SCB_GetActiveSlotByName(name) or nil
    local assumption = SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil
    if not slot then return false end

    slot.assumedRole = slot.assumedRole or (assumption and assumption.role) or slot.role
    if role then
        slot.confirmedRole = role
        slot.role = role
    end
    if extraKnown then slot.extra = extra end
    slot.detected = role and true or slot.detected
    slot.updatedAt = GetTime and GetTime() or 0
    if SCB_RefreshRefillButton then SCB_RefreshRefillButton() end
    return true
end

local SCB_OriginalBindReplacementToActiveSlot_Detection = SCB_BindReplacementToActiveSlot
if SCB_OriginalBindReplacementToActiveSlot_Detection then
    function SCB_BindReplacementToActiveSlot(slotID, newName, group)
        local ok = SCB_OriginalBindReplacementToActiveSlot_Detection(slotID, newName, group)
        local slot = SCB_GetActiveSlot and SCB_GetActiveSlot(slotID) or nil
        local assumption = newName and SCB.assumedRolesByName and SCB.assumedRolesByName[newName] or nil
        if ok and slot then
            if assumption and assumption.role then slot.assumedRole = assumption.role end
            slot.role = slot.assumedRole or slot.role
            slot.confirmedRole = nil
            slot.roleEvidence = nil
            slot.detected = nil
        end
        return ok
    end
end

-- Enrich every fresh Live Roster snapshot from the durable evidence/Active
-- layers. RoleTracking.lua already attaches assumedRole before this wrapper runs.
local SCB_OriginalBuildLiveRoster_Detection = SCB_BuildLiveRoster
if SCB_OriginalBuildLiveRoster_Detection then
    function SCB_BuildLiveRoster()
        local roster = SCB_OriginalBuildLiveRoster_Detection()
        local i, member, state, slot
        for i = 1, table.getn(roster and roster.members or {}) do
            member = roster.members[i]
            if member and member.isBot and member.name then
                state = SCB.roleEvidenceByName[member.name]
                slot = SCB_GetActiveSlotByName and SCB_GetActiveSlotByName(member.name) or nil
                if state then
                    member.roleEvidence = state.byRole
                    member.confirmedRole = state.confirmedRole
                    member.roleCandidate = state.candidateRole
                elseif slot then
                    member.roleEvidence = slot.roleEvidence
                    member.confirmedRole = slot.confirmedRole
                end
                if SCB_GetResolvedLiveRole then
                    member.resolvedRole = SCB_GetResolvedLiveRole(member)
                else
                    member.resolvedRole = member.confirmedRole or member.assumedRole
                end
            end
        end
        return roster
    end
end

-- -------------------------------------------------------------------------
-- Associate name-linked spawn assumptions with preset rows for the first tick.
-- -------------------------------------------------------------------------

local function SCB_CurrentSlotMatchesTrackerAssignment(slotIndex, assignment)
    local slot = SCB.presetEditorSlots and SCB.presetEditorSlots[slotIndex] or nil
    local aExtra, sExtra
    if not slot or not assignment then return false end
    if slot.class ~= assignment.class or slot.role ~= assignment.role then return false end
    aExtra = assignment.extra or ""
    sExtra = slot.extra or ""
    return aExtra == sExtra
end

function SCB_LinkAssumptionsToTrackerSlots()
    local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil
    local used, i, assignment, name, intent, chosenName, chosenAt
    if not tracker or not tracker.assignments then return end
    used = {}

    -- Preserve still-valid links first.
    for i = 1, table.getn(tracker.assignments) do
        assignment = tracker.assignments[i]
        name = assignment and assignment.scbAssumedName or nil
        intent = name and SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil
        if assignment and assignment.initialActive and intent
            and intent.spawnKind ~= "bootstrap" and intent.command == assignment.command then
            used[name] = true
        elseif assignment then
            assignment.scbAssumedName = nil
        end
    end

    -- Then match every unresolved preset assignment to the earliest unclaimed
    -- name-linked intent with the exact spawn command. Identical commands are
    -- interchangeable by definition; differing role/spec commands are not.
    for i = 1, table.getn(tracker.assignments) do
        assignment = tracker.assignments[i]
        if assignment and assignment.initialActive and not assignment.scbAssumedName then
            chosenName, chosenAt = nil, nil
            for name, intent in pairs(SCB.assumedRolesByName or {}) do
                if not used[name] and intent and intent.spawnKind ~= "bootstrap"
                    and intent.command == assignment.command then
                    if not chosenAt or (intent.boundAt or 0) < chosenAt then
                        chosenName = name
                        chosenAt = intent.boundAt or 0
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

local SCB_OriginalHandleAssumedRoleSystemMessage_Detection = SCB_HandleAssumedRoleSystemMessage
if SCB_OriginalHandleAssumedRoleSystemMessage_Detection then
    function SCB_HandleAssumedRoleSystemMessage(text)
        local changed = SCB_OriginalHandleAssumedRoleSystemMessage_Detection(text)
        if changed then
            SCB_LinkAssumptionsToTrackerSlots()
            if SCB_RefreshPresetRoleIndicators then SCB_RefreshPresetRoleIndicators() end
        end
        return changed
    end
end

local SCB_OriginalHandleRosterChange_Detection = SCB_HandleRosterChange
if SCB_OriginalHandleRosterChange_Detection then
    function SCB_HandleRosterChange()
        local result = SCB_OriginalHandleRosterChange_Detection()
        local current = SCB_GetRosterNames and SCB_GetRosterNames() or {}
        local name

        SCB_LinkAssumptionsToTrackerSlots()
        for name in pairs(SCB.roleEvidenceByName or {}) do
            if not current[name] then SCB.roleEvidenceByName[name] = nil end
        end
        if SCB_RefreshPresetRoleIndicators then SCB_RefreshPresetRoleIndicators() end
        return result
    end
end

-- -------------------------------------------------------------------------
-- Preset role-icon overlays
-- -------------------------------------------------------------------------
-- Both status marks are anchored to the role button itself. Their size and
-- overlap are derived from the configured role icon size, so layout-option
-- changes cannot move or scale the role icon independently of its indicators.
-- Neither indicator changes row, group or panel geometry.

local SCB_CONFIRM_COLORS = {
    [0] = { 1.00, 0.10, 0.10 },
    [1] = { 1.00, 0.90, 0.00 },
    [2] = { 0.20, 1.00, 0.20 },
}

local function SCB_UpdatePresetRoleIndicatorGeometry(row)
    local roleSize, tickSize, overlap, confirmedOffset
    if not row or not row.roleButton or not row.scbAssumedTick or not row.scbConfirmedTick then return end

    roleSize = SCB_GetLayoutValue and SCB_GetLayoutValue("preset", "roleSize") or 24
    if roleSize < 1 then roleSize = 1 end
    tickSize = math.floor((roleSize * 0.375) + 0.5)
    if tickSize < 4 then tickSize = 4 end
    overlap = math.floor((tickSize * 0.22) + 0.5)
    if overlap < 1 then overlap = 1 end
    confirmedOffset = tickSize - overlap

    row.scbAssumedTick:SetWidth(tickSize)
    row.scbAssumedTick:SetHeight(tickSize)
    row.scbAssumedTick:ClearAllPoints()
    -- Assumed role is deliberately the rightmost mark.
    row.scbAssumedTick:SetPoint("BOTTOMRIGHT", row.roleButton, "BOTTOMRIGHT", 0, 0)

    row.scbConfirmedTick:SetWidth(tickSize)
    row.scbConfirmedTick:SetHeight(tickSize)
    row.scbConfirmedTick:ClearAllPoints()
    -- Confirmation sits immediately to its left with a small proportional
    -- overlap, keeping the two marks visually tight at every configured size.
    row.scbConfirmedTick:SetPoint("BOTTOMRIGHT", row.roleButton, "BOTTOMRIGHT", -confirmedOffset, 0)
end

local function SCB_CreatePresetRoleIndicatorPair(row)
    local assumed, confirmed
    if not row or not row.roleButton then return end
    if row.scbAssumedTick and row.scbConfirmedTick then
        SCB_UpdatePresetRoleIndicatorGeometry(row)
        return
    end

    assumed = row.roleButton:CreateTexture(nil, "OVERLAY")
    assumed:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    assumed:SetVertexColor(0.20, 1.00, 0.20)
    assumed:Hide()
    row.scbAssumedTick = assumed

    confirmed = row.roleButton:CreateTexture(nil, "OVERLAY")
    confirmed:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    confirmed:Hide()
    row.scbConfirmedTick = confirmed

    SCB_UpdatePresetRoleIndicatorGeometry(row)
end

local function SCB_FindTrackerAssignmentForIndicator(slotIndex)
    local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil
    local i, assignment
    if not tracker or not tracker.assignments then return nil end
    if tracker.size and SCB_CurrentPresetSize and tracker.size ~= SCB_CurrentPresetSize() then return nil end
    for i = 1, table.getn(tracker.assignments) do
        assignment = tracker.assignments[i]
        if assignment and assignment.slotIndex == slotIndex and assignment.initialActive then
            if SCB_CurrentSlotMatchesTrackerAssignment(slotIndex, assignment) then return assignment end
            return nil
        end
    end
    return nil
end

local function SCB_GetIndicatorBotName(assignment)
    local name, intent, member
    if not assignment then return nil end
    name = assignment.scbAssumedName or assignment.botName
    if not name then return nil end

    intent = SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil
    if intent and intent.spawnKind ~= "bootstrap" then return name end

    member = SCB_GetLiveMember and SCB_GetLiveMember(name, false) or nil
    if member and member.isBot and member.assumedRole then return name end
    return nil
end

function SCB_RefreshPresetRoleIndicators()
    local size = SCB_CurrentPresetSize and SCB_CurrentPresetSize() or 0
    local i, row, assignment, name, stage, color

    for i = 1, 40 do
        row = SCB.presetSlotRows and SCB.presetSlotRows[i] or nil
        if row then
            SCB_CreatePresetRoleIndicatorPair(row)
            SCB_UpdatePresetRoleIndicatorGeometry(row)
            if row.scbAssumedTick then row.scbAssumedTick:Hide() end
            if row.scbConfirmedTick then row.scbConfirmedTick:Hide() end

            if i <= size and not row.scbPresentPlayerKey then
                assignment = SCB_FindTrackerAssignmentForIndicator(i)
                name = SCB_GetIndicatorBotName(assignment)
                if assignment and name then
                    -- Both marks appear only once a real named bot has acquired
                    -- this preset's assumed role. Right = assumption exists.
                    row.scbAssumedTick:Show()

                    -- Left = confidence in that exact assumed role. Zero is red,
                    -- one matching observation is yellow, and two confirms green.
                    stage = SCB_GetBotRoleEvidenceStage(name, assignment.role)
                    if stage <= 0 then
                        local slot = SCB_GetActiveSlotByName and SCB_GetActiveSlotByName(name) or nil
                        local scores = slot and slot.roleEvidence or nil
                        stage = scores and scores[assignment.role] or 0
                        if slot and slot.confirmedRole == assignment.role then stage = SCB.ROLE_CONFIRM_THRESHOLD end
                    end
                    if stage < 0 then stage = 0 end
                    if stage > SCB.ROLE_CONFIRM_THRESHOLD then stage = SCB.ROLE_CONFIRM_THRESHOLD end
                    color = SCB_CONFIRM_COLORS[stage] or SCB_CONFIRM_COLORS[0]
                    row.scbConfirmedTick:SetVertexColor(color[1], color[2], color[3])
                    row.scbConfirmedTick:Show()
                end
            end
        end
    end
end

local SCB_OriginalCreatePresetUI_Detection = SCB_CreatePresetUI
if SCB_OriginalCreatePresetUI_Detection then
    function SCB_CreatePresetUI(frame)
        local result = SCB_OriginalCreatePresetUI_Detection(frame)
        SCB_RefreshPresetRoleIndicators()
        return result
    end
end

local SCB_OriginalRefreshPresetSlots_Detection = SCB_RefreshPresetSlots
if SCB_OriginalRefreshPresetSlots_Detection then
    function SCB_RefreshPresetSlots()
        local result = SCB_OriginalRefreshPresetSlots_Detection()
        SCB_RefreshPresetRoleIndicators()
        return result
    end
end

local SCB_OriginalRefreshPresetPlayers_Detection = SCB_RefreshPresetPlayers
if SCB_OriginalRefreshPresetPlayers_Detection then
    function SCB_RefreshPresetPlayers()
        local result = SCB_OriginalRefreshPresetPlayers_Detection()
        SCB_RefreshPresetRoleIndicators()
        return result
    end
end

-- -------------------------------------------------------------------------
-- Vanilla combat-text listener
-- -------------------------------------------------------------------------

local detectionFrame = CreateFrame("Frame", "SoloCraftBotsRoleDetectionEventFrame", UIParent)
local SCB_DETECTION_EVENTS = {
    "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF",
    "CHAT_MSG_SPELL_SELF_BUFF",
    "CHAT_MSG_SPELL_PARTY_BUFF",
    "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
    "CHAT_MSG_SPELL_CAST_START",
    "CHAT_MSG_SPELL_CAST_SUCCESS",
    "CHAT_MSG_SPELL_DAMAGE",
    "CHAT_MSG_SPELL_HEAL",
    "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
    "CHAT_MSG_SPELL_PARTY_DAMAGE",
    "CHAT_MSG_COMBAT_PARTY_HITS",
}
local i
for i = 1, table.getn(SCB_DETECTION_EVENTS) do detectionFrame:RegisterEvent(SCB_DETECTION_EVENTS[i]) end

detectionFrame:SetScript("OnEvent", function()
    if arg1 then SCB_HandleRoleCombatText(arg1, event) end
end)