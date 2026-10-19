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

-- Boss presence is independent of confirmed engagement. The eventual SCB
-- lifecycle owner decides when a valid server combat observation occurs.
function mechanics.MarkEncounterEngaged(expectedGeneration)
    if not active or (expectedGeneration and expectedGeneration ~= active.generation) then
        return false, "stale encounter"
    end
    if active.engaged then return true end
    active.engaged = true
    return mechanics.InitializeAbilities(active.generation)
end

function mechanics.GetEncounterState()
    if not active then return nil end
    return { id = active.id, generation = active.generation,
        bossVisible = active.bossVisible == true, engaged = active.engaged == true }
end

-- Return an immutable-by-copy view of genuinely observed abilities in a named
-- group, in first-seen order. Empty means none observed, NOT none configured.
function mechanics.GetObservedAbilities(group, expectedGeneration)
    local result, data, i
    if not active or (expectedGeneration and expectedGeneration ~= active.generation)
        or type(group) ~= "string" then return nil end
    result = {}
    data = active.observedAbilities and active.observedAbilities[group]
    if data then
        for i = 1, table.getn(data.order) do result[i] = data.order[i] end
    end
    return result
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
    if active == session and session.definition.declarative then
        delivered = delivered + mechanics.DispatchDeclarativeEvent(session, eventName, message)
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
-- Three adjacent top-centred columns, left to right: Timer | Aura | Action.
-- Total width: 220 + 12 + 190 + 12 + 190 = 624, centred about UIParent.
local presentation = {
    timer = { pool = {}, position = { "TOPLEFT", "TOP", -312, -150 }, width = 220, height = 23 },
    aura = { pool = {}, position = { "TOPLEFT", "TOP", -80, -150 }, width = 190, height = 25 },
    action = { pool = {}, position = { "TOPLEFT", "TOP", 122, -150 }, width = 190, height = 28 },
}
local presentationOrder = 0

-- Position previews have no encounter/event/tick dependency. Their sample rows
-- are made with the actual presentation factory and cannot execute actions.
-- The persistent positions belong to the existing SCB options DB; unlocking
-- itself is temporary, so reloads never leave the edit handles open.
local SCB_BOSSMOD_PREVIEW_HEADER = 22
local bossModsPreview = { unlocked = false, handles = {} }
local previewDefaults = {
    timer = { anchor = "TOP", x = -312, y = -128 },
    aura = { anchor = "TOP", x = -80, y = -128 },
    action = { anchor = "TOP", x = 122, y = -128 },
}
local function PreviewPosition(kind)
    local options = SoloCraftBotsDB and SoloCraftBotsDB.options
    local saved = options and options.bossModsPositions
        and options.bossModsPositions[kind]
    if type(saved) == "table"
        and (saved.anchor == "TOP" or saved.anchor == "TOPLEFT"
            or saved.anchor == "TOPRIGHT" or saved.anchor == "BOTTOMLEFT"
            or saved.anchor == "BOTTOMRIGHT")
        and type(saved.x) == "number" and saved.x == saved.x
        and math.abs(saved.x) < math.huge
        and type(saved.y) == "number" and saved.y == saved.y
        and math.abs(saved.y) < math.huge then
        return saved
    end
    return previewDefaults[kind]
end

local function ApplyPreviewPosition(kind)
    local pos = PreviewPosition(kind)
    local group = presentation[kind]
    if not group then return end
    -- Saved coordinates anchor the preview header; live rows start beneath it.
    group.position = { "TOPLEFT", pos.anchor, pos.x,
        pos.y - SCB_BOSSMOD_PREVIEW_HEADER }
    local handle = bossModsPreview.handles[kind]
    if handle then
        handle:ClearAllPoints()
        handle:SetPoint("TOPLEFT", UIParent, pos.anchor, pos.x, pos.y)
    end
    -- Uses the existing real-row layout owner.
    -- LayoutPresentation is declared below, and invoked by LoadPreviewPositions.
end

function mechanics.LoadPreviewPositions()
    for kind in pairs(presentation) do
        ApplyPreviewPosition(kind)
    end
    -- The live UI is still dormant at this stage; existing rows are normally
    -- empty here. Reposition any previously allocated slots when requested.
    for kind, group in pairs(presentation) do
        local index = 0
        for _, slot in ipairs(group.pool) do
            if slot.used then
                index = index + 1
                local p = slot.position or group.position
                slot.frame:ClearAllPoints()
                slot.frame:SetPoint(p[1], UIParent, p[2], p[3],
                    p[4] - (slot.position and 0 or (index - 1) * (group.height + 4)))
            end
        end
    end
end

function mechanics.IsPreviewUnlocked()
    return bossModsPreview.unlocked
end

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
        bar:SetHeight(8)
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

-- UI-only layout editor: two real-style sample elements per column.
-- They never use AcquirePresentation, an active encounter or command owners.
local function SavePreviewDrag(kind, handle)
    if not SoloCraftBotsDB then return end
    SoloCraftBotsDB.options = SoloCraftBotsDB.options or {}
    local opts = SoloCraftBotsDB.options
    opts.bossModsPositions = opts.bossModsPositions or {}
    local left, right, top, bottom = handle:GetLeft(), handle:GetRight(),
        handle:GetTop(), handle:GetBottom()
    local pl, pr, pt, pb = UIParent:GetLeft(), UIParent:GetRight(),
        UIParent:GetTop(), UIParent:GetBottom()
    if not left or not right or not top or not bottom
        or not pl or not pr or not pt or not pb then return end
    local horizontal = (left - pl <= pr - right) and "LEFT" or "RIGHT"
    local vertical = (pt - top <= bottom - pb) and "TOP" or "BOTTOM"
    local anchor = vertical .. horizontal
    local originX = horizontal == "LEFT" and pl or pr
    local originY = vertical == "TOP" and pt or pb
    opts.bossModsPositions[kind] = {
        anchor = anchor, x = left - originX, y = top - originY,
    }
    mechanics.LoadPreviewPositions()
