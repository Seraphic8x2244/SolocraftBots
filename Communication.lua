-- SoloCraftBots preset communications for Vanilla WoW 1.12.1.
-- SendAddonMessage has no WHISPER destination in 1.12, so messages are sent
-- through RAID (which falls back to PARTY) and carry their intended target.

local SCB = SoloCraftBots
local COMM_PREFIX = "SCBPRESET"
local COMM_PROTOCOL = 3
local COMM_CHUNK = 190
local COMM_TIMEOUT = 30
local COMM_HANDSHAKE_RETRY = 2

SCB.commOutgoing = SCB.commOutgoing or { S = nil, R = nil }
SCB.commOffers = SCB.commOffers or {}
SCB.commAssemblies = SCB.commAssemblies or {}
SCB.commSequence = SCB.commSequence or 0

local function Now()
    return (GetTime and GetTime()) or 0
end

local function SelfName()
    return (UnitName and UnitName("player")) or ""
end

local function Escape(value)
    value = tostring(value or "")
    return string.gsub(value, "([^%w _%.%-])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local function Unescape(value)
    local decoded = string.gsub(value or "", "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return decoded
end

local function Split(text, separator)
    local result, start = {}, 1
    local first, last
    text = text or ""
    while true do
        first, last = string.find(text, separator, start, true)
        if not first then
            table.insert(result, string.sub(text, start))
            break
        end
        table.insert(result, string.sub(text, start, first - 1))
        start = last + 1
    end
    return result
end

local function SendRaw(message)
    if not SendAddonMessage then return false end
    SendAddonMessage(COMM_PREFIX, message, "RAID")
    return true
end

local function SendControl(kind, tx, target, value)
    return SendRaw(kind .. ":" .. tx .. ":" .. target .. ":" .. (value or ""))
end

local function SerializeSnapshot(snapshot)
    local fields, slots, players = {}, {}, {}
    local i, slot, player, counts
    counts = snapshot.roleCounts or {}
    for i = 1, snapshot.size do
        slot = snapshot.slots[i]
        table.insert(slots, Escape(slot.class) .. "," .. Escape(slot.role) .. "," .. Escape(slot.extra))
    end
    for i = 1, table.getn(snapshot.players or {}) do
        player = snapshot.players[i]
        table.insert(players,
            Escape(player.name) .. ","
            .. Escape(player.group or "") .. ","
            .. Escape(player.slotIndex or "") .. ","
            .. Escape(player.role or "") .. ","
            .. Escape(player.extra or "")
        )
    end
    fields[1] = tostring(COMM_PROTOCOL)
    fields[2] = Escape(snapshot.groupID or "")
    fields[3] = Escape(snapshot.groupName or "")
    fields[4] = tostring(snapshot.size or 0)
    fields[5] = Escape(snapshot.presetName or SCB_L("PRESET_PLACEHOLDER"))
    fields[6] = tostring(counts.tank or 0)
    fields[7] = tostring(counts.healer or 0)
    fields[8] = tostring(counts.meleedps or 0)
    fields[9] = tostring(counts.rangedps or 0)
    fields[10] = table.concat(slots, ";")
    fields[11] = table.concat(players, ";")
    return table.concat(fields, "~")
end

local function DeserializeSnapshot(payload)
    local fields = Split(payload, "~")
    local snapshot, slotItems, playerItems, i, parts
    if table.getn(fields) ~= 11 or tonumber(fields[1]) ~= COMM_PROTOCOL then return nil end
    snapshot = {
        protocol = COMM_PROTOCOL,
        groupID = Unescape(fields[2]),
        groupName = Unescape(fields[3]),
        size = tonumber(fields[4]),
        presetName = Unescape(fields[5]),
        roleCounts = {
            tank = tonumber(fields[6]), healer = tonumber(fields[7]),
            meleedps = tonumber(fields[8]), rangedps = tonumber(fields[9]),
        },
        slots = {}, players = {},
    }
    if snapshot.groupID == "" then snapshot.groupID = nil end
    slotItems = fields[10] ~= "" and Split(fields[10], ";") or {}
    for i = 1, table.getn(slotItems) do
        parts = Split(slotItems[i], ",")
        if table.getn(parts) ~= 3 then return nil end
        snapshot.slots[i] = { class = Unescape(parts[1]), role = Unescape(parts[2]), extra = Unescape(parts[3]) }
        if snapshot.slots[i].extra == "" then snapshot.slots[i].extra = nil end
    end
    playerItems = fields[11] ~= "" and Split(fields[11], ";") or {}
    for i = 1, table.getn(playerItems) do
        parts = Split(playerItems[i], ",")
        if table.getn(parts) ~= 5 then return nil end
        snapshot.players[i] = {
            name = Unescape(parts[1]),
            group = tonumber(Unescape(parts[2])) or 1,
            slotIndex = tonumber(Unescape(parts[3])),
            role = Unescape(parts[4]),
            extra = Unescape(parts[5]),
        }
        if snapshot.players[i].extra == "" then snapshot.players[i].extra = nil end
    end
    return snapshot
end

local function SnapshotHasPlayer(snapshot, name)
    local i
    for i = 1, table.getn(snapshot.players or {}) do
        if snapshot.players[i].name == name then return true end
    end
    return false
end

local function NextTransactionID()
    SCB.commSequence = (SCB.commSequence or 0) + 1
    if SCB.commSequence > 999 then SCB.commSequence = 1 end
    return tostring(math.floor(Now() * 1000)) .. tostring(SCB.commSequence)
end

function SCB_CommsSetButtonPending(mode, pending)
    local button = mode == "S" and SCB.presetSendButton or SCB.presetRequestButton
    if not button or not button.label then return end
    if pending then
        button:Disable()
        button.label:SetText(SCB_L(mode == "S" and "PRESET_SEND_PENDING" or "PRESET_REQUEST_PENDING"))
    else
        button:Enable()
        button.label:SetText(mode == "S" and SCB_L("PRESET_SEND") or SCB_L("PRESET_REQUEST"))
    end
end

local function ClearOutgoing(mode, status)
    local out = SCB.commOutgoing[mode]
    if not out then return end
    SCB.commOutgoing[mode] = nil
    SCB_CommsSetButtonPending(mode, false)
    if status == "SAVED" then
        SCB_Print(string.format(SCB_L("COMM_SAVED"), out.target))
    elseif status == "SUMMONED" then
        SCB_Print(string.format(SCB_L("COMM_SUMMON_ACCEPTED"), out.target))
    elseif status == "REFUSED" then
        SCB_Print(string.format(SCB_L(mode == "S" and "COMM_SEND_REFUSED" or "COMM_REQUEST_REFUSED"), out.target))
    elseif status == "BUSY" then
        SCB_Print(string.format(SCB_L("COMM_TARGET_BUSY"), out.target))
    elseif status == "ERROR" then
        SCB_Print(string.format(SCB_L("COMM_TARGET_ERROR"), out.target))
    elseif status == "TIMEOUT" then
        if not out.handshakeDone then
            SCB_Print(string.format(SCB_L("COMM_TIMEOUT_HANDSHAKE"), out.target))
        elseif not out.acknowledged then
            SCB_Print(string.format(SCB_L("COMM_TIMEOUT_ACK"), out.target))
        else
            SCB_Print(string.format(SCB_L("COMM_TIMEOUT_RESPONSE"), out.target))
        end
    end
end

function SCB_CommsGetRaidRank(name)
    local i, raidName, rank
    if not name or not GetNumRaidMembers or not GetRaidRosterInfo then return nil end
    for i = 1, GetNumRaidMembers() do
        raidName, rank = GetRaidRosterInfo(i)
        if raidName == name then return rank end
    end
    return nil
end

local function BuildChunks(out)
    local payload = SerializeSnapshot(out.snapshot)
    local pos = 1
    out.chunks = {}
    while pos <= string.len(payload) do
        table.insert(out.chunks, string.sub(payload, pos, pos + COMM_CHUNK - 1))
        pos = pos + COMM_CHUNK
    end
    if table.getn(out.chunks) == 0 then table.insert(out.chunks, "") end
    out.nextChunk = 1
    out.chunkElapsed = 0
    out.phase = "sending"
end

local function BeginHandshake(out)
    if not out then return end
    out.phase = "handshake"
    out.handshakeElapsed = COMM_HANDSHAKE_RETRY
    out.handshakeDone = nil
    out.acknowledged = nil
    out.deadline = Now() + COMM_TIMEOUT
end

local function BeginOutgoing(mode, target, snapshot)
    local out
    if not SendAddonMessage then
        SCB_Print(SCB_L("COMM_UNAVAILABLE"))
        return
    end
    if SCB.commOutgoing[mode] then
        SCB_Print(SCB_L(mode == "S" and "COMM_SEND_PENDING" or "COMM_REQUEST_PENDING"))
        return
    end
    if not SnapshotHasPlayer(snapshot, target) then
        SCB_Print(SCB_L("COMM_TARGET_NOT_IN_SNAPSHOT"))
        return
    end

    out = {
        mode = mode, target = target, snapshot = snapshot,
        tx = NextTransactionID(), deadline = Now() + COMM_TIMEOUT,
    }
    SCB.commOutgoing[mode] = out
    if SCB_CommsWakeTimer then SCB_CommsWakeTimer() end
    SCB_CommsSetButtonPending(mode, true)

    -- A preset request no longer requires the requester to pre-build a raid
    -- or pre-promote the receiver. Acceptance owns the leadership handoff so
    -- the receiver can convert to raid and apply its own loot policy itself.
    BeginHandshake(out)
end

function SCB_CommsHideTargetMenu()
    if SCB.commTargetMenu then SCB.commTargetMenu:Hide() end
    SCB.commTargetMode = nil
end

local function CreateTargetMenu()
    local menu
    if SCB.commTargetMenu then return SCB.commTargetMenu end
    menu = CreateFrame("Frame", "SoloCraftBotsCommTargetMenu", UIParent)
    menu:SetWidth(150)
    menu:SetHeight(28)
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    menu:SetBackdropColor(0.03, 0.03, 0.03, 0.98)
    menu:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
    menu:SetFrameStrata("DIALOG")
    menu.buttons = {}
    menu:Hide()
    SCB.commTargetMenu = menu
    return menu
end

function SCB_CommsTargetChoiceOnClick()
    local target = this and this.scbTargetName
    local mode = SCB.commTargetMode
    local snapshot, errorText
    SCB_CommsHideTargetMenu()
    if not target or not mode then return end
    snapshot, errorText = SCB_BuildPresetExecutionSnapshot()
    if not snapshot then SCB_Print(errorText) return end
    BeginOutgoing(mode, target, snapshot)
end

local function OpenTargetMenu(mode)
    local snapshot, errorText = SCB_BuildPresetExecutionSnapshot()
    local roster, menu, button, count, i, info, classInfo, classColor
    if not snapshot then SCB_Print(errorText) return end
    if SCB.commOutgoing[mode] then
        SCB_Print(SCB_L(mode == "S" and "COMM_SEND_PENDING" or "COMM_REQUEST_PENDING"))
        return
    end

    roster = SCB_GetHumanRoster()
    menu = CreateTargetMenu()
    count = 0
    for i = 1, table.getn(roster) do
        info = roster[i]
        if info.name ~= SelfName() then
            count = count + 1
            button = menu.buttons[count]
            if not button then
                button = SCB_CreateTextButton(menu, nil, 142, 20, "")
                button.scbClassIcon = button:CreateTexture(nil, "ARTWORK")
                button.scbClassIcon:SetWidth(16)
                button.scbClassIcon:SetHeight(16)
                button.scbClassIcon:SetPoint("LEFT", button, "LEFT", 4, 0)
                button.label:ClearAllPoints()
                button.label:SetPoint("LEFT", button.scbClassIcon, "RIGHT", 4, 0)
                button.label:SetJustifyH("LEFT")
                button:SetScript("OnClick", SCB_CommsTargetChoiceOnClick)
                menu.buttons[count] = button
            end
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - ((count - 1) * 20))
            classInfo = info.classToken and SCB_FindClass(string.lower(info.classToken)) or nil
            if classInfo and button.scbClassIcon then
                button.scbClassIcon:SetTexture(SCB.assetRoot .. classInfo.icon)
                button.scbClassIcon:Show()
            elseif button.scbClassIcon then
                button.scbClassIcon:Hide()
            end
            classColor = RAID_CLASS_COLORS and info.classToken and RAID_CLASS_COLORS[info.classToken] or nil
            if classColor then
                button.label:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
            else
                button.label:SetTextColor(1, 1, 1, 1)
            end
            button.label:SetText(info.name)
            button.scbTargetName = info.name
            button:Show()
        end
    end
    for i = count + 1, table.getn(menu.buttons) do menu.buttons[i]:Hide() end
    if count == 0 then SCB_CommsHideTargetMenu(); SCB_Print(SCB_L("COMM_NO_TARGET")) return end

    SCB_HidePresetMenus()
    SCB.commTargetMode = mode
    menu:SetHeight(8 + (count * 20))
    menu:ClearAllPoints()
    local anchor = mode == "S" and SCB.presetSendButton or SCB.presetRequestButton
    menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    menu:Show()
    menu:Raise()
end

function SCB_CommsSendOnClick()
    OpenTargetMenu("S")
end

function SCB_CommsRequestOnClick()
    OpenTargetMenu("R")
end

local function CreatePromptUI()
    local frame, title, subtitle, roleBox, i, defs, icon, countText, accept, refuse
    if SCB.commPromptFrame then return SCB.commPromptFrame end
    frame = CreateFrame("Frame", "SoloCraftBotsCommPrompt", UIParent)
    frame:SetWidth(340)
    frame:SetHeight(170)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.98)

    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetWidth(310)
    title:SetPoint("TOP", frame, "TOP", 0, -18)
    title:SetJustifyH("CENTER")
    frame.title = title

    subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetWidth(310)
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -8)
    subtitle:SetJustifyH("CENTER")
    subtitle:SetTextColor(0.82, 0.82, 0.82, 1)
    frame.subtitle = subtitle

    roleBox = CreateFrame("Frame", nil, frame)
    roleBox:SetWidth(190)
    roleBox:SetHeight(34)
    roleBox:SetPoint("TOP", subtitle, "BOTTOM", 0, -10)
    roleBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    roleBox:SetBackdropColor(0.02, 0.02, 0.02, 0.45)
    roleBox:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)
    frame.roleCounts = {}
    defs = {
        { key = "tank", icon = "tank.tga" },
        { key = "healer", icon = "healer.tga" },
        { key = "meleedps", icon = "melee.tga" },
        { key = "rangedps", icon = "ranged.tga" },
    }
    for i = 1, 4 do
        icon = roleBox:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(24); icon:SetHeight(24)
        icon:SetPoint("LEFT", roleBox, "LEFT", 7 + ((i - 1) * 44), 0)
        icon:SetTexture(SCB.assetRoot .. defs[i].icon)
        countText = roleBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countText:SetWidth(14)
        countText:SetPoint("LEFT", icon, "RIGHT", 2, 0)
        countText:SetJustifyH("CENTER")
        frame.roleCounts[defs[i].key] = countText
    end

    accept = SCB_CreateTextButton(frame, nil, 112, 24, SCB_L("BUTTON_SAVE"))
    accept:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -5, 18)
    accept:SetScript("OnClick", function() SCB_CommsPromptAccept() end)
    frame.accept = accept
    refuse = SCB_CreateTextButton(frame, nil, 112, 24, SCB_L("BUTTON_REFUSE"))
    refuse:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 5, 18)
    refuse:SetScript("OnClick", function() SCB_CommsPromptRefuse() end)
    frame.refuse = refuse
    frame:Hide()
    SCB.commPromptFrame = frame
    return frame
