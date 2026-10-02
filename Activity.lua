-- SoloCraft Bots - neutral read-only activity/status surface.
--
-- Execution domains publish compact snapshots here. Presentation consumers read
-- defensive copies and never own command, spawn, communications or roster logic.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local SCB_ACTIVITY_CHANNELS = {
    "command",
    "botOperation",
    "communication",
    "rosterLayout",
}

local surface = {
    revision = 0,
    channels = {},
}

local function SCB_ActivityNow()
    return GetTime and GetTime() or 0
end

local function SCB_CopyActivityValue(value)
    local copied, key, item
    if type(value) ~= "table" then return value end
    copied = {}
    for key, item in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            copied[key] = SCB_CopyActivityValue(item)
        end
    end
    return copied
end

local function SCB_InitializeActivityChannels()
    local i, channel
    for i = 1, table.getn(SCB_ACTIVITY_CHANNELS) do
        channel = SCB_ACTIVITY_CHANNELS[i]
        surface.channels[channel] = {
            channel = channel,
            active = false,
            status = "idle",
            phase = "idle",
            revision = 0,
            surfaceRevision = 0,
            updatedAt = 0,
        }
    end
end

SCB_InitializeActivityChannels()

function SCB_PublishActivityStatus(channel, status)
    local current, nextState
    if type(channel) ~= "string" or channel == "" then return false end

    current = surface.channels[channel]
    nextState = SCB_CopyActivityValue(status or {})
    surface.revision = surface.revision + 1

    nextState.channel = channel
    nextState.active = nextState.active and true or false
    nextState.status = nextState.status
        or (nextState.active and "active" or "idle")
    nextState.phase = nextState.phase
        or (nextState.active and "active" or "idle")
    nextState.revision = ((current and current.revision) or 0) + 1
    nextState.surfaceRevision = surface.revision
    nextState.updatedAt = SCB_ActivityNow()

    surface.channels[channel] = nextState
    return true
end

function SCB_GetActivityStatus(channel)
    if channel then
        return SCB_CopyActivityValue(surface.channels[channel])
    end
    return SCB_CopyActivityValue(surface)
end

function SCB_GetActivityStatusRevision()
    return surface.revision
end
