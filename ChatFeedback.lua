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
-- and chat feedback. Vanilla 1.12.1 has no built-in RAID_CLASS_COLORS table.
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

local function SCB_AddedDescription(classKey, role, extra)
    local classInfo, roleInfo, parts, roleCount
    if not classKey then return nil end

    classInfo = SCB_FindClass and SCB_FindClass(classKey) or nil
    roleInfo = SCB_FindRoleEntry and SCB_FindRoleEntry(classInfo, role, extra) or nil
    parts = {}

    if classKey == "paladin" and extra and extra ~= "" then
        table.insert(parts, SCB_ColorExtra("blessing", extra))
    elseif classKey == "mage" then
        if extra == "fire" or (roleInfo and roleInfo.label == SCB_L("ROLE_FIRE")) then
            table.insert(parts, SCB_ColorExtra("fire", SCB_L("ROLE_FIRE")))
        else
            table.insert(parts, SCB_ColorExtra("frost", SCB_L("ROLE_FROST")))
        end
    end

    table.insert(parts, SCB_ColorClass(classKey, classInfo and classInfo.name or tostring(classKey)))

    roleCount = classInfo and classInfo.roles and table.getn(classInfo.roles) or 0
    if classKey ~= "mage" and roleCount > 1 and roleInfo and roleInfo.label then
        table.insert(parts, SCB_ColorRole(role, roleInfo.label))
    end

    return table.concat(parts, " ")
end

local function SCB_PrintAddedRequest(classKey, role, extra)
    local description = SCB_AddedDescription(classKey, role, extra)
    if not description then return end
    SCB_Print(SCB_L("CHAT_ADDED", "Added") .. " "
        .. SCB_ColorText(SCB_ThemeColor("COLOR_SCB", "88CCFF"), "1")
        .. " " .. description)
end

local function SCB_GetFinalSpawnExtra(command)
    local _, _, extra
    if type(command) ~= "string" then return nil end
    _, _, extra = string.find(command, "^add%s+%S+%s+%S+%s*(.*)$")
    if extra == "" then extra = nil end
    return extra
end

-- Manual summon feedback is request feedback: print immediately when the
-- validated command is sent. Preset summons intentionally do not print one line
-- per bot; their single preset summary below is the only normal chat feedback.
function SCB_SpawnOnClick()
    local extra, command, finalExtra
    if not this.scbClass or not this.scbRole then return end

    extra = this.scbExtra
    if this.scbClass == "paladin" then extra = SCB.mainPaladinBlessing or "BoK" end
    command = SCB_BuildSpawnCommand(this.scbClass, this.scbRole, extra)
    finalExtra = SCB_GetFinalSpawnExtra(command)

    if SCB_AllowActiveRosterAdoption then SCB_AllowActiveRosterAdoption() end
    if SCB_SendSpawnCommand(command) then
        SCB_PrintAddedRequest(this.scbClass, this.scbRole, finalExtra)
    end
end

-- Keep preset scheduling untouched; this only provides the agreed compact
-- one-line request summary. Individual preset bot requests stay silent.
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

-- Reuse the existing centre-screen warning frame for summon failures while
-- preserving its normal survivor-safety wording for all existing callers.
local SCB_ChatPreviousShowSafetyMessage = SCB_ShowSafetyMessage
if SCB_ChatPreviousShowSafetyMessage then
    function SCB_ShowSafetyMessage(message)
        if SCB.safetyMessageFrame and SCB.safetyMessageFrame.text then
            SCB.safetyMessageFrame.text:SetText(message or SCB_L("SURVIVOR_MESSAGE"))
        end
        return SCB_ChatPreviousShowSafetyMessage()
    end
end

local SCB_HIDDEN_AURAS = {
    ["Stealth"] = "stealth",
    ["Prowl"] = "prowl",
    ["Shadowmeld"] = "shadowmeld",
    ["Invisibility"] = "invisibility",
    ["Lesser Invisibility"] = "invisibility",
}

local function SCB_GetHiddenAuraKind()
    local tooltip, buffIndex, line, auraName, i

    -- Vanilla 1.12 does not expose player buff names directly. Only inspect
    -- tooltip text after the server has already rejected a summon; there is no
    -- background aura polling or ongoing cost.
    if GetPlayerBuff and GameTooltip then
        tooltip = SCB.hiddenAuraTooltip
        if not tooltip then
            tooltip = CreateFrame("GameTooltip", "SoloCraftBotsHiddenAuraTooltip", UIParent, "GameTooltipTemplate")
            tooltip:SetOwner(UIParent, "ANCHOR_NONE")
            SCB.hiddenAuraTooltip = tooltip
        end

        for i = 0, 31 do
            buffIndex = GetPlayerBuff(i, "HELPFUL")
            if not buffIndex or buffIndex < 0 then break end
            tooltip:ClearLines()
            tooltip:SetPlayerBuff(buffIndex)
            line = getglobal("SoloCraftBotsHiddenAuraTooltipTextLeft1")
            auraName = line and line:GetText() or nil
            if auraName and SCB_HIDDEN_AURAS[auraName] then
                tooltip:Hide()
                return SCB_HIDDEN_AURAS[auraName], auraName
            end
        end
        tooltip:Hide()
    end

    -- Covers stealth-like states even if their tooltip text differs on a fork.
    if IsStealthed and IsStealthed() then return "stealth", nil end
    return nil, nil
end

local function SCB_HandleSpawnServerRejection(text)
    local hadOperation, hiddenKind, auraName, warning
    if text ~= "Cannot add bots right now." then return end

    hadOperation = SCB_HasBotSpawnOperation and SCB_HasBotSpawnOperation() or false
    if hadOperation and SCB_AbortBotSpawnOperations then
        SCB_AbortBotSpawnOperations()
    end

    hiddenKind, auraName = SCB_GetHiddenAuraKind()
    if hiddenKind == "prowl" then
        warning = SCB_L("SUMMON_BLOCKED_PROWL", "Cannot summon bots while prowling.")
    elseif hiddenKind == "shadowmeld" then
        warning = SCB_L("SUMMON_BLOCKED_SHADOWMELD", "Cannot summon bots while Shadowmelded.")
    elseif hiddenKind == "invisibility" then
        warning = SCB_L("SUMMON_BLOCKED_INVISIBILITY", "Cannot summon bots while invisible.")
    elseif hiddenKind == "stealth" then
        warning = SCB_L("SUMMON_BLOCKED_STEALTH", "Cannot summon bots while stealthed.")
    else
        warning = SCB_L("SUMMON_BLOCKED_NOW", "Cannot summon bots right now.")
    end

    if SCB_ShowSafetyMessage then SCB_ShowSafetyMessage(warning) end

    if SCB_DebugLog then
        SCB_DebugLog("Spawn", "Server rejected bot summon; active operation aborted=" .. tostring(hadOperation)
            .. ", hidden=" .. tostring(hiddenKind) .. ", aura=" .. tostring(auraName))
    end
end

local spawnFailureFrame = CreateFrame("Frame", "SoloCraftBotsSpawnFailureFrame", UIParent)
spawnFailureFrame:RegisterEvent("CHAT_MSG_SYSTEM")
spawnFailureFrame:SetScript("OnEvent", function()
    if arg1 then SCB_HandleSpawnServerRejection(arg1) end
end)
