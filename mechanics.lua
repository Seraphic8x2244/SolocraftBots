-- SoloCraft Bots - dormant Boss Mods encounter core (Lua 5.0.3).
-- Not loaded by the TOC. Activation must forward events and ticks through the
-- existing SCB lifecycle owner; this file deliberately creates no frame,
-- registrations, command transport, bot-control path, or SavedVariables.
--
-- Definition: { events = { { event = "CHAT_MSG_...", pattern = "...",
--             plain = true/false, filter = function(message, details, event),
--             handler = function(message, details, event, generation) } },
--             onStart = function(generation),
--             onStop = function(reason, generation) }
-- A rule may omit pattern/filter to match every occurrence of its event.
-- Timers are encounter-scoped, named, and serviced only by UpdateTimers().

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots
local mechanics = {}
SCB.mechanics = mechanics

local encounters = {}
local active = nil
local generation = 0
local timers = {}
local timerOrder = 0
local bindings = {} -- encounter-local names only; never cache roster objects

local function Now()
    return (GetTime and GetTime()) or 0
end

local function ClearTimers()
    timers = {}
    timerOrder = 0
end

function mechanics.RegisterEncounter(id, definition)
    local rules, i, rule
    if type(id) ~= "string" or id == "" or type(definition) ~= "table" then
        return false, "invalid encounter"
    end
    if encounters[id] then return false, "encounter already registered" end
    if definition.onStart and type(definition.onStart) ~= "function" then
        return false, "invalid start callback"
    end
    if definition.onStop and type(definition.onStop) ~= "function" then
        return false, "invalid stop callback"
    end
    rules = definition.events or {}
    if type(rules) ~= "table" then return false, "invalid event rules" end
    for i = 1, table.getn(rules) do
        rule = rules[i]
        if type(rule) ~= "table" or type(rule.event) ~= "string"
            or rule.event == "" or type(rule.handler) ~= "function" then
            return false, "invalid event rule"
        end
        if rule.pattern ~= nil and type(rule.pattern) ~= "string" then
            return false, "invalid event pattern"
        end
        if rule.filter ~= nil and type(rule.filter) ~= "function" then
            return false, "invalid event filter"
        end
    end
    -- Definitions are registered once and treated as immutable thereafter.
    encounters[id] = definition
    return true
end

function mechanics.GetActiveEncounter()
    if not active then return nil end
    return active.id, active.generation
end

function mechanics.GetGeneration()
    return generation
end

function mechanics.StopEncounter(reason, expectedGeneration)
    local old = active
    if not old or (expectedGeneration and old.generation ~= expectedGeneration) then
        return false
    end
    -- Invalidate before callbacks: a late event/timer from the previous fight
    -- must not act on a newly started fight, even if its encounter id matches.
    active = nil
    generation = generation + 1
    ClearTimers()
    bindings = {}
    mechanics.ClearPresentation()
    if old.definition.onStop then
        old.definition.onStop(reason or "stopped", old.generation)
    end
    return true
end

function mechanics.Reset(reason)
    if active then return mechanics.StopEncounter(reason or "reset") end
    generation = generation + 1
    ClearTimers()
    bindings = {}
    mechanics.ClearPresentation()
    return true
end

function mechanics.StartEncounter(id)
    local definition = encounters[id]
    if not definition then return false, "unknown encounter" end
    if active then
        mechanics.StopEncounter("replaced")
        -- A lifecycle callback may itself start a different encounter. Do not
        -- silently overwrite the replacement it installed.
        if active then return false, "encounter changed during stop" end
    end
    generation = generation + 1
    ClearTimers()
    bindings = {}
    mechanics.ClearPresentation()
    active = { id = id, generation = generation, definition = definition }
    if definition.onStart then definition.onStart(generation) end
    if not active or active.generation ~= generation then
        return false, "encounter changed during start"
    end
    return true, generation
end

