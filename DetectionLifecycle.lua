-- SoloCraft Bots - optional role-detection event lifecycle.
-- Combat confirmation is diagnostic validation, not a core summoner dependency.
-- It defaults off. When enabled, only currently-unconfirmed tracked bots reach
-- the expensive combat detector; once none remain, the combat events unregister.

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

local function SCB_NormalizeDetectionName(name)
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

local function SCB_ExtractDetectionSource(text)
    local i, _, _, name
    if type(text) ~= "string" then return nil end
    for i = 1, table.getn(SCB_COMBAT_SOURCE_PATTERNS) do
        _, _, name = string.find(text, SCB_COMBAT_SOURCE_PATTERNS[i])
        if name and name ~= "" then return name end
    end
    return nil
end

local function SCB_EnsureRoleDetectionOption()
    SoloCraftBotsDB = SoloCraftBotsDB or {}
    SoloCraftBotsDB.options = SoloCraftBotsDB.options or {}
    if SoloCraftBotsDB.options.confirmBotRolesFromCombat == nil then
        SoloCraftBotsDB.options.confirmBotRolesFromCombat = false
    end
    return SoloCraftBotsDB.options.confirmBotRolesFromCombat == true
end

local SCB_PreviousEnsureOptionsDB_Lifecycle = SCB_EnsureOptionsDB
if SCB_PreviousEnsureOptionsDB_Lifecycle then
    function SCB_EnsureOptionsDB()
        SCB_PreviousEnsureOptionsDB_Lifecycle()
        SCB_EnsureRoleDetectionOption()
    end
end

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

local function SCB_RebuildRoleDetectionPendingNames()
    local roster = SCB_GetLiveRoster and SCB_GetLiveRoster(true) or nil
    local pending = {}
    local i, member, key

    for i = 1, table.getn(roster and roster.members or {}) do
        member = roster.members[i]
        if SCB_LiveBotNeedsRoleConfirmation(member) then
            key = SCB_NormalizeDetectionName(member.name)
            if key then pending[key] = true end
        end
    end
    SCB.roleDetectionPendingNames = pending
    return next(pending) ~= nil
end

local function SCB_SetRoleDetectionEventsEnabled(enabled, reason)
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
        SCB_DebugLog("Detection", enabled and "Combat role scanning enabled" or (reason or "Combat role scanning sleeping"))
    end
end

function SCB_RefreshRoleDetectionLifecycle()
    local enabled = SCB_EnsureRoleDetectionOption()
    local pending

    if not enabled then
        SCB.roleDetectionPendingNames = {}
        SCB_SetRoleDetectionEventsEnabled(false, "Combat role scanning disabled by option")
        return
    end

    pending = SCB_RebuildRoleDetectionPendingNames()
    SCB_SetRoleDetectionEventsEnabled(pending, "Combat role scanning sleeping; all tracked bots confirmed")
end

local function SCB_CombatSourceNeedsRoleConfirmation(text)
    local source = SCB_ExtractDetectionSource(text)
    local key = SCB_NormalizeDetectionName(source)
    return key and SCB.roleDetectionPendingNames and SCB.roleDetectionPendingNames[key] == true
end

-- The event frame calls the global handler at runtime. Filter here before the
-- original detector rebuilds/scans the live roster, so combat from confirmed
-- bots, humans and unrelated units is effectively free while confirmation runs.
local SCB_PreviousHandleRoleCombatText_Lifecycle = SCB_HandleRoleCombatText
if SCB_PreviousHandleRoleCombatText_Lifecycle then
    function SCB_HandleRoleCombatText(text, eventName)
        if not SCB_EnsureRoleDetectionOption() then return false end
        if not SCB_CombatSourceNeedsRoleConfirmation(text) then return false end
        return SCB_PreviousHandleRoleCombatText_Lifecycle(text, eventName)
    end
end

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