end

local function CreatePreviewHandle(kind)
    local group = presentation[kind]
    local handle = CreateFrame("Frame", nil, UIParent)
    handle:SetWidth(group.width)
    handle:SetHeight(SCB_BOSSMOD_PREVIEW_HEADER + 2 * (group.height + 4))
    handle:SetFrameStrata("DIALOG")
    handle:SetMovable(true)
    handle:SetClampedToScreen(true)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    handle:SetBackdropColor(0.04, 0.08, 0.12, 0.65)
    handle:SetBackdropBorderColor(0.4, 0.7, 0.95, 1)
    local title = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", handle, "TOPLEFT", 6, -4)
    title:SetText(SCB_L("BOSSMODS_DRAG_" .. string.upper(kind)))
    for i = 1, 2 do
        local sample = CreatePresentationFrame(kind, group)
        sample:SetParent(handle)
        sample:SetFrameStrata("DIALOG")
        sample:SetFrameLevel(handle:GetFrameLevel() + 1)
        sample:ClearAllPoints()
        sample:SetPoint("TOPLEFT", handle, "TOPLEFT", 0,
            -SCB_BOSSMOD_PREVIEW_HEADER - (i - 1) * (group.height + 4))
        -- Preview actions must never execute the real bound bot callback.
        if kind == "action" then sample:EnableMouse(false) end
        if kind == "timer" then
            sample.label:SetText(SCB_L(i == 1 and "BOSSMODS_SAMPLE_BLAST" or "BOSSMODS_SAMPLE_SHADOW"))
            sample.detail:SetText(i == 1 and "20s" or "12s")
            sample.bar:SetValue(i == 1 and 0.65 or 0.3)
        elseif kind == "aura" then
            sample.label:SetText(SCB_L(i == 1 and "BOSSMODS_SAMPLE_AURA_BOT" or "BOSSMODS_SAMPLE_AURA_PLAYER"))
            sample.detail:SetText(i == 1 and "16s" or "10s")
        else
            sample.label:SetText(SCB_L(i == 1 and "BOSSMODS_SAMPLE_KICK" or "BOSSMODS_SAMPLE_EGGBREAKER"))
            sample.detail:SetText("")
            if i == 2 then
                sample.scbOverlay:SetPoint("CENTER", sample, "LEFT", 0, 3)
                sample.scbOverlay:SetWidth(24)
                sample.scbOverlay:SetHeight(24)
                sample.scbOverlay:SetTexture("Interface\\Icons\\INV_Egg_03")
                sample.scbOverlay:Show()
            end
        end
        sample:Show()
    end
    handle:SetScript("OnDragStart", function()
        if bossModsPreview.unlocked then this:StartMoving() end
    end)
    handle:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        if this.SetUserPlaced then this:SetUserPlaced(false) end
        SavePreviewDrag(kind, this)
    end)
    handle:SetScript("OnHide", function()
        this:StopMovingOrSizing()
    end)
    handle:Hide()
    bossModsPreview.handles[kind] = handle
    ApplyPreviewPosition(kind)
    return handle
end

function mechanics.SetPreviewUnlocked(enabled)
    bossModsPreview.unlocked = enabled and true or false
    if bossModsPreview.unlocked then
        mechanics.LoadPreviewPositions()
        for _, kind in ipairs({ "timer", "aura", "action" }) do
            local handle = bossModsPreview.handles[kind] or CreatePreviewHandle(kind)
            handle:Show()
        end
    else
        for _, handle in pairs(bossModsPreview.handles) do handle:Hide() end
    end
    return true
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
    slot.memberBinding = nil
    slot.abilityRecord, slot.abilityHint = nil, nil
    slot.timerName = nil
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
            slot.memberBinding = nil
            slot.abilityRecord, slot.abilityHint = nil, nil
            slot.timerName = nil
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

-- Aura rows display caller-observed state. Only recipient/member auras have
-- a memberBinding; observed *ability names* (e.g. Chromaggus breaths) do not.
-- Member auras are retired when the target is dead or leaves the live roster.
function mechanics.ShowTrackedAura(key, label, target, expiresAt, memberBinding)
    local slot, err
    if type(label) ~= "string" or type(target) ~= "string"
        or (expiresAt ~= nil and (type(expiresAt) ~= "number" or expiresAt ~= expiresAt))
        or (memberBinding ~= nil and (type(memberBinding) ~= "string"
            or memberBinding == "")) then
        return false, "invalid aura"
    end
    slot, err = AcquirePresentation("aura", key)
    if not slot then return false, err end
    slot.label = label
    slot.target = target
    slot.expiresAt = expiresAt
    slot.memberBinding = memberBinding
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