-- Called only by the eventual SCB-owned event router. Optional token rejects
-- delayed/stale forwarded events; direct native events may omit it.
-- details is a caller-owned payload, not a duplicate roster or bot state.
function mechanics.DispatchEvent(eventName, message, details, expectedGeneration)
    local session = active
    local rules, i, rule, matched, delivered
    if not session or (expectedGeneration and expectedGeneration ~= session.generation) then
        return 0
    end
    if type(eventName) ~= "string" then return 0 end
    rules = session.definition.events or {}
    delivered = 0
    for i = 1, table.getn(rules) do
        if active ~= session then break end
        rule = rules[i]
        if rule.event == eventName then
            matched = true
            if rule.pattern then
                matched = type(message) == "string"
                    and string.find(message, rule.pattern, 1, rule.plain == true) ~= nil
            end
            if matched and rule.filter then
                matched = rule.filter(message, details, eventName) == true
            end
            if active ~= session then break end
            if matched then
                -- Never issue bot commands here. Encounter actions must call
                -- the SCB-authoritative owners when integration is approved.
                rule.handler(message, details, eventName, session.generation)
                delivered = delivered + 1
            end
        end
    end
    return delivered
end

-- A name is unique within the current encounter. Re-scheduling replaces it.
-- kind preserves fixed / predicted / observed provenance for later templates.
function mechanics.ScheduleTimer(name, delay, callback, kind)
    if not active then return false, "no active encounter" end
    if type(name) ~= "string" or name == "" or type(delay) ~= "number"
        or delay < 0 or delay ~= delay or delay == math.huge then
        return false, "invalid timer"
    end
    if callback ~= nil and type(callback) ~= "function" then
        return false, "invalid timer callback"
    end
    kind = kind or "fixed"
    if kind ~= "fixed" and kind ~= "predicted" and kind ~= "observed" then
        return false, "invalid timer kind"
    end
    timerOrder = timerOrder + 1
    timers[name] = {
        name = name, deadline = Now() + delay, callback = callback,
        kind = kind, generation = active.generation, order = timerOrder,
    }
    return true
end

function mechanics.CancelTimer(name)
    if not timers[name] then return false end
    timers[name] = nil
    return true
end

function mechanics.GetTimer(name)
    local timer = timers[name]
    if not active or not timer or timer.generation ~= active.generation then
        return nil
    end
    -- Return a copy; rendering callers must not mutate scheduler ownership.
    return { name = timer.name, deadline = timer.deadline,
        kind = timer.kind, generation = timer.generation }
end

function mechanics.GetTimerRemaining(name)
    local timer = mechanics.GetTimer(name)
    if not timer then return nil end
    return math.max(0, timer.deadline - Now())
end

-- No independent OnUpdate frame. The SCB event/lifecycle owner will call this
-- after the separate activation approval; callbacks can safely reset, replace
-- or reschedule timers while an expiration batch is being processed.
function mechanics.UpdateTimers(now)
    local session = active
    local due, name, timer, i, fired
    if not session then return 0 end
    if type(now) ~= "number" then now = Now() end
    due = {}
    for name, timer in pairs(timers) do
        if timer.generation == session.generation and timer.deadline <= now then
            table.insert(due, timer)
        end
    end
    table.sort(due, function(a, b)
        if a.deadline == b.deadline then return a.order < b.order end
        return a.deadline < b.deadline
    end)
    fired = 0
    for i = 1, table.getn(due) do
        if active ~= session then break end
        timer = due[i]
        if timers[timer.name] == timer then
            timers[timer.name] = nil
            fired = fired + 1
            if timer.callback then
                timer.callback(timer.name, timer.kind, session.generation)
            end
        end
    end
    return fired
end


-- Dormant presentation templates. The SCB lifecycle owner will invoke
-- UpdatePresentation() along with UpdateTimers() after activation. Nothing in
-- this section registers events, installs an OnUpdate or alters bot state.
-- Anchors are session-local; persistence/options belong to activation.
local presentation = {
    timer = { pool = {}, position = { "TOP", "TOP", 0, -150 }, width = 220, height = 23 },
    aura = { pool = {}, position = { "TOPLEFT", "TOPLEFT", 30, -180 }, width = 190, height = 25 },
    action = { pool = {}, position = { "TOPRIGHT", "TOPRIGHT", -30, -180 }, width = 190, height = 28 },
}
local presentationOrder = 0

local function PresentationGroup(kind)
    if type(kind) ~= "string" then return nil end
    return presentation[kind]
end

