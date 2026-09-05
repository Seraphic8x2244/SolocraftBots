-- SoloCraft Bots - Debug laboratory
-- Loaded after SoloCraftBots.lua; intentionally behavior-preserving.

local SCB = SoloCraftBots

-- ---------------------------------------------------------------------------
-- Debug laboratory
-- ---------------------------------------------------------------------------

SCB.debug = SCB.debug or {
    lines = {},
    batch = {},
    batchIndex = 1,
    batchElapsed = 0,
    batchRunning = false,
    combatStates = {},
    roster = {},
    petTraces = {},
}

function SCB_DebugTimestamp()
    if GetTime then return string.format("%.3f", GetTime()) end
    return "0.000"
end

function SCB_DebugRefreshLog()
    if not SCB.debugLogEditBox then return end

    local text = table.concat(SCB.debug.lines, "\n")
    local lineCount = table.getn(SCB.debug.lines)
    local height = math.max(250, (lineCount * 14) + 12)

    SCB.debugLogEditBox:SetText(text)
    SCB.debugLogEditBox:SetHeight(height)

    if SCB.debugLogScroll and SCB.debugLogScroll.UpdateScrollChildRect then
        SCB.debugLogScroll:UpdateScrollChildRect()
        SCB.debugLogScroll:SetVerticalScroll(math.max(0, height - SCB.debugLogScroll:GetHeight()))
    end
end

function SCB_DebugLog(kind, text)
    if not SCB.developerDebugEnabled then return end
    if not text then return end
    table.insert(SCB.debug.lines, SCB_DebugTimestamp() .. "  " .. kind .. "  " .. tostring(text))

    while table.getn(SCB.debug.lines) > 2000 do
        table.remove(SCB.debug.lines, 1)
    end

    SCB_DebugRefreshLog()
end

function SCB_DebugClear()
    SCB.debug.lines = {}
    SCB_DebugRefreshLog()
    if SCB.debugLogScroll then
        SCB.debugLogScroll:SetVerticalScroll(0)
    end
    if SCB.debugLogEditBox and SCB.debugLogEditBox.SetCursorPosition then
        SCB.debugLogEditBox:SetCursorPosition(0)
    end
end

function SCB_DebugSelectAll()
    if not SCB.debugLogEditBox then return end
    SCB.debugLogEditBox:SetFocus()
    SCB.debugLogEditBox:HighlightText()
end

function SCB_DebugUnitSummary(unit, subgroup)
    local name = UnitName(unit)
    if not name then return nil end

    local _, class = UnitClass(unit)
    local bot = string.sub(name, -1) == "*"
    local status = UnitIsDeadOrGhost(unit) and "dead" or "alive"
    local combat = UnitAffectingCombat and UnitAffectingCombat(unit) and "combat" or "clear"

    local result = name .. " [" .. (class or "?") .. "]"
    if subgroup then result = result .. " G" .. subgroup end
    result = result .. " " .. status .. " " .. combat
    if bot then result = result .. " BOT" else result = result .. " PLAYER" end
    return result
end

function SCB_DebugCollectRoster()
    local roster = {}
    local count, i, name, subgroup, unit

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        count = GetNumRaidMembers()
        for i = 1, count do
            name, _, subgroup = GetRaidRosterInfo(i)
            unit = "raid" .. i
            if name then
                local _, class = UnitClass(unit)
                roster[name] = {
                    summary = SCB_DebugUnitSummary(unit, subgroup) or name,
                    unit = unit,
                    class = class,
                }
            end
        end
    else
        name = UnitName("player")
        if name then
            local _, class = UnitClass("player")
            roster[name] = {
                summary = SCB_DebugUnitSummary("player", nil) or name,
                unit = "player",
                class = class,
            }
        end

        count = GetNumPartyMembers and GetNumPartyMembers() or 0
        for i = 1, count do
            unit = "party" .. i
            name = UnitName(unit)
            if name then
                local _, class = UnitClass(unit)
                roster[name] = {
                    summary = SCB_DebugUnitSummary(unit, nil) or name,
                    unit = unit,
                    class = class,
                }
            end
        end
    end

    return roster
end

function SCB_DebugStartPetTrace(name, class)
    if not name or (class ~= "HUNTER" and class ~= "WARLOCK") then return end
    SCB.debug.petTraces[name] = {
        class = class,
        expires = (GetTime and GetTime() or 0) + 2.5,
        exists = false,
        petName = nil,
        combat = nil,
    }
    if SCB.debugCombatCheck and SCB.debugCombatCheck:GetChecked() then
        SCB_DebugLog("PET TRACE", name .. " [" .. class .. "] started")
    end