-- Generic delayed, targeted action sequence. A click targets the assigned
-- roster bot, then uses the EXISTING encounter-owned named timer scheduler
-- for the data-defined delay. When due, every command goes through
-- SCB_RequestCommand; mechanics owns neither command transport nor a ticker.
-- This is deliberately a target-propagation delay, NOT a server ACK.
local sequenceSerial = 0
-- Boss Mods-only settle after an addon-controlled target change. Regular
-- player-initiated Single commands and Group's own settle are unaffected.
local SCB_BOSSMOD_TARGET_SETTLE = 0.10
local function ValidSequenceTargetDelay(value)
    return value == nil or (type(value) == "number" and value > 0
        and value == value and value < math.huge)
end

local function AssignedBotStillTargeted(name)
    return UnitName and UnitName("target") == name
        and SCB_IsFriendlyBotTarget and SCB_IsFriendlyBotTarget()
end

function mechanics.RunBoundBotAction(bindingKey, action, expectedGeneration)
    local name, member, i, step, info, route, capturedGeneration, timerName
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
        or table.getn(action.steps) == 0
        or not ValidSequenceTargetDelay(action.targetDelay) then
        return false, "invalid delayed sequence"
    end
    for i = 1, table.getn(action.steps) do
        step = action.steps[i]
        info = type(step) == "table" and SCB.commands and SCB.commands[step.command] or nil
        route = info and info.routes and info.routes[step.scope] or nil
        if not route then return false, "unsupported command route" end
    end
    if not TargetUnit or not SCB_RequestCommand then
        return false, "target or command owner unavailable"
    end

    -- Target selection is the only immediate operation. Commands must not be
    -- sent on this click/frame, even if UnitName("target") updates instantly.
    TargetUnit(member.unit)
    if not AssignedBotStillTargeted(name) then
        return false, "assigned bot target selection failed"
    end
    capturedGeneration = active.generation
    local originalBinding = bindings[bindingKey]
    sequenceSerial = sequenceSerial + 1
    timerName = "delayed-bot-sequence:" .. capturedGeneration .. ":" .. sequenceSerial
    -- Unique timer names preserve repeated clicks (including rapid Come spam).
    -- Reset/death/encounter change clears the encounter timer and bindings.
    return mechanics.ScheduleTimer(timerName,
        action.targetDelay or SCB_BOSSMOD_TARGET_SETTLE, function()
        local currentName, currentMember, commandStep, n
        if not active or active.generation ~= capturedGeneration
            or bindings[bindingKey] ~= originalBinding then return end
        for n = 1, table.getn(action.steps) do
            currentName, currentMember =
                mechanics.GetBoundMember(bindingKey, capturedGeneration, true)
            if bindings[bindingKey] ~= originalBinding
                or currentName ~= name or not currentMember or not currentMember.isBot
                or not SCB_IsBotName or not SCB_IsBotName(name)
                or not AssignedBotStillTargeted(name) then
                return
            end
            commandStep = action.steps[n]
            if not SCB_RequestCommand
                or not SCB_RequestCommand(commandStep.command, commandStep.scope) then
                return
            end
        end
    end, "fixed")
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
                or table.getn(config.action.steps) == 0
                or not ValidSequenceTargetDelay(config.action.targetDelay) then
                return false, "invalid delayed sequence"
            end
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
            slot.memberBinding = nil
            slot.frame:Hide()
        end
    end
end

-- A member aura disappears when its recorded recipient is confirmed dead
-- or no longer occupies a live SCB roster unit (including after filtered kick).
-- Read the authoritative roster; never maintain a shadow roster or poll units
-- with a separate frame. Ability observations have no memberBinding and persist.
local function TrackedMemberGone(name)
    local member
    if not SCB_GetLiveMember or not UnitName then return false end
    member = SCB_GetLiveMember(name, false)
    if not member or not member.unit or UnitName(member.unit) ~= name
        or (UnitExists and not UnitExists(member.unit)) then return true end
    return UnitIsDeadOrGhost and UnitIsDeadOrGhost(member.unit) and true or false
end

local function RetireTrackedMemberAura(slot)
    local key, binding = slot.key, slot.memberBinding
    mechanics.CancelTimer("expiration:" .. key)
    ReleasePresentation("action", "kick:" .. key)
    mechanics.ClearBinding(binding, slot.generation)
    ReleasePresentation("aura", key)
end

-- The existing SCB owner supplies the tick; do not attach frame OnUpdate.
function mechanics.UpdatePresentation(now)
    local session = active
    local group, slot, timer, remaining
    if not session then return end
    if type(now) ~= "number" then now = Now() end
    mechanics.UpdateAbilityStates(now)
    group = presentation.timer
    for _, slot in ipairs(group.pool) do
        if slot.used and slot.generation == session.generation then
            if slot.abilityRecord or slot.abilityHint then
                RenderAbilityBar(slot, now)
            else
                timer = mechanics.GetTimer(slot.timerName)
                if not timer then
                    ReleasePresentation("timer", slot.key)
                else
                    remaining = math.max(0, timer.deadline - now)
                    slot.frame.label:SetText(timer.kind == "predicted"
                        and "~" .. slot.label or slot.label)
                    slot.frame.detail:SetText(string.format("%.0fs", remaining))
                    slot.frame.bar:SetValue(math.max(0, math.min(1, (now -
                        (slot.startedAt or now)) / math.max(0.001, timer.deadline -
                        (slot.startedAt or now)))))
                    slot.frame.bar:SetStatusBarColor(0.22, 0.55, 0.94)
                    slot.frame:Show()
                end
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
            if slot.memberBinding and TrackedMemberGone(slot.target) then
                RetireTrackedMemberAura(slot)
            else
                slot.frame.label:SetText(slot.target .. ": " .. slot.label)
                if slot.expiresAt then
                    slot.frame.detail:SetText(string.format("%.0fs", math.max(0, slot.expiresAt - now)))
                else
                    slot.frame.detail:SetText("")
                end
            end
        end
    end
