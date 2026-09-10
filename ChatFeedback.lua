-- SoloCraft Bots - user-facing chat feedback and colour formatting.
-- This module is presentation-only: spawn scheduling and identity remain owned
-- by Spawn.lua/RaidIdentity.lua.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local function SCB_NormalizeHex(hex, fallback)
    hex = type(hex) == "string" and string.upper(hex) or fallback
    if not hex or string.len(hex) ~= 6 or string.find(hex, "[^0-9A-F]") then
        return fallback or "FFFFFF"
    end
    return hex
end

function SCB_ColorText(hex, text)
    return "|cff" .. SCB_NormalizeHex(hex, "FFFFFF") .. tostring(text or "") .. "|r"
end

function SCB_ThemeColor(key, fallback)
    return SCB_NormalizeHex(SCB_L(key, fallback), fallback or "FFFFFF")
end

local SCB_CLASS_COLOR_KEYS = {
    WARRIOR = "COLOR_CLASS_WARRIOR",
    PALADIN = "COLOR_CLASS_PALADIN",
    HUNTER = "COLOR_CLASS_HUNTER",
    ROGUE = "COLOR_CLASS_ROGUE",
    PRIEST = "COLOR_CLASS_PRIEST",
    SHAMAN = "COLOR_CLASS_SHAMAN",
    MAGE = "COLOR_CLASS_MAGE",
    WARLOCK = "COLOR_CLASS_WARLOCK",
    DRUID = "COLOR_CLASS_DRUID",
}

local SCB_ROLE_COLOR_KEYS = {
    tank = "COLOR_ROLE_TANK",
    healer = "COLOR_ROLE_HEALER",
    meleedps = "COLOR_ROLE_MELEE",
    rangedps = "COLOR_ROLE_RANGED",
}

-- One authoritative class-colour source for both existing preset player names
-- and new chat feedback. Vanilla 1.12.1 has no built-in RAID_CLASS_COLORS table.
function SCB_ClassColor(classToken)
    local token = classToken and string.upper(classToken) or nil
    local key = token and SCB_CLASS_COLOR_KEYS[token] or nil
    local hex, r, g, b
    if not key then return nil end
    hex = SCB_ThemeColor(key, "FFFFFF")
    r = tonumber(string.sub(hex, 1, 2), 16) or 255
    g = tonumber(string.sub(hex, 3, 4), 16) or 255
    b = tonumber(string.sub(hex, 5, 6), 16) or 255
    return { r = r / 255, g = g / 255, b = b / 255, hex = hex }
end

function SCB_ColorClass(classKey, text)
    local key = classKey and SCB_CLASS_COLOR_KEYS[string.upper(classKey)] or nil
    return SCB_ColorText(key and SCB_ThemeColor(key, "FFFFFF") or "FFFFFF", text)
end

function SCB_ColorRole(role, text)
    local key = role and SCB_ROLE_COLOR_KEYS[role] or nil
    return SCB_ColorText(key and SCB_ThemeColor(key, "FFFFFF") or "FFFFFF", text)
end

function SCB_ColorExtra(extraType, text)
    local key
    if extraType == "blessing" then
        key = "COLOR_EXTRA_BLESSING"
    elseif extraType == "fire" then
        key = "COLOR_EXTRA_FIRE"
    elseif extraType == "frost" then
        key = "COLOR_EXTRA_FROST"
    end
    return SCB_ColorText(key and SCB_ThemeColor(key, "FFFFFF") or "FFFFFF", text)
end

local function SCB_RefreshChatPrefix()
    local raw = SCB_L("CHAT_PREFIX", "[SCB]")
    SCB.prefix = SCB_ColorText(SCB_ThemeColor("COLOR_SCB", "88CCFF"), raw) .. " "
end
SCB_RefreshChatPrefix()

local function SCB_ParseFeedbackCommand(command)
    local _, _, classKey, role, extra
    if type(command) ~= "string" then return nil end
    _, _, classKey, role, extra = string.find(command, "^add%s+(%S+)%s+(%S+)%s*(.*)$")
    if not classKey or not role then return nil end
    if extra == "" then extra = nil end
    return { class = classKey, role = role, extra = extra, command = command, spawnKind = "manual" }
end

local function SCB_AddedDescription(intent)
    local classInfo, roleInfo, parts, roleCount
    if not intent or not intent.class then return nil end

    classInfo = SCB_FindClass and SCB_FindClass(intent.class) or nil
    roleInfo = SCB_FindRoleEntry and SCB_FindRoleEntry(classInfo, intent.role, intent.extra) or nil
    parts = {}

    if intent.class == "paladin" and intent.extra and intent.extra ~= "" then
        table.insert(parts, SCB_ColorExtra("blessing", intent.extra))
    elseif intent.class == "mage" then
        if intent.extra == "fire" or (roleInfo and roleInfo.label == SCB_L("ROLE_FIRE")) then
            table.insert(parts, SCB_ColorExtra("fire", SCB_L("ROLE_FIRE")))
        else
            table.insert(parts, SCB_ColorExtra("frost", SCB_L("ROLE_FROST")))
        end
    end

    table.insert(parts, SCB_ColorClass(intent.class, classInfo and classInfo.name or tostring(intent.class)))

    roleCount = classInfo and classInfo.roles and table.getn(classInfo.roles) or 0
    if intent.class ~= "mage" and roleCount > 1 and roleInfo and roleInfo.label then
        table.insert(parts, SCB_ColorRole(intent.role, roleInfo.label))
    end

    return table.concat(parts, " ")