end

function SCB_DebugFindGroupUnitByName(wantedName)
    local i, unit, name
    if not wantedName then return nil end

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            unit = "raid" .. i
            name = UnitName(unit)
            if name == wantedName then return unit end
        end
    else
        if UnitName("player") == wantedName then return "player" end
        local count = GetNumPartyMembers and GetNumPartyMembers() or 0
        for i = 1, count do
            unit = "party" .. i
            name = UnitName(unit)
            if name == wantedName then return unit end
        end
    end
    return nil
end

function SCB_DebugScanPetTraces()
    local now = GetTime and GetTime() or 0
    local ownerName, trace
    for ownerName, trace in pairs(SCB.debug.petTraces) do
        if now > (trace.expires or 0) then
            SCB.debug.petTraces[ownerName] = nil
        else
            local ownerUnit = SCB_DebugFindGroupUnitByName(ownerName)
            if ownerUnit then
                local petUnit = ownerUnit .. "pet"
                local exists = UnitExists and UnitExists(petUnit) and true or false
                local petName = exists and UnitName(petUnit) or nil
                local petCombat = exists and UnitAffectingCombat and UnitAffectingCombat(petUnit) and true or false

                if exists and not trace.exists then
                    SCB_DebugLog("PET", ownerName .. " [" .. trace.class .. "] " .. petUnit .. " appeared: " .. (petName or "?") .. " " .. (petCombat and "combat" or "clear"))
                elseif not exists and trace.exists then
                    SCB_DebugLog("PET", ownerName .. " [" .. trace.class .. "] pet disappeared")
                elseif exists and trace.petName and petName ~= trace.petName then
                    SCB_DebugLog("PET", ownerName .. " [" .. trace.class .. "] " .. petUnit .. " changed: " .. trace.petName .. " -> " .. (petName or "?"))
                end

                if exists and trace.combat ~= nil and petCombat ~= trace.combat then
                    SCB_DebugLog("PET COMBAT", ownerName .. " [" .. trace.class .. "] " .. (petName or "?") .. " " .. petUnit .. " -> " .. (petCombat and "IN" or "OUT"))
                end

                trace.exists = exists
                trace.petName = petName
                trace.combat = exists and petCombat or nil
            end
        end
    end
end

function SCB_DebugRosterChanged()
    if not SCB.developerDebugEnabled then return end
    local current = SCB_DebugCollectRoster()
    local name, data

    if SCB.debugRosterCheck and SCB.debugRosterCheck:GetChecked() then
        for name, data in pairs(current) do
            if not SCB.debug.roster[name] then
                SCB_DebugLog("ROSTER", "+ " .. data.summary)
                SCB_DebugStartPetTrace(name, data.class)
            elseif SCB.debug.roster[name].summary ~= data.summary then
                SCB_DebugLog("ROSTER", "~ " .. data.summary)
            end
        end

        for name, data in pairs(SCB.debug.roster) do
            if not current[name] then
                SCB_DebugLog("ROSTER", "- " .. data.summary)
            end
        end
    end

    SCB.debug.roster = current
end

function SCB_DebugSnapshotRoster()
    local current = SCB_DebugCollectRoster()
    local name, data

    SCB_DebugLog("ROSTER", "--- snapshot ---")
    for name, data in pairs(current) do
        SCB_DebugLog("ROSTER", data.summary)
    end
    SCB.debug.roster = current
end

function SCB_DebugCollectCombatStates()
    local states = {}
    local count, i

    local function add(unitID)
        local name = UnitName(unitID)
        if not name then return end
        states[name] = UnitAffectingCombat and UnitAffectingCombat(unitID) and true or false
    end

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        count = GetNumRaidMembers()
        for i = 1, count do add("raid" .. i) end
    else
        add("player")
        count = GetNumPartyMembers and GetNumPartyMembers() or 0
        for i = 1, count do add("party" .. i) end
    end

    return states
end

function SCB_DebugPollCombat()
    local current = SCB_DebugCollectCombatStates()
    local name, state

    if SCB.debugCombatCheck and SCB.debugCombatCheck:GetChecked() then
        for name, state in pairs(current) do
            if SCB.debug.combatStates[name] ~= nil and SCB.debug.combatStates[name] ~= state then
                SCB_DebugLog("COMBAT POLL", name .. " -> " .. (state and "IN" or "OUT"))
            end
        end
    end

    SCB.debug.combatStates = current