end


-- Encounter -> unique caster -> ability -> cast occurrence.
-- Pure encounter-local observations. No polling, transport, roster clone or
-- invented server casts; the existing SCB owner supplies events and time.
local function AbilityClock()
    return Now()
end

local function GetAbilitySession()
    if not active or not active.definition.declarative then return nil end
    return active
end

local function AddAbilityState(session, spec, spellName, observed)
    local id = spec.id
    if spellName then id = id .. ":" .. spellName end
    if session.abilities[id] then return session.abilities[id] end
    local now = AbilityClock()
    local state = {
        id = id, baseId = spec.id, name = spellName,
        spec = spec, caster = spec.caster, phase = "unstarted",
        casts = 0, auras = {}, generation = session.generation,
        observed = observed == true, uncertainty = nil,
    }
    if spec.firstDelay and not observed then
        state.startedAt = now
        state.readyAt = now + spec.firstDelay
        state.phase = "cooldown"
    elseif observed then
        state.phase = "ready"
        state.startedAt = now
        state.readyAt = now
    end
    session.abilities[id] = state
    table.insert(session.abilityOrder, id)
    return state
end

function mechanics.InitializeAbilities(expectedGeneration)
    local session = GetAbilitySession()
    local spec, group, i, j
    if not session or (expectedGeneration and session.generation ~= expectedGeneration) then
        return false, "stale encounter"
    end
    if not session.engaged then return false, "not engaged" end
    if session.abilities then return true end
    session.abilities, session.abilityOrder = {}, {}
    session.casterCasts, session.castSerial, session.firstSlotHints = {}, 0, {}
    for i, spec in ipairs(session.definition.declarative.abilities or {}) do
        AddAbilityState(session, spec, nil, false)
    end
    -- Unconfirmed first slots are visual predictions, never named breaths.
    for i, group in ipairs(session.definition.declarative.abilityGroups or {}) do
        session.firstSlotHints[group.id] = {}
        for j, duration in ipairs(group.firstSlots or {}) do
            session.firstSlotHints[group.id][j] = {
                id = "first:" .. group.id .. ":" .. j,
                label = group.label .. " " .. j, startedAt = AbilityClock(),
                readyAt = AbilityClock() + duration, speculative = true,
                provenance = "predicted",
            }
        end
    end
    if mechanics.ShowAbilityBars then mechanics.ShowAbilityBars() end
    return true
end

-- Dynamic names are learned from observed casts alone; never guess the
-- weekly breath setup from a first-countdown placeholder.
local function ResolveAbility(id, spellName)
    local session, group, i, j, observed, count, state
    session = GetAbilitySession()
    if not session or not session.engaged then return nil end
    if not session.abilities then mechanics.InitializeAbilities(session.generation) end
    state = session.abilities[id]
    if state then return state end
    for i, group in ipairs(session.definition.declarative.abilityGroups or {}) do
        if group.id == id and type(spellName) == "string" then
            observed = false
            for j = 1, table.getn(group.names or {}) do
                if group.names[j] == spellName then observed = true; break end
            end
            if not observed then return nil end
            state = session.abilities[id .. ":" .. spellName]
            if state then return state end
            count = 0
            for _, other in pairs(session.abilities) do
                if other.baseId == id then count = count + 1 end
            end
            -- Continue recognising later observations without a third UI bar.
            if count >= (group.maxVisible or 2) then return nil end
            state = AddAbilityState(session, group, spellName, true)
            session.observedAbilities = session.observedAbilities or {}
            if not session.observedAbilities[id] then
                session.observedAbilities[id] = { order = {}, names = {} }
            end
            table.insert(session.observedAbilities[id].order, spellName)
            session.observedAbilities[id].names[spellName] = true
            if mechanics.ShowAbilityBars then mechanics.ShowAbilityBars() end
            return state
        end
    end
    return nil
end

local function BeginAbilityCooldown(state, at)
    local spec = state.spec
    if not spec.repeatDelay then
        state.phase, state.readyAt = "ready", at
        state.startedAt = at
        return
    end
    state.startedAt = at
    state.readyAt = at + spec.repeatDelay
    state.phase = "cooldown"
end

-- Only observed starts can enter CASTING; a ready clock never synthesises one.
function mechanics.ObserveAbilityStart(id, spellName, expectedGeneration)
    local session, state, now, previous, occurrence
    session = GetAbilitySession()
    if not session or (expectedGeneration and session.generation ~= expectedGeneration)
        or not session.engaged then return false, "stale encounter" end
    state = ResolveAbility(id, spellName)
    if not state then return false, "unknown ability" end
    now = AbilityClock()
    if state.phase == "casting" and state.occurrence and not state.occurrence.finished then
        return true, state.occurrence.id
    end
    -- A new authoritative cast by this NPC supersedes an unresolved predicted
    -- finish of the previous ordinary cast; never move another spell's timer.
    previous = session.casterCasts[state.caster]
    if previous and previous ~= state and previous.occurrence
        and not previous.occurrence.finished then
        previous.phase, previous.uncertainty = "unresolved", "superseded"
        previous.occurrence.finished = true
    end
    session.castSerial = session.castSerial + 1
    occurrence = {
        id = session.castSerial, startedAt = now,
        expectedEnd = now + (state.spec.castTime or 0),
        finished = false, observedStart = true,
    }
    state.occurrence, state.lastCastAt = occurrence, now
    state.casts, state.uncertainty = state.casts + 1, nil
    state.phase = "casting"
    if state.spec.ordinary ~= false then session.casterCasts[state.caster] = state end
    if state.spec.resetOn == "start" then
        -- An optional explicit startOffset is an estimate, NOT an observed
        -- cast completion. Keep that uncertainty visible to read-only callers.
        BeginAbilityCooldown(state, now + (state.spec.startOffset or 0))
        state.phase = "casting"
        state.cooldownFromStart = true
    else
        state.cooldownFromStart = false
    end
    return true, occurrence.id