local function LayoutPresentation(kind)
    local group = PresentationGroup(kind)
    local index, slot, frame, p
    if not group then return end
    index = 0
    for _, slot in ipairs(group.pool) do
        if slot.used then
            index = index + 1
            frame = slot.frame
            p = slot.position or group.position
            frame:ClearAllPoints()
            frame:SetPoint(p[1], UIParent, p[2], p[3], p[4] - (slot.position and 0 or (index - 1) * (group.height + 4)))
        end
    end
end

local function CreatePresentationFrame(kind, group)
    local frame = CreateFrame(kind == "action" and "Button" or "Frame", nil, UIParent)
    frame:SetWidth(group.width)
    frame:SetHeight(group.height)
    frame:SetFrameStrata("MEDIUM")
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetTexture(0, 0, 0, 0.7)
    frame.background = background
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", frame, "LEFT", 6, 0)
    label:SetJustifyH("LEFT")
    label:SetWidth(group.width - 58)
    frame.label = label
    local detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    detail:SetJustifyH("RIGHT")
    detail:SetWidth(49)
    frame.detail = detail
    if kind == "timer" then
        local bar = CreateFrame("StatusBar", nil, frame)
        bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 2)
        bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
        bar:SetHeight(4)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetStatusBarColor(0.3, 0.65, 0.9)
        bar:SetMinMaxValues(0, 1)
        frame.bar = bar
    elseif kind == "action" then
        local overlay = frame:CreateTexture(nil, "OVERLAY")
        overlay:Hide()
        frame.scbOverlay = overlay
        frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        frame:SetScript("OnClick", function()
            local slot = frame.scbSlot
            if not slot or not slot.used or not active
                or slot.generation ~= active.generation then return end
            mechanics.HandleActionClick(slot.key, arg1 or "LeftButton")
        end)
    end
    frame:Hide()
    return frame
end

local function AcquirePresentation(kind, key)
    local group = PresentationGroup(kind)
    local slot, free
    if not active then return nil, "no active encounter" end
    if not group or type(key) ~= "string" or key == "" then
        return nil, "invalid presentation"
    end
    for _, slot in ipairs(group.pool) do
        if slot.used and slot.key == key and slot.generation == active.generation then
            return slot
        end
        if not slot.used and not free then free = slot end
    end
    slot = free
    if not slot then
        slot = { frame = CreatePresentationFrame(kind, group) }
        table.insert(group.pool, slot)
        slot.frame.scbSlot = slot
    end
    presentationOrder = presentationOrder + 1
    slot.used = true
    slot.key = key
    slot.generation = active.generation
    slot.callback = nil
    slot.boundDefinition = nil
    slot.position = nil
    slot.expiresAt = nil
    if slot.frame.scbOverlay then slot.frame.scbOverlay:Hide() end
    slot.frame:Show()
    LayoutPresentation(kind)
    return slot
end

local function ReleasePresentation(kind, key)
    local group = PresentationGroup(kind)
    if not group then return false end
    for _, slot in ipairs(group.pool) do
        if slot.used and slot.key == key then
            slot.used = false
            slot.key = nil
            slot.callback = nil
            slot.boundDefinition = nil
            slot.position = nil
            slot.expiresAt = nil
            slot.generation = nil
            if slot.frame.scbOverlay then slot.frame.scbOverlay:Hide() end
            slot.frame:Hide()
            slot.frame.label:SetText("")
            slot.frame.detail:SetText("")
            LayoutPresentation(kind)
            return true
        end
    end
    return false
end

-- point and relativePoint are ordinary WoW anchor strings. No SavedVariables
-- or global positioning preferences are modified here.
function mechanics.SetTemplatePosition(kind, point, relativePoint, x, y)
    local group = PresentationGroup(kind)
    if not group or type(point) ~= "string" or type(relativePoint) ~= "string"
        or type(x) ~= "number" or type(y) ~= "number"
        or x ~= x or y ~= y or math.abs(x) == math.huge
        or math.abs(y) == math.huge then
        return false, "invalid template position"
    end
    group.position = { point, relativePoint, x, y }
    LayoutPresentation(kind)
    return true
end

function mechanics.GetTemplatePosition(kind)
    local group = PresentationGroup(kind)
    if not group then return nil end
    local p = group.position
    return p[1], p[2], p[3], p[4]