end

function SCB_DebugParseBatch()
    local text = SCB.debugInput and SCB.debugInput:GetText() or ""
    local batch = {}
    local line

    for line in string.gfind(text, "[^\r\n]+") do
        line = string.gsub(line, "^%s+", "")
        line = string.gsub(line, "%s+$", "")

        if line ~= "" and string.sub(line, 1, 1) ~= "#" then
            if string.sub(string.lower(line), 1, 10) == ".partybot " then
                line = string.sub(line, 11)
            end
            table.insert(batch, line)
        end
    end

    return batch
end

function SCB_DebugSendLine(line)
    if not line or line == "" then return end

    SCB_DebugLog("SEND", ".partybot " .. line)

    if string.sub(string.lower(line), 1, 4) == "add " then
        SendChatMessage(".partybot " .. line, "SAY")
    else
        SendChatMessage(".partybot " .. line, "PARTY")
    end
end

function SCB_DebugStartBatch()
    local delay = tonumber(SCB.debugDelay and SCB.debugDelay:GetText() or "") or 0.10

    if delay < 0 then delay = 0 end
    if delay > 5 then delay = 5 end
    if SCB.debugDelay then SCB.debugDelay:SetText(string.format("%.2f", delay)) end

    SCB.debug.batch = SCB_DebugParseBatch()
    SCB.debug.batchIndex = 1
    SCB.debug.batchElapsed = delay
    SCB.debug.batchDelay = delay
    SCB.debug.batchWaitRemaining = nil
    SCB.debug.batchRunning = table.getn(SCB.debug.batch) > 0

    if SCB.debug.batchRunning then
        SCB_DebugLog("BATCH", "start " .. table.getn(SCB.debug.batch) .. " commands @ " .. string.format("%.2fs", delay))
    else
        SCB_DebugLog("BATCH", "no commands")
    end
end

function SCB_DebugStopBatch()
    if SCB.debug.batchRunning then
        SCB.debug.batchRunning = false
        SCB_DebugLog("BATCH", "stopped")
    end
end

function SCB_DebugProcessNextBatchLine()
    local line = SCB.debug.batch[SCB.debug.batchIndex]
    if not line then
        SCB.debug.batchRunning = false
        SCB_DebugLog("BATCH", "complete")
        return false
    end

    local _, _, waitText = string.find(string.lower(line), "^wait%s+([%d%.]+)$")
    local waitSeconds = waitText and tonumber(waitText) or nil
    if waitSeconds then
        if waitSeconds < 0 then waitSeconds = 0 end
        if waitSeconds > 30 then waitSeconds = 30 end
        SCB.debug.batchIndex = SCB.debug.batchIndex + 1
        SCB.debug.batchWaitRemaining = waitSeconds
        SCB_DebugLog("BATCH", "wait " .. string.format("%.2fs", waitSeconds))
        return false
    end

    SCB_DebugSendLine(line)
    SCB.debug.batchIndex = SCB.debug.batchIndex + 1
    return true
end

function SCB_DebugOnUpdate()
    if not SCB.developerDebugEnabled then return end
    local elapsed = arg1 or 0

    SCB.debug.combatElapsed = (SCB.debug.combatElapsed or 0) + elapsed
    if SCB.debug.combatElapsed >= 0.25 then
        SCB.debug.combatElapsed = 0
        SCB_DebugPollCombat()
    end

    SCB_DebugScanPetTraces()

    if not SCB.debug.batchRunning then return end

    if SCB.debug.batchWaitRemaining then
        SCB.debug.batchWaitRemaining = SCB.debug.batchWaitRemaining - elapsed
        if SCB.debug.batchWaitRemaining > 0 then return end
        SCB.debug.batchWaitRemaining = nil
        SCB.debug.batchElapsed = SCB.debug.batchDelay
        SCB_DebugLog("BATCH", "wait complete")
    end

    -- A true 0.00 delay is an intentional stress-test mode: consume commands
    -- in the same frame until a WAIT boundary or the batch ends.
    if SCB.debug.batchDelay <= 0 then
        while SCB.debug.batchRunning and not SCB.debug.batchWaitRemaining do
            if not SCB_DebugProcessNextBatchLine() then break end
        end
        return
    end

    SCB.debug.batchElapsed = SCB.debug.batchElapsed + elapsed
    if SCB.debug.batchElapsed < SCB.debug.batchDelay then return end
    SCB.debug.batchElapsed = 0
    SCB_DebugProcessNextBatchLine()