end

-- One AoE cast -> one completion; subsequent recipient hits during the
-- resulting cooldown cannot restart it. Missing start logs remain explicit.
function mechanics.ObserveAbilityFinish(id, spellName, expectedGeneration)
    local session, state, occurrence, now
    session = GetAbilitySession()
    if not session or (expectedGeneration and session.generation ~= expectedGeneration)
        or not session.engaged then return false, "stale encounter" end
    state = ResolveAbility(id, spellName)
    if not state then return false, "unknown ability" end
    now = AbilityClock()
    occurrence = state.occurrence
    if occurrence and occurrence.finished and not state.cooldownFromStart
        and state.readyAt and now < state.readyAt then
        return true, "duplicate hit"
    end
    if not occurrence or occurrence.finished then
        -- If no fresh start message exists, multiple hits inside an observed
        -- cooldown describe one event, not many invented casts.
        if state.lastFinishedAt and state.readyAt and now < state.readyAt then
            return true, "duplicate hit"
        end
        session.castSerial = session.castSerial + 1
        occurrence = { id = session.castSerial, finished = false,
            observedStart = false }
        state.occurrence = occurrence
        state.casts = state.casts + 1
    end
    occurrence.finished, occurrence.observedFinish = true, true
    occurrence.finishedAt = now
    state.lastFinishedAt, state.uncertainty = now, nil
    if session.casterCasts[state.caster] == state then
        session.casterCasts[state.caster] = nil
    end
    if state.spec.resetOn == "finish" or not state.cooldownFromStart then
        BeginAbilityCooldown(state, now)
    else
        state.phase = now >= (state.readyAt or 0) and "ready" or "cooldown"
    end
    return true, occurrence.id
end

function mechanics.ObserveAbilityInterrupt(id, spellName, expectedGeneration)
    local session, state
    session = GetAbilitySession()
    if not session or (expectedGeneration and session.generation ~= expectedGeneration) then
        return false, "stale encounter"
    end
    state = ResolveAbility(id, spellName)
    if not state or not state.occurrence or state.occurrence.finished then
        return false, "no active cast"
    end
    state.occurrence.finished = true
    state.phase, state.uncertainty = "unresolved", "interrupted"
    if session.casterCasts[state.caster] == state then session.casterCasts[state.caster] = nil end
    return true
end

-- Expected cast length limits the FLASHING display only. It is never proof
-- of success, does not reset a finish-anchored cooldown, and never invents a hit.
function mechanics.UpdateAbilityStates(now)
    local session, state, key
    session = GetAbilitySession()
    if not session or not session.abilities then return end
    if type(now) ~= "number" then now = AbilityClock() end
    for key, state in pairs(session.abilities) do
        if state.phase == "casting" and state.occurrence and
            now >= state.occurrence.expectedEnd then
            if state.cooldownFromStart then
                state.phase = now >= state.readyAt and "ready" or "cooldown"
                state.uncertainty = "finish not observed"
            else
                state.phase, state.uncertainty = "unresolved", "finish not observed"
            end
            if session.casterCasts[state.caster] == state then
                session.casterCasts[state.caster] = nil
            end
        elseif state.phase == "cooldown" and state.readyAt and now >= state.readyAt then
            state.phase = "ready"
        end
    end
end

function mechanics.GetAbilityState(id, spellName, expectedGeneration)
    local session, state, result
    session = GetAbilitySession()
    if not session or not session.abilities
        or (expectedGeneration and expectedGeneration ~= session.generation) then return nil end
    state = session.abilities[spellName and id .. ":" .. spellName or id]
    if not state then return nil end
    result = { id = state.id, caster = state.caster, name = state.name,
        phase = state.phase, readyAt = state.readyAt, startedAt = state.startedAt,
        lastCastAt = state.lastCastAt, lastFinishedAt = state.lastFinishedAt,
        uncertainty = state.uncertainty, casts = state.casts,
        occurrenceId = state.occurrence and state.occurrence.id,
        observedStart = state.occurrence and state.occurrence.observedStart,
        observedFinish = state.occurrence and state.occurrence.observedFinish,
        generation = session.generation }
    return result
end

-- One presentation factory for prediction, ready and observed casting
-- states. Timers are still owned by the encounter; no separate UI clock.
function mechanics.ShowAbilityBars()
    local session = GetAbilitySession()
    local state, hint, group, key, slot, err, i, j
    if not session or not session.engaged or not session.abilities then return false end
    for i, key in ipairs(session.abilityOrder) do
        state = session.abilities[key]
        if state then
            slot, err = AcquirePresentation("timer", "ability:" .. key)
            if not slot then return false, err end
            slot.abilityRecord, slot.abilityHint = state, nil
            slot.label = state.name or state.spec.label
        end
    end
    for _, group in ipairs(session.definition.declarative.abilityGroups or {}) do
        for j, hint in ipairs(session.firstSlotHints[group.id] or {}) do
            if not hint.expired then
                slot, err = AcquirePresentation("timer", "ability:" .. hint.id)
                if not slot then return false, err end
                slot.abilityRecord, slot.abilityHint = nil, hint
                slot.label = hint.label
            end
        end
    end
    mechanics.UpdatePresentation()
    return true
