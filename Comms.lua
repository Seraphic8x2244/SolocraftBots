-- SoloCraftBots preset communications for Vanilla WoW 1.12.1.
-- SendAddonMessage has no WHISPER destination in 1.12, so messages are sent
-- through RAID (which falls back to PARTY) and carry their intended target.

local SCB = SoloCraftBots
local COMM_PREFIX = "SCBPRESET"
local COMM_PROTOCOL = 1
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
    return string.gsub(value or "", "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
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
    return SendRaw(kind .. "|" .. tx .. "|" .. target .. "|" .. (value or ""))
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
    fields[5] = Escape(snapshot.presetName or "Preset")
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
        button.label:SetText(mode == "S" and "Send..." or "Request...")
    else
        button:Enable()
        button.label:SetText(mode == "S" and SCB_L("PRESET_SEND", "Send") or SCB_L("PRESET_REQUEST", "Request"))
    end
end

local function ClearOutgoing(mode, status)
    local out = SCB.commOutgoing[mode]
    if not out then return end
    SCB.commOutgoing[mode] = nil
    SCB_CommsSetButtonPending(mode, false)
    if status == "SAVED" then
        SCB_Print(out.target .. " saved the preset.")
    elseif status == "SUMMONED" then
        SCB_Print(out.target .. " accepted the summon request.")
    elseif status == "REFUSED" then
        SCB_Print(out.target .. " refused the preset " .. (mode == "S" and "send." or "request."))
    elseif status == "BUSY" then
        SCB_Print(out.target .. " already has another SCB preset prompt open.")
    elseif status == "ERROR" then
        SCB_Print(out.target .. " could not process the preset.")
    elseif status == "TIMEOUT" then
        if not out.handshakeDone then
            SCB_Print("No SCB handshake reply from " .. out.target .. " within 30 seconds.")
        elseif not out.acknowledged then
            SCB_Print("SCB handshake with " .. out.target .. " succeeded, but preset data was not acknowledged within 30 seconds.")
        else
            SCB_Print(out.target .. " received the preset but did not respond within 30 seconds.")
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
    local out, targetRank, selfRank
    if not SendAddonMessage then
        SCB_Print("Preset communication is unavailable on this client.")
        return
    end
    if SCB.commOutgoing[mode] then
        SCB_Print(mode == "S" and "A preset Send is already waiting for a reply." or "A preset Request is already waiting for a reply.")
        return
    end
    if not SnapshotHasPlayer(snapshot, target) then
        SCB_Print("The selected player is no longer in the validated preset snapshot.")
        return
    end

    out = {
        mode = mode, target = target, snapshot = snapshot,
        tx = NextTransactionID(), deadline = Now() + COMM_TIMEOUT,
    }
    SCB.commOutgoing[mode] = out
    SCB_CommsSetButtonPending(mode, true)

    if mode == "R" and snapshot.size > 5 then
        if not GetNumRaidMembers or GetNumRaidMembers() == 0 then
            SCB_Print("Request requires an existing raid for presets larger than 5 players.")
            ClearOutgoing(mode)
            return
        end
        targetRank = SCB_CommsGetRaidRank(target)
        if targetRank == nil then
            SCB_Print(target .. " is no longer in the raid.")
            ClearOutgoing(mode)
            return
        end
        if targetRank == 0 then
            selfRank = SCB_CommsGetRaidRank(SelfName())
            if selfRank == 2 and PromoteToAssistant then
                out.phase = "promoting"
                PromoteToAssistant(target)
                return
            end
            SCB_Print(target .. " needs Raid Assistant to summon this preset.")
            ClearOutgoing(mode)
            return
        end
    end
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
    local roster, menu, button, count, i, info
    if not snapshot then SCB_Print(errorText) return end
    if SCB.commOutgoing[mode] then
        SCB_Print(mode == "S" and "A preset Send is already waiting for a reply." or "A preset Request is already waiting for a reply.")
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
                button:SetScript("OnClick", SCB_CommsTargetChoiceOnClick)
                menu.buttons[count] = button
            end
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - ((count - 1) * 20))
            button.label:SetText(info.name)
            button.scbTargetName = info.name
            button:Show()
        end
    end
    for i = count + 1, table.getn(menu.buttons) do menu.buttons[i]:Hide() end
    if count == 0 then SCB_CommsHideTargetMenu(); SCB_Print("No other human player is available for preset communication.") return end

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

    accept = SCB_CreateTextButton(frame, nil, 112, 24, "Save")
    accept:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -5, 18)
    accept:SetScript("OnClick", function() SCB_CommsPromptAccept() end)
    frame.accept = accept
    refuse = SCB_CreateTextButton(frame, nil, 112, 24, "Refuse")
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
    if incoming.mode == "S" then
        frame.title:SetText(incoming.sender .. " sent you a preset. Save it?")
        frame.accept.label:SetText("Save")
    else
        frame.title:SetText(incoming.sender .. " wants you to summon a preset. Proceed?")
        frame.accept.label:SetText("Summon Preset")
    end
    frame.subtitle:SetText((snapshot.groupName or "Preset Group") .. " - " .. (snapshot.presetName or "Preset"))
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
    local playerGroups, playerRoles = {}, {}
    local i, player, key, preset
    if not group then return false end
    for i = 1, table.getn(snapshot.players or {}) do
        player = snapshot.players[i]
        key = player.name == SelfName() and "$self" or player.name
        playerGroups[key] = player.group or 1
        playerRoles[key] = { role = player.role, extra = player.extra }
    end
    preset = {
        name = name,
        slots = SCB_CopySlots(snapshot.slots),
        playerGroups = playerGroups,
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
        SCB_Print("Could not match the received preset group.")
        FinishIncoming(incoming, "ERROR")
        return
    end
    SCB_Print("Saved received preset as " .. name .. ".")
    FinishIncoming(incoming, "SAVED")
end

StaticPopupDialogs["SOLOCRAFTBOTS_RECEIVED_PRESET_NAME"] = {
    text = "Save received preset as",
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
            editBox:SetText(incoming and incoming.defaultSaveName or "Preset")
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

function SCB_CommsPromptAccept()
    local incoming = SCB.commPromptTransaction
    local ok, errorText, rank
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
    if incoming.snapshot.size > 5 then
        rank = SCB_CommsGetRaidRank(SelfName())
        if not rank or rank < 1 then
            SCB_Print("You need Raid Assistant to summon this requested preset.")
            FinishIncoming(incoming, "ERROR")
            return
        end
    end
    ok, errorText = SCB_StartPresetSummonSnapshot(incoming.snapshot)
    if not ok then
        if errorText then SCB_Print(errorText) end
        FinishIncoming(incoming, "ERROR")
        return
    end
    FinishIncoming(incoming, "SUMMONED")
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
    parts = Split(message, "|")
    kind = parts[1]
    tx = parts[2]
    target = parts[3]
    if not tx or target ~= SelfName() then return end

    if kind == "O" and table.getn(parts) == 4 then
        local _, _, parsedMode, parsedProtocol = string.find(parts[4] or "", "^([SR]):(%d+)$")
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
        SendControl("H", tx, sender, "READY")
        return
    end

    if kind == "H" and table.getn(parts) == 4 and parts[4] == "READY" then
        for outgoingMode, out in pairs(SCB.commOutgoing) do
            if out and out.tx == tx and out.target == sender and out.phase == "handshake" then
                out.handshakeDone = true
                out.deadline = Now() + COMM_TIMEOUT
                SCB_Print("SCB handshake with " .. out.target .. " succeeded; sending preset data.")
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
                    SCB_Print(out.target .. " received the preset data; waiting for response.")
                end
                out.acknowledged = true
                out.deadline = Now() + COMM_TIMEOUT
            end
        end
        return
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
            elseif out.phase == "promoting" then
                if (SCB_CommsGetRaidRank(out.target) or 0) >= 1 then BeginHandshake(out) end
            elseif out.phase == "handshake" then
                out.handshakeElapsed = (out.handshakeElapsed or 0) + elapsed
                if out.handshakeElapsed >= COMM_HANDSHAKE_RETRY then
                    out.handshakeElapsed = 0
                    SendControl("O", out.tx, out.target, out.mode .. ":" .. COMM_PROTOCOL)
                end
            elseif out.phase == "sending" then
                out.chunkElapsed = (out.chunkElapsed or 0) + elapsed
                if out.chunkElapsed >= 0.08 and out.nextChunk <= table.getn(out.chunks) then
                    out.chunkElapsed = 0
                    packet = "C|" .. out.tx .. "|" .. out.target .. "|" .. out.mode .. "|" .. out.nextChunk .. "|" .. table.getn(out.chunks) .. "|" .. out.chunks[out.nextChunk]
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
    if incoming and not incoming.done and now >= incoming.deadline then FinishIncoming(incoming, "TIMEOUT") end
end)
