-- SoloCraft Bots - live raid presentation without mutating preset intent.
-- Blizzard may reorder members within a subgroup. Keep that as display state:
-- the preset remains Saved unless a member actually changes subgroup.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local LIVE_LOCATION_TOOLTIP = "Not in preset location due to Blizzard raid handling"

local function SCB_CopyMap(source)
    local copy = {}
    local key, value
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

local function SCB_IsTrackedPresetSelected(tracker)
    local group = SCB_CurrentPresetGroup and SCB_CurrentPresetGroup() or nil
    if not tracker or not group then return false end
    return tracker.presetGroupIndex
        and tracker.presetIndex
        and SoloCraftBotsDB
        and SoloCraftBotsDB.currentPresetGroup == tracker.presetGroupIndex
        and group.currentPreset == tracker.presetIndex
end

local function SCB_CaptureTrackerPlayers(tracker)
    local result = {}
    local i, player
    for i = 1, table.getn(tracker and tracker.players or {}) do
        player = tracker.players[i]
        if player and player.name then
            result[player.name] = { slotIndex = player.slotIndex, group = player.group }
        end
    end
    return result
end

local function SCB_UpdateLiveRaidPlayerPresentation(tracker, beforePlayers)
    local roster, keyByName = SCB_GetHumanRoster(), {}
    local i, player, key, before
    local anyMoved = false
    local groupChanged = false

    for i = 1, table.getn(roster or {}) do
        if roster[i].name then keyByName[roster[i].name] = roster[i].key end
    end

    SCB.liveRaidPlayerSlots = {}
    SCB.liveRaidPlayerSlotMismatch = {}
    SCB.liveRaidPlayerPresetGroupIndex = tracker and tracker.presetGroupIndex or nil
    SCB.liveRaidPlayerPresetIndex = tracker and tracker.presetIndex or nil

    for i = 1, table.getn(tracker and tracker.players or {}) do
        player = tracker.players[i]
        if player and player.name and player.slotIndex then
            key = keyByName[player.name] or player.name
            SCB.liveRaidPlayerSlots[key] = player.slotIndex
            before = beforePlayers and beforePlayers[player.name] or nil
            if before and before.slotIndex and before.slotIndex ~= player.slotIndex then
                anyMoved = true
                if before.group ~= player.group then
                    groupChanged = true
                else
                    SCB.liveRaidPlayerSlotMismatch[key] = true
                end
            end
        end
    end

    return anyMoved, groupChanged
end

local function SCB_GuardRaidPresentation(callback)
    local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil
    local selected = SCB_IsTrackedPresetSelected(tracker)
    local beforeRevision = tracker and tracker.layoutRevision or nil
    local beforePlayers = selected and SCB_CaptureTrackerPlayers(tracker) or nil
    local beforeSlots = selected and SCB_CopySlots(SCB.presetEditorSlots or {}) or nil
    local beforePlayerGroups = selected and SCB_CopyMap(SCB.presetEditorPlayers) or nil
    local beforePlayerSlots = selected and SCB_CopyMap(SCB.presetEditorPlayerSlots) or nil
    local beforeDirty = selected and (SCB.presetDirty == true) or nil
    local result = callback()
    local afterTracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil
    local revisionChanged = selected and afterTracker == tracker
        and (afterTracker.layoutRevision or 0) ~= (beforeRevision or 0)

    if revisionChanged then
        local anyMoved, groupChanged = SCB_UpdateLiveRaidPlayerPresentation(afterTracker, beforePlayers)

        -- Same-subgroup row movement is presentation only. RaidLayout may have
        -- permuted the working editor to mirror Blizzard before we get here;
        -- restore the user's preset intent while retaining the live row map.
        if anyMoved and not groupChanged then
            SCB.presetEditorSlots = beforeSlots
            SCB.presetEditorPlayers = beforePlayerGroups
            SCB.presetEditorPlayerSlots = beforePlayerSlots
            SCB.scbEditorLayoutTrackerRevision = nil
            if SCB_SetPresetDirty then SCB_SetPresetDirty(beforeDirty, false) else SCB.presetDirty = beforeDirty end
            if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() end
            if SCB_DebugLog then SCB_DebugLog("Raid", "Blizzard same-group row reorder kept as live presentation only") end
        end
    end

    return result
end