end

local function RenderAbilityBar(slot, now)
    local state, hint, phase, start, deadline, remaining, progress, total
    local frame = slot.frame
    state, hint = slot.abilityRecord, slot.abilityHint
    if hint then
        if now >= hint.readyAt then
            hint.expired = true
            ReleasePresentation("timer", slot.key)
            return
        end
        phase = "cooldown"
        start, deadline = hint.startedAt, hint.readyAt
    elseif state then
        phase = state.phase
        start, deadline = state.startedAt, state.readyAt
    else
        ReleasePresentation("timer", slot.key)
        return
    end
    frame.label:SetText((phase == "casting" and "" or "~") .. slot.label)
    if phase == "casting" then
        frame.bar:SetValue(1)
        frame.detail:SetText("CAST")
        -- Flash only the bar fill; frame/background border is unchanged.
        if math.mod(math.floor(now * 4), 2) == 0 then
            frame.bar:SetStatusBarColor(0.12, 0.96, 0.20)
        else
            frame.bar:SetStatusBarColor(0.04, 0.46, 0.12)
        end
    elseif phase == "unresolved" then
        frame.bar:SetValue(1)
        frame.bar:SetStatusBarColor(0.94, 0.56, 0.12)
        frame.detail:SetText("?")
    elseif phase == "ready" or not deadline or now >= deadline then
        frame.bar:SetValue(1)
        frame.bar:SetStatusBarColor(0.12, 0.90, 0.22)
        frame.detail:SetText("READY")
    else
        total = math.max(0.001, deadline - (start or now))
        remaining = math.max(0, deadline - now)
        progress = math.max(0, math.min(1, (now - (start or now)) / total))
        frame.bar:SetValue(progress)
        frame.detail:SetText(string.format("~%.0fs", remaining))
        if remaining / total < 0.25 then
            frame.bar:SetStatusBarColor(0.96, 0.61, 0.10)
        else
            frame.bar:SetStatusBarColor(0.22, 0.55, 0.94)
        end
    end
    frame:Show()
end

-- Dormant declarative encounter system. The SCB lifecycle owner must explicitly
-- register the catalogue and forward zone-scoped boss observations and events.
-- No automatic loading, polling, independent frame, or command transport.
local function IsId(v)
    return type(v) == "string" and v ~= ""
        and string.find(v, "^[%w_]+$") ~= nil
end

local function IsDuration(v)
    return type(v) == "number" and v > 0 and v == v and v < math.huge
end

local function CheckEffect(e, hasPattern)
    local i, names
    if type(e) ~= "table" or not IsId(e.id) then return false end
    if e.type == "timer" then
        return type(e.label) == "string" and e.label ~= ""
            and IsDuration(e.duration)
            and (e.provenance == "predicted" or e.provenance == "fixed"
                or e.provenance == "observed")
    elseif e.type == "notice" then
        return type(e.label) == "string" and e.label ~= ""
            and IsDuration(e.lifespan)
    elseif e.type == "ability_observed" then
        if type(e.label) ~= "string" or e.label == ""
            or (e.noticeLifespan ~= nil and not IsDuration(e.noticeLifespan)) then
            return false
        end
        if e.ability ~= nil then
            return type(e.ability) == "string" and e.ability ~= ""
                and e.target == nil and e.allowed == nil
        end
        -- Captured ability names must come from an explicit allowlist. This
        -- blocks unrelated casts matching an intentionally generic pattern.
        if e.target ~= "capture" or not hasPattern
            or type(e.allowed) ~= "table" or table.getn(e.allowed) == 0 then
            return false
        end
        names = {}
        for i = 1, table.getn(e.allowed) do
            if type(e.allowed[i]) ~= "string" or e.allowed[i] == ""
                or names[e.allowed[i]] then return false end
            names[e.allowed[i]] = true
        end
        return true
    elseif e.type == "aura_apply" or e.type == "aura_remove" then
        if e.target ~= "player" and (e.target ~= "capture" or not hasPattern) then
            return false
        end
        if e.type == "aura_remove" then return true end
        return type(e.label) == "string" and e.label ~= ""
            and (e.duration == nil or IsDuration(e.duration))
            and (e.action == nil or e.action == "kick")
            and (e.kickLabel == nil or (type(e.kickLabel) == "string" and e.kickLabel ~= ""))
    end
    return false
end

local function IsFiniteNumber(value)
    return type(value) == "number" and value == value
        and math.abs(value) < math.huge
end

local function CheckWidgetAppearance(w)
    local art, pos
    if w.assignedLabel ~= nil and type(w.assignedLabel) ~= "string" then
        return false
    end
    art = w.icon
    if art ~= nil then
        if type(art) ~= "table" or type(art.texture) ~= "string" or art.texture == ""
            or (art.size ~= nil and (not IsFiniteNumber(art.size) or art.size <= 0))
            or (art.point ~= nil and type(art.point) ~= "string")
            or (art.relativePoint ~= nil and type(art.relativePoint) ~= "string")
            or (art.x ~= nil and not IsFiniteNumber(art.x))
            or (art.y ~= nil and not IsFiniteNumber(art.y)) then
            return false
        end
    end
    pos = w.position
    if pos ~= nil then
        if type(pos) ~= "table" or type(pos[1]) ~= "string"
            or type(pos[2]) ~= "string" or not IsFiniteNumber(pos[3])
            or not IsFiniteNumber(pos[4]) then return false end
    end
    return w.expiresAt == nil or IsFiniteNumber(w.expiresAt)