end

function SCB_DebugMakeCheck(parent, label)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetWidth(22)
    check:SetHeight(22)
    check:SetChecked(1)

    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", check, "RIGHT", 1, 0)
    text:SetText(label)
    text:SetTextColor(0.9, 0.9, 0.9, 1)

    check.scbLabel = text
    return check
end

function SCB_CreateDebugUI()
    if SCB.debugFrame then return end

    local frame = CreateFrame("Frame", "SoloCraftBotsDebugFrame", UIParent)
    frame:SetWidth(560)
    frame:SetHeight(520)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(60)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    SCB_ButtonBackdrop(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)
    title:SetText("SoloCraftBots Debug")
    title:SetTextColor(1, 0.82, 0, 1)

    local close = SCB_CreateTextButton(frame, nil, 24, 22, "X")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() frame:Hide() end)

    local inputLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    inputLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -42)
    inputLabel:SetText("Batch commands")
    inputLabel:SetTextColor(0.9, 0.9, 0.9, 1)

    local inputScroll = CreateFrame("ScrollFrame", "SoloCraftBotsDebugInputScroll", frame, "UIPanelScrollFrameTemplate")
    inputScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -58)
    inputScroll:SetWidth(512)
    inputScroll:SetHeight(68)
    SCB_ButtonBackdrop(inputScroll)

    local input = CreateFrame("EditBox", nil, inputScroll)
    input:SetWidth(490)
    input:SetHeight(68)
    input:SetMultiLine(true)
    input:SetAutoFocus(false)
    input:SetFontObject(ChatFontNormal)
    input:SetTextInsets(6, 6, 4, 4)
    input:SetMaxLetters(8192)
    input:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    input:SetScript("OnTextChanged", function()
        local _, lines = string.gsub(this:GetText() or "", "\n", "\n")
        local height = math.max(68, ((lines or 0) + 1) * 14 + 10)
        this:SetHeight(height)
        if inputScroll.UpdateScrollChildRect then
            inputScroll:UpdateScrollChildRect()
            inputScroll:SetVerticalScroll(math.max(0, height - inputScroll:GetHeight()))
        end
    end)
    inputScroll:SetScrollChild(input)
    SCB.debugInput = input
    SCB.debugInputScroll = inputScroll

    local delayLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    delayLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -134)
    delayLabel:SetText("Delay")
    delayLabel:SetTextColor(0.9, 0.9, 0.9, 1)

    local delay = CreateFrame("EditBox", nil, frame)
    delay:SetWidth(48)
    delay:SetHeight(22)
    delay:SetPoint("LEFT", delayLabel, "RIGHT", 8, 0)
    delay:SetAutoFocus(false)
    delay:SetFontObject(ChatFontNormal)
    delay:SetText("0.10")
    delay:SetJustifyH("CENTER")
    delay:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    SCB_ButtonBackdrop(delay)
    SCB.debugDelay = delay

    local send = SCB_CreateTextButton(frame, nil, 82, 22, "Send Batch")
    send:SetPoint("LEFT", delay, "RIGHT", 8, 0)
    send:SetScript("OnClick", SCB_DebugStartBatch)

    local stop = SCB_CreateTextButton(frame, nil, 48, 22, "Stop")
    stop:SetPoint("LEFT", send, "RIGHT", 6, 0)
    stop:SetScript("OnClick", SCB_DebugStopBatch)

    local snapshot = SCB_CreateTextButton(frame, nil, 92, 22, "Roster Now")
    snapshot:SetPoint("LEFT", stop, "RIGHT", 6, 0)
    snapshot:SetScript("OnClick", SCB_DebugSnapshotRoster)

    local rosterCheck = SCB_DebugMakeCheck(frame, "Roster")
    rosterCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -158)
    SCB.debugRosterCheck = rosterCheck

    local combatCheck = SCB_DebugMakeCheck(frame, "Combat")
    combatCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 100, -158)
    SCB.debugCombatCheck = combatCheck

    local serverCheck = SCB_DebugMakeCheck(frame, "Server")
    serverCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 188, -158)
    SCB.debugServerCheck = serverCheck

    local logLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    logLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -188)
    logLabel:SetText("Result log")
    logLabel:SetTextColor(0.9, 0.9, 0.9, 1)

    local scroll = CreateFrame("ScrollFrame", "SoloCraftBotsDebugScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -204)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 46)
    SCB_ButtonBackdrop(scroll)
    SCB.debugLogScroll = scroll

    local log = CreateFrame("EditBox", nil, scroll)
    log:SetWidth(500)
    log:SetHeight(250)
    log:SetMultiLine(true)
    log:SetAutoFocus(false)
    log:SetFontObject(ChatFontNormal)
    log:SetTextInsets(5, 5, 5, 5)
    log:SetMaxLetters(200000)
    log:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    scroll:SetScrollChild(log)
    SCB.debugLogEditBox = log

    local selectAll = SCB_CreateTextButton(frame, nil, 74, 22, "Select All")
    selectAll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 14)
    selectAll:SetScript("OnClick", SCB_DebugSelectAll)

    local clear = SCB_CreateTextButton(frame, nil, 54, 22, "Clear")
    clear:SetPoint("LEFT", selectAll, "RIGHT", 6, 0)
    clear:SetScript("OnClick", SCB_DebugClear)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 18)
    hint:SetText("Select All, then Ctrl+C")
    hint:SetTextColor(0.6, 0.6, 0.6, 1)

    frame:SetScript("OnShow", function()
        SCB.debug.roster = SCB_DebugCollectRoster()
        SCB.debug.combatStates = SCB_DebugCollectCombatStates()
        SCB_DebugRefreshLog()
    end)

    frame:Hide()
    SCB.debugFrame = frame

    if UISpecialFrames then
        table.insert(UISpecialFrames, "SoloCraftBotsDebugFrame")
    end
