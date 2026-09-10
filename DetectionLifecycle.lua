-- SoloCraft Bots - role-detection event lifecycle.
-- Combat parsing is temporary work: once every SCB-tracked live bot has a
-- confirmed role, unregister the high-volume Vanilla combat-text events.
-- Roster/identity changes re-enable them only when confirmation work exists.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local detectionFrame = getglobal and getglobal("SoloCraftBotsRoleDetectionEventFrame") or nil
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

local function SCB_LiveBotNeedsRoleConfirmation(member)
    local slot
    if not member or not member.isBot or member.spawnKind == "bootstrap" then return false end
    if member.confirmedRole then return false end
    if member.assumedRole then return true end

    if SCB_GetActiveSlotByName and member.name then
        slot = SCB_GetActiveSlotByName(member.name)
        if slot and (slot.assumedRole or slot.role) then
            return slot.confirmedRole == nil
        end
    end
    return false
end

local function SCB_RoleDetectionWorkPending()
    local roster = SCB_GetLiveRoster and SCB_GetLiveRoster(true) or nil
    local i, member
    for i = 1, table.getn(roster and roster.members or {}) do
        member = roster.members[i]
        if SCB_LiveBotNeedsRoleConfirmation(member) then return true end
    end
    return false
end

local function SCB_SetRoleDetectionEventsEnabled(enabled)
    local i
    if not detectionFrame then return end
    enabled = enabled == true
    if SCB.roleDetectionEventsEnabled == enabled then return end

    if enabled then
        for i = 1, table.getn(SCB_DETECTION_EVENTS) do
            detectionFrame:RegisterEvent(SCB_DETECTION_EVENTS[i])
        end
    else
        for i = 1, table.getn(SCB_DETECTION_EVENTS) do
            detectionFrame:UnregisterEvent(SCB_DETECTION_EVENTS[i])
        end
    end
    SCB.roleDetectionEventsEnabled = enabled

    if SCB_DebugLog then
        SCB_DebugLog("Detection", enabled and "Combat role scanning enabled" or "Combat role scanning disabled; all tracked bots confirmed")
    end
end

function SCB_RefreshRoleDetectionLifecycle()
    SCB_SetRoleDetectionEventsEnabled(SCB_RoleDetectionWorkPending())
end

-- Detection.lua initially registers the events before this module loads.
SCB.roleDetectionEventsEnabled = true
SCB_RefreshRoleDetectionLifecycle()

local SCB_PreviousAddBotRoleEvidence_Lifecycle = SCB_AddBotRoleEvidence
if SCB_PreviousAddBotRoleEvidence_Lifecycle then
    function SCB_AddBotRoleEvidence(name, classKey, role, spell, eventName)
        local changed = SCB_PreviousAddBotRoleEvidence_Lifecycle(name, classKey, role, spell, eventName)
        SCB_RefreshRoleDetectionLifecycle()
        return changed
    end
end

local SCB_PreviousHandleRosterChange_Lifecycle = SCB_HandleRosterChange
if SCB_PreviousHandleRosterChange_Lifecycle then
    function SCB_HandleRosterChange()
        local result = SCB_PreviousHandleRosterChange_Lifecycle()
        SCB_RefreshRoleDetectionLifecycle()
        return result
    end
end

local SCB_PreviousHandleAssumedRoleSystemMessage_Lifecycle = SCB_HandleAssumedRoleSystemMessage
if SCB_PreviousHandleAssumedRoleSystemMessage_Lifecycle then
    function SCB_HandleAssumedRoleSystemMessage(text)
        local changed = SCB_PreviousHandleAssumedRoleSystemMessage_Lifecycle(text)
        if changed then SCB_RefreshRoleDetectionLifecycle() end
        return changed
    end
end
