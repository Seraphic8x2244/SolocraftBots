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
    if slot.frame.scbOverlay then
        slot.frame.scbOverlay:Hide()
        -- Recycled action frames may previously have contained an art overlay.
        slot.frame.label:ClearAllPoints()
        slot.frame.label:SetPoint("LEFT", slot.frame, "LEFT", 6, 0)
        slot.frame.label:SetWidth(group.width - 58)
    end
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


-- Chunk 3: encounter-local bindings. Save only a name and generation; never
-- maintain a second bot roster or retain a unit token across observations.
local function ResolveBoundLive(name, botOnly, refresh)
    local member
    if type(name) ~= "string" or name == "" or not SCB_GetLiveMember then return nil end
    member = SCB_GetLiveMember(name, refresh and true or false)
    if not member or member.name ~= name or not member.unit
        or not UnitName or UnitName(member.unit) ~= name
        or (UnitExists and not UnitExists(member.unit)) then return nil end
    if botOnly and (not member.isBot or not SCB_IsBotName
        or not SCB_IsBotName(name)) then return nil end
    return member
end

function mechanics.BindObservedMember(key, name, expectedGeneration)
    if not active or (expectedGeneration and expectedGeneration ~= active.generation) then
        return false, "stale encounter"
    end
    if type(key) ~= "string" or key == "" or not ResolveBoundLive(name, false, true) then
        return false, "member not in live roster"
    end
    bindings[key] = { name = name, generation = active.generation }
    return true
end

function mechanics.BindSelectedBot(key, expectedGeneration)
    local name
    if not active or (expectedGeneration and expectedGeneration ~= active.generation) then
        return false, "stale encounter"
    end
    if not SCB_IsFriendlyBotTarget or not SCB_IsFriendlyBotTarget() then
        return false, "select a friendly bot"
    end
    name = UnitName and UnitName("target") or nil
    if not ResolveBoundLive(name, true, true) then return false, "bot not in live roster" end
    bindings[key] = { name = name, generation = active.generation }
    return true, name
end

function mechanics.ClearBinding(key, expectedGeneration)
    if not active or (expectedGeneration and expectedGeneration ~= active.generation)
        or not bindings[key] then return false end
    bindings[key] = nil
    return true
end

function mechanics.GetBoundMember(key, expectedGeneration, refresh)
    local binding = bindings[key]
    if not active or (expectedGeneration and expectedGeneration ~= active.generation)
        or not binding or binding.generation ~= active.generation then return nil end
    return binding.name, ResolveBoundLive(binding.name, false, refresh)
end

-- Authoritative integration seam, intentionally NOT implemented here:
--   SCB_RequestVerifiedBotSequence(name, steps, stillValid)
-- The SCB targeted-command owner must select the exact live bot; prove that
-- server-side target identity has updated (a client target event, UnitName or
-- fixed settle delay is NOT proof); then issue each step through its own
-- SCB_RequestCommand owner in order. The owner must reject lost identity,
-- timeout, overlapping commands or stale generation without leaking an
-- object command to "all". No verified target-selection owner currently exists.
-- Thus this dormant adapter fails CLOSED rather than faking acknowledgement.
function mechanics.RunBoundBotAction(bindingKey, action, expectedGeneration)
    local name, member, i, step, info, route, capturedGeneration
    if not active or (expectedGeneration and expectedGeneration ~= active.generation) then
        return false, "stale encounter"
    end
    if type(action) ~= "table" then return false, "invalid action" end
    name, member = mechanics.GetBoundMember(bindingKey, expectedGeneration, true)
    if not name or not member or not member.isBot or not SCB_IsBotName
        or not SCB_IsBotName(name) then return false, "not a confirmed live bot" end
    if action.type == "kick" then
        if not SCB_KickBots then return false, "kick owner unavailable" end
        -- Existing queue, final-bot and Loot Safe decisions remain authoritative.
        return SCB_KickBots("all", { name = name })
    end
    if action.type ~= "sequence" or type(action.steps) ~= "table"
        or table.getn(action.steps) == 0 then return false, "invalid sequence" end
    for i = 1, table.getn(action.steps) do
        step = action.steps[i]
        info = type(step) == "table" and SCB.commands and SCB.commands[step.command] or nil
        route = info and info.routes and info.routes[step.scope] or nil
        if not route then return false, "unsupported command route" end
    end
    if not SCB_RequestVerifiedBotSequence then
        return false, "server target-confirmation owner unavailable"
    end
    capturedGeneration = active.generation
    return SCB_RequestVerifiedBotSequence(name, action.steps, function()
        local liveName, liveMember = mechanics.GetBoundMember(bindingKey, capturedGeneration, true)
        return liveName == name and liveMember and liveMember.isBot
            and SCB_IsBotName and SCB_IsBotName(name) or false
    end)
end

local function RefreshBoundAction(slot)
    local config = slot.boundDefinition
    local name, member, isBot, label
    if not config then return end
    name, member = mechanics.GetBoundMember(config.binding, slot.generation, false)
    isBot = member and member.isBot and SCB_IsBotName and SCB_IsBotName(name)
    -- A human aura victim may have an observed binding, but must never see a
    -- kick action. Also hide an unavailable victim rather than guessing.
    if config.action and config.action.type == "kick" and not config.assignable
        and not isBot then slot.frame:Hide(); return end
    if name then
        if config.assignedLabel == "name" then label = name
        else label = (config.assignedLabel or config.label) .. ": " .. name end
    else
        label = config.label
    end
    slot.frame.label:SetText(label)
    slot.frame.detail:SetText(name and not isBot and "Unavailable" or (config.detail or ""))
    slot.frame:Show()
end