end

function SCB_DebugIsGroupUnit(unit)
    if not unit then return false end
    if unit == "player" or unit == "pet" then return true end
    if string.find(unit, "^party%d+$") or string.find(unit, "^raid%d+$") then return true end
    if string.find(unit, "^party%d+pet$") or string.find(unit, "^raid%d+pet$") then return true end
    return false
end

function SCB_DebugDescribeEventUnit(unit)
    local name = UnitName(unit) or "?"
    local _, class = UnitClass(unit)
    if string.find(unit or "", "pet$") then
        local ownerUnit = string.gsub(unit, "pet$", "")
        local ownerName = UnitName(ownerUnit) or "?"
        local _, ownerClass = UnitClass(ownerUnit)
        return name .. " [PET of " .. ownerName .. " " .. (ownerClass or "?") .. "] " .. unit
    end
    return name .. " [" .. (class or "?") .. "] " .. unit
end

function SCB_DebugUnitFlags(unit)
    if not SCB.developerDebugEnabled then return end
    if not (SCB.debugCombatCheck and SCB.debugCombatCheck:GetChecked()) then return end
    if not SCB_DebugIsGroupUnit(unit) then return end
    if not UnitName(unit) then return end

    local state = UnitAffectingCombat and UnitAffectingCombat(unit) and true or false
    local name = UnitName(unit)
    local oldState = SCB.debug.combatStates[name]
    if oldState ~= nil and oldState ~= state then
        SCB_DebugLog("COMBAT EVENT", SCB_DebugDescribeEventUnit(unit) .. " -> " .. (state and "IN" or "OUT"))
    end
    SCB.debug.combatStates[name] = state
end

function SCB_DebugUnitCombat(unit, action, critical, amount, damageType)
    if not SCB.developerDebugEnabled then return end
    if not (SCB.debugCombatCheck and SCB.debugCombatCheck:GetChecked()) then return end
    if not SCB_DebugIsGroupUnit(unit) then return end
    if not UnitName(unit) then return end

    local parts = { SCB_DebugDescribeEventUnit(unit) }
    if action ~= nil then table.insert(parts, tostring(action)) end
    if critical ~= nil then table.insert(parts, "crit=" .. tostring(critical)) end
    if amount ~= nil then table.insert(parts, "amount=" .. tostring(amount)) end
    if damageType ~= nil then table.insert(parts, "type=" .. tostring(damageType)) end
    SCB_DebugLog("UNIT_COMBAT", table.concat(parts, " "))
end

function SCB_DebugToggle()
    if not SCB.debugFrame then SCB_CreateDebugUI() end

    if SCB.debugFrame:IsShown() then
        SCB.debugFrame:Hide()
    else
        SCB.debugFrame:Show()
        SCB.debugFrame:Raise()
    end
end

local debugUpdateFrame = CreateFrame("Frame", "SoloCraftBotsDebugUpdateFrame", UIParent)
debugUpdateFrame:SetScript("OnUpdate", SCB_DebugOnUpdate)
