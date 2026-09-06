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
    if not available then return SCB_L("LOCATION_UNAVAILABLE") end
    if not value or value == "" then return SCB_L("LOCATION_EMPTY") end
    return tostring(value)
end

function SCB_GetLocationGroupName(groupID)
    if groupID == "5man" then return SCB_L("GROUP_WORLD") end
    if groupID == "10man" then return SCB_L("GROUP_DUNGEON") end
    if groupID == "ubrs" then return SCB_L("GROUP_BRS") end
    if groupID == "zg" then return SCB_L("GROUP_ZG") end
    if groupID == "aq20" then return SCB_L("GROUP_AQ20") end
    if groupID == "mc" then return SCB_L("GROUP_MC") end
    if groupID == "onyxia" then return SCB_L("GROUP_ONYXIA") end
    if groupID == "bwl" then return SCB_L("GROUP_BWL") end
    if groupID == "aq40" then return SCB_L("GROUP_AQ40") end
    if groupID == "naxx" then return SCB_L("GROUP_NAXX") end
    return groupID and tostring(groupID) or SCB_L("UNKNOWN")
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
    context = context or SCB_GetLocationContext()

    if not context.inInstanceAvailable then return "?" end

    -- World zone changes are not Preset Group transitions. This deliberately
    -- keeps a manually-selected raid preset open while travelling outdoors.
    if not context.inInstance then return "world" end

    -- Inside instances, preserve the resolved zone so direct instance-to-
    -- instance transitions still auto-swap correctly (for example BRD -> MC,
    -- BRS -> BWL, or Stratholme -> Naxxramas).
    return "instance\031" .. (context.resolvedZone or "")
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
        SCB_Print(SCB_L("AUTO_SWAP_SKIPPED_UNSAVED"))
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
        inInstance = SCB_L("LOCATION_UNAVAILABLE")
    elseif context.inInstance then
        inInstance = SCB_L("YES")
    else
        inInstance = SCB_L("NO")
    end

    SCB_Print(SCB_L("LOCATION_PROBE"))
    SCB_Print(string.format(SCB_L("LOCATION_IN_INSTANCE"), inInstance))
    SCB_Print(string.format(SCB_L("LOCATION_REAL_ZONE"), ProbeValue(context.realZone, GetRealZoneText ~= nil)))
    SCB_Print(string.format(SCB_L("LOCATION_ZONE"), ProbeValue(context.zone, GetZoneText ~= nil)))
    SCB_Print(string.format(SCB_L("LOCATION_SUB_ZONE"), ProbeValue(context.subZone, GetSubZoneText ~= nil)))
    SCB_Print(string.format(SCB_L("LOCATION_MINIMAP_ZONE"), ProbeValue(context.minimapZone, GetMinimapZoneText ~= nil)))
    SCB_Print(string.format(SCB_L("LOCATION_RESOLVED_TYPE"), SCB_L(context.locationType == "instance" and "LOCATION_TYPE_INSTANCE" or "LOCATION_TYPE_WORLD")))
    SCB_Print(string.format(SCB_L("LOCATION_RESOLVED_GROUP"), context.groupName, context.groupID))
end