-- Generic action frame: assignable bot icon (left assign, left act, right clear)
-- or observed-member action (e.g. an individual Burning Adrenaline kick).
-- "icon" and "position" are optional presentation data, not encounter logic.
-- icon = { texture=path, size=30, point="CENTER",
--          relativePoint="LEFT", x=0, y=0 }
-- position = { "TOP", "TOP", x, y }; expiresAt = absolute GetTime.
function mechanics.ShowBoundBotAction(key, config)
    local slot, err, icon, pos, step, i, overlay
    if type(config) ~= "table" or type(config.binding) ~= "string"
        or config.binding == "" or type(config.label) ~= "string"
        or config.label == "" or (config.assignedLabel ~= nil
        and type(config.assignedLabel) ~= "string")
        or (config.detail ~= nil and type(config.detail) ~= "string")
        or (config.assignable ~= nil and type(config.assignable) ~= "boolean") then
        return false, "invalid bound action"
    end
    if config.action ~= nil then
        if type(config.action) ~= "table" then return false, "invalid bound action" end
        if config.action.type == "sequence" then
            if type(config.action.steps) ~= "table"
                or table.getn(config.action.steps) == 0 then return false, "invalid sequence" end
            for i = 1, table.getn(config.action.steps) do
                step = config.action.steps[i]
                if type(step) ~= "table" or type(step.command) ~= "string"
                    or type(step.scope) ~= "string" then return false, "invalid step" end
            end
        elseif config.action.type ~= "kick" then return false, "invalid action type" end
    end
    icon = config.icon
    if icon ~= nil and (type(icon) ~= "table" or type(icon.texture) ~= "string"
        or icon.texture == "" or (icon.size ~= nil
        and (type(icon.size) ~= "number" or icon.size <= 0
        or icon.size ~= icon.size or icon.size == math.huge))
        or (icon.point ~= nil and type(icon.point) ~= "string")
        or (icon.relativePoint ~= nil and type(icon.relativePoint) ~= "string")
        or (icon.x ~= nil and (type(icon.x) ~= "number" or icon.x ~= icon.x
        or math.abs(icon.x) == math.huge))
        or (icon.y ~= nil and (type(icon.y) ~= "number" or icon.y ~= icon.y
        or math.abs(icon.y) == math.huge))) then
        return false, "invalid overlay"
    end
    pos = config.position
    if pos ~= nil and (type(pos) ~= "table" or type(pos[1]) ~= "string"
        or type(pos[2]) ~= "string" or type(pos[3]) ~= "number"
        or type(pos[4]) ~= "number" or pos[3] ~= pos[3] or pos[4] ~= pos[4]
        or math.abs(pos[3]) == math.huge or math.abs(pos[4]) == math.huge) then
        return false, "invalid position"
    end
    if config.expiresAt ~= nil and (type(config.expiresAt) ~= "number"
        or config.expiresAt ~= config.expiresAt or config.expiresAt == math.huge) then
        return false, "invalid lifespan"
    end
    slot, err = AcquirePresentation("action", key)
    if not slot then return false, err end
    slot.boundDefinition = config
    slot.position = pos
    slot.expiresAt = config.expiresAt
    overlay = slot.frame.scbOverlay
    if icon then
        overlay:ClearAllPoints()
        overlay:SetPoint(icon.point or "CENTER", slot.frame,
            icon.relativePoint or "LEFT", icon.x or 0, icon.y or 0)
        overlay:SetWidth(icon.size or 30)
        overlay:SetHeight(icon.size or 30)
        overlay:SetTexture(icon.texture)
        overlay:Show()
        slot.frame.label:ClearAllPoints()
        slot.frame.label:SetPoint("LEFT", slot.frame, "LEFT", 22, 0)
        slot.frame.label:SetWidth(presentation.action.width - 74)
    else
        slot.frame.label:ClearAllPoints()
        slot.frame.label:SetPoint("LEFT", slot.frame, "LEFT", 6, 0)
        slot.frame.label:SetWidth(presentation.action.width - 58)
    end
    LayoutPresentation("action")
    RefreshBoundAction(slot)
    return true
end

-- Synthetic and UI clicks share this guard; no callbacks outlive a generation.
function mechanics.HandleActionClick(key, mouseButton)
    local slot, cfg, name, member, ok, err
    if not active then return false, "no active encounter" end
    for _, slot in ipairs(presentation.action.pool) do
        if slot.used and slot.key == key and slot.generation == active.generation then
            if slot.expiresAt and Now() >= slot.expiresAt then
                ReleasePresentation("action", key)
                return false, "action expired"
            end
            cfg = slot.boundDefinition
            if not cfg then
                if mouseButton ~= "RightButton" and slot.callback then
                    slot.callback(key, active.generation)
                    return true
                end
                return false, "no action"
            end
            if mouseButton == "RightButton" then
                if not cfg.assignable then return false, "not assignable" end
                ok = mechanics.ClearBinding(cfg.binding, active.generation)
                RefreshBoundAction(slot)
                return ok
            end
            if mouseButton ~= "LeftButton" then return false, "invalid click" end
            name, member = mechanics.GetBoundMember(cfg.binding, active.generation, false)
            if not name and cfg.assignable then
                ok, err = mechanics.BindSelectedBot(cfg.binding, active.generation)
                RefreshBoundAction(slot)
                return ok, err
            end
            if not cfg.action then return false, "no action configured" end
            ok, err = mechanics.RunBoundBotAction(cfg.binding, cfg.action, active.generation)
            RefreshBoundAction(slot)
            return ok, err
        end
    end
    return false, "action not shown"
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
    for _, slot in ipairs(presentation.action.pool) do
        if slot.used and slot.generation == session.generation then
            if slot.expiresAt and now >= slot.expiresAt then
                ReleasePresentation("action", slot.key)
            elseif slot.boundDefinition then
                RefreshBoundAction(slot)
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