end

function SCB_CommsShowPrompt(incoming)
    local frame = CreatePromptUI()
    local snapshot = incoming.snapshot
    local counts = snapshot.roleCounts or {}
    SCB.commPromptTransaction = incoming
    if SCB_CommsWakeTimer then SCB_CommsWakeTimer() end
    if incoming.mode == "S" then
        frame.title:SetText(string.format(SCB_L("COMM_PROMPT_SEND"), incoming.sender))
        frame.accept.label:SetText(SCB_L("BUTTON_SAVE"))
    else
        frame.title:SetText(string.format(SCB_L("COMM_PROMPT_REQUEST"), incoming.sender))
        frame.accept.label:SetText(SCB_L("BUTTON_SUMMON_PRESET"))
    end
    frame.subtitle:SetText(string.format(SCB_L("COMM_PROMPT_SUBTITLE"), snapshot.groupName or SCB_L("PRESET_GROUP_PLACEHOLDER"), snapshot.presetName or SCB_L("PRESET_PLACEHOLDER")))
    frame.roleCounts.tank:SetText(tostring(counts.tank or 0))
    frame.roleCounts.healer:SetText(tostring(counts.healer or 0))
    frame.roleCounts.meleedps:SetText(tostring(counts.meleedps or 0))
    frame.roleCounts.rangedps:SetText(tostring(counts.rangedps or 0))
    frame:Show()
    frame:Raise()
end

local function FinishIncoming(incoming, status)
    if not incoming or incoming.done then return end
    incoming.done = true
    SendControl("R", incoming.tx, incoming.sender, status)
    if SCB.commPromptTransaction == incoming then
        SCB.commPromptTransaction = nil
        if SCB.commPromptFrame then SCB.commPromptFrame:Hide() end
    end
    if SCB.pendingReceivedSave == incoming then
        SCB.pendingReceivedSave = nil
        if StaticPopup_Hide then StaticPopup_Hide("SOLOCRAFTBOTS_RECEIVED_PRESET_NAME") end
    end
end

local function FindOrCreateSnapshotGroup(snapshot)
    local i, group
    SCB_EnsurePresetDB()
    if snapshot.groupID then
        for i = 1, table.getn(SoloCraftBotsDB.presetGroups) do
            group = SoloCraftBotsDB.presetGroups[i]
            if group.id == snapshot.groupID then
                if group.size ~= snapshot.size then return nil end
                return group
            end
        end
        return nil
    end
    for i = 1, table.getn(SoloCraftBotsDB.presetGroups) do
        group = SoloCraftBotsDB.presetGroups[i]
        if not group.isDefault and group.name == snapshot.groupName and group.size == snapshot.size then return group end
    end
    group = {
        name = snapshot.groupName, size = snapshot.size, isDefault = false,
        presets = {}, currentPreset = nil,
    }
    table.insert(SoloCraftBotsDB.presetGroups, group)
    return group
end

local function SaveIncomingSnapshot(incoming, name)
    local snapshot = incoming.snapshot
    local group = FindOrCreateSnapshotGroup(snapshot)
    local playerGroups, playerSlots, playerRoles = {}, {}, {}
    local i, player, key, preset
    if not group then return false end
    for i = 1, table.getn(snapshot.players or {}) do
        player = snapshot.players[i]
        key = player.name == SelfName() and "$self" or player.name
        playerGroups[key] = player.group or 1
        if player.slotIndex then playerSlots[key] = player.slotIndex end
        playerRoles[key] = { role = player.role, extra = player.extra }
    end
    preset = {
        name = name,
        slots = SCB_CopySlots(snapshot.slots),
        playerGroups = playerGroups,
        playerSlots = playerSlots,
        playerRoles = playerRoles,
    }
    table.insert(group.presets, preset)
    if not group.currentPreset then group.currentPreset = table.getn(group.presets) end
    return true
end

local function PopupEditBox(dialog)
    if dialog and dialog.editBox then return dialog.editBox end
    if dialog and dialog.GetName then return getglobal(dialog:GetName() .. "EditBox") end
    return nil
end