end

local function CheckDeclaration(d)
    local i, j, w, rule, step, seen = 0, 0, nil, nil, nil, {}
    if type(d) ~= "table" or type(d.detect) ~= "table"
        or type(d.detect.zone) ~= "string" or d.detect.zone == ""
        or type(d.detect.boss) ~= "string" or d.detect.boss == ""
        or type(d.mechanics) ~= "table" or type(d.triggers) ~= "table" then
        return false, "missing detect, mechanics or triggers"
    end
    for i = 1, table.getn(d.mechanics) do
        w = d.mechanics[i]
        if type(w) ~= "table" or not IsId(w.id) or seen[w.id]
            or w.when ~= "present" or w.type ~= "assignable_bot_action"
            or not IsId(w.binding) or type(w.label) ~= "string"
            or w.label == "" or w.assignable ~= true
            or type(w.action) ~= "table" or w.action.type ~= "sequence"
            or type(w.action.steps) ~= "table"
            or table.getn(w.action.steps) == 0
            or not ValidSequenceTargetDelay(w.action.targetDelay) then
            return false, "invalid presence widget"
        end
        if not CheckWidgetAppearance(w) then
            return false, "invalid widget appearance"
        end
        seen[w.id] = true
        for j = 1, table.getn(w.action.steps) do
            step = w.action.steps[j]
            if type(step) ~= "table" or not IsId(step.command)
                or not IsId(step.scope) then
                return false, "invalid command step"
            end
        end
    end
    for i = 1, table.getn(d.triggers) do
        rule = d.triggers[i]
        if type(rule) ~= "table" or type(rule.effects) ~= "table"
            or table.getn(rule.effects) == 0
            or (type(rule.contains) ~= "string" and type(rule.pattern) ~= "string")
            or (rule.contains ~= nil and rule.pattern ~= nil)
            or (rule.event ~= nil and rule.events ~= nil) then
            return false, "invalid trigger"
        end
        if rule.events then
            if type(rule.events) ~= "table" or table.getn(rule.events) == 0 then
                return false, "invalid event list"
            end
            for j = 1, table.getn(rule.events) do
                if type(rule.events[j]) ~= "string" or rule.events[j] == "" then
                    return false, "invalid event name"
                end
            end
        elseif type(rule.event) ~= "string" or rule.event == "" then
            return false, "missing event"
        end
        if rule.pattern and not pcall(string.find, "", rule.pattern) then
            return false, "invalid Lua pattern"
        end
        for j = 1, table.getn(rule.effects) do
            if not CheckEffect(rule.effects[j], rule.pattern ~= nil) then
                return false, "invalid effect"
            end
        end
    end
    return true
end

-- Pure Lua-table catalogue, e.g. { bwl = { razorgore = { ... } } }.
-- Registration is all-or-nothing; the caller owns loading encounters.lua.
function mechanics.RegisterDeclarativeEncounters(catalogue)
    local pending, raid, bosses, name, def, id, ok, why, count
    if type(catalogue) ~= "table" then return false, "invalid catalogue" end
    pending, count = {}, 0
    for raid, bosses in pairs(catalogue) do
        if not IsId(raid) or type(bosses) ~= "table" then
            return false, "invalid raid group"
        end
        for name, def in pairs(bosses) do
            if not IsId(name) then return false, "invalid encounter name" end
            id = raid .. "." .. name
            if pending[id] or encounters[id] then return false, "duplicate " .. id end
            ok, why = CheckDeclaration(def)
            if not ok then return false, id .. ": " .. why end
            pending[id] = { events = {}, declarative = def }
            count = count + 1
        end
    end
    if count == 0 then return false, "empty catalogue" end
    for id, def in pairs(pending) do encounters[id] = def end
    return true, count
end

-- Only the SCB-owned, zone-gated observation pipeline may call this API.
-- "absent" hides the pre-pull action without deleting its binding; missing
-- visibility is NOT treated as death. "dead" must be a confirmed dead boss.
function mechanics.ObserveBoss(zone, boss, state)
    local id, entry, d, w, i, ok, why
    if type(zone) ~= "string" or type(boss) ~= "string"
        or (state ~= "alive" and state ~= "absent" and state ~= "dead") then
        return false, "invalid observation"
    end
    if active and active.definition.declarative
        and active.definition.declarative.detect.zone ~= zone then
        mechanics.StopEncounter("zone change")
    end
    if active and active.definition.declarative then
        d = active.definition.declarative
        if d.detect.zone == zone and d.detect.boss == boss then
            if state == "dead" then
                mechanics.StopEncounter("confirmed boss death")
                return true
            elseif state == "absent" then
                for i = 1, table.getn(d.mechanics) do
                    mechanics.HidePresentation("action", "presence:" .. d.mechanics[i].id)
                end
                active.bossVisible = false
                return true
            end
            if active.bossVisible then return true end
            active.bossVisible = true
        elseif state ~= "alive" then
            return false, "other boss observed"
        else
            mechanics.StopEncounter("different boss")
        end
    elseif state ~= "alive" then
        return false, "boss not active"
    end
    if not active then
        for id, entry in pairs(encounters) do
            d = entry.declarative
            if d and d.detect.zone == zone and d.detect.boss == boss then
                ok, why = mechanics.StartEncounter(id)
                if not ok then return false, why end
                active.bossVisible = true
                break
            end
        end
    end
    if not active or not active.definition.declarative then
        return false, "no matching boss definition"
    end
    d = active.definition.declarative
    if d.detect.zone ~= zone or d.detect.boss ~= boss then
        return false, "boss mismatch"
    end
    for i = 1, table.getn(d.mechanics) do
        w = d.mechanics[i]
        if w.when == "present" then
            mechanics.ShowBoundBotAction("presence:" .. w.id, w)
        end
    end
    return true