end

-- Timer presentation reads the named encounter timer owned by Chunk 1.
-- A missing/expired timer removes its bar; kind labels are explicit so an
-- estimated cooldown is never implicitly displayed as an observed cast.
function mechanics.ShowTimer(key, timerName, label)
    local timer = mechanics.GetTimer(timerName)
    local slot, err
    if not timer then return false, "timer not scheduled" end
    slot, err = AcquirePresentation("timer", key)
    if not slot then return false, err end
    slot.timerName = timerName
    slot.startedAt = Now()
    slot.label = label or timerName
    mechanics.UpdatePresentation()
    return true
end

-- Aura rows display caller-observed state, never infer target identity or
-- independently scan/track party members. expiresAt is optional.
function mechanics.ShowTrackedAura(key, label, target, expiresAt)
    local slot, err
    if type(label) ~= "string" or type(target) ~= "string"
        or (expiresAt ~= nil and (type(expiresAt) ~= "number" or expiresAt ~= expiresAt)) then
        return false, "invalid aura"
    end
    slot, err = AcquirePresentation("aura", key)
    if not slot then return false, err end
    slot.label = label
    slot.target = target
    slot.expiresAt = expiresAt
    mechanics.UpdatePresentation()
    return true
end

-- Action callbacks are supplied only by the future SCB-owned integration
-- contracts (Chunk 3); this builder never resolves or manipulates a bot.
function mechanics.ShowBotAction(key, label, detail, callback)
    local slot, err
    if type(label) ~= "string" or (detail ~= nil and type(detail) ~= "string")
        or (callback ~= nil and type(callback) ~= "function") then
        return false, "invalid action"
    end
    slot, err = AcquirePresentation("action", key)
    if not slot then return false, err end
    slot.label = label
    slot.callback = callback
    slot.boundDefinition = nil
    slot.frame.label:SetText(label)
    slot.frame.detail:SetText(detail or "")
    return true
end

function mechanics.HidePresentation(kind, key)
    return ReleasePresentation(kind, key)
end

-- Clears active slots, not allocations: a new encounter reuses hidden frames.
-- This is also invoked on Start/Stop/Reset, before stop callbacks.
function mechanics.ClearPresentation()
    for kind, group in pairs(presentation) do
        for _, slot in ipairs(group.pool) do
            slot.used = false
            slot.key = nil
            slot.callback = nil
            slot.boundDefinition = nil
            slot.position = nil
            slot.expiresAt = nil
            if slot.frame.scbOverlay then slot.frame.scbOverlay:Hide() end
            slot.generation = nil
            slot.timerName = nil
            slot.label = nil
            slot.target = nil
            slot.expiresAt = nil
            slot.frame:Hide()
        end
    end
end

-- The existing SCB owner supplies the tick; do not attach frame OnUpdate.
function mechanics.UpdatePresentation(now)
    local session = active
    local group, slot, timer, remaining
    if not session then return end
    if type(now) ~= "number" then now = Now() end
    group = presentation.timer
    for _, slot in ipairs(group.pool) do
        if slot.used and slot.generation == session.generation then
            timer = mechanics.GetTimer(slot.timerName)
            if not timer then
                ReleasePresentation("timer", slot.key)
            else
                remaining = math.max(0, timer.deadline - now)
                slot.frame.label:SetText(slot.label)
                slot.frame.detail:SetText(string.format("%.0fs", remaining))
                slot.frame.bar:SetValue(remaining / math.max(1, timer.deadline - (slot.startedAt or now)))
                slot.frame.bar:SetStatusBarColor(
                    timer.kind == "predicted" and 0.9 or 0.3,
                    timer.kind == "observed" and 0.8 or 0.65, 0.3)
                slot.frame:Show()
            end
        end
    end
    for _, slot in ipairs(presentation.aura.pool) do
        if slot.used and slot.generation == session.generation then
            slot.frame.label:SetText(slot.target .. ": " .. slot.label)
            if slot.expiresAt then
                slot.frame.detail:SetText(string.format("%.0fs", math.max(0, slot.expiresAt - now)))
            else
                slot.frame.detail:SetText("")
            end
        end
    end
end