function SCB_CommsAcceptReceivedPresetName(dialog)
    local incoming = SCB.pendingReceivedSave
    local editBox = PopupEditBox(dialog)
    local name = editBox and editBox:GetText() or ""
    if not incoming or incoming.done then return end
    if not name or name == "" then name = incoming.defaultSaveName end
    if not SaveIncomingSnapshot(incoming, name) then
        SCB_Print(SCB_L("COMM_GROUP_MATCH_ERROR"))
        FinishIncoming(incoming, "ERROR")
        return
    end
    SCB_Print(string.format(SCB_L("COMM_SAVED_AS"), name))
    FinishIncoming(incoming, "SAVED")
end

StaticPopupDialogs["SOLOCRAFTBOTS_RECEIVED_PRESET_NAME"] = {
    text = SCB_L("COMM_SAVE_RECEIVED_AS"),
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 48,
    OnAccept = function() SCB_CommsAcceptReceivedPresetName(this) end,
    OnCancel = function()
        local incoming = SCB.pendingReceivedSave
        SCB.pendingReceivedSave = nil
        if incoming and not incoming.done then SCB_CommsShowPrompt(incoming) end
    end,
    OnShow = function()
        local editBox = PopupEditBox(this)
        local incoming = SCB.pendingReceivedSave
        if editBox then
            editBox:SetText(incoming and incoming.defaultSaveName or SCB_L("PRESET_PLACEHOLDER"))
            editBox:HighlightText(); editBox:SetFocus()
        end
    end,
    EditBoxOnEnterPressed = function()
        local editBox = this
        local dialog = editBox and editBox.GetParent and editBox:GetParent() or nil
        SCB_CommsAcceptReceivedPresetName(dialog)
        if dialog and dialog.Hide then dialog:Hide() end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
}

local function SCB_CommsStartAcceptedRequest(incoming)
    local ok, errorText, raidCount, partyCount
    if not incoming or incoming.done or incoming.mode ~= "R" then return false end

    if not SCB_IsLocalGroupLeader or not SCB_IsLocalGroupLeader() then
        return false
    end

    raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    partyCount = (GetNumPartyMembers and GetNumPartyMembers()) or 0

    if (incoming.snapshot.size or 0) > 5 and raidCount == 0 then
        if partyCount <= 0 or not ConvertToRaid then
            SCB_Print(SCB_L("COMM_REQUEST_CONVERT_FAILED"))
            FinishIncoming(incoming, "ERROR")
            return false
        end
        incoming.phase = "converting"
        incoming.deadline = Now() + COMM_TIMEOUT
        ConvertToRaid()
        if SCB_CommsWakeTimer then SCB_CommsWakeTimer() end
        return true
    end

    if SCB_ApplyAutoLootMethod then SCB_ApplyAutoLootMethod() end
    if SCB_QueueAutoLootApply then SCB_QueueAutoLootApply() end

    ok, errorText = SCB_StartPresetRebuild(incoming.snapshot, false)
    if not ok then
        if errorText then SCB_Print(errorText) end
        FinishIncoming(incoming, "ERROR")
        return false
    end
    FinishIncoming(incoming, "SUMMONED")
    return true
end

function SCB_CommsPromptAccept()
    local incoming = SCB.commPromptTransaction
    local ok, errorText
    if not incoming or incoming.done then return end
    if incoming.mode == "S" then
        incoming.defaultSaveName = incoming.sender .. "-" .. (incoming.snapshot.presetName or "Preset")
        SCB.pendingReceivedSave = incoming
        if SCB.commPromptFrame then SCB.commPromptFrame:Hide() end
        StaticPopup_Show("SOLOCRAFTBOTS_RECEIVED_PRESET_NAME")
        return
    end

    ok, errorText = SCB_ValidatePresetExecutionSnapshot(incoming.snapshot, true)
    if not ok then
        SCB_Print(errorText)
        FinishIncoming(incoming, "ERROR")
        return
    end
    incoming.requestAccepted = true
    incoming.deadline = Now() + COMM_TIMEOUT
    if SCB.commPromptFrame then SCB.commPromptFrame:Hide() end

    if SCB_IsLocalGroupLeader and SCB_IsLocalGroupLeader() then
        SCB_CommsStartAcceptedRequest(incoming)
        return
    end

    incoming.phase = "await-leader"
    if not SendControl("L", incoming.tx, incoming.sender, "REQUEST") then
        SCB_Print(SCB_L("COMM_REQUEST_LEADER_FAILED"))
        FinishIncoming(incoming, "ERROR")
        return
    end
    SCB_Print(SCB_L("COMM_REQUEST_WAIT_LEADER"))
    if SCB_CommsWakeTimer then SCB_CommsWakeTimer() end
end

function SCB_CommsPromptRefuse()
    local incoming = SCB.commPromptTransaction
    if incoming then FinishIncoming(incoming, "REFUSED") end
end

local function CompleteAssembly(assembly)
    local payload, snapshot, valid, errorText
    local i
    payload = ""
    for i = 1, assembly.total do
        if not assembly.chunks[i] then return end
        payload = payload .. assembly.chunks[i]
    end
    snapshot = DeserializeSnapshot(payload)
    if not snapshot then
        SendControl("R", assembly.tx, assembly.sender, "ERROR")
        return
    end
    valid, errorText = SCB_ValidatePresetExecutionSnapshot(snapshot, false)
    if not valid or not SnapshotHasPlayer(snapshot, assembly.sender) or not SnapshotHasPlayer(snapshot, SelfName()) then
        SendControl("R", assembly.tx, assembly.sender, "ERROR")
        return
    end
    SendControl("A", assembly.tx, assembly.sender, "RECEIVED")
    if SCB.commPromptTransaction and not SCB.commPromptTransaction.done then
        SendControl("R", assembly.tx, assembly.sender, "BUSY")
        return
    end
    assembly.snapshot = snapshot
    assembly.deadline = Now() + COMM_TIMEOUT
    SCB_CommsShowPrompt(assembly)
end

function SCB_CommsOnAddonMessage(prefix, message, channel, sender)
    local parts, kind, tx, target, mode, seq, total, chunk, key, assembly, out, offer
    local offerMode, offerProtocol, outgoingMode
    if prefix ~= COMM_PREFIX or not message or not sender then return end
    if channel ~= "RAID" and channel ~= "PARTY" then return end

    parts = Split(message, ":")
    kind = parts[1]
    tx = parts[2]
    target = parts[3]
    if not tx or target ~= SelfName() then return end

    if kind == "O" and table.getn(parts) == 4 then
        local _, _, parsedMode, parsedProtocol = string.find(parts[4] or "", "^([SR])(%d+)$")
        offerMode = parsedMode
        offerProtocol = tonumber(parsedProtocol)
        if not offerMode or offerProtocol ~= COMM_PROTOCOL then
            SendControl("R", tx, sender, "ERROR")
            return
        end
        key = sender .. "|" .. tx
        SCB.commOffers[key] = {
            sender = sender, tx = tx, mode = offerMode,
            deadline = Now() + COMM_TIMEOUT,
        }
        if SCB_CommsWakeTimer then SCB_CommsWakeTimer() end
        SendControl("H", tx, sender, "READY")
        return
    end

    if kind == "H" and table.getn(parts) == 4 and parts[4] == "READY" then
        for outgoingMode, out in pairs(SCB.commOutgoing) do
            if out and out.tx == tx and out.target == sender and out.phase == "handshake" then
                out.handshakeDone = true
                out.deadline = Now() + COMM_TIMEOUT
                SCB_Print(string.format(SCB_L("COMM_HANDSHAKE_SUCCESS"), out.target))
                BuildChunks(out)
                return
            end
        end
        return
    end

    if kind == "C" then
        if table.getn(parts) ~= 7 then return end
        mode = parts[4]
        seq = tonumber(parts[5]); total = tonumber(parts[6]); chunk = parts[7]
        if (mode ~= "S" and mode ~= "R") or not seq or not total or total < 1 or total > 50 or seq < 1 or seq > total then return end
        key = sender .. "|" .. tx
        offer = SCB.commOffers[key]
        if not offer or offer.mode ~= mode then return end
        assembly = SCB.commAssemblies[key]
        if not assembly then
            assembly = { sender = sender, tx = tx, mode = mode, total = total, chunks = {}, received = 0, deadline = Now() + COMM_TIMEOUT }
            SCB.commAssemblies[key] = assembly
        elseif assembly.mode ~= mode or assembly.total ~= total then
            SCB.commAssemblies[key] = nil
            return
        end
        if not assembly.chunks[seq] then
            assembly.chunks[seq] = chunk
            assembly.received = assembly.received + 1
        end
        assembly.deadline = Now() + COMM_TIMEOUT
        if assembly.received == assembly.total then
            SCB.commAssemblies[key] = nil
            SCB.commOffers[key] = nil
            CompleteAssembly(assembly)
        end
        return
    end

    if kind == "A" and table.getn(parts) == 4 then
        for mode, out in pairs(SCB.commOutgoing) do
            if out and out.tx == tx and out.target == sender then
                if not out.acknowledged then
                    SCB_Print(string.format(SCB_L("COMM_DATA_RECEIVED"), out.target))
                end
                out.acknowledged = true
                out.deadline = Now() + COMM_TIMEOUT
            end
        end
        return
    end

    if kind == "L" and table.getn(parts) == 4 then
        if parts[4] == "REQUEST" then
            for mode, out in pairs(SCB.commOutgoing) do
                if mode == "R" and out and out.tx == tx and out.target == sender then
                    if SCB_IsLocalGroupLeader and SCB_IsLocalGroupLeader() and PromoteToLeader then
                        PromoteToLeader(sender)
                        out.deadline = Now() + COMM_TIMEOUT
                        SendControl("L", tx, sender, "PROMOTED")
                    else
                        SendControl("L", tx, sender, "ERROR")
                    end
                    return
                end
            end
            SendControl("L", tx, sender, "ERROR")
            return
        end

        local incoming = SCB.commPromptTransaction
        if incoming and not incoming.done and incoming.tx == tx and incoming.sender == sender
            and incoming.mode == "R" and incoming.requestAccepted then
            incoming.deadline = Now() + COMM_TIMEOUT
            if parts[4] == "ERROR" then
                SCB_Print(SCB_L("COMM_REQUEST_LEADER_FAILED"))
                FinishIncoming(incoming, "ERROR")
            end
            return
        end
    end

    if kind == "R" and table.getn(parts) == 4 then
        for mode, out in pairs(SCB.commOutgoing) do
            if out and out.tx == tx and out.target == sender then
                ClearOutgoing(mode, parts[4])
                return
            end
        end
    end
