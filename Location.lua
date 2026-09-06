-- SoloCraft Bots - canonical location state and optional PresetGroup auto-swap.
-- Location resolution is always active; the auto-swap consumer is optional.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

SCB.INSTANCE_GROUP_BY_ZONE = {}
do
    local groupID, zoneName
    for groupID, zoneName in pairs(SCB.INSTANCE_ZONE_BY_GROUP or {}) do
        SCB.INSTANCE_GROUP_BY_ZONE[zoneName] = groupID
    end
end

local function LocationText(func)
    local value
    if not func then return "" end
    value = func()
    if not value then return "" end
    return tostring(value)
end

local function ProbeValue(value, available)
    if not available then return "<unavailable>" end
    if not value or value == "" then return "<empty>" end
    return tostring(value)
end

function SCB_GetLocationGroupName(groupID)
    if groupID == "5man" then return SCB_L("GROUP_WORLD", "World") end
    if groupID == "10man" then return SCB_L("GROUP_DUNGEON", "Dungeon") end
    if groupID == "ubrs" then return SCB_L("GROUP_BRS", "Blackrock Spire") end
    if groupID == "zg" then return SCB_L("GROUP_ZG", "Zul'Gurub") end
    if groupID == "aq20" then return SCB_L("GROUP_AQ20", "Ruins of Ahn'Qiraj") end
    if groupID == "mc" then return SCB_L("GROUP_MC", "Molten Core") end
    if groupID == "onyxia" then return SCB_L("GROUP_ONYXIA", "Onyxia's Lair") end
    if groupID == "bwl" then return SCB_L("GROUP_BWL", "Blackwing Lair") end
    if groupID == "aq40" then return SCB_L("GROUP_AQ40", "Temple of Ahn'Qiraj") end
    if groupID == "naxx" then return SCB_L("GROUP_NAXX", "Naxxramas") end
    return tostring(groupID or "unknown")
end

function SCB_GetLocationContext()
    local context = {}
    local resolvedZone

    context.inInstanceAvailable = IsInInstance and true or false
    context.inInstance = IsInInstance and (IsInInstance() and true or false) or false
    context.realZone = LocationText(GetRealZoneText)
    context.zone = LocationText(GetZoneText)
    context.subZone = LocationText(GetSubZoneText)
    context.minimapZone = LocationText(GetMinimapZoneText)

    resolvedZone = context.realZone ~= "" and context.realZone or context.zone
    context.resolvedZone = resolvedZone

    if context.inInstance then
        context.locationType = "instance"
        context.groupID = SCB.INSTANCE_GROUP_BY_ZONE[resolvedZone] or "10man"
    else
        context.locationType = "world"
        context.groupID = "5man"
    end

    context.groupName = SCB_GetLocationGroupName(context.groupID)
    return context
end

function SCB_GetLocationSignature(context)
    local state
    context = context or SCB_GetLocationContext()

    if not context.inInstanceAvailable then
        state = "?"
    elseif context.inInstance then
        state = "1"
    else
        state = "0"
    end

    -- Deliberately ignore subzone/minimap changes. A meaningful transition is
    -- world/instance state or the real zone changing.
    return state .. "\031" .. (context.resolvedZone or "")
end

function SCB_FindDefaultPresetGroupIndex(groupID)
    local i, group
    SCB_EnsurePresetDB()
    for i = 1, table.getn(SoloCraftBotsDB.presetGroups or {}) do
        group = SoloCraftBotsDB.presetGroups[i]
        if group and group.isDefault and group.id == groupID then return i end
    end
    return nil
end

function SCB_ApplyLocationPresetGroup(context)
    local groupIndex, group
    context = context or SCB_GetLocationContext()
    groupIndex = SCB_FindDefaultPresetGroupIndex(context.groupID)

    if not groupIndex or SoloCraftBotsDB.currentPresetGroup == groupIndex then
        return false
    end

    -- Never discard an unsaved editor state just because the player zoned.
    if SCB.presetDirty then
        SCB_Print(SCB_L("AUTO_SWAP_SKIPPED_UNSAVED", "Auto Swap Preset Group skipped: current preset has unsaved changes."))
        return false
    end

    group = SoloCraftBotsDB.presetGroups[groupIndex]
    SCB_LoadPreset(groupIndex, group and group.currentPreset or nil)
    return true
end

function SCB_ApplyCurrentLocationPresetGroup()
    SCB_EnsureOptionsDB()
    if not SoloCraftBotsDB.options.autoSwapPresetGroup then return false end
    return SCB_ApplyLocationPresetGroup(SCB_GetLocationContext())
end

function SCB_HandleLocationRefresh()
    local context = SCB_GetLocationContext()
    local signature = SCB_GetLocationSignature(context)

    SCB.locationContext = context
    if signature == SCB.lastLocationSignature then return end
    SCB.lastLocationSignature = signature

    SCB_EnsureOptionsDB()
    if SoloCraftBotsDB.options.autoSwapPresetGroup then
        SCB_ApplyLocationPresetGroup(context)
    end
end

function SCB_QueueLocationRefresh(delay)
    local frame

    if not SCB.locationRefreshFrame then
        frame = CreateFrame("Frame", "SoloCraftBotsLocationRefreshFrame", UIParent)
        frame:Hide()
        frame:SetScript("OnUpdate", function()
            this.scbElapsed = (this.scbElapsed or 0) + (arg1 or 0)
            if this.scbElapsed < (this.scbDelay or 0.20) then return end
            this.scbElapsed = 0
            this:Hide()
            SCB_HandleLocationRefresh()
        end)
        SCB.locationRefreshFrame = frame
    end

    frame = SCB.locationRefreshFrame
    -- Zone events can arrive in a burst, and ZONE_CHANGED_NEW_AREA can precede
    -- the zone-text APIs updating. Debounce and read the settled state.
    frame.scbDelay = delay or 0.20
    frame.scbElapsed = 0
    frame:Show()
end

-- Replaces the earlier raw probe once this module loads.
function SCB_PrintLocationProbe()
    local context = SCB_GetLocationContext()
    local inInstance

    if not context.inInstanceAvailable then
        inInstance = "<unavailable>"
    elseif context.inInstance then
        inInstance = "yes"
    else
        inInstance = "no"
    end

    SCB_Print("Location probe:")
    SCB_Print("InInstance: " .. inInstance)
    SCB_Print("RealZone: " .. ProbeValue(context.realZone, GetRealZoneText ~= nil))
    SCB_Print("Zone: " .. ProbeValue(context.zone, GetZoneText ~= nil))
    SCB_Print("SubZone: " .. ProbeValue(context.subZone, GetSubZoneText ~= nil))
    SCB_Print("MinimapZone: " .. ProbeValue(context.minimapZone, GetMinimapZoneText ~= nil))
    SCB_Print("ResolvedType: " .. context.locationType)
    SCB_Print("ResolvedGroup: " .. context.groupName .. " [" .. context.groupID .. "]")
end
