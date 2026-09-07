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

-- Location capacity answers only how large a maintained group may be here.
-- It never manufactures expected bots: the Active Roster contains only bot
-- occupants the player actually had. Dungeons and Blackrock Spire deliberately
-- expose smaller challenge tiers; raid locations keep their normal raid cap.
function SCB_GetLocationCapacityTiers(context)
    context = context or SCB_GetLocationContext()
    if not context.inInstance then return { 5 } end
    if context.groupID == "10man" then return { 5, 10 } end
    if context.groupID == "ubrs" then return { 5, 10, 15 } end
    if context.groupID == "zg" or context.groupID == "aq20" then return { 20 } end
    if context.groupID == "mc" or context.groupID == "onyxia" or context.groupID == "bwl"
        or context.groupID == "aq40" or context.groupID == "naxx" then
        return { 40 }
    end
    return { 5, 10 }
end

function SCB_GetLocationMaxCapacity(context)
    local tiers = SCB_GetLocationCapacityTiers(context)
    return tiers[table.getn(tiers)] or 5
end

-- previousCap makes normal observation sticky upward. explicitSize is the one
-- deliberate shrink path: pressing Summon with a smaller preset is the user's
-- authoritative statement that the maintained roster should become smaller.
function SCB_ResolveLocationExpectedCap(context, currentCount, previousCap, explicitSize)
    local tiers, resolved, i
    context = context or SCB_GetLocationContext()
    currentCount = tonumber(currentCount) or 0

    if explicitSize and tonumber(explicitSize) and tonumber(explicitSize) > 0 then
        return tonumber(explicitSize)
    end

    tiers = SCB_GetLocationCapacityTiers(context)
    resolved = tiers[table.getn(tiers)] or 5

    if not context.inInstance or context.groupID == "10man" or context.groupID == "ubrs" then
        for i = 1, table.getn(tiers) do
            if currentCount <= tiers[i] then
                resolved = tiers[i]
                break
            end
        end
    end

    if previousCap and tonumber(previousCap) and tonumber(previousCap) > resolved then
        resolved = tonumber(previousCap)
    end
    -- A currently-existing group is never described as smaller than itself,
    -- even during an unusual transition that exceeds the local summon cap.
    if currentCount > resolved then resolved = currentCount end
    return resolved
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