end

local commFrame = CreateFrame("Frame", "SoloCraftBotsCommsFrame", UIParent)
commFrame:RegisterEvent("CHAT_MSG_ADDON")

local function SCB_CommsHasTimedWork()
    local _, value
    for _, value in pairs(SCB.commOutgoing or {}) do if value then return true end end
    if next(SCB.commOffers or {}) then return true end
    if next(SCB.commAssemblies or {}) then return true end
    if SCB.commPromptTransaction and not SCB.commPromptTransaction.done then return true end
    return false
end

function SCB_CommsWakeTimer()
    commFrame:Show()
end

commFrame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" then SCB_CommsOnAddonMessage(arg1, arg2, arg3, arg4) end
end)
commFrame:SetScript("OnUpdate", function()
    local elapsed = arg1 or 0
    local now = Now()
    local mode, out, packet, key, assembly, incoming, offer

    for mode, out in pairs(SCB.commOutgoing) do
        if out then
            if now >= out.deadline then
                ClearOutgoing(mode, "TIMEOUT")
            elseif out.phase == "handshake" then
                out.handshakeElapsed = (out.handshakeElapsed or 0) + elapsed
                if out.handshakeElapsed >= COMM_HANDSHAKE_RETRY then
                    out.handshakeElapsed = 0
                    SendControl("O", out.tx, out.target, out.mode .. COMM_PROTOCOL)
                end
            elseif out.phase == "sending" then
                out.chunkElapsed = (out.chunkElapsed or 0) + elapsed
                if out.chunkElapsed >= 0.08 and out.nextChunk <= table.getn(out.chunks) then
                    out.chunkElapsed = 0
                    packet = "C:" .. out.tx .. ":" .. out.target .. ":" .. out.mode .. ":" .. out.nextChunk .. ":" .. table.getn(out.chunks) .. ":" .. out.chunks[out.nextChunk]
                    SendRaw(packet)
                    out.nextChunk = out.nextChunk + 1
                    if out.nextChunk > table.getn(out.chunks) then out.phase = "waiting" end
                end
            end
        end
    end

    for key, offer in pairs(SCB.commOffers) do
        if now >= offer.deadline then SCB.commOffers[key] = nil end
    end

    for key, assembly in pairs(SCB.commAssemblies) do
        if now >= assembly.deadline then SCB.commAssemblies[key] = nil end
    end

    incoming = SCB.commPromptTransaction
    if incoming and not incoming.done then
        if now >= incoming.deadline then
            FinishIncoming(incoming, "TIMEOUT")
        elseif incoming.mode == "R" and incoming.requestAccepted then
            if incoming.phase == "await-leader"
                and SCB_IsLocalGroupLeader and SCB_IsLocalGroupLeader() then
                SCB_CommsStartAcceptedRequest(incoming)
            elseif incoming.phase == "converting"
                and GetNumRaidMembers and GetNumRaidMembers() > 0
                and SCB_IsLocalGroupLeader and SCB_IsLocalGroupLeader() then
                SCB_CommsStartAcceptedRequest(incoming)
            end
        end
    end

    if not SCB_CommsHasTimedWork() then commFrame:Hide() end
end)
commFrame:Hide()

-- -------------------------------------------------------------------------
-- Direct bot commands (absorbed from Commands.lua in 0.8.33).
-- Scoped to preserve the former file's local namespace.
-- -------------------------------------------------------------------------

do
-- SoloCraft Bots - Direct commands and raid marks
-- Loaded after SoloCraftBots.lua; intentionally behavior-preserving.

local SCB = SoloCraftBots

-- -------------------------------------------------------------------------
-- Direct command matrix
-- -------------------------------------------------------------------------

SCB.recipients = {
    { key = "all", label = SCB_L("RECIPIENT_ALL"), icon = "all.tga", highlightIcon = "all_h.tga" },
    { key = "group", label = SCB_L("RECIPIENT_GROUP"), icon = "all.tga", highlightIcon = "all_h.tga" },
    { key = "target", label = SCB_L("RECIPIENT_ONE"), icon = "one.tga", highlightIcon = "one_h.tga" },
    { key = "tank", label = SCB_L("RECIPIENT_TANKS"), icon = "tank.tga", highlightIcon = "tank_h.tga" },
    { key = "melee", label = SCB_L("RECIPIENT_MELEE"), icon = "melee.tga", highlightIcon = "melee_h.tga" },
    { key = "ranged", label = SCB_L("RECIPIENT_RANGED"), icon = "ranged.tga", highlightIcon = "ranged_h.tga" },
    { key = "healer", label = SCB_L("RECIPIENT_HEALERS"), icon = "healer.tga", highlightIcon = "healer_h.tga" },
}

SCB.commandOrder = {
    "play", "move", "stay", "pause",
    "pull", "spread", "hug", "object", "aoe", "attackstart", "attackstop",
}

SCB.commandTargetSemantics = {
    agnostic = "target-agnostic",
    friendlyBot = "friendly-bot-recipient",
    livingEnemy = "living-enemy-context",
    conditional = "conditional-friendly-player-or-bot",
}

SCB.commands = {
    play = {
        label = SCB_L("COMMAND_PLAY"),
        icon = "unpause.tga",
        highlightIcon = "unpause_h.tga",
        targetSemantic = SCB.commandTargetSemantics.agnostic,
        targetSemanticByScope = {
            all = SCB.commandTargetSemantics.conditional,
            group = SCB.commandTargetSemantics.friendlyBot,
            target = SCB.commandTargetSemantics.friendlyBot,
        },
        routes = {
            all = { "unpause all" },
            target = { "unpause" },
        },
    },
    move = {
        label = SCB_L("COMMAND_MOVE"),
        icon = "move.tga",
        highlightIcon = "move_h.tga",
        targetSemantic = SCB.commandTargetSemantics.agnostic,
        targetSemanticByScope = {
            group = SCB.commandTargetSemantics.friendlyBot,
            target = SCB.commandTargetSemantics.friendlyBot,
        },
        routes = {
            all = { "moveall" },
            target = { "move" },
            tank = { "movetank" },
            healer = { "moveheal" },
            melee = { "movemelee" },
            ranged = { "moverange" },
            tankmelee = { "movetank", "movemelee" },
            meleeranged = { "movemelee", "moverange" },
            rangedhealer = { "moverange", "moveheal" },
        },
    },
    come = {
        label = SCB_L("COMMAND_COME"),
        icon = "come.tga",
        highlightIcon = "come_h.tga",
        targetSemantic = SCB.commandTargetSemantics.agnostic,
        targetSemanticByScope = {
            all = SCB.commandTargetSemantics.conditional,
            group = SCB.commandTargetSemantics.friendlyBot,
            target = SCB.commandTargetSemantics.friendlyBot,
        },
        routes = {
            all = { "cometome" },
            target = { "come" },
            tank = { "cometank" },
            healer = { "comeheal" },
            melee = { "comemelee" },
            ranged = { "comerange" },
            tankmelee = { "cometank", "comemelee" },
            meleeranged = { "comemelee", "comerange" },
            rangedhealer = { "comerange", "comeheal" },
        },
    },
    stay = {
        label = SCB_L("COMMAND_STAY"),
        icon = "stay.tga",
        highlightIcon = "stay_h.tga",
        targetSemantic = SCB.commandTargetSemantics.agnostic,
        targetSemanticByScope = {
            group = SCB.commandTargetSemantics.friendlyBot,
            target = SCB.commandTargetSemantics.friendlyBot,
        },
        routes = {
            all = { "stayall" },
            target = { "stay" },
            tank = { "staytank" },
            healer = { "stayheal" },
            melee = { "staymelee" },
            ranged = { "stayrange" },
        },
    },
    pause = {
        label = SCB_L("COMMAND_PAUSE"),
        icon = "pause.tga",
        highlightIcon = "pause_h.tga",
        targetSemantic = SCB.commandTargetSemantics.agnostic,
        targetSemanticByScope = {
            all = SCB.commandTargetSemantics.conditional,
            group = SCB.commandTargetSemantics.friendlyBot,
            target = SCB.commandTargetSemantics.friendlyBot,
        },
        routes = {
            all = { "pause all" },
            target = { "pause" },
        },
    },
    pull = {
        label = SCB_L("COMMAND_PULL"),
        icon = "pull.tga",
        highlightIcon = "pull_h.tga",
        targetSemantic = SCB.commandTargetSemantics.agnostic,
        routes = { tank = { "pull" } },
    },
    spread = {
        label = SCB_L("COMMAND_SPREAD"),
        icon = "spread.tga",
        highlightIcon = "spread_h.tga",
        targetSemantic = SCB.commandTargetSemantics.agnostic,
        routes = { ranged = { "spread" } },
    },
    hug = {
        label = SCB_L("COMMAND_HUG"),
        icon = "unspread.tga",
        highlightIcon = "unspread_h.tga",
        targetSemantic = SCB.commandTargetSemantics.agnostic,
        routes = { ranged = { "spreadoff" } },
    },
    spreadtoggle = {
        label = SCB_L("COMMAND_SPREAD"),
        icon = "spread.tga",
        highlightIcon = "spread_h.tga",
        targetSemantic = SCB.commandTargetSemantics.agnostic,
        routes = { ranged = { "spread" } },
    },
    object = {
        label = SCB_L("COMMAND_OBJECT"),
        icon = "object.tga",
        highlightIcon = "object_h.tga",
        targetSemantic = SCB.commandTargetSemantics.agnostic,
        routes = { all = { "usegobject" } },
    },
    aoe = {
        label = SCB_L("COMMAND_AOE"),
        icon = "aoe.tga",
        highlightIcon = "aoe_h.tga",
        targetSemantic = SCB.commandTargetSemantics.livingEnemy,
        routes = { all = { "aoe" } },
    },
    attackstart = {
        label = SCB_L("COMMAND_ATTACK_START"),
        icon = "attackstart.tga",
        highlightIcon = "attackstart_h.tga",
        targetSemantic = SCB.commandTargetSemantics.livingEnemy,
        routes = { all = { "attackstart" } },
    },
    attackstop = {
        label = SCB_L("COMMAND_ATTACK_STOP"),
        icon = "attackstop.tga",
        highlightIcon = "attackstop_h.tga",
        targetSemantic = SCB.commandTargetSemantics.livingEnemy,
        routes = { all = { "attackstop" } },
    },
}