-- Prefer Blizzard's current human rows when showing the active tracked preset,
-- but keep the saved/editor row as the underlying preset intent.
local SCB_PreviousGetPresetHumanLayout_Presentation = SCB_GetPresetHumanLayout
if SCB_PreviousGetPresetHumanLayout_Presentation then
    function SCB_GetPresetHumanLayout()
        local roster, present, playerRows, assignedPresent = SCB_PreviousGetPresetHumanLayout_Presentation()
        local group = SCB_CurrentPresetGroup and SCB_CurrentPresetGroup() or nil
        local key, liveSlot, intendedGroup, liveGroup
        local active = group and SoloCraftBotsDB
            and SoloCraftBotsDB.currentPresetGroup == SCB.liveRaidPlayerPresetGroupIndex
            and group.currentPreset == SCB.liveRaidPlayerPresetIndex

        if not active or SCB_CurrentPresetSize() <= 5 then
            return roster, present, playerRows, assignedPresent
        end

        for key, liveSlot in pairs(SCB.liveRaidPlayerSlots or {}) do
            intendedGroup = SCB.presetEditorPlayers and SCB.presetEditorPlayers[key] or nil
            liveGroup = math.floor((liveSlot - 1) / 5) + 1
            if present[key] and intendedGroup == liveGroup then
                playerRows[key] = liveSlot
                assignedPresent[key] = true
            end
        end
        return roster, present, playerRows, assignedPresent
    end
end

local function SCB_LiveSlotPulseOnUpdate()
    local t = GetTime and GetTime() or 0
    local mix = (math.sin(t * 3.14159265) + 1) / 2
    if this and this.scbLiveSlotBackground then
        this.scbLiveSlotBackground:SetAlpha(0.08 + (0.22 * mix))
    end
end

local function SCB_SetLiveSlotPresentation(button, enabled)
    if not button then return end
    if enabled then
        if not button.scbLiveSlotBackground then
            local bg = button:CreateTexture(nil, "BACKGROUND")
            bg:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 1)
            bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -1)
            bg:SetTexture(0.20, 1.00, 0.25, 1)
            button.scbLiveSlotBackground = bg
        end
        button.scbLiveSlotBackground:Show()
        button:SetScript("OnUpdate", SCB_LiveSlotPulseOnUpdate)
        if not button.scbBaseTooltip then button.scbBaseTooltip = button.scbTooltip end
        button.scbTooltip = (button.scbBaseTooltip or "") .. "\n" .. LIVE_LOCATION_TOOLTIP
    else
        button:SetScript("OnUpdate", nil)
        if button.scbLiveSlotBackground then button.scbLiveSlotBackground:Hide() end
        if button.scbBaseTooltip then
            button.scbTooltip = button.scbBaseTooltip
            button.scbBaseTooltip = nil
        end
    end
end

local SCB_PreviousRefreshPresetPlayers_Presentation = SCB_RefreshPresetPlayers
if SCB_PreviousRefreshPresetPlayers_Presentation then
    function SCB_RefreshPresetPlayers()
        local result = SCB_PreviousRefreshPresetPlayers_Presentation()
        local i, row, key
        for i = 1, 40 do
            row = SCB.presetSlotRows and SCB.presetSlotRows[i] or nil
            if row and row.playerOverlay and row.playerOverlay:IsShown() then
                key = row.scbPresentPlayerKey
                SCB_SetLiveSlotPresentation(row.playerOverlay,
                    key and SCB.liveRaidPlayerSlotMismatch and SCB.liveRaidPlayerSlotMismatch[key] == true)
            elseif row and row.playerOverlay then
                SCB_SetLiveSlotPresentation(row.playerOverlay, false)
            end
        end
        return result
    end
end

local SCB_PreviousHandleRosterChange_Presentation = SCB_HandleRosterChange
if SCB_PreviousHandleRosterChange_Presentation then
    function SCB_HandleRosterChange()
        return SCB_GuardRaidPresentation(SCB_PreviousHandleRosterChange_Presentation)
    end
end

local SCB_PreviousTryFinalizeRaidRoleTracking_Presentation = SCB_TryFinalizeRaidRoleTracking
if SCB_PreviousTryFinalizeRaidRoleTracking_Presentation then
    function SCB_TryFinalizeRaidRoleTracking()
        return SCB_GuardRaidPresentation(SCB_PreviousTryFinalizeRaidRoleTracking_Presentation)
    end
end