-- When confirmation is disabled, keep the green assumed-role mark but hide the
-- red/yellow/green combat-confidence mark entirely rather than showing false red.
local SCB_PreviousRefreshPresetRoleIndicators_Lifecycle = SCB_RefreshPresetRoleIndicators
if SCB_PreviousRefreshPresetRoleIndicators_Lifecycle then
    function SCB_RefreshPresetRoleIndicators()
        local result = SCB_PreviousRefreshPresetRoleIndicators_Lifecycle()
        local i, row
        if not SCB_EnsureRoleDetectionOption() then
            for i = 1, 40 do
                row = SCB.presetSlotRows and SCB.presetSlotRows[i] or nil
                if row and row.scbConfirmedTick then row.scbConfirmedTick:Hide() end
            end
        end
        return result
    end
end

-- Options.lua is loaded before this module so the normal generic checkbox
-- machinery can be reused without a parallel settings implementation.
if SoloCraftBotsLocale then
    SoloCraftBotsLocale["OPTION_CONFIRM_BOT_ROLES"] = SoloCraftBotsLocale["OPTION_CONFIRM_BOT_ROLES"] or "Confirm bot roles from combat"
    SoloCraftBotsLocale["OPTION_CONFIRM_BOT_ROLES_TIP"] = SoloCraftBotsLocale["OPTION_CONFIRM_BOT_ROLES_TIP"] or "Validate requested bot roles from combat text. Disabled by default for performance."
end

local SCB_PreviousOptionCheckOnClick_Lifecycle = SCB_OptionCheckOnClick
if SCB_PreviousOptionCheckOnClick_Lifecycle then
    function SCB_OptionCheckOnClick()
        local key = this and this.scbOptionKey or nil
        SCB_PreviousOptionCheckOnClick_Lifecycle()
        if key == "confirmBotRolesFromCombat" then
            SCB_RefreshRoleDetectionLifecycle()
            if SCB_RefreshPresetRoleIndicators then SCB_RefreshPresetRoleIndicators() end
        end
    end
end

local SCB_PreviousRefreshOptionsUI_Lifecycle = SCB_RefreshOptionsUI
if SCB_PreviousRefreshOptionsUI_Lifecycle then
    function SCB_RefreshOptionsUI()
        local result = SCB_PreviousRefreshOptionsUI_Lifecycle()
        SCB_EnsureRoleDetectionOption()
        if SCB.optionConfirmBotRolesCheck then
            SCB.optionConfirmBotRolesCheck:SetChecked(SoloCraftBotsDB.options.confirmBotRolesFromCombat and 1 or nil)
        end
        return result
    end
end

local SCB_PreviousCreateOptionsUI_Lifecycle = SCB_CreateOptionsUI
if SCB_PreviousCreateOptionsUI_Lifecycle then
    function SCB_CreateOptionsUI(frame)
        local result = SCB_PreviousCreateOptionsUI_Lifecycle(frame)
        local content = SCB.optionMiscSection and SCB.optionMiscSection.scbContent or nil
        local check
        if content and SCB_CreateOptionCheck and not SCB.optionConfirmBotRolesCheck then
            check = SCB_CreateOptionCheck(content, "confirmBotRolesFromCombat", "OPTION_CONFIRM_BOT_ROLES", -112)
            check.scbTooltip = SCB_L("OPTION_CONFIRM_BOT_ROLES_TIP")
            check:SetScript("OnEnter", SCB_TooltipOnEnter)
            check:SetScript("OnLeave", SCB_TooltipOnLeave)
            SCB.optionConfirmBotRolesCheck = check
            SCB.optionMiscSection.scbExpandedHeight = 168
            content:SetHeight(142)
        end
        SCB_RefreshOptionsUI()
        if SCB_LayoutOptionsUI then SCB_LayoutOptionsUI() end
        return result
    end
end

-- Detection.lua registered these before all addon files loaded. Apply the
-- default-off/current-option state immediately now that the final wrappers exist.
SCB.roleDetectionEventsEnabled = true
SCB_EnsureRoleDetectionOption()
SCB_RefreshRoleDetectionLifecycle()