function SCB_IsFriendlyBotTarget()
    local name
    if not UnitExists or not UnitExists("target") then
        return false
    end
    if UnitIsFriend and UnitIsFriend("player", "target") ~= 1 then
        return false
    end
    name = UnitName and UnitName("target")
    if not name or string.sub(name, -1) ~= "*" then
        return false
    end
    return true
end

local function SCB_IsFriendlyPlayerOrBotTarget()
    if not UnitExists or not UnitExists("target") then return false end
    if UnitIsFriend and UnitIsFriend("player", "target") ~= 1 then return false end
    if SCB_IsFriendlyBotTarget() then return true end
    if UnitIsPlayer and UnitIsPlayer("target") then return true end
    return false
end

local function SCB_IsLivingEnemyTarget()
    if not UnitExists or not UnitExists("target") then return false end
    if UnitCanAttack then
        if UnitCanAttack("player", "target") ~= 1 then return false end
    elseif UnitIsFriend and UnitIsFriend("player", "target") == 1 then
        return false
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("target") then return false end
    if UnitIsDead and UnitIsDead("target") then return false end
    if UnitHealth and UnitHealth("target") <= 0 then return false end
    return true
end

local function SCB_ShowTargetedCommandError(key)
    local text = SCB_L(key)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(text, 1.0, 0.1, 0.1, 1.0)
    else
        SCB_Print(text)
    end
end

local function SCB_ShowTargetedBusyError()
    local state = SCB.targetedCommandState
    if state and state.mode == "group" then
        SCB_ShowTargetedCommandError("TARGETED_BUSY_GROUP")
    else
        SCB_ShowTargetedCommandError("TARGETED_BUSY_SINGLE")
    end
end

local function SCB_ShowInvalidTargetError()
    if not UnitExists or not UnitExists("target") then
        SCB_ShowTargetedCommandError("TARGETED_NO_TARGET")
        return
    end
    if UnitIsFriend and UnitIsFriend("player", "target") == 1 then
        SCB_ShowTargetedCommandError("TARGETED_HUMAN_TARGET")
        return
    end
    SCB_ShowTargetedCommandError("TARGETED_NO_TARGET")
end

function SCB_GetTargetLiveGroup(refresh)
    local name, roster, member
    if not SCB_IsFriendlyBotTarget() then return nil, nil end

    name = UnitName and UnitName("target") or nil
    if not name then return nil, nil end

    roster = SCB_GetLiveRoster and SCB_GetLiveRoster(refresh and true or false) or nil
    member = roster and roster.byName and roster.byName[name] or nil
    if not member or not member.isBot then return nil, roster end
    return member.currentGroup or member.subgroup or 1, roster
end

local function SCB_GetGroupScopedBots(group, roster)
    local bots = {}
    local i, member
    for i = 1, table.getn(roster and roster.members or {}) do
        member = roster.members[i]
        if member and member.isBot and member.name
            and (member.currentGroup or member.subgroup or 1) == group then
            table.insert(bots, member.name)
        end
    end
    return bots
end

local function SCB_GetCommandRoute(commandKey, scope)
    local commandInfo = SCB.commands and SCB.commands[commandKey] or nil
    local routeScope = scope
    if not commandInfo then return nil, nil end
    if scope == "group" then routeScope = "target" end
    return commandInfo, commandInfo.routes and commandInfo.routes[routeScope] or nil
end

local function SCB_GetCommandTargetSemantic(commandKey, scope)
    local commandInfo = SCB.commands and SCB.commands[commandKey] or nil
    if not commandInfo then return nil end
    if commandInfo.targetSemanticByScope and commandInfo.targetSemanticByScope[scope] then
        return commandInfo.targetSemanticByScope[scope]
    end
    return commandInfo.targetSemantic or SCB.commandTargetSemantics.agnostic
end

local function SCB_IsCommandTargetContextValid(commandKey, scope)
    local semantic = SCB_GetCommandTargetSemantic(commandKey, scope)
    if semantic == SCB.commandTargetSemantics.friendlyBot then
        return SCB_IsFriendlyBotTarget()
    elseif semantic == SCB.commandTargetSemantics.livingEnemy then
        return SCB_IsLivingEnemyTarget()
    elseif semantic == SCB.commandTargetSemantics.conditional then
        return not SCB_IsFriendlyPlayerOrBotTarget()
    end
    return semantic == SCB.commandTargetSemantics.agnostic
end

function SCB_IsCommandRequestAvailable(commandKey, scope)
    local commandInfo, route = SCB_GetCommandRoute(commandKey, scope)
    local group, roster
    if not commandInfo or not route or not SCB_IsCommandTargetContextValid(commandKey, scope) then
        return false
    end
    if scope == "group" then
        group, roster = SCB_GetTargetLiveGroup()
        return group ~= nil and table.getn(SCB_GetGroupScopedBots(group, roster)) > 0
    end
    return true
end

local SCB_TARGETED_TARGET_SETTLE = 0.10
local SCB_TARGETED_BUDGET_POLL = 0.05
local SCB_TARGETED_COMMAND_LIMIT = 24
local SCB_TARGETED_COMMAND_WINDOW = 1.0

local function SCB_PruneTargetedCommandHistory(now)
    local history = SCB.targetedCommandSendTimes or {}
    local kept = {}
    local i, sentAt
    for i = 1, table.getn(history) do
        sentAt = history[i]
        if sentAt and (now - sentAt) < SCB_TARGETED_COMMAND_WINDOW then
            table.insert(kept, sentAt)
        end
    end
    SCB.targetedCommandSendTimes = kept
    return kept
end

local function SCB_TargetedCommandBudgetAllows(required)
    local now = GetTime and GetTime() or 0
    local history = SCB_PruneTargetedCommandHistory(now)
    return table.getn(history) + (required or 0) <= SCB_TARGETED_COMMAND_LIMIT
end

local function SCB_RecordTargetedCommandSend()
    local now = GetTime and GetTime() or 0
    local history = SCB_PruneTargetedCommandHistory(now)
    table.insert(history, now)
end

local function SCB_TargetedAckKindForCommand(command)
    if command == "move" then return "move" end
    if command == "come" then return "come" end
    if command == "stay" then return "stay" end
    if command == "pause" then return "pause" end
    if command == "unpause" then return "unpause" end
    return nil
end

local function SCB_BuildTargetedExpectedAcks(commands)
    local expected = {}
    local count = 0
    local i, kind
    for i = 1, table.getn(commands or {}) do
        kind = SCB_TargetedAckKindForCommand(commands[i])
        if not kind then return nil, 0 end
        if not expected[kind] then
            expected[kind] = true
            count = count + 1
        end
    end
    return expected, count
end

local function SCB_ParseTargetedCommandAck(text)
    local _, _, actor
    if not text or text == "" then return nil, nil end
    _, _, actor = string.find(text, "^([^%s]+%*) ")
    if not actor then return nil, nil end

    if string.find(text, "is coming to your position.", 1, true)
        or string.find(text, "is not a party bot or it cannot come.", 1, true) then
        return actor, "come"
    end
    if string.find(text, "is now moving.", 1, true)
        or string.find(text, "is moving.", 1, true)
        or string.find(text, "is not a party bot or it cannot move.", 1, true) then
        return actor, "move"
    end
    if string.find(text, "is now staying.", 1, true)
        or string.find(text, "is staying.", 1, true)
        or string.find(text, "is not a party bot or it cannot stay.", 1, true) then
        return actor, "stay"
    end
    if string.find(text, "paused for 30 seconds.", 1, true) then
        return actor, "pause"
    end
    if string.find(text, "unpaused.", 1, true) then
        return actor, "unpause"
    end
    return nil, nil
end

local function SCB_BuildTargetedCommandAttempt(commandKey, forceMove)
    local commandInfo = SCB.commands and SCB.commands[commandKey] or nil
    local route = commandInfo and commandInfo.routes and commandInfo.routes.target or nil
    local moveRoute = SCB.commands and SCB.commands.move and SCB.commands.move.routes.target or nil
    local commands = {}
    local expectedAcks, expectedCount
    local i

    if not route then return nil, nil, nil end
    if forceMove and commandKey == "come" and moveRoute then
        for i = 1, table.getn(moveRoute) do table.insert(commands, moveRoute[i]) end
    end
    for i = 1, table.getn(route) do table.insert(commands, route[i]) end
    if table.getn(commands) == 0 then return nil, nil, nil end

    expectedAcks, expectedCount = SCB_BuildTargetedExpectedAcks(commands)
    if not expectedAcks or expectedCount ~= table.getn(commands) then
        return nil, nil, nil
    end
    return commandInfo, commands, expectedAcks
end

local function SCB_RestoreTargetedOriginalTarget(state)
    local originalName, currentName, member
    if not state or state.mode ~= "group" or not state.originalTargetName or not TargetUnit then return end

    originalName = state.originalTargetName
    currentName = UnitName and UnitName("target") or nil
    if currentName == originalName then return end

    member = SCB_GetLiveMember and SCB_GetLiveMember(originalName, false) or nil
    if member and member.unit then TargetUnit(member.unit) end
end