end

local function Recipient(effect, captured)
    if effect.target == "player" or captured == "you" or captured == "You" then
        return UnitName and UnitName("player") or nil
    end
    if type(captured) ~= "string" or captured == "" then return nil end
    return captured
end

local function RunDeclaredEffect(effect, captured)
    local key, name, binding, deadline, token, seen
    if not active then return end
    key = "decl:" .. effect.id
    if effect.type == "timer" then
        if mechanics.ScheduleTimer(key, effect.duration, nil, effect.provenance) then
            mechanics.ShowTimer(key, key, effect.label)
        end
    elseif effect.type == "ability_observed" then
        -- No cast => no ability. No observed second breath => no second slot.
        -- No inferred alternation or speculative cooldown is created.
        name = effect.target == "capture" and captured or effect.ability
        if type(name) ~= "string" or name == "" then return end
        if effect.allowed then
            local permitted = false
            for _, candidate in ipairs(effect.allowed) do
                if candidate == name then permitted = true; break end
            end
            if not permitted then return end
        end
        active.observedAbilities = active.observedAbilities or {}
        seen = active.observedAbilities[effect.id]
        if not seen then
            seen = { order = {}, names = {} }
            active.observedAbilities[effect.id] = seen
        end
        if not seen.names[name] then
            seen.names[name] = true
            table.insert(seen.order, name)
            mechanics.ShowTrackedAura("seen:" .. effect.id .. ":" .. name,
                effect.label, name, nil)
        end
        -- Transient alert per actual cast; repeated casts refresh the notice
        -- but do not add fake new abilities or next-cast predictions.
        if effect.noticeLifespan and mechanics.ShowBotAction(
            "cast:" .. effect.id, "Casting " .. name, nil, nil) then
            for _, slot in ipairs(presentation.action.pool) do
                if slot.used and slot.key == "cast:" .. effect.id
                    and slot.generation == active.generation then
                    slot.expiresAt = Now() + effect.noticeLifespan
                    break
                end
            end
        end
    elseif effect.type == "notice" then
        if mechanics.ShowBotAction(key, effect.label, nil, nil) then
            for _, slot in ipairs(presentation.action.pool) do
                if slot.used and slot.key == key and slot.generation == active.generation then
                    slot.expiresAt = Now() + effect.lifespan
                    break
                end
            end
        end
    elseif effect.type == "aura_apply" or effect.type == "aura_remove" then
        name = Recipient(effect, captured)
        if not name then return end
        key = key .. ":" .. name
        binding = "aura:" .. effect.id .. ":" .. name
        if effect.type == "aura_remove" then
            mechanics.CancelTimer("expiration:" .. key)
            mechanics.HidePresentation("aura", key)
            mechanics.HidePresentation("action", "kick:" .. key)
            mechanics.ClearBinding(binding)
        else
            deadline = effect.duration and Now() + effect.duration or nil
            mechanics.ShowTrackedAura(key, effect.label, name, deadline, binding)
            if effect.action == "kick" and mechanics.BindObservedMember(binding, name) then
                mechanics.ShowBoundBotAction("kick:" .. key, {
                    binding = binding, label = (effect.kickLabel or "Kick") .. " " .. name,
                    action = { type = "kick" },
                })
            end
            if effect.duration then
                token = active.generation
                mechanics.ScheduleTimer("expiration:" .. key, effect.duration, function()
                    if not active or active.generation ~= token then return end
                    mechanics.HidePresentation("aura", key)
                    mechanics.HidePresentation("action", "kick:" .. key)
                    mechanics.ClearBinding(binding, token)
                end, "observed")
            end
        end
    end
end

-- Called ONLY through DispatchEvent on the currently active declaration.
-- The first Lua-pattern capture supplies a recipient for multi-aura tracking.
function mechanics.DispatchDeclarativeEvent(session, eventName, message)
    local d, rule, matched, captured, a, b, i, j, count
    if not session or active ~= session or type(message) ~= "string" then return 0 end
    d = session.definition.declarative
    if not d then return 0 end
    count = 0
    for i = 1, table.getn(d.triggers) do
        if active ~= session then break end
        rule = d.triggers[i]
        local eventMatches = rule.event == eventName
        if rule.events then
            eventMatches = false
            for j = 1, table.getn(rule.events) do
                if rule.events[j] == eventName then eventMatches = true; break end
            end
        end
        if eventMatches then
            captured = nil
            if rule.contains then
                matched = string.find(message, rule.contains, 1, true) ~= nil
            else
                a, b, captured = string.find(message, rule.pattern)
                matched = a ~= nil
            end
            if matched then
                for j = 1, table.getn(rule.effects) do
                    if active ~= session then break end
                    RunDeclaredEffect(rule.effects[j], captured)
                end
                count = count + 1
            end
        end
    end
    return count
end
