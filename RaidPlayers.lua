-- SoloCraft Bots - exact live human rows in raid presets.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local function SCB_CopyExactPlayerSlots(source, size)
    local copy = {}
    local key, slot
    size = tonumber(size) or 0
    for key, slot in pairs(source or {}) do
        if type(key) == "string" and type(slot) == "number"
            and slot >= 1 and slot <= size then
            copy[key] = slot
        end
    end
    return copy
end

-- -------------------------------------------------------------------------
-- Exact live human rows in raid presets
-- -------------------------------------------------------------------------

-- Raid presets still assign humans to a group as the durable saved intent, but
-- may additionally remember the exact live row Blizzard finally chose. Missing
-- exact rows fall back to stable roster order in the first free row of the
-- assigned group, preserving compatibility with every existing preset.
function SCB_GetPresetHumanLayout()
    local size = SCB_CurrentPresetSize()
    local roster = SCB_GetHumanRoster()
    local present, assignedPresent, playerRows = {}, {}, {}
    local used = {}
    local i, info, key, groupIndex, slotIndex, groupStart, groupEnd, candidate

    for i = 1, table.getn(roster) do
        present[roster[i].key] = roster[i]
    end

    if size <= 5 then
        local auto = SCB_AutoPartyPlayerSlots(roster)
        for key, slotIndex in pairs(auto) do
            if present[key] and slotIndex >= 1 and slotIndex <= size then
                playerRows[key] = slotIndex
                assignedPresent[key] = true
            end
        end
        return roster, present, playerRows, assignedPresent
    end

    -- First honour exact saved/working rows that still belong to the player's
    -- assigned group and are not already claimed by another human.
    for i = 1, table.getn(roster) do
        info = roster[i]
        groupIndex = SCB.presetEditorPlayers and SCB.presetEditorPlayers[info.key]
        slotIndex = SCB.presetEditorPlayerSlots and SCB.presetEditorPlayerSlots[info.key]
        if groupIndex and slotIndex
            and groupIndex >= 1 and groupIndex <= math.ceil(size / 5)
            and slotIndex >= 1 and slotIndex <= size
            and math.floor((slotIndex - 1) / 5) + 1 == groupIndex
            and not used[slotIndex] then
            playerRows[info.key] = slotIndex
            assignedPresent[info.key] = true
            used[slotIndex] = true
        end
    end

    -- Old/group-only presets get exactly the previous behavior, except that
    -- rows already claimed by an exact player are skipped.
    for i = 1, table.getn(roster) do
        info = roster[i]
        if not playerRows[info.key] then
            groupIndex = SCB.presetEditorPlayers and SCB.presetEditorPlayers[info.key]
            if groupIndex and groupIndex >= 1 and groupIndex <= math.ceil(size / 5) then
                groupStart = ((groupIndex - 1) * 5) + 1
                groupEnd = math.min(groupStart + 4, size)
                candidate = groupStart
                while candidate <= groupEnd and used[candidate] do
                    candidate = candidate + 1
                end
                if candidate <= groupEnd then
                    playerRows[info.key] = candidate
                    assignedPresent[info.key] = true
                    used[candidate] = true
                end
            end
        end
    end

    return roster, present, playerRows, assignedPresent
end

local function SCB_GetEditorExactPlayerSlots()
    local size = SCB_CurrentPresetSize()
    local exact = SCB_CopyExactPlayerSlots(SCB.presetEditorPlayerSlots, size)
    local roster, present, playerRows = SCB_GetPresetHumanLayout()
    local key, slotIndex

    -- Present players' rendered positions are the authoritative working rows.
    for key, slotIndex in pairs(playerRows or {}) do
        if present[key] then exact[key] = slotIndex end
    end
    return exact
end

local SCB_072PreviousAssignPresetPlayer = SCB_AssignPresetPlayer
if SCB_072PreviousAssignPresetPlayer then
    function SCB_AssignPresetPlayer(key, groupIndex)
        local result = SCB_072PreviousAssignPresetPlayer(key, groupIndex)
        if SCB_CurrentPresetSize() > 5 and key then
            SCB.presetEditorPlayerSlots = SCB.presetEditorPlayerSlots or {}
            -- A group-level editor drag deliberately relinquishes any exact
            -- Blizzard row. The normal layout resolver chooses the first free
            -- row until the live raid establishes a new exact one.
            SCB.presetEditorPlayerSlots[key] = nil
        end
        return result
    end
end

local SCB_072PreviousPresetPlayerOnClick = SCB_PresetPlayerOnClick
if SCB_072PreviousPresetPlayerOnClick then
    function SCB_PresetPlayerOnClick()
        local key = this and this.scbPlayerKey or nil
        local remove = arg1 == "RightButton" and key and key ~= "$self"
            and SCB_CurrentPresetSize() > 5
        local result = SCB_072PreviousPresetPlayerOnClick()
        if remove and SCB.presetEditorPlayers and not SCB.presetEditorPlayers[key] then
            SCB.presetEditorPlayerSlots = SCB.presetEditorPlayerSlots or {}
            SCB.presetEditorPlayerSlots[key] = nil
        end
        return result
    end
end

local SCB_072PreviousLoadPreset = SCB_LoadPreset
if SCB_072PreviousLoadPreset then
    function SCB_LoadPreset(groupIndex, presetIndex)
        local group, preset, size
        -- Never let exact rows from the previously-selected preset leak into
        -- the first refresh performed by the legacy loader. Reloading a preset
        -- also deliberately breaks the editor's live-layout alignment: this is
        -- the existing lightweight "revert to saved" behavior.
        SCB.presetEditorPlayerSlots = {}
        SCB.scbEditorLayoutTrackerRevision = nil
        SCB_072PreviousLoadPreset(groupIndex, presetIndex)

        group = SCB_CurrentPresetGroup()
        preset = SCB_CurrentPreset()
        size = group and group.size or SCB_CurrentPresetSize()
        SCB.presetEditorPlayerSlots = SCB_CopyExactPlayerSlots(
            preset and preset.playerSlots or nil,
            size
        )
        if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() end
    end
end

local SCB_072PreviousSaveCurrentPreset = SCB_SaveCurrentPreset
if SCB_072PreviousSaveCurrentPreset then
    function SCB_SaveCurrentPreset()
        local exact = SCB_GetEditorExactPlayerSlots()
        local result = SCB_072PreviousSaveCurrentPreset()
        local preset = SCB_CurrentPreset()
        if preset then
            SCB.presetEditorPlayerSlots = exact
            preset.playerSlots = SCB_CopyExactPlayerSlots(exact, SCB_CurrentPresetSize())
        end
        return result
    end
end

local SCB_072PreviousAcceptPresetName = SCB_AcceptPresetName
if SCB_072PreviousAcceptPresetName then
    function SCB_AcceptPresetName(dialog)
        local exact = SCB_GetEditorExactPlayerSlots()
        local result = SCB_072PreviousAcceptPresetName(dialog)
        local preset = SCB_CurrentPreset()
        if preset then
            preset.playerSlots = SCB_CopyExactPlayerSlots(exact, SCB_CurrentPresetSize())
            SCB.presetEditorPlayerSlots = SCB_CopyExactPlayerSlots(exact, SCB_CurrentPresetSize())
            if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() end
        end
        return result
    end
end