local function SCB_FinishTargetedCommandSequence()
    local state = SCB.targetedCommandState
    if state then SCB_RestoreTargetedOriginalTarget(state) end
    SCB.targetedCommandState = nil
    if SCB.targetedCommandFrame then SCB.targetedCommandFrame:Hide() end
end

local function SCB_FailSingleTargetCommand()
    local state = SCB.targetedCommandState
    if state and state.mode == "single" then
        SCB_Print(string.format(
            SCB_L("TARGET_COMMAND_FAILED", "Couldn't confirm %s for %s."),
            state.commandLabel or (state.commands and state.commands[1]) or "command",
            state.currentName or SCB_L("UNKNOWN")
        ))
        if PlaySound then PlaySound("igQuestFailed") end
    end
    SCB.targetedCommandState = nil
    if SCB.targetedCommandFrame then SCB.targetedCommandFrame:Hide() end
end

local function SCB_TargetedCommandAllAcksSeen(state)
    local kind
    if not state then return false end
    for kind in pairs(state.expectedAcks or {}) do
        if not state.ackSeen or not state.ackSeen[kind] then return false end
    end
    return true
end

local function SCB_SelectCurrentGroupRecipient()
    local state = SCB.targetedCommandState
    local name, member, currentName
    if not state or state.mode ~= "group" then return false end

    while (state.index or 1) <= table.getn(state.bots or {}) do
        name = state.bots[state.index or 1]
        member = name and SCB_GetLiveMember and SCB_GetLiveMember(name, false) or nil
        if member and member.isBot and member.unit
            and (member.currentGroup or member.subgroup or 1) == state.group then
            currentName = UnitName and UnitName("target") or nil
            if currentName ~= name then
                if not TargetUnit then
                    SCB_FinishTargetedCommandSequence()
                    return false
                end
                TargetUnit(member.unit)
                if not UnitName or UnitName("target") ~= name then
                    state.index = (state.index or 1) + 1
                else
                    state.currentName = name
                    state.phase = "settle"
                    state.phaseElapsed = 0
                    return true
                end
            else
                state.currentName = name
                state.phase = "settle"
                state.phaseElapsed = 0
                return true
            end
        else
            state.index = (state.index or 1) + 1
        end
    end

    SCB_FinishTargetedCommandSequence()
    return false
end

local function SCB_AdvanceGroupTargetedRecipient()
    local state = SCB.targetedCommandState
    if not state or state.mode ~= "group" then return end
    state.index = (state.index or 1) + 1
    state.currentName = nil
    state.ackSeen = {}
    state.ackFailed = nil
    if state.index > table.getn(state.bots or {}) then
        SCB_FinishTargetedCommandSequence()
        return
    end
    SCB_SelectCurrentGroupRecipient()
end

local function SCB_SendCurrentTargetedCommands()
    local state = SCB.targetedCommandState
    local name, member, i
    if not state then return end

    name = state.currentName
    if state.mode == "group" then
        member = name and SCB_GetLiveMember and SCB_GetLiveMember(name, false) or nil
        if not member or not member.isBot or not member.unit
            or (member.currentGroup or member.subgroup or 1) ~= state.group then
            SCB_AdvanceGroupTargetedRecipient()
            return
        end

        -- Group owns its target while sequencing. A real target change gets the
        -- normal 0.10-second settle before the next send.
        if not UnitName or UnitName("target") ~= name or not SCB_IsFriendlyBotTarget() then
            SCB_SelectCurrentGroupRecipient()
            return
        end
    else
        -- Single-target control never takes the target back from the player.
        -- This check mainly matters if the shared rate budget delayed the send.
        if not UnitName or UnitName("target") ~= name or not SCB_IsFriendlyBotTarget() then
            SCB_FailSingleTargetCommand()
            return
        end
    end

    if not SCB_TargetedCommandBudgetAllows(table.getn(state.commands or {})) then
        state.phase = "budget"
        state.phaseElapsed = 0
        return
    end

    state.ackSeen = {}
    state.ackFailed = nil
    state.phase = "await"
    state.phaseElapsed = 0
    for i = 1, table.getn(state.commands or {}) do
        if SCB_SendCommand(state.commands[i], { targetedSequence = true }) then
            SCB_RecordTargetedCommandSend()
        end
    end
end

local function SCB_ResolveTargetedAttempt(state)
    if not state then return end

    if not state.ackFailed then
        if state.mode == "group" then
            SCB_AdvanceGroupTargetedRecipient()
        else
            SCB_FinishTargetedCommandSequence()
        end
        return
    end

    if state.mode == "group" then
        -- Group starts only from a bot target. If the server is one bot behind,
        -- resend immediately to the already client-selected intended bot.
        SCB_SendCurrentTargetedCommands()
        return
    end

    -- Single-target control is intentionally non-invasive: retry exactly once,
    -- and only if the player still has the original intended bot selected.
    if (state.retryCount or 0) < 1
        and UnitName and UnitName("target") == state.currentName
        and SCB_IsFriendlyBotTarget() then
        state.retryCount = 1
        SCB_SendCurrentTargetedCommands()
    else
        SCB_FailSingleTargetCommand()
    end
end

function SCB_TargetedCommandHandleServerMessage(text)
    local state = SCB.targetedCommandState
    local actor, kind
    if not state or state.phase ~= "await" then return false end

    actor, kind = SCB_ParseTargetedCommandAck(text)
    if not actor or not kind or not state.expectedAcks or not state.expectedAcks[kind] then
        return false
    end

    -- One command attempt expects at most one reply of each kind. Ctrl-Come
    -- therefore consumes both Move and Come before deciding whether the pair
    -- succeeded or failed.
    if state.ackSeen[kind] then return true end

    state.ackSeen[kind] = true
    if actor ~= state.currentName then state.ackFailed = true end
    if not SCB_TargetedCommandAllAcksSeen(state) then return true end

    SCB_ResolveTargetedAttempt(state)
    return true
end

local function SCB_EnsureTargetedCommandFrame()
    local frame = SCB.targetedCommandFrame
    if frame then return frame end

    frame = CreateFrame("Frame", "SoloCraftBotsTargetedCommandFrame", UIParent)
    frame:Hide()
    frame:SetScript("OnUpdate", function()
        local state = SCB.targetedCommandState
        local elapsed = arg1 or 0
        if not state then
            this:Hide()
            return
        end

        state.phaseElapsed = (state.phaseElapsed or 0) + elapsed
        if state.phase == "settle" then
            if state.phaseElapsed < SCB_TARGETED_TARGET_SETTLE then return end
            state.phaseElapsed = 0
            SCB_SendCurrentTargetedCommands()
        elseif state.phase == "budget" then
            if state.phaseElapsed < SCB_TARGETED_BUDGET_POLL then return end
            state.phaseElapsed = 0
            SCB_SendCurrentTargetedCommands()
        end
    end)
    SCB.targetedCommandFrame = frame
    return frame
end

function SCB_QueueSingleTargetCommand(commandKey, forceMove)
    local commandInfo, commands = SCB_BuildTargetedCommandAttempt(commandKey, forceMove)
    local i

    if not commandInfo then return false end
    if not SCB_IsFriendlyBotTarget() then
        SCB_ShowInvalidTargetError()
        return false
    end

    -- Single is a direct combat control. Once the player has selected a bot,
    -- every click is intentional: do not create acknowledgement state, block
    -- repeated clicks, or apply the Group sequencer's 24/sec pacing budget.
    for i = 1, table.getn(commands or {}) do
        SCB_SendCommand(commands[i])
    end
    return true
end

function SCB_QueueGroupScopedCommand(commandKey, forceMove)
    local commandInfo, commands, expectedAcks = SCB_BuildTargetedCommandAttempt(commandKey, forceMove)
    local group, roster = SCB_GetTargetLiveGroup(true)
    local bots = {}
    local originalTargetName = UnitName and UnitName("target") or nil
    local requiredCommands
    local frame

    if SCB.targetedCommandState then
        SCB_ShowTargetedBusyError()
        return false
    end
    if not commandInfo then return false end
    if not group or not originalTargetName or not SCB_IsFriendlyBotTarget() then
        SCB_ShowInvalidTargetError()
        return false
    end
    bots = SCB_GetGroupScopedBots(group, roster)
    if table.getn(bots) == 0 then return false end

    requiredCommands = table.getn(bots) * table.getn(commands)
    if not SCB_TargetedCommandBudgetAllows(requiredCommands) then return false end

    SCB.targetedCommandState = {
        mode = "group",
        group = group,
        bots = bots,
        commands = commands,
        expectedAcks = expectedAcks,
        ackSeen = {},
        index = 1,
        phase = "target",
        phaseElapsed = 0,
        originalTargetName = originalTargetName,
        commandLabel = commandInfo.label,
    }
    frame = SCB_EnsureTargetedCommandFrame()

    -- Group changes targets itself, so every actual target change gets 0.10s.
    SCB_SelectCurrentGroupRecipient()
    if SCB.targetedCommandState then frame:Show() end
    return true
end

function SCB_RequestCommand(commandKey, scope, modifiers)
    local commandInfo, route
    if SCB_CanOperateBots and not SCB_CanOperateBots(true) then return false end
    commandInfo, route = SCB_GetCommandRoute(commandKey, scope)
    local moveInfo, moveRoute
    local forceMove = modifiers and modifiers.forceMove and true or false
    local sent = true
    local i

    if not commandInfo or not route then return false end

    -- Preserve Group's established busy-message precedence. An active Group
    -- sequence owns this request before current-target validation is considered.
    if scope == "group" and SCB.targetedCommandState then
        return SCB_QueueGroupScopedCommand(commandKey, forceMove)
    end

    if not SCB_IsCommandTargetContextValid(commandKey, scope) then
        if (scope == "target" or scope == "group")
            and not (modifiers and modifiers.silentInvalidTarget) then
            SCB_ShowInvalidTargetError()
        end
        return false
    end

    if scope == "group" then
        return SCB_QueueGroupScopedCommand(commandKey, forceMove)
    elseif scope == "target" then
        return SCB_QueueSingleTargetCommand(commandKey, forceMove)
    end

    if forceMove and commandKey == "come" then
        moveInfo, moveRoute = SCB_GetCommandRoute("move", scope)
        if moveInfo and moveRoute then
            for i = 1, table.getn(moveRoute) do
                if not SCB_SendCommand(moveRoute[i]) then sent = false end
            end
        end
    end

    for i = 1, table.getn(route) do
        if not SCB_SendCommand(route[i]) then sent = false end
    end
    return sent