end

local function SCB_PrintAddedIntent(intent)
    local description
    if not intent or intent.spawnKind == "bootstrap" then return end
    description = SCB_AddedDescription(intent)
    if not description then return end
    SCB_Print(SCB_L("CHAT_ADDED", "Added") .. " "
        .. SCB_ColorText(SCB_ThemeColor("COLOR_SCB", "88CCFF"), "1")
        .. " " .. description)
end

SCB.chatAnnouncedSpawnIntents = SCB.chatAnnouncedSpawnIntents or {}
local function SCB_AnnounceNewBoundIntents()
    local _, intent
    for _, intent in pairs(SCB.assumedRolesByName or {}) do
        if intent and not SCB.chatAnnouncedSpawnIntents[intent] then
            SCB.chatAnnouncedSpawnIntents[intent] = true
            SCB_PrintAddedIntent(intent)
        end
    end
end

SCB.pendingManualChatFeedback = SCB.pendingManualChatFeedback or {}
local SCB_ChatPreviousSendSpawnCommand = SCB_SendSpawnCommand
if SCB_ChatPreviousSendSpawnCommand then
    function SCB_SendSpawnCommand(command)
        local managed = SCB_HasBotSpawnOperation and SCB_HasBotSpawnOperation() or false
        local result = SCB_ChatPreviousSendSpawnCommand(command)
        local intent
        if result and not managed then
            intent = SCB_ParseFeedbackCommand(command)
            if intent then table.insert(SCB.pendingManualChatFeedback, intent) end
        end
        return result
    end
end

local function SCB_ParseJoinedName(text)
    local _, _, name
    if type(text) ~= "string" then return nil end
    _, _, name = string.find(text, "^([^%s]+%*) joins the party%.$")
    if not name then _, _, name = string.find(text, "^([^%s]+%*) has joined the raid group%.?$") end
    return name
end

-- Preserve the explicit identity handler exactly, then add presentation from the
-- identity it bound. The bound-intent scan also covers the existing roster-delta
-- compatibility path without making that fallback part of message semantics.
local SCB_ChatPreviousHandleAssumedRoleSystemMessage = SCB_HandleAssumedRoleSystemMessage
if SCB_ChatPreviousHandleAssumedRoleSystemMessage then
    function SCB_HandleAssumedRoleSystemMessage(text)
        local name = SCB_ParseJoinedName(text)
        local alreadyBound = name and SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil
        local result = SCB_ChatPreviousHandleAssumedRoleSystemMessage(text)

        SCB_AnnounceNewBoundIntents()

        if name and not alreadyBound and not result
            and table.getn(SCB.pendingManualChatFeedback or {}) > 0
            and not (SCB.assumedRolesByName and SCB.assumedRolesByName[name]) then
            SCB_PrintAddedIntent(table.remove(SCB.pendingManualChatFeedback, 1))
        end
        return result
    end
end

-- Replace only the click-time presentation. The authoritative sender still owns
-- command validation and registration; successful feedback waits for the join.
function SCB_SpawnOnClick()
    local extra, command
    if not this.scbClass or not this.scbRole then return end
    extra = this.scbExtra
    if this.scbClass == "paladin" then extra = SCB.mainPaladinBlessing or "BoK" end
    command = SCB_BuildSpawnCommand(this.scbClass, this.scbRole, extra)
    if SCB_AllowActiveRosterAdoption then SCB_AllowActiveRosterAdoption() end
    SCB_SendSpawnCommand(command)
end

-- Keep preset scheduling untouched; this only replaces the old
-- "Summoning Preset ..." start message with the agreed compact summary.
function SCB_PresetSummonOnClick()
    local snapshot, errorText, ok, botCount, botWord

    if IsControlKeyDown and IsControlKeyDown() and SCB_HasBotSpawnOperation and SCB_HasBotSpawnOperation() then
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

    botCount = (snapshot.size or 0) - table.getn(snapshot.players or {})
    if botCount < 0 then botCount = 0 end
    botWord = botCount == 1 and SCB_L("CHAT_BOT_ONE", "bot") or SCB_L("CHAT_BOT_MANY", "bots")
    SCB_Print(string.format(
        SCB_L("CHAT_LOADED_PRESET", "Loaded %s preset with %s %s"),
        tostring(snapshot.presetName or SCB_L("PRESET_PLACEHOLDER", "Preset")),
        SCB_ColorText(SCB_ThemeColor("COLOR_SCB", "88CCFF"), tostring(botCount)),
        botWord
    ))
end

-- RoleTracking's roster-delta compatibility binding can run before the visible
-- membership line on some event orders. Announce any newly-bound exact intent
-- after those roster events as well; intent-table dedupe prevents duplicates.
local chatRosterFrame = CreateFrame("Frame", "SoloCraftBotsChatFeedbackRosterFrame", UIParent)
chatRosterFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
chatRosterFrame:RegisterEvent("RAID_ROSTER_UPDATE")
chatRosterFrame:SetScript("OnEvent", function()
    SCB_AnnounceNewBoundIntents()
end)