end

local function SCB_SetCommandButtonAvailability(button)
    local available
    if not button or not button.scbCommandKey or not button.scbRecipientKey then return end

    available = SCB_IsCommandRequestAvailable(button.scbCommandKey, button.scbRecipientKey)
    button:SetAlpha(available and 1 or 0.5)
    if available then
        button:Enable()
    else
        button:Disable()
    end
end

function SCB_RefreshCommandAvailability()
    local layout = SCB.commandLayout
    local i, r, row
    if not layout then return end

    for r = 1, table.getn(layout.rows or {}) do
        row = layout.rows[r]
        SCB_SetCommandButtonAvailability(row and row.recipientButton)
        for i = 1, table.getn(row and row.commandButtons or {}) do
            SCB_SetCommandButtonAvailability(row.commandButtons[i])
        end
    end
    for i = 1, table.getn(layout.pairedComeButtons or {}) do
        SCB_SetCommandButtonAvailability(layout.pairedComeButtons[i] and layout.pairedComeButtons[i].button)
    end
    for i = 1, table.getn(layout.standaloneButtons or {}) do
        SCB_SetCommandButtonAvailability(layout.standaloneButtons[i])
    end
end

function SCB_RefreshTargetCommandRow()
    SCB_RefreshCommandAvailability()
end

function SCB_RefreshSpreadToggle(button)
    if not button then return end
    if SCB.rangedSpreadOn then
        SCB_SetArtButtonTexture(button, SCB.assetRoot .. "unspread.tga", SCB.assetRoot .. "unspread_h.tga")
        button.scbTooltip = SCB_L("TIP_RANGED_SPREAD_OFF")
    else
        SCB_SetArtButtonTexture(button, SCB.assetRoot .. "spread.tga", SCB.assetRoot .. "spread_h.tga")
        button.scbTooltip = SCB_L("TIP_RANGED_SPREAD")
    end
    SCB_RefreshVisibleTooltip(button)
end

function SCB_SpreadToggleOnClick()
    local commandKey = SCB.rangedSpreadOn and "hug" or "spread"
    if SCB_RequestCommand(commandKey, "ranged") then
        SCB.rangedSpreadOn = not SCB.rangedSpreadOn
    end
    SCB_RefreshSpreadToggle(this)
end

function SCB_DirectCommandOnClick()
    local forceMove = this.scbCommandKey == "come" and IsControlKeyDown and IsControlKeyDown()
    SCB_RequestCommand(this.scbCommandKey, this.scbRecipientKey, { forceMove = forceMove })
end

-- -------------------------------------------------------------------------
-- Raidmarks
-- -------------------------------------------------------------------------

SCB.raidMarks = {
    { key = "skull", name = SCB_L("MARK_SKULL") },
    { key = "cross", name = SCB_L("MARK_CROSS") },
    { key = "square", name = SCB_L("MARK_SQUARE") },
    { key = "moon", name = SCB_L("MARK_MOON") },
    { key = "triangle", name = SCB_L("MARK_TRIANGLE") },
    { key = "diamond", name = SCB_L("MARK_DIAMOND") },
    { key = "circle", name = SCB_L("MARK_CIRCLE") },
    { key = "star", name = SCB_L("MARK_STAR") },
}

function SCB_RefreshRaidmarkModeButton()
    if not SCB.assignmentModeButton then
        return
    end
    if SCB.raidMarkMode == "cc" then
        SCB_SetArtButtonTexture(SCB.assignmentModeButton, SCB.assetRoot .. "lucide_wand_sparkles.tga", nil)
        SCB.assignmentModeButton.scbTooltip = SCB_L("TIP_ASSIGNMENT_CC")
    else
        SCB.raidMarkMode = "focus"
        SCB_SetArtButtonTexture(SCB.assignmentModeButton, SCB.assetRoot .. "lucide_crosshair.tga", nil)
        SCB.assignmentModeButton.scbTooltip = SCB_L("TIP_ASSIGNMENT_FOCUS")
    end
    SCB_RefreshVisibleTooltip(SCB.assignmentModeButton)
end

function SCB_RaidmarkModeOnClick()
    if SCB.raidMarkMode == "focus" then
        SCB.raidMarkMode = "cc"
    else
        SCB.raidMarkMode = "focus"
    end
    SCB_RefreshRaidmarkModeButton()
end

function SCB_RaidMarkOnClick()
    if not this.scbMark or not SCB.raidMarkMode then
        return
    end
    if SCB_CanOperateBots and not SCB_CanOperateBots(true) then return end
    SCB_SendCommand(SCB.raidMarkMode .. "mark " .. this.scbMark)
end

-- -------------------------------------------------------------------------
-- Safe bot removal
-- -------------------------------------------------------------------------

SCB.raidZoneLocaleKeys = {
    "GROUP_ZG", "GROUP_AQ20", "GROUP_MC", "GROUP_ONYXIA",
    "GROUP_BWL", "GROUP_AQ40", "GROUP_NAXX",
}

function SCB_IsKnownRaidZone(zoneName)
    local i, key
    if not zoneName or zoneName == "" then return false end
    for i = 1, table.getn(SCB.raidZoneLocaleKeys) do
        key = SCB.raidZoneLocaleKeys[i]
        if zoneName == SCB_L(key) then return true end
    end
    return false
end

function SCB_GetSavedRaidDecision()
    local zoneName, count, i, savedName, savedID, reset, sawNamedMatch
    zoneName = (GetRealZoneText and GetRealZoneText()) or ""

    if not GetRealZoneText or not GetNumSavedInstances or not GetSavedInstanceInfo then
        return false, "api", zoneName, nil, nil, 0
    end
    if not SCB_IsKnownRaidZone(zoneName) then
        return false, "notraid", zoneName, nil, nil, 0
    end

    count = GetNumSavedInstances() or 0
    for i = 1, count do
        savedName, savedID, reset = GetSavedInstanceInfo(i)
        if savedName == zoneName then
            sawNamedMatch = true
            if savedID and savedID ~= 0 and reset and reset > 0 then
                return true, "matched", zoneName, savedID, reset, count
            end
        end
    end

    if sawNamedMatch then
        return false, "invalid", zoneName, nil, nil, count
    end
    return false, "nomatch", zoneName, nil, nil, count
end

function SCB_CurrentRaidHasSavedID()
    local matched = SCB_GetSavedRaidDecision()
    return matched
end

local function SCB_ActivePresetRebuildSnapshot()
    local operation = SCB_GetActiveBotOperation and SCB_GetActiveBotOperation() or nil
    local intent = operation and operation.desiredIntent or nil
    local snapshot = intent and intent.snapshot or nil

    if not operation or operation.kind ~= "preset" or not operation.rebuild or not snapshot then
        return nil
    end
    return snapshot
end

local function SCB_PresetNeedsRetainedBootstrap()
    local snapshot = SCB_ActivePresetRebuildSnapshot()
    local size, context, raidCount

    if not snapshot then return false end
    size = tonumber(snapshot.size) or 0

    if size > 5 then return true end

    context = SCB_GetLocationContext and SCB_GetLocationContext() or nil
    raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    return size > 0 and size <= 5 and context and context.inInstance and raidCount == 0
end

function SCB_SurvivorSafetyRequired()
    if SCB_PresetNeedsRetainedBootstrap() then return true end

    local context = SCB_GetLocationContext()
    if not context.inInstance then return false end

    local matched, reason, zoneName, savedID, reset, count = SCB_GetSavedRaidDecision()
    local zoneText = (zoneName and zoneName ~= "") and zoneName or "?"

    -- Keep the debug laboratory explicit about why survivor safety was or was
    -- not applied. This is diagnostic only; the policy itself remains
    -- conservative inside instances for dungeons, unknown zones, and invalid ID reads.
    if SCB.developerDebugEnabled and SCB_DebugLog then
        if matched then
            SCB_DebugLog(SCB_L("DEBUG_KIND_RAID_ID"), string.format(SCB_L("DEBUG_RAID_ID_MATCH"), zoneText, tostring(savedID), tostring(reset)))
        elseif reason == "api" then
            SCB_DebugLog(SCB_L("DEBUG_KIND_RAID_ID"), string.format(SCB_L("DEBUG_RAID_ID_API"), zoneText))
        elseif reason == "notraid" then
            SCB_DebugLog(SCB_L("DEBUG_KIND_RAID_ID"), string.format(SCB_L("DEBUG_RAID_ID_NOT_RAID"), zoneText))
        elseif reason == "invalid" then
            SCB_DebugLog(SCB_L("DEBUG_KIND_RAID_ID"), string.format(SCB_L("DEBUG_RAID_ID_INVALID"), zoneText, count or 0))
        else
            SCB_DebugLog(SCB_L("DEBUG_KIND_RAID_ID"), string.format(SCB_L("DEBUG_RAID_ID_NO_MATCH"), zoneText, count or 0))
        end
    end

    return not matched
end

function SCB_FindGroupOneSurvivor(members)
    local i, fallback
    for i = 1, table.getn(members or {}) do
        if members[i].isBot then
            if not fallback then fallback = members[i].name end
            if members[i].subgroup == 1 then
                return members[i].name
            end
        end
    end
    return fallback
end

function SCB_SafetyMessageOnUpdate()
    local frame = this
    frame.scbElapsed = (frame.scbElapsed or 0) + arg1
    if frame.scbElapsed >= 2.4 then
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
        return
    end
    local pulse = 0.82 + (0.18 * math.abs(math.sin(frame.scbElapsed * math.pi * 2)))
    local fade = 1
    if frame.scbElapsed > 1.8 then
        fade = 1 - ((frame.scbElapsed - 1.8) / 0.6)
    end
    frame:SetAlpha(pulse * fade)
end

function SCB_ShowSafetyMessage(message)
    if SCB.safetyMessageFrame and SCB.safetyMessageFrame.text then
        SCB.safetyMessageFrame.text:SetText(message or SCB_L("SURVIVOR_MESSAGE"))
    end
    SCB_EnsureOptionsDB()
    if SoloCraftBotsDB.options.hideSCBScreenWarnings then return end
    if not SCB.safetyMessageFrame then return end
    SCB.safetyMessageFrame.scbElapsed = 0
    SCB.safetyMessageFrame:SetAlpha(1)
    SCB.safetyMessageFrame:Show()
    SCB.safetyMessageFrame:SetScript("OnUpdate", SCB_SafetyMessageOnUpdate)
end

local SCB_KICK_BATCH_SIZE = 5
local SCB_KICK_BATCH_INTERVAL = 0.10
local SCB_kickQueueFrame = CreateFrame("Frame", nil, UIParent)
SCB_kickQueueFrame:Hide()

function SCB_IsKickQueueActive()
    return SCB.kickQueueState and SCB.kickQueueState.active and true or false
end

local function SCB_FinishKickQueue()
    local state = SCB.kickQueueState
    SCB.kickQueueState = nil
    SCB_kickQueueFrame:SetScript("OnUpdate", nil)
    SCB_kickQueueFrame:Hide()
    if SCB_RefreshManualAddButtons then SCB_RefreshManualAddButtons() end

    if state and not state.silent and not state.safetyApplied and (state.issued or 0) > 0 then
        if state.mode == "dead" then
            SCB_Print(string.format(SCB_L(state.issued == 1 and "KICKED_DEAD_ONE" or "KICKED_DEAD_MANY"), state.issued))
        else
            SCB_Print(string.format(SCB_L(state.issued == 1 and "KICKED_ONE" or "KICKED_MANY"), state.issued))
        end
    end
end

local function SCB_RunKickQueueBatch()
    local state = SCB.kickQueueState
    local sent, name = 0, nil
    if not state or not state.active then
        SCB_FinishKickQueue()
        return
    end

    while state.index <= table.getn(state.names) and sent < SCB_KICK_BATCH_SIZE do
        name = state.names[state.index]
        state.index = state.index + 1
        UninviteByName(name)
        state.issued = (state.issued or 0) + 1
        sent = sent + 1
    end

    if state.index > table.getn(state.names) then
        state.active = false
        SCB_FinishKickQueue()
    end
end

local function SCB_KickQueueOnUpdate()
    local state = SCB.kickQueueState
    if not state or not state.active then
        SCB_FinishKickQueue()
        return
    end

    state.elapsed = (state.elapsed or 0) + (arg1 or 0)
    if state.elapsed < SCB_KICK_BATCH_INTERVAL then return end

    -- Deliberately discard excess elapsed time. A lag spike must never cause
    -- several missed batches to be fired together on the next frame.
    state.elapsed = 0
    SCB_RunKickQueueBatch()
end

local function SCB_StartKickQueue(names, mode, safetyApplied, silent)
    if table.getn(names or {}) == 0 then return true end
    if SCB_IsKickQueueActive() then return false end

    SCB.kickQueueState = {
        active = true,
        names = names,
        index = 1,
        issued = 0,
        elapsed = 0,
        mode = mode,
        safetyApplied = safetyApplied and true or false,
        silent = silent and true or false,
    }
    if SCB_RefreshManualAddButtons then SCB_RefreshManualAddButtons() end

    -- Every multi-bot removal uses the same proven client/server-safe pacing.
    SCB_RunKickQueueBatch()
    if SCB_IsKickQueueActive() then
        SCB_kickQueueFrame:SetScript("OnUpdate", SCB_KickQueueOnUpdate)
        SCB_kickQueueFrame:Show()
    end
    return true
end

-- One authoritative physical bot-removal entry point.
-- mode: "all" or "dead"
-- options.names: optional set of exact bot names allowed to be removed
-- options.manageSafety: false when a higher-level coordinator already owns the survivor
-- options.preserveName: explicit name to preserve
-- options.silent: suppress normal kick-count chat (used by maintenance)
function SCB_KickBots(mode, options)
    local members
    if SCB_CanOperateBots and not SCB_CanOperateBots(not (options and options.silent)) then return false end
    members = SCB_CollectGroupMembers()
    local bots, candidates, kickNames = {}, {}, {}
    local otherHumans = 0
    local i, member, survivorName, safetyApplied
    local names = options and options.names or nil
    if options and options.name then
        names = names or {}
        names[options.name] = true
    end
    local manageSafety = not options or options.manageSafety ~= false
    local preserveName = options and options.preserveName or nil
    local silent = options and options.silent or false

    if mode ~= "all" and mode ~= "dead" then return false end
    if not UninviteByName then
        if not silent then SCB_Print(SCB_L("KICK_NATIVE_UNAVAILABLE")) end
        return false
    end
    if SCB_IsKickQueueActive() then return false end

    for i = 1, table.getn(members) do
        member = members[i]
        if member.isBot then
            table.insert(bots, member)
            if (mode == "all" or member.dead)
                and (not names or names[member.name]) then
                table.insert(candidates, member)
            end
        elseif not member.isSelf then
            otherHumans = otherHumans + 1
        end
    end

    -- A filtered maintenance call with no live candidate is still a successful
    -- no-op: Replace Missing deliberately enters through this same function.
    if table.getn(candidates) == 0 and names then return true end

    if table.getn(bots) == 0 then
        if not silent then SCB_Print(SCB_L("KICK_NONE")) end
        return false
    end
    if mode == "dead" and table.getn(candidates) == 0 then
        if not silent then SCB_Print(SCB_L("KICK_NONE_DEAD")) end
        return false
    end

    if manageSafety and otherHumans == 0 and SCB_SurvivorSafetyRequired() then
        survivorName = SCB_FindGroupOneSurvivor(members)
    else
        survivorName = preserveName
    end

    safetyApplied = false
    for i = 1, table.getn(candidates) do
        if survivorName and candidates[i].name == survivorName then
            safetyApplied = true
        else
            table.insert(kickNames, candidates[i].name)
        end
    end

    if mode == "all" and manageSafety then
        if safetyApplied and survivorName then
            SCB_SetKickAllAnchor(survivorName)
        else
            SCB_ClearKickAllAnchor()
        end
    end

    if safetyApplied and not silent then
        SCB_Print(SCB_L("SURVIVOR_CHAT"))
        SCB_ShowSafetyMessage()
    end

    return SCB_StartKickQueue(kickNames, mode, safetyApplied, silent)
end

function SCB_KickDeadOnClick()
    SCB_KickBots("dead")
end

function SCB_KickAllOnClick()
    SCB_KickBots("all")
end
end

-- -------------------------------------------------------------------------
-- User-facing chat feedback (absorbed from ChatFeedback.lua in 0.8.34).
-- Scoped to preserve the former file's local namespace.
-- -------------------------------------------------------------------------

do
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
    local extra, command, finalExtra, ok
    if not this.scbClass or not this.scbRole then return end

    extra = this.scbExtra
    if this.scbClass == "paladin" then extra = SCB.mainPaladinBlessing or "BoK" end

    if not SCB_RequestManualAdd then return end
    ok, command = SCB_RequestManualAdd(this.scbClass, this.scbRole, extra)
    if ok then
        finalExtra = SCB_GetFinalSpawnExtra(command)
        SCB_PrintAddedRequest(this.scbClass, this.scbRole, finalExtra)
    end
end

-- Keep preset scheduling untouched; this only provides the agreed compact
-- one-line request summary. Individual preset bot requests stay silent.
function SCB_PresetSummonOnClick()
    local snapshot, errorText, ok, botCount, botWord
    local forced = IsControlKeyDown and IsControlKeyDown() and true or false

    if SCB_CanOperateBots and not SCB_CanOperateBots(true) then return end
    local operation = SCB_GetActiveBotOperation and SCB_GetActiveBotOperation() or nil
    local legacyActive = SCB_HasBotSpawnOperation and SCB_HasBotSpawnOperation() or false

    if forced and (legacyActive or operation ~= nil) then
        if operation and SCB_SetBotOperationPhase then SCB_SetBotOperationPhase("replacing") end
        if SCB_AbortBotSpawnOperations then SCB_AbortBotSpawnOperations(true) end
    end

    snapshot, errorText = SCB_BuildPresetExecutionSnapshot()
    if not snapshot then
        if forced and operation and SCB_AbortBotOperation then
            SCB_AbortBotOperation("replacement snapshot invalid")
        end
        SCB_Print(errorText)
        return
    end

    SCB.presetEditorSlots = SCB_CopySlots(snapshot.slots)
    SCB_RefreshPresetPlayers()

    ok, errorText = SCB_StartPresetRebuild(snapshot, forced)
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

function SCB_HandleSpawnServerRejection(text)
    local hadOperation, hiddenKind, auraName, warning
    local flying = text == "Cannot add bots while flying."
    if text ~= "Cannot add bots right now." and not flying then return end

    hadOperation = SCB_HasBotSpawnOperation and SCB_HasBotSpawnOperation() or false
    if hadOperation and SCB_AbortBotSpawnOperations then
        SCB_AbortBotSpawnOperations()
    end

    if flying then
        warning = SCB_L("SUMMON_BLOCKED_FLYING")
    else
        hiddenKind, auraName = SCB_GetHiddenAuraKind()
    end
    if flying then
        -- Exact taxi rejection already selected the warning above.
    elseif hiddenKind == "prowl" then
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

    if SCB.developerDebugEnabled and SCB_DebugLog then
        SCB_DebugLog("Spawn", "Server rejected bot summon; active operation aborted=" .. tostring(hadOperation)
            .. ", hidden=" .. tostring(hiddenKind) .. ", aura=" .. tostring(auraName))
    end
end

end
