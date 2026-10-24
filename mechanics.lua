-- SoloCraft Bots - Boss Mods encounter engine (Lua 5.0.3).
-- Loaded by SCB after Communication.lua. The existing SCB lifecycle owner
-- forwards observations/ticks; this file never registers native events,
-- installs an independent update frame or sends commands directly.
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
local prepSuppressed = {} -- boss death within this BWL zone session
local BeginPostBossCleanup
local FinishPostBossCleanup

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
    if active.postBossCleanup then return false, "boss already dead" end
    if active.engaged then return true end
    active.engaged = true
    if not active.definition.declarative then return true end
    local ok, why = mechanics.InitializeAbilities(active.generation)
    if not ok then return false, why end
    return mechanics.InitializeCounters(active.generation)
end

function mechanics.GetEncounterState()
    if not active then return nil end
    return { id = active.id, generation = active.generation,
        boss = active.definition.declarative and active.definition.declarative.detect.boss,
        bossVisible = active.bossVisible == true, engaged = active.engaged == true,
        prepared = active.prepared == true,
        postBossCleanup = active.postBossCleanup == true }
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
    -- Zone-exit reset clears death suppression even if a fight is active.
    prepSuppressed = {}
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
    if session.postBossCleanup then
        return mechanics.DispatchAbilityEvent(session, eventName, message, details)
    end
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
        delivered = delivered + mechanics.DispatchDeclarativeEvent(session, eventName, message, details)
    end
    return delivered
end

-- A name is unique within the current encounter. Re-scheduling replaces it.
-- kind preserves fixed / predicted / observed provenance for later templates.
function mechanics.ScheduleTimer(name, delay, callback, kind)
    if not active or active.postBossCleanup then return false, "no active encounter" end
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
-- Three logical pools remain for encounter/binding ownership, but rows render
-- inside just TWO shared backgrounds. Each panel auto-fits its visible rows.
local presentation = {
    timer = { pool = {}, position = { "TOPLEFT", "TOP", -312, -150 }, width = 220, height = 20 },
    aura = { pool = {}, position = { "TOPLEFT", "TOP", -80, -150 }, width = 220, height = 20 },
    action = { pool = {}, position = { "TOPLEFT", "TOP", -80, -150 }, width = 220, height = 20 },
    hp = { pool = {}, position = { "TOPLEFT", "TOP", -80, -150 }, width = 220, height = 20 },
}
local panelSpecs = {
    timer = { width = 220, height = 20, position = { "TOP", -312, -128 } },
    tracker = { width = 220, height = 20, position = { "TOP", -80, -128 } },
}
local presentationOrder = 0
local LayoutPresentation

-- Position previews have no encounter/event/tick dependency. Their sample rows
-- are made with the actual presentation factory and cannot execute actions.
-- The persistent positions belong to the existing SCB options DB; unlocking
-- itself is temporary, so reloads never leave the edit handles open.
-- Countdown text overlays the full-width timer bar.
local SCB_BOSSMOD_PREVIEW_HEADER = 22
local bossModsPreview = { unlocked = false, handles = {} }

-- Two independent global layout preferences owned by the existing SCB DB.
-- Nil/false preserve the historical top-anchored, downward-growing panels.
local function PanelExpandsUp(kind)
    local opts = SoloCraftBotsDB and SoloCraftBotsDB.options
    if not opts then return false end
    if kind == "timer" then return opts.bossModsTimersExpandUp == true end
    if kind == "tracker" then return opts.bossModsTrackerExpandUp == true end
    return false
end

local function PanelFrameAnchor(kind)
    return PanelExpandsUp(kind) and "BOTTOMLEFT" or "TOPLEFT"
end

-- Labels are presentation-only, never a roster/binding filter.
-- Missing preferences default ON to preserve information in existing profiles.
local function TrackerMemberLabel(name, aura)
    local opts = SoloCraftBotsDB and SoloCraftBotsDB.options or {}
    local showName = opts.bossModsShowPlayerName ~= false
    local showAura = opts.bossModsShowAuraName ~= false
    if showName and showAura then return name .. ": " .. aura end
    if showName then return name end
    if showAura then return aura end
    return ""
end

function mechanics.RefreshTrackerPreview()
    local handle = bossModsPreview.handles.tracker
    if not handle then return end
    for _, sample in ipairs(handle.scbSamples or {}) do
        if sample.scbPreviewUnit and sample.scbPreviewAura then
            sample.label:SetText(TrackerMemberLabel(
                sample.scbPreviewUnit, sample.scbPreviewAura))
        end
    end
end
local previewDefaults = {
    timer = { anchor = "TOP", x = -312, y = -128 },
    tracker = { anchor = "TOP", x = -80, y = -128 },
}
local function PreviewPosition(kind)
    local options = SoloCraftBotsDB and SoloCraftBotsDB.options
    local positions = options and options.bossModsPositions
    -- Preserve old keys. The former aura anchor seeds Unit Tracker until
    -- the user moves the new panel, then only tracker is written.
    local saved = positions and (positions[kind]
        or (kind == "tracker" and positions.aura))
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
    local panel = panelSpecs[kind]
    if not panel then return end
    panel.position = { pos.anchor, pos.x, pos.y }
    local handle = bossModsPreview.handles[kind]
    if handle then
        handle:ClearAllPoints()
        handle:SetPoint(PanelFrameAnchor(kind), UIParent,
            pos.anchor, pos.x, pos.y)
    end
end

function mechanics.LoadPreviewPositions()
    if mechanics.LoadPanelSizes then mechanics.LoadPanelSizes() end
    for kind in pairs(panelSpecs) do ApplyPreviewPosition(kind) end
    if LayoutPresentation then LayoutPresentation("timer"); LayoutPresentation("tracker") end
end

function mechanics.IsPreviewUnlocked()
    return bossModsPreview.unlocked
end

local function PresentationGroup(kind)
    if type(kind) ~= "string" then return nil end
    return presentation[kind]
end

local function EnsurePanel(kind)
    local panel = panelSpecs[kind]
    if not panel then return nil end
    if panel.frame then return panel.frame end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetWidth(panel.width)
    frame:SetHeight(SCB_BOSSMOD_PREVIEW_HEADER + 8)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true, tileSize = 16,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.78)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -4)
    title:SetJustifyH("LEFT")
    panel.frame, panel.title = frame, title
    frame:Hide()
    return frame
end

local function PanelKind(kind)
    return kind == "timer" and "timer" or "tracker"
end

LayoutPresentation = function(kind)
    local panelKind = PanelKind(kind)
    local panel = panelSpecs[panelKind]
    local root = EnsurePanel(panelKind)
    local rows, auras, attached = {}, {}, {}
    local slot, parent, i, rowHeight, rowWidth, attachedSlot
    if panelKind == "timer" then
        for _, slot in ipairs(presentation.timer.pool) do
            if slot.used then table.insert(rows, slot) end
        end
    else
        for _, slot in ipairs(presentation.hp.pool) do
            if slot.used then table.insert(rows, slot) end
        end
        for _, slot in ipairs(presentation.aura.pool) do
            if slot.used then
                table.insert(rows, slot)
                auras[slot.key] = slot
            end
        end
        for _, slot in ipairs(presentation.action.pool) do
            if slot.used and slot.frame:IsShown() then
                parent = string.sub(slot.key or "", 1, 5) == "kick:"
                    and auras[string.sub(slot.key, 6)] or nil
                if parent then
                    attached[parent.key] = slot
                else
                    table.insert(rows, slot)
                end
            end
        end
    end
    if table.getn(rows) == 0 then root:Hide(); return end
    rowHeight, rowWidth = panel.height, panel.width - 8
    root:ClearAllPoints()
    root:SetPoint(PanelFrameAnchor(panelKind), UIParent,
        panel.position[1], panel.position[2], panel.position[3])
    root:SetWidth(panel.width)
    root:SetHeight(SCB_BOSSMOD_PREVIEW_HEADER + 4
        + table.getn(rows) * rowHeight + (table.getn(rows) - 1) * 3 + 4)
    local state = mechanics.GetEncounterState()
    local bossName = state and state.boss
    if panelKind == "timer" then
        panel.title:SetText((bossName and (bossName .. " - ") or "")
            .. SCB_L("BOSSMODS_PANEL_TIMERS"))
    else
        panel.title:SetText((bossName and (bossName .. " - ") or "")
            .. SCB_L("BOSSMODS_PANEL_TRACKER"))
    end
    for i, slot in ipairs(rows) do
        local frame = slot.frame
        if frame:GetParent() ~= root then frame:SetParent(root) end
        frame:SetFrameLevel(root:GetFrameLevel() + 1)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", root, "TOPLEFT", 4,
            -SCB_BOSSMOD_PREVIEW_HEADER - 4 - (i - 1) * (rowHeight + 3))
        frame:SetWidth(rowWidth)
        frame:SetHeight(rowHeight)
        frame.icon:SetWidth(rowHeight)
        frame.icon:SetHeight(rowHeight)
        frame.icon:Show()
        frame.label:ClearAllPoints()
        frame.label:SetPoint("LEFT", frame, "LEFT", rowHeight + 6, 0)
        frame.label:Show()
        frame.detail:ClearAllPoints()
        if panelKind == "tracker" then
            -- The Kick/Use square is always reserved, even when empty.
            frame.detail:SetPoint("RIGHT", frame, "RIGHT", -rowHeight - 4, 0)
            frame.detail:SetWidth(50)
            frame.label:SetWidth(math.max(8, rowWidth - 2 * rowHeight - 68))
        else
            -- Name and countdown share the coloured bar.
            frame.detail:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
            frame.detail:SetWidth(50)
            frame.label:SetWidth(math.max(8, rowWidth - rowHeight - 64))
        end
        frame.detail:Show()
        if frame.bar then
            frame.bar:ClearAllPoints()
            frame.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", rowHeight + 2, 0)
            frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",
                -(panelKind == "tracker" and rowHeight or 0) - 2, 0)
            frame.bar:Show()
        end
        if frame.scbRightSlot then
            frame.scbRightSlot:SetWidth(rowHeight)
            frame.scbRightSlot:SetHeight(rowHeight)
        end
        if frame.scbUseButton then
            frame.scbUseButton:SetWidth(rowHeight)
            frame.scbUseButton:SetHeight(rowHeight)
            frame.scbUseButton:SetFrameLevel(frame:GetFrameLevel() + 2)
        end
        if slot.boundDefinition and slot.boundDefinition.icon then
            -- One row-sized egg icon; no legacy superimposed art.
            frame.icon:SetTexture(slot.boundDefinition.icon.texture)
            if frame.scbOverlay then frame.scbOverlay:Hide() end
        end
        frame:Show()
        if panelKind == "tracker" then
            attachedSlot = attached[slot.key]
            if attachedSlot then
                local button = attachedSlot.frame
                if button:GetParent() ~= frame then button:SetParent(frame) end
                button:SetFrameLevel(frame:GetFrameLevel() + 1)
                button:ClearAllPoints()
                button:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
                button:SetWidth(rowHeight)
                button:SetHeight(rowHeight)
                button.label:Hide()
                button.detail:Hide()
                button.icon:Hide()
                if button.bar then button.bar:Hide() end
                if button.scbUseButton then button.scbUseButton:Hide() end
                button.scbOverlay:ClearAllPoints()
                button.scbOverlay:SetAllPoints(button)
                button.scbOverlay:SetTexture("Interface\\Icons\\Ability_Kick")
                button.scbOverlay:Show()
                button:Show()
            end
        end
    end
    root:Show()
end

-- Only width and row height are user-adjustable; no per-column remnants.
-- The old aura/action positions remain untouched in SavedVariables.
local function ValidPanelDimension(width, height)
    return type(width) == "number" and width == math.floor(width)
        and width >= 120 and width <= 500
        and type(height) == "number" and height == math.floor(height)
        and height >= 14 and height <= 40
end

local function ApplyPanelSize(kind, width, height)
    local panel = panelSpecs[kind]
    if not panel or not ValidPanelDimension(width, height) then return false end
    panel.width, panel.height = width, height
    local kinds = kind == "timer" and { "timer" } or { "aura", "action", "hp" }
    for _, poolKind in ipairs(kinds) do
        presentation[poolKind].width = width
        presentation[poolKind].height = height
    end
    local handle = bossModsPreview.handles[kind]
    if handle then
        handle:SetWidth(width)
        local n = kind == "tracker" and 3 or 2
        handle:SetHeight(SCB_BOSSMOD_PREVIEW_HEADER + 8
            + n * height + (n - 1) * 3)
        for i, sample in ipairs(handle.scbSamples or {}) do
            sample:ClearAllPoints()
            sample:SetPoint("TOPLEFT", handle, "TOPLEFT", 4,
                -SCB_BOSSMOD_PREVIEW_HEADER - 4 - (i - 1) * (height + 3))
            sample:SetWidth(width - 8)
            sample:SetHeight(height)
            sample.icon:SetWidth(height)
            sample.icon:SetHeight(height)
            sample.label:ClearAllPoints()
            sample.label:SetPoint("LEFT", sample, "LEFT", height + 6, 0)
            if kind == "tracker" then
                sample.label:SetWidth(math.max(8, width - 2 * height - 68))
            else
                sample.label:SetWidth(math.max(8, width - height - 72))
            end
            sample.detail:ClearAllPoints()
            if kind == "tracker" then
                sample.detail:SetPoint("RIGHT", sample, "RIGHT", -height - 4, 0)
                sample.detail:SetWidth(50)
            else
                sample.detail:SetPoint("RIGHT", sample, "RIGHT", -6, 0)
                sample.detail:SetWidth(50)
            end
            if sample.bar then
                sample.bar:ClearAllPoints()
                sample.bar:SetPoint("TOPLEFT", sample, "TOPLEFT", height + 2, 0)
                sample.bar:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT",
                    -(kind == "tracker" and height or 0) - 2, 0)
            end
            if sample.scbRightSlot then
                sample.scbRightSlot:SetWidth(height)
                sample.scbRightSlot:SetHeight(height)
            end
            if sample.scbUseButton then
                sample.scbUseButton:SetWidth(height)
                sample.scbUseButton:SetHeight(height)
            end
            if sample.scbPreviewKick then
                sample.scbPreviewKick:SetWidth(height)
                sample.scbPreviewKick:SetHeight(height)
            end
        end
    end
    if LayoutPresentation then LayoutPresentation(kind) end
    return true
end

function mechanics.LoadPanelSizes()
    local opts = SoloCraftBotsDB and SoloCraftBotsDB.options
    local sizes = opts and opts.bossModsSizes or {}
    for kind, panel in pairs(panelSpecs) do
        local saved = sizes[kind]
        if type(saved) == "table" and ValidPanelDimension(saved.width, saved.height) then
            ApplyPanelSize(kind, saved.width, saved.height)
        else
            ApplyPanelSize(kind, 220, 20)
        end
    end
end

function mechanics.GetPanelSize(kind)
    local panel = panelSpecs[kind]
    if not panel then return nil end
    return panel.width, panel.height
end

function mechanics.SetPanelSize(kind, width, height)
    if not ApplyPanelSize(kind, width, height) then return false end
    if not SoloCraftBotsDB then return false end
    SoloCraftBotsDB.options = SoloCraftBotsDB.options or {}
    local opts = SoloCraftBotsDB.options
    opts.bossModsSizes = opts.bossModsSizes or {}
    opts.bossModsSizes[kind] = { width = width, height = height }
    return true
end

local function CreatePresentationFrame(kind, group)
    local frame = CreateFrame((kind == "action" or kind == "hp") and "Button" or "Frame", nil, UIParent)
    frame.scbKind = kind
    frame:SetWidth(group.width)
    frame:SetHeight(group.height)
    frame:SetFrameStrata("MEDIUM")
    -- The group owns the shared dark background, so rows remain transparent.
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetTexture(0, 0, 0, 0)
    frame.background = background
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
    icon:SetWidth(group.height)
    icon:SetHeight(group.height)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    frame.icon = icon
    if kind == "timer" or kind == "aura" or kind == "action" or kind == "hp" then
        local bar = CreateFrame("StatusBar", nil, frame)
        bar:SetPoint("TOPLEFT", frame, "TOPLEFT", group.height + 2, 0)
        bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetStatusBarColor(0.22, 0.55, 0.94)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        if kind == "action" then
            bar:SetStatusBarColor(0.15, 0.37, 0.58)
        end
        bar:SetFrameLevel(frame:GetFrameLevel())
        frame.bar = bar
    end
    if kind == "aura" or kind == "action" or kind == "hp" then
        -- Only tracker rows keep the fixed action-icon background.
        local slotBackground = frame:CreateTexture(nil, "ARTWORK")
        slotBackground:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        slotBackground:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        slotBackground:SetWidth(group.height)
        slotBackground:SetTexture(0.10, 0.13, 0.17, 0.80)
        frame.scbRightSlot = slotBackground
    end
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", frame, "LEFT", group.height + 6, 0)
    label:SetJustifyH("LEFT")
    label:SetWidth(group.width - group.height - 64)
    frame.label = label
    local detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    detail:SetJustifyH("RIGHT")
    detail:SetWidth(50)
    frame.detail = detail
    if kind == "hp" then
        frame:RegisterForClicks("LeftButtonUp")
        frame:SetScript("OnClick", function()
            local slot = frame.scbSlot
            if not slot or not slot.used or not slot.clickTarget or not active
                or slot.generation ~= active.generation then return end
            -- Never target a recycled token or a same-name replacement.
            local unit = slot.unit
            if unit and mechanics.NPCInstanceID(unit) == slot.instanceID
                and UnitExists and UnitExists(unit)
                and UnitIsDeadOrGhost and not UnitIsDeadOrGhost(unit)
                and TargetUnit then TargetUnit(unit) end
        end)
    end
    if kind == "action" then
        local overlay = frame:CreateTexture(nil, "OVERLAY")
        overlay:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        overlay:SetWidth(group.height)
        overlay:SetHeight(group.height)
        overlay:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        overlay:Hide()
        frame.scbOverlay = overlay
        local use = CreateFrame("Button", nil, frame)
        use:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        use:SetWidth(group.height)
        use:SetHeight(group.height)
        use:SetFrameLevel(frame:GetFrameLevel() + 2)
        local cog = use:CreateTexture(nil, "OVERLAY")
        cog:SetAllPoints(use)
        cog:SetTexture(SCB.assetRoot .. "lucide_cog.tga")
        frame.scbUseButton = use
        use:RegisterForClicks("LeftButtonUp")
        use:SetScript("OnClick", function()
            local slot = frame.scbSlot
            if not slot or not slot.used or not active
                or slot.generation ~= active.generation then return end
            -- Use the exact existing generation-guarded action entry point.
            mechanics.HandleActionClick(slot.key, "LeftButton")
        end)
        use:Hide()
        frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        frame:SetScript("OnClick", function()
            local slot = frame.scbSlot
            if not slot or not slot.used or not active
                or slot.generation ~= active.generation then return end
            -- Once assigned, only the cog invokes the action. The row itself
            -- still assigns on first click, and right-click still clears.
            if (arg1 or "LeftButton") == "LeftButton"
                and slot.boundDefinition and slot.boundDefinition.assignable
                and mechanics.GetBoundMember(slot.boundDefinition.binding,
                    slot.generation, false) then return end
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
    local up = PanelExpandsUp(kind)
    local anchor = (up and "BOTTOM" or "TOP") .. horizontal
    local originX = horizontal == "LEFT" and pl or pr
    local originY = up and pb or pt
    opts.bossModsPositions[kind] = {
        anchor = anchor, x = left - originX,
        y = (up and bottom or top) - originY,
    }
    mechanics.LoadPreviewPositions()
end

local function CreatePreviewHandle(kind)
    local panel = panelSpecs[kind]
    local rowKind = kind == "timer" and "timer" or "aura"
    local group = presentation[rowKind]
    local handle = CreateFrame("Frame", nil, UIParent)
    handle:SetWidth(panel.width)
    local sampleCount = kind == "tracker" and 3 or 2
    handle:SetHeight(SCB_BOSSMOD_PREVIEW_HEADER + 8
        + sampleCount * panel.height + (sampleCount - 1) * 3)
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
    handle:SetBackdropColor(0, 0, 0, 0.78)
    handle:SetBackdropBorderColor(0.4, 0.7, 0.95, 1)
    local title = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", handle, "TOPLEFT", 6, -4)
    title:SetText(SCB_L(kind == "timer" and
        "BOSSMODS_DRAG_TIMER" or "BOSSMODS_DRAG_TRACKER"))
    handle.scbSamples = {}
    for i = 1, sampleCount do
        local sample = CreatePresentationFrame(
            kind == "tracker" and i == 3 and "action" or rowKind, group)
        table.insert(handle.scbSamples, sample)
        sample:SetParent(handle)
        sample:SetFrameStrata("DIALOG")
        sample:SetFrameLevel(handle:GetFrameLevel() + 1)
        sample:ClearAllPoints()
        sample:SetPoint("TOPLEFT", handle, "TOPLEFT", 4,
            -SCB_BOSSMOD_PREVIEW_HEADER - 4 - (i - 1) * (panel.height + 3))
        sample:SetWidth(panel.width - 8)
        sample:SetHeight(panel.height)
        if kind == "timer" then
            sample.label:SetText(SCB_L(i == 1 and "BOSSMODS_SAMPLE_BLAST" or "BOSSMODS_SAMPLE_SHADOW"))
            sample.icon:SetTexture(i == 1 and
                "Interface\\Icons\\Spell_Holy_Excorcism_02" or
                "Interface\\Icons\\Spell_Fire_Incinerate")
            sample.detail:SetText(i == 1 and "20s" or "12s")
            sample.bar:SetValue(i == 1 and 0.65 or 0.3)
        elseif i < 3 then
            sample.scbPreviewUnit = SCB_L(i == 1 and
                "BOSSMODS_SAMPLE_BOT_NAME" or "BOSSMODS_SAMPLE_PLAYER_NAME")
            sample.scbPreviewAura = SCB_L("BOSSMODS_SAMPLE_AURA_NAME")
            sample.icon:SetTexture("Interface\\Icons\\INV_Gauntlets_03")
            sample.label:SetText(TrackerMemberLabel(
                sample.scbPreviewUnit, sample.scbPreviewAura))
            sample.detail:SetText(i == 1 and "16s" or "10s")
            if i == 1 then
                -- Inert sample Kick; the victim's bar always has room for it.
                local kick = sample:CreateTexture(nil, "OVERLAY")
                kick:SetPoint("RIGHT", sample, "RIGHT", 0, 0)
                kick:SetTexture("Interface\\Icons\\Ability_Kick")
                sample.scbPreviewKick = kick
            end
        else
            sample.label:SetText(SCB_L("BOSSMODS_SAMPLE_EGGBREAKER"))
            sample.detail:SetText("")
            sample.icon:SetTexture("Interface\\Icons\\INV_Egg_03")
            -- Shows post-assignment Use without binding or invoking a command.
            sample.scbUseButton:Show()
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
    handle:SetScript("OnHide", function() this:StopMovingOrSizing() end)
    handle:Hide()
    bossModsPreview.handles[kind] = handle
    ApplyPanelSize(kind, panel.width, panel.height)
    ApplyPreviewPosition(kind)
    return handle
end

-- Rebase the stored preview position when changing growth direction.
-- Keep the preview in its current screen rectangle instead of teleporting
-- between top/bottom corners. Only orientation and position are persisted;
-- the encounter, action and SCB update owners are untouched.
function mechanics.SetPanelExpansion(kind, enabled)
    local panel = panelSpecs[kind]
    local opts = SoloCraftBotsDB and SoloCraftBotsDB.options
    if not panel or not opts then return false end
    local optionKey = kind == "timer" and "bossModsTimersExpandUp"
        or "bossModsTrackerExpandUp"
    local wasUp = PanelExpandsUp(kind)
    local up = enabled and true or false
    if wasUp == up then return true end

    local pos = PreviewPosition(kind)
    local pl, pr = UIParent:GetLeft(), UIParent:GetRight()
    local pt, pb = UIParent:GetTop(), UIParent:GetBottom()
    if not pl or not pr or not pt or not pb then return false end
    local referenceX
    if string.find(pos.anchor, "LEFT", 1, true) then
        referenceX = pl
    elseif string.find(pos.anchor, "RIGHT", 1, true) then
        referenceX = pr
    else
        referenceX = (pl + pr) / 2
    end
    local referenceY = string.sub(pos.anchor, 1, 6) == "BOTTOM" and pb or pt
    local left = referenceX + pos.x
    local oldY = referenceY + pos.y
    local height = SCB_BOSSMOD_PREVIEW_HEADER + 8
        + (kind == "timer" and 2 or 3) * panel.height
        + (kind == "timer" and 1 or 2) * 3
    local newY
    if up then newY = wasUp and oldY or oldY - height
    else newY = wasUp and oldY + height or oldY end
    local horizontal = (left - pl <= pr - (left + panel.width))
        and "LEFT" or "RIGHT"
    local newAnchor = (up and "BOTTOM" or "TOP") .. horizontal
    local originX = horizontal == "LEFT" and pl or pr

    opts[optionKey] = up
    opts.bossModsPositions = opts.bossModsPositions or {}
    opts.bossModsPositions[kind] = {
        anchor = newAnchor, x = left - originX,
        y = newY - (up and pb or pt),
    }
    mechanics.LoadPreviewPositions()
    return true
end

function mechanics.SetPreviewUnlocked(enabled)
    bossModsPreview.unlocked = enabled and true or false
    if bossModsPreview.unlocked then
        mechanics.LoadPreviewPositions()
        for _, kind in ipairs({ "timer", "tracker" }) do
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
    if not active or active.postBossCleanup then return nil, "no active encounter" end
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
    slot.retainAfterBossDeath = nil
    slot.abilityRecord, slot.abilityHint = nil, nil
    slot.instanceID, slot.unit, slot.dead = nil, nil, nil
    slot.clickTarget, slot.hideOnDeath = nil, nil
    slot.timerName = nil
    slot.progressKind, slot.progressState = nil, nil
    slot.startedAt = nil
    slot.frame.label:Show()
    slot.frame.detail:Show()
    slot.frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    slot.frame.icon:Show()
    if slot.frame.scbUseButton then slot.frame.scbUseButton:Hide() end
    if slot.frame.bar then slot.frame.bar:Show() end
    if slot.frame.scbOverlay then
        slot.frame.scbOverlay:Hide()
        -- Recycled action frames may previously have contained an art overlay.
        slot.frame.label:ClearAllPoints()
        slot.frame.label:SetPoint("LEFT", slot.frame, "LEFT", group.height + 6, 0)
        slot.frame.label:SetWidth(group.width - group.height - 64)
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
            slot.retainAfterBossDeath = nil
            slot.abilityRecord, slot.abilityHint = nil, nil
            slot.instanceID, slot.unit, slot.dead = nil, nil, nil
            slot.clickTarget, slot.hideOnDeath = nil, nil
            slot.timerName = nil
            slot.progressKind, slot.progressState = nil, nil
            slot.generation = nil
            if slot.frame.scbOverlay then slot.frame.scbOverlay:Hide() end
            if slot.frame.scbUseButton then slot.frame.scbUseButton:Hide() end
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


-- Hit counts are POSITIVELY OBSERVED messages only; reference maxima are
-- presentation scales and must not assert full combat-log coverage.
function mechanics.InitializeCounters(expectedGeneration)
    if not active or not active.engaged or not active.definition.declarative
        or (expectedGeneration and expectedGeneration ~= active.generation) then
        return false, "stale encounter"
    end
    if active.counters then return true end
    active.counters = {}
    for _, spec in ipairs(active.definition.declarative.counters or {}) do
        local state = { count = 0, seen = {}, spec = spec, generation = active.generation }
        active.counters[spec.id] = state
        local slot, err = AcquirePresentation("timer", "counter:" .. spec.id)
        if not slot then return false, err end
        slot.progressKind, slot.progressState = "counter", state
        slot.label, slot.group = spec.label, spec.group
        if spec.icon then slot.frame.icon:SetTexture(spec.icon) end
    end
    mechanics.UpdatePresentation()
    return true
end

function mechanics.ObserveCounterHit(id, occurrenceId, expectedGeneration)
    if not active or not active.engaged or active.postBossCleanup
        or (expectedGeneration and expectedGeneration ~= active.generation) then
        return false, "stale encounter"
    end
    local state = active.counters and active.counters[id]
    if not state then return false, "unknown counter" end
    if occurrenceId ~= nil and (type(occurrenceId) ~= "string" or occurrenceId == "")
        then return false, "invalid occurrence" end
    if occurrenceId and state.seen[occurrenceId] then return false, "duplicate observation" end
    if occurrenceId then state.seen[occurrenceId] = true end
    state.count = state.count + 1
    return true
end

-- A counter only resets on an explicit event/caller, never when its reference
-- maximum is reached or when an unrelated ability clock expires.
function mechanics.ResetCounter(id, expectedGeneration)
    if not active or not active.engaged or active.postBossCleanup
        or (expectedGeneration and expectedGeneration ~= active.generation) then
        return false, "stale encounter"
    end
    local state = active.counters and active.counters[id]
    if not state then return false, "unknown counter" end
    state.count, state.seen = 0, {}
    return true
end

function mechanics.GetCounter(id, expectedGeneration)
    if not active or (expectedGeneration and expectedGeneration ~= active.generation)
        then return nil end
    local state = active.counters and active.counters[id]
    if not state then return nil end
    return { count = state.count, maximum = state.spec.maximum,
        maximumKind = state.spec.maximumKind or "reference",
        generation = state.generation }
end

-- A named encounter timer only marks the earliest readiness boundary.
-- A new stage requires a POSITIVE event; readiness never implies phase change.
function mechanics.SetTimerStage(id, spec, expectedGeneration)
    if not active or not active.engaged or active.postBossCleanup
        or (expectedGeneration and expectedGeneration ~= active.generation) then
        return false, "stale encounter"
    end
    if type(id) ~= "string" or id == "" or type(spec) ~= "table"
        or type(spec.label) ~= "string" or spec.label == ""
        or type(spec.minDelay) ~= "number" or spec.minDelay < 0
        or spec.minDelay ~= spec.minDelay or spec.minDelay == math.huge
        or (spec.maxDelay ~= nil and (type(spec.maxDelay) ~= "number"
            or spec.maxDelay < spec.minDelay or spec.maxDelay == math.huge
            or spec.maxDelay ~= spec.maxDelay))
        or (spec.provenance ~= nil and spec.provenance ~= "fixed"
            and spec.provenance ~= "predicted")
        or (spec.icon ~= nil and (type(spec.icon) ~= "string" or spec.icon == ""))
        or (spec.group ~= nil and (type(spec.group) ~= "string"
            or not string.find(spec.group, "^[%w_]+$"))) then
        return false, "invalid timer stage"
    end
    local now = Now()
    local stage = { label = spec.label, group = spec.group,
        startedAt = now, minimumAt = now + spec.minDelay,
        maximumAt = now + (spec.maxDelay or spec.minDelay),
        provenance = spec.provenance or "predicted",
        generation = active.generation }
    local slot, err = AcquirePresentation("timer", "stage:" .. id)
    if not slot then return false, err end
    mechanics.CancelTimer("stage-ready:" .. id)
    active.stageTimers = active.stageTimers or {}
    active.stageTimers[id] = stage
    slot.progressKind, slot.progressState = "stage", stage
    slot.label, slot.group = spec.label, spec.group
    if spec.icon then slot.frame.icon:SetTexture(spec.icon) end
    local token = active.generation
    local ok = mechanics.ScheduleTimer("stage-ready:" .. id, spec.minDelay, function()
        if active and active.generation == token
            and active.stageTimers and active.stageTimers[id] == stage then
            stage.ready = true
        end
    end, stage.provenance)
    if not ok then return false, "timer unavailable" end
    mechanics.UpdatePresentation()
    return true
end

function mechanics.GetTimerStage(id, expectedGeneration)
    if not active or (expectedGeneration and expectedGeneration ~= active.generation)
        then return nil end
    local stage = active.stageTimers and active.stageTimers[id]
    if not stage then return nil end
    return { label = stage.label, startedAt = stage.startedAt,
        minimumAt = stage.minimumAt, maximumAt = stage.maximumAt,
        provenance = stage.provenance, ready = stage.ready == true
            or Now() >= stage.minimumAt, generation = stage.generation }
end

-- SuperWoW exposes a per-spawn GUID as UnitExists' second result;
-- some clients also expose UnitGUID. A creature name or NPC type ID is
-- never an adequate key for simultaneous instances. Fail closed if neither
-- interface provides an individual identity.
function mechanics.NPCInstanceID(unit)
    local exists, id
    if type(unit) ~= "string" or unit == "" or not UnitExists then return nil end
    exists, id = UnitExists(unit)
    if not exists then return nil end
    if (type(id) ~= "string" or id == "") and type(UnitGUID) == "function" then
        id = UnitGUID(unit)
    end
    if type(id) ~= "string" or id == "" then return nil end
    return id
end

-- Generic per-instance HP template. Calling code supplies only positively
-- observed unit tokens, never guessed creatures. No new event/tick owner.
-- Rows survive temporary sight loss with last OBSERVED health, not invented
-- death; a positive death observation determines DEAD versus retirement.
function mechanics.ObserveNPCHealth(key, unit, options)
    local id, health, maximum, slot, err
    if type(key) ~= "string" or key == "" or type(options) ~= "table"
        or type(options.label) ~= "string" or options.label == ""
        or (options.group ~= nil and (type(options.group) ~= "string"
            or not string.find(options.group, "^[%w_%-]+$")))
        or (options.hideOnDeath ~= nil and type(options.hideOnDeath) ~= "boolean")
        or (options.clickTarget ~= nil and type(options.clickTarget) ~= "boolean")
        then return false, "invalid hp row" end
    id = mechanics.NPCInstanceID(unit)
    if not id or not UnitHealth or not UnitHealthMax then
        return false, "unidentified npc instance"
    end
    -- Keys represent a template plus a unique instance; a replaced spawn
    -- never inherits the DEAD state of a prior GUID.
    health, maximum = UnitHealth(unit), UnitHealthMax(unit)
    if type(health) ~= "number" or type(maximum) ~= "number"
        or maximum <= 0 or health ~= health then return false, "invalid hp" end
    local rowKey = key .. ":" .. id
    for _, other in ipairs(presentation.hp.pool) do
        if other.used and other.instanceID == id and other.key ~= rowKey then
            return false, "instance already tracked"
        end
    end
    for _, other in ipairs(presentation.hp.pool) do
        if other.used and other.key == rowKey then
            slot = other
            break
        end
    end
    if not slot then
        slot, err = AcquirePresentation("hp", rowKey)
        if not slot then return false, err end
    end
    slot.instanceID, slot.unit, slot.label = id, unit, options.label
    slot.group = options.group
    slot.hideOnDeath, slot.clickTarget = options.hideOnDeath == true,
        options.clickTarget == true
    if options.icon then slot.frame.icon:SetTexture(options.icon) end
    slot.health, slot.maximum = health, maximum
    if health <= 0 or (UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)) then
        slot.dead = true
    end
    if slot.dead and slot.hideOnDeath then
        ReleasePresentation("hp", rowKey)
        return true, rowKey
    end
    mechanics.UpdatePresentation()
    return true, rowKey
end


-- HP projection uses only positively identified, live unit observations.
-- No valid token means retain last displayed HP but WITHHOLD the ETA.
function mechanics.ObserveHPThreshold(key, unit, options, expectedGeneration)
    if not active or not active.engaged or active.postBossCleanup
        or (expectedGeneration and expectedGeneration ~= active.generation) then
        return false, "stale encounter"
    end
    if type(key) ~= "string" or key == "" or type(options) ~= "table"
        or type(options.label) ~= "string" or options.label == ""
        or type(options.threshold) ~= "number" or options.threshold <= 0
        or options.threshold >= 1 or options.threshold ~= options.threshold
        or (options.icon ~= nil and (type(options.icon) ~= "string"
            or options.icon == ""))
        or (options.group ~= nil and (type(options.group) ~= "string"
            or not string.find(options.group, "^[%w_]+$")))
        then return false, "invalid threshold" end
    local id = mechanics.NPCInstanceID(unit)
    if not id or not UnitHealth or not UnitHealthMax then
        return false, "unidentified npc instance"
    end
    local health, maximum = UnitHealth(unit), UnitHealthMax(unit)
    if type(health) ~= "number" or type(maximum) ~= "number"
        or maximum <= 0 or health ~= health or health < 0
        or health > maximum then
        return false, "invalid hp"
    end
    local slot, err = AcquirePresentation("timer", "threshold:" .. key)
    if not slot then return false, err end
    if slot.progressKind == "threshold" and slot.progressState
        and slot.progressState.instanceID ~= id then
        return false, "different npc instance"
    end
    local state = slot.progressState
    if not state then
        state = { instanceID = id, threshold = options.threshold,
            baselineAt = Now(), baselinePct = health / maximum }
    elseif state.threshold ~= options.threshold then
        return false, "threshold changed"
    end
    -- Rebinding a token must NOT overwrite the previous measured HP sample:
    -- doing so would conceal healing and corrupt the projected loss rate.
    state.unit = unit
    if not state.currentPct then state.currentPct = health / maximum end
    if not state.lastPct then state.lastPct = health / maximum end
    slot.progressKind, slot.progressState = "threshold", state
    slot.label, slot.group = options.label, options.group
    if options.icon then slot.frame.icon:SetTexture(options.icon) end
    mechanics.UpdatePresentation()
    return true
end

-- SCB's existing positive-unit scan owns these observations. No name-only
-- identity or alternate scan/tick/command path is introduced.
function mechanics.ObserveDeclaredUnits(tokens, expectedGeneration)
    if not active or not active.engaged or active.postBossCleanup
        or (expectedGeneration and active.generation ~= expectedGeneration)
        or type(tokens) ~= "table" then return false, "stale encounter" end
    local d = active.definition.declarative
    if not d then return false, "no declaration" end
    local unit, name, spec, i
    for i = 1, table.getn(tokens) do
        unit = tokens[i]
        if type(unit) == "string" and UnitExists and UnitExists(unit) and UnitName then
            name = UnitName(unit)
            for _, spec in ipairs(d.hpUnits or {}) do
                if name == spec.name then
                    mechanics.ObserveNPCHealth(spec.id, unit, spec)
                end
            end
            for _, spec in ipairs(d.thresholds or {}) do
                if name == spec.name then
                    mechanics.ObserveHPThreshold(spec.id, unit, spec, active.generation)
                end
            end
        end
    end
    return true
end

-- Dev-only Defender interval sampler. Samples are consecutive locally
-- observed applications/hits for exactly one positively GUID-bound Defender;
-- no ability cooldown is inferred from them. No independent polling owner.
local defenderSampleNames = { "meteor", "plague", "shadowstorm", "thunderclap" }
local function DefenderRecorderDB()
    local version = GetAddOnMetadata and GetAddOnMetadata("SoloCraftBots", "Version")
    if type(version) ~= "string" or not string.find(version, "%-dev$")
        or type(SoloCraftBotsDB) ~= "table" then return nil end
    return SoloCraftBotsDB
end

function mechanics.RecordDefenderHit(ability, expectedGeneration)
    local db = DefenderRecorderDB()
    if not db or db.bossModDefenderRecord ~= true
        or not active or active.id ~= "aq40_defender" or not active.engaged
        or active.postBossCleanup
        or (expectedGeneration and expectedGeneration ~= active.generation) then
        return false, "recorder unavailable"
    end
    local allowed, i = false, 0
    for i = 1, table.getn(defenderSampleNames) do
        if defenderSampleNames[i] == ability then allowed = true; break end
    end
    if not allowed then return false, "invalid ability" end
    -- Require exactly one live, currently identified Defender instance.
    local id, candidate
    for _, slot in ipairs(presentation.hp.pool) do
        if slot.used and slot.key
            and string.find(slot.key, "^defender:")
            and not slot.dead and slot.unit
            and UnitName and UnitName(slot.unit) == "Anubisath Defender"
            and mechanics.NPCInstanceID(slot.unit) == slot.instanceID then
            if id and id ~= slot.instanceID then
                return false, "ambiguous defender"
            end
            id = slot.instanceID
        end
    end
    if not id then return false, "defender GUID unavailable" end
    active.defenderLastHits = active.defenderLastHits or {}
    active.defenderLastHits[id] = active.defenderLastHits[id] or {}
    local times = active.defenderLastHits[id]
    local now, before = Now(), times[ability]
    -- One locally targeted hit/application line represents a sampling
    -- opportunity. Equal timestamps cannot yield a meaningful interval.
    if before and now <= before then return false, "duplicate timestamp" end
    times[ability] = now
    if not before then return true, "initial observation" end
    local dt = now - before
    db.bossModDefenderIntervals = db.bossModDefenderIntervals or {}
    local samples = db.bossModDefenderIntervals[ability] or {}
    db.bossModDefenderIntervals[ability] = samples
    table.insert(samples, dt)
    if table.getn(samples) > 200 then table.remove(samples, 1) end
    return true, dt
end

-- Only dev builds expose the recorder. All readout is via the existing chat.
if type(GetAddOnMetadata) == "function"
    and type(GetAddOnMetadata("SoloCraftBots", "Version")) == "string"
    and string.find(GetAddOnMetadata("SoloCraftBots", "Version"), "%-dev$")
    and type(SlashCmdList) == "table" then
    SLASH_SCBDEFENDER1 = "/scbdefender"
    SlashCmdList.SCBDEFENDER = function(message)
        local db = DefenderRecorderDB()
        if not db then return end
        message = string.lower(message or "")
        if message == "on" then db.bossModDefenderRecord = true
        elseif message == "off" then db.bossModDefenderRecord = false
        elseif message ~= "export" then
            DEFAULT_CHAT_FRAME:AddMessage("SCB Defender: /scbdefender on|off|export")
            return
        end
        if message ~= "export" then
            DEFAULT_CHAT_FRAME:AddMessage("SCB Defender recorder: " ..
                (db.bossModDefenderRecord and "ON" or "OFF"))
            return
        end
        for _, name in ipairs(defenderSampleNames) do
            local samples = db.bossModDefenderIntervals
                and db.bossModDefenderIntervals[name] or {}
            local minimum, row = nil, {}
            for _, dt in ipairs(samples) do
                if not minimum or dt < minimum then minimum = dt end
                table.insert(row, string.format("%.3f", dt))
            end
            DEFAULT_CHAT_FRAME:AddMessage("SCB " .. name .. " count=" ..
                table.getn(samples) .. " min=" ..
                (minimum and string.format("%.3f", minimum) or "?"))
            for i = 1, table.getn(row), 10 do
                local chunk = {}
                for j = i, math.min(i + 9, table.getn(row)) do
                    table.insert(chunk, row[j])
                end
                DEFAULT_CHAT_FRAME:AddMessage(name .. ": " ..
                    table.concat(chunk, ","))
            end
        end
    end
end

-- Aura rows display caller-observed state. Only recipient/member auras have
-- a memberBinding; observed *ability names* (e.g. Chromaggus breaths) do not.
-- Member auras are retired when the target is dead or leaves the live roster.
function mechanics.ShowTrackedAura(key, label, target, expiresAt, memberBinding, retainAfterBossDeath, iconTexture, rowGroup)
    local slot, err
    if type(label) ~= "string" or type(target) ~= "string"
        or (expiresAt ~= nil and (type(expiresAt) ~= "number" or expiresAt ~= expiresAt))
        or (memberBinding ~= nil and (type(memberBinding) ~= "string"
            or memberBinding == ""))
        or (iconTexture ~= nil and (type(iconTexture) ~= "string"
            or iconTexture == ""))
        or (rowGroup ~= nil and (type(rowGroup) ~= "string"
            or rowGroup == "" or not string.find(rowGroup, "^[%w_%-]+$"))) then
        return false, "invalid aura"
    end
    slot, err = AcquirePresentation("aura", key)
    if not slot then return false, err end
    if iconTexture then slot.frame.icon:SetTexture(iconTexture) end
    slot.label = label
    slot.target = target
    slot.startedAt = Now()
    slot.expiresAt = expiresAt
    slot.memberBinding = memberBinding
    slot.retainAfterBossDeath = retainAfterBossDeath == true
    slot.group = rowGroup -- data only; never alters aura ordering or placement.
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
    LayoutPresentation("action")
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
    local name, member, i, step, info, route, capturedGeneration, timerName, settle
    if not active or (expectedGeneration and expectedGeneration ~= active.generation) then
        return false, "stale encounter"
    end
    if type(action) ~= "table" then return false, "invalid action" end
    if active.postBossCleanup then
        if action.type ~= "kick" then return false, "boss already dead" end
        local valid = false
        for _, auraSlot in ipairs(presentation.aura.pool) do
            if auraSlot.used and auraSlot.retainAfterBossDeath
                and auraSlot.generation == active.generation
                and auraSlot.memberBinding == bindingKey then
                valid = true
                break
            end
        end
        if not valid then return false, "recipient no longer tracked" end
    end
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
    if not TargetUnit or not SCB_RequestCommand
        or not SCB_GetTargetPropagationSettle then
        return false, "target, command or settle owner unavailable"
    end

    -- Target selection is the only immediate operation. A client's
    -- UnitName("target") may update before the server knows that target.
    -- Use SCB's already-established RTT-aware initial settle (minimum 0.25s)
    -- rather than a 0.10s local-only confirmation, which could broadcast Come
    -- to every bot on the first auto-target action.
    TargetUnit(member.unit)
    if not AssignedBotStillTargeted(name) then
        return false, "assigned bot target selection failed"
    end
    settle = math.max(action.targetDelay or SCB_BOSSMOD_TARGET_SETTLE,
        SCB_GetTargetPropagationSettle())
    capturedGeneration = active.generation
    local originalBinding = bindings[bindingKey]
    sequenceSerial = sequenceSerial + 1
    timerName = "delayed-bot-sequence:" .. capturedGeneration .. ":" .. sequenceSerial
    -- Unique timer names preserve repeated clicks (including rapid Come spam).
    -- Reset/death/encounter change clears the encounter timer and bindings.
    return mechanics.ScheduleTimer(timerName, settle, function()
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

-- Conditions are evaluated against SCB's current observed roster, never a
-- cached role or a guessed unit. Unknown roles fail closed.
local function BoundActionAvailable(slot)
    local config = slot.boundDefinition
    local condition = config and config.condition
    if not condition then return true end
    local name, member = mechanics.GetBoundMember(config.binding, slot.generation, false)
    if not member then return config.assignable == true and not name end
    local bot = member.isBot and SCB_IsBotName and SCB_IsBotName(name)
    if condition.recipient == "bot" and not bot then return false end
    if condition.recipient == "human" and bot then return false end
    if condition.role and (member.confirmedRole or member.assumedRole or member.role)
        ~= condition.role then return false end
    if condition.target == "bound" and (not UnitName
        or UnitName("target") ~= name) then return false end
    return true
end

local function ActionForMember(config, member)
    local action = config.action
    if not action or not action.byRole then return action end
    local role = member and (member.confirmedRole or member.assumedRole or member.role)
    return role and action.byRole[role] or nil
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
    local available = BoundActionAvailable(slot)
    if config.hideWhenUnavailable and not available then
        slot.frame:Hide()
        return
    end
    slot.frame:SetAlpha(available and 1 or 0.4)
    slot.actionEnabled = available
    if name then
        if config.assignedLabel == "name" then label = name
        else label = (config.assignedLabel or config.label) .. ": " .. name end
    else
        label = config.label
    end
    slot.frame.label:SetText(label)
    slot.frame.detail:SetText(not available and "Unavailable"
        or (name and not isBot and "Unavailable" or (config.detail or "")))
    if slot.frame.scbUseButton then
        if config.assignable and config.action and isBot and available then
            slot.frame.scbUseButton:Show()
        else
            slot.frame.scbUseButton:Hide()
        end
    end
    slot.frame:Show()
end

-- Generic action frame: assignable bot icon (left assign, left act, right clear)
-- or observed-member action (e.g. an individual Burning Adrenaline kick).
-- "icon" and "position" are optional presentation data, not encounter logic.
-- icon = { texture=path, size=30, point="CENTER",
--          relativePoint="LEFT", x=0, y=0 }
-- position = { "TOP", "TOP", x, y }; expiresAt = absolute GetTime.
function mechanics.ShowBoundBotAction(key, config)
    local slot, err, icon, pos, step, i
    if type(config) ~= "table" or type(config.binding) ~= "string"
        or config.binding == "" or type(config.label) ~= "string"
        or config.label == "" or (config.assignedLabel ~= nil
        and type(config.assignedLabel) ~= "string")
        or (config.detail ~= nil and type(config.detail) ~= "string")
        or (config.assignable ~= nil and type(config.assignable) ~= "boolean")
        or (config.hideWhenUnavailable ~= nil
            and type(config.hideWhenUnavailable) ~= "boolean") then
        return false, "invalid bound action"
    end
    if config.condition ~= nil then
        local c = config.condition
        if type(c) ~= "table"
            or (c.recipient ~= nil and c.recipient ~= "bot"
                and c.recipient ~= "human" and c.recipient ~= "any")
            or (c.role ~= nil and (type(c.role) ~= "string" or c.role == ""))
            or (c.target ~= nil and c.target ~= "bound") then
            return false, "invalid action condition"
        end
    end
    if config.action ~= nil then
        if type(config.action) ~= "table" then return false, "invalid bound action" end
        if config.action.type == "by_role" then
            if type(config.action.byRole) ~= "table"
                or not next(config.action.byRole) then
                return false, "invalid role actions"
            end
            for role, variant in pairs(config.action.byRole) do
                if type(role) ~= "string" or role == ""
                    or type(variant) ~= "table"
                    or variant.type ~= "sequence" or type(variant.steps) ~= "table"
                    or table.getn(variant.steps) == 0
                    or not ValidSequenceTargetDelay(variant.targetDelay) then
                    return false, "invalid role action"
                end
                for _, commandStep in ipairs(variant.steps) do
                    if type(commandStep) ~= "table"
                        or type(commandStep.command) ~= "string"
                        or type(commandStep.scope) ~= "string" then
                        return false, "invalid role command"
                    end
                end
            end
        elseif config.action.type == "sequence" then
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
    slot.actionEnabled = nil
    if icon then
        -- The old overlay is never used for egg art; attached Kick still uses it.
        slot.frame.scbOverlay:Hide()
        slot.frame.label:ClearAllPoints()
        slot.frame.label:SetPoint("LEFT", slot.frame, "LEFT", presentation.action.height + 6, 0)
        slot.frame.label:SetWidth(presentation.action.width - presentation.action.height - 64)
        slot.frame.icon:SetTexture(icon.texture)
    else
        slot.frame.label:ClearAllPoints()
        slot.frame.label:SetPoint("LEFT", slot.frame, "LEFT", presentation.action.height + 6, 0)
        slot.frame.label:SetWidth(presentation.action.width - presentation.action.height - 64)
    end
    RefreshBoundAction(slot)
    LayoutPresentation("action")
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
            if active.postBossCleanup and (not cfg or not cfg.action
                or cfg.action.type ~= "kick"
                or string.sub(slot.key, 1, 5) ~= "kick:") then
                return false, "post-boss action unavailable"
            end
            if not cfg then
                if mouseButton ~= "RightButton" and slot.callback then
                    slot.callback(key, active.generation)
                    return true
                end
                return false, "no action"
            end
            if not BoundActionAvailable(slot) then
                RefreshBoundAction(slot)
                return false, "action condition not met"
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
            local action = ActionForMember(cfg, member)
            if not action then return false, "no action for recipient role" end
            ok, err = mechanics.RunBoundBotAction(cfg.binding, action, active.generation)
            RefreshBoundAction(slot)
            return ok, err
        end
    end
    return false, "action not shown"
end

-- Optional post-aura retention: caller supplies positive fade/expiration evidence
-- and a bounded duration; the existing presentation tick owns the expiry.
-- Repeated calls may extend availability without introducing a second timer.
function mechanics.RetainBoundActionAfterAura(key, seconds)
    if not active or type(seconds) ~= "number" or seconds < 0
        or seconds ~= seconds or seconds == math.huge then
        return false, "invalid retention"
    end
    for _, slot in ipairs(presentation.action.pool) do
        if slot.used and slot.key == key and slot.generation == active.generation then
            slot.expiresAt = math.max(slot.expiresAt or 0, Now() + seconds)
            return true
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
            if slot.frame.scbUseButton then slot.frame.scbUseButton:Hide() end
            slot.generation = nil
            slot.timerName = nil
            slot.progressKind, slot.progressState = nil, nil
            slot.label = nil
            slot.target = nil
            slot.expiresAt = nil
            slot.memberBinding = nil
            slot.retainAfterBossDeath = nil
            slot.instanceID, slot.unit, slot.dead = nil, nil, nil
            slot.clickTarget, slot.hideOnDeath = nil, nil
            slot.frame:Hide()
        end
    end
    for _, panel in pairs(panelSpecs) do
        if panel.frame then panel.frame:Hide() end
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

-- After a confirmed boss death, keep only previously observed recipient
-- auras explicitly declared as retained. The existing SCB event/tick owner
-- continues to process their fades and safe individual filtered Kick actions.
BeginPostBossCleanup = function()
    local session, now = active, Now()
    local retained, survivingBindings, key = {}, {}, nil
    if not session or session.postBossCleanup then return false end
    for _, slot in ipairs(presentation.aura.pool) do
        if slot.used and slot.generation == session.generation
            and slot.retainAfterBossDeath and slot.expiresAt
            and slot.expiresAt > now and not TrackedMemberGone(slot.target) then
            retained[slot.key] = true
            if slot.memberBinding and bindings[slot.memberBinding] then
                survivingBindings[slot.memberBinding] = bindings[slot.memberBinding]
            end
        end
    end
    if not next(retained) then return false end
    session.postBossCleanup = true
    session.bossVisible = false
    -- All cooldowns and delayed command sequences stop immediately.
    -- Retained aura expiry now runs on the existing 10 Hz owner.
    ClearTimers()
    for _, slot in ipairs(presentation.timer.pool) do
        if slot.used then ReleasePresentation("timer", slot.key) end
    end
    for _, slot in ipairs(presentation.action.pool) do
        if slot.used then
            key = slot.key
            if string.sub(key, 1, 5) ~= "kick:"
                or not retained[string.sub(key, 6)]
                or not slot.boundDefinition
                or not slot.boundDefinition.action
                or slot.boundDefinition.action.type ~= "kick" then
                ReleasePresentation("action", key)
            end
        end
    end
    for _, slot in ipairs(presentation.aura.pool) do
        if slot.used and not retained[slot.key] then
            ReleasePresentation("aura", slot.key)
        end
    end
    bindings = survivingBindings
    LayoutPresentation("timer")
    LayoutPresentation("tracker")
    return true
end

FinishPostBossCleanup = function()
    if not active or not active.postBossCleanup then return end
    for _, slot in ipairs(presentation.aura.pool) do
        if slot.used and slot.generation == active.generation
            and slot.retainAfterBossDeath then return end
    end
    mechanics.StopEncounter("post-boss auras resolved", active.generation)
end

-- The existing SCB owner supplies the tick; do not attach frame OnUpdate.
local RenderAbilityBar
-- The SCB 10 Hz owner handles ability transitions, roster checks and cleanup.
-- The faster UpdatePresentation below only interpolates visible bars.
function mechanics.UpdatePresentationState(now)
    local session = active
    if not session then return end
    if type(now) ~= "number" then now = Now() end
    if not session.postBossCleanup then mechanics.UpdateAbilityStates(now) end
    local actionVisibilityChanged = false
    for _, slot in ipairs(presentation.action.pool) do
        if slot.used and slot.generation == session.generation then
            if slot.expiresAt and now >= slot.expiresAt then
                ReleasePresentation("action", slot.key)
            elseif slot.boundDefinition then
                local wasShown = slot.frame:IsShown()
                RefreshBoundAction(slot)
                if wasShown ~= slot.frame:IsShown() then
                    actionVisibilityChanged = true
                end
            end
        end
    end
    for _, slot in ipairs(presentation.aura.pool) do
        if slot.used and slot.generation == session.generation
            and slot.memberBinding
            and (TrackedMemberGone(slot.target)
                or (session.postBossCleanup and slot.expiresAt
                    and now >= slot.expiresAt)) then
            RetireTrackedMemberAura(slot)
        end
    end
    mechanics.PruneAbilityAuras(now)
    if actionVisibilityChanged then LayoutPresentation("tracker") end
    FinishPostBossCleanup()
end

function mechanics.UpdatePresentation(now)
    local session = active
    local group, slot, timer, remaining
    if not session then return end
    if type(now) ~= "number" then now = Now() end
    group = presentation.timer
    for _, slot in ipairs(group.pool) do
        if slot.used and slot.generation == session.generation then
            if slot.progressKind then
                local state, frame = slot.progressState, slot.frame
                if slot.progressKind == "counter" then
                    frame.label:SetText(slot.label)
                    frame.detail:SetText(tostring(state.count) .. "/" ..
                        (state.spec.maximumKind == "observed" and "" or "~") ..
                        tostring(state.spec.maximum))
                    frame.bar:SetValue(math.max(0, math.min(1,
                        state.count / state.spec.maximum)))
                    frame.bar:SetStatusBarColor(0.22, 0.55, 0.94)
                elseif slot.progressKind == "stage" then
                    frame.label:SetText(state.label)
                    local earliest = math.max(0, state.minimumAt - now)
                    local latest = math.max(0, state.maximumAt - now)
                    local total = math.max(0.001, state.minimumAt - state.startedAt)
                    frame.bar:SetValue(math.max(0, math.min(1, earliest / total)))
                    if now >= state.minimumAt then
                        -- Earliest possible readiness is not observed proof.
                        if state.provenance == "predicted"
                            or state.maximumAt > state.minimumAt then
                            frame.detail:SetText("Ready?")
                        else
                            frame.detail:SetText(SCB_L("BOSSMODS_READY"))
                        end
                        frame.bar:SetStatusBarColor(0.05, 0.38, 0.14)
                    else
                        if state.maximumAt > state.minimumAt then
                            frame.detail:SetText(string.format("~%.0f-%.0fs",
                                earliest, latest))
                        elseif state.provenance == "fixed" then
                            frame.detail:SetText(string.format("%.0fs", earliest))
                        else
                            frame.detail:SetText(string.format("~%.0fs", earliest))
                        end
                        frame.bar:SetStatusBarColor(0.22, 0.55, 0.94)
                    end
                elseif slot.progressKind == "threshold" then
                    frame.label:SetText(slot.label)
                    local unit = state.unit
                    local observed = unit and mechanics.NPCInstanceID(unit)
                        == state.instanceID and UnitHealth and UnitHealthMax
                    local health, maximum
                    if observed then
                        health, maximum = UnitHealth(unit), UnitHealthMax(unit)
                        observed = type(health) == "number"
                            and type(maximum) == "number" and maximum > 0
                            and health == health and health >= 0
                            and health <= maximum
                    end
                    if observed then
                        local pct = math.max(0, math.min(1, health / maximum))
                        if state.lastPct and pct > state.lastPct then
                            -- Healing invalidates the measured loss baseline.
                            state.baselinePct, state.baselineAt = pct, now
                        end
                        state.currentPct, state.lastPct = pct, pct
                    end
                    local pct = state.currentPct or 1
                    frame.bar:SetValue(math.max(0, math.min(1,
                        (pct - state.threshold) / (1 - state.threshold))))
                    frame.bar:SetStatusBarColor(0.96, 0.61, 0.10)
                    local elapsed = now - (state.baselineAt or now)
                    local loss = (state.baselinePct or pct) - pct
                    if not observed then
                        frame.detail:SetText("?")
                    elseif pct <= state.threshold then
                        -- Reaching HP percentage does not prove a boss ability.
                        frame.detail:SetText(string.format("%.0f%% HP", 100 * state.threshold))
                    elseif elapsed > 0 and loss > 0 then
                        frame.detail:SetText(string.format("~%.0fs",
                            (pct - state.threshold) * elapsed / loss))
                    else
                        frame.detail:SetText("?")
                    end
                end
                frame:Show()
            elseif slot.abilityRecord or slot.abilityHint then
                RenderAbilityBar(slot, now)
            else
                timer = mechanics.GetTimer(slot.timerName)
                if not timer then
                    ReleasePresentation("timer", slot.key)
                else
                    remaining = math.max(0, timer.deadline - now)
                    slot.frame.label:SetText(slot.label)
                    slot.frame.detail:SetText(string.format("%.0fs", remaining))
                    slot.frame.bar:SetValue(math.max(0, math.min(1,
                        remaining / math.max(0.001, timer.deadline -
                            (slot.startedAt or now)))))
                    if remaining / math.max(0.001, timer.deadline -
                        (slot.startedAt or now)) <= 0.25 then
                        slot.frame.bar:SetStatusBarColor(0.96, 0.61, 0.10)
                    else
                        slot.frame.bar:SetStatusBarColor(0.22, 0.55, 0.94)
                    end
                    slot.frame:Show()
                end
            end
        end
    end
    for _, slot in ipairs(presentation.hp.pool) do
        if slot.used and slot.generation == session.generation then
            local unit = slot.unit
            if not slot.dead and unit
                and mechanics.NPCInstanceID(unit) == slot.instanceID
                and UnitHealth and UnitHealthMax then
                local health, maximum = UnitHealth(unit), UnitHealthMax(unit)
                if type(health) == "number" and type(maximum) == "number"
                    and maximum > 0 and health == health then
                    slot.health, slot.maximum = health, maximum
                    if health <= 0 or (UnitIsDeadOrGhost
                        and UnitIsDeadOrGhost(unit)) then slot.dead = true end
                end
            end
            if slot.dead and slot.hideOnDeath then
                ReleasePresentation("hp", slot.key)
            else
                slot.frame.label:SetText(slot.label)
                if slot.dead then
                    slot.frame.detail:SetText("DEAD")
                    slot.frame.bar:SetValue(0)
                    slot.frame.bar:SetStatusBarColor(0.35, 0.35, 0.35)
                else
                    slot.frame.detail:SetText(string.format("%.0f%%",
                        100 * math.max(0, math.min(1,
                            (slot.health or 0) / math.max(1, slot.maximum or 1)))))
                    slot.frame.bar:SetValue(math.max(0, math.min(1,
                        (slot.health or 0) / math.max(1, slot.maximum or 1))))
                    slot.frame.bar:SetStatusBarColor(0.12, 0.55, 0.20)
                end
            end
        end
    end
    for _, slot in ipairs(presentation.aura.pool) do
        if slot.used and slot.generation == session.generation then
            if slot.memberBinding then
                slot.frame.label:SetText(TrackerMemberLabel(slot.target, slot.label))
            else
                -- Observed abilities without a recipient keep their own name.
                slot.frame.label:SetText(slot.target)
            end
            if slot.expiresAt then
                local remain = math.max(0, slot.expiresAt - now)
                local duration = math.max(0.001, slot.expiresAt - (slot.startedAt or now))
                slot.frame.detail:SetText(string.format("%.0fs", remain))
                slot.frame.bar:SetValue(math.max(0, math.min(1, remain / duration)))
                slot.frame.bar:SetStatusBarColor(0.22, 0.55, 0.94)
            else
                slot.frame.detail:SetText("")
                slot.frame.bar:SetValue(1)
                slot.frame.bar:SetStatusBarColor(0.12, 0.40, 0.18)
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
        spec = spec, caster = spec.caster, group = spec.group, phase = "unstarted",
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
                group = group.group,
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
            -- Reuse a speculative visual slot without assigning its guessed
            -- first-cast time to this real observed breath's identity.
            for _, hint in ipairs(session.firstSlotHints[id] or {}) do
                if not hint.expired then
                    hint.expired = true
                    mechanics.HidePresentation("timer", "ability:" .. hint.id)
                    break
                end
            end
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
        state.readyAt, state.startedAt = nil, at
        if spec.observedOnly then
            state.phase, state.uncertainty = "observed", "cooldown not established"
        else
            state.phase = "ready" -- preserve BWL baseline
        end
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
        previous.uncertainty = "finish not observed; superseded by next cast"
        previous.occurrence.finished = true
        if previous.cooldownFromStart then
            -- The other ability's clock is already running from its OWN
            -- observed start. Never halt or move it because this caster
            -- started a different spell.
            previous.phase = previous.readyAt and now >= previous.readyAt
                and "ready" or "cooldown"
        else
            previous.phase = "unresolved"
        end
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
    if mechanics.ShowAbilityBars then mechanics.ShowAbilityBars() end
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
    if mechanics.ShowAbilityBars then mechanics.ShowAbilityBars() end
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
        if state and state.phase ~= "unstarted" then
            slot, err = AcquirePresentation("timer", "ability:" .. key)
            if not slot then return false, err end
            slot.abilityRecord, slot.abilityHint = state, nil
            slot.label = state.name or state.spec.label
            -- Native 1.12.1 cannot resolve arbitrary NPC spells by name.
            -- Use the specific, validated encounter icon (including each
            -- observed Chromaggus breath), not the pool's '?' default.
            local iconTexture = state.name and state.spec.icons
                and state.spec.icons[state.name] or state.spec.icon
            if iconTexture then slot.frame.icon:SetTexture(iconTexture) end
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

RenderAbilityBar = function(slot, now)
    local state, hint, phase, start, deadline, remaining, total, progress
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
    frame.label:SetText(slot.label)
    if phase == "casting" then
        -- Estimated visual casting length never proves actual completion.
        local occurrence = state and state.occurrence
        local from = occurrence and occurrence.startedAt or now
        local finish = occurrence and occurrence.expectedEnd or now
        total = math.max(0.001, finish - from)
        progress = math.max(0, math.min(1, (now - from) / total))
        frame.bar:SetValue(progress)
        frame.bar:SetStatusBarColor(0.12, 0.96, 0.20)
        frame.detail:SetText(SCB_L("BOSSMODS_CAST"))
    elseif phase == "observed" then
        frame.bar:SetValue(1)
        frame.bar:SetStatusBarColor(0.45, 0.45, 0.45)
        frame.detail:SetText("Observed")
    elseif phase == "unresolved" then
        frame.bar:SetValue(1)
        frame.bar:SetStatusBarColor(0.94, 0.56, 0.12)
        frame.detail:SetText(SCB_L("BOSSMODS_UNRESOLVED"))
    elseif phase == "ready" or not deadline or now >= deadline then
        frame.bar:SetValue(1)
        frame.bar:SetStatusBarColor(0.05, 0.38, 0.14)
        frame.detail:SetText(SCB_L("BOSSMODS_READY"))
    else
        total = math.max(0.001, deadline - (start or now))
        remaining = math.max(0, deadline - now)
        progress = math.max(0, math.min(1, remaining / total))
        frame.bar:SetValue(progress)
        frame.detail:SetText(string.format("~%.0fs", remaining))
        if progress <= 0.25 then
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

local function IsFiniteNumber(value)
    return type(value) == "number" and value == value
        and math.abs(value) < math.huge
end

local function CheckEffect(e, hasPattern)
    local i, names
    if type(e) ~= "table" or not IsId(e.id) then return false end
    if e.type == "dev_interval" then
        return e.ability == "meteor" or e.ability == "plague"
            or e.ability == "shadowstorm" or e.ability == "thunderclap"
    elseif e.type == "counter_hit" or e.type == "counter_reset" then
        return e.label == nil and e.duration == nil
    elseif e.type == "timer_stage" then
        return type(e.label) == "string" and e.label ~= ""
            and IsFiniteNumber(e.minDelay) and e.minDelay >= 0
            and (e.maxDelay == nil or (IsFiniteNumber(e.maxDelay)
                and e.maxDelay >= e.minDelay))
            and (e.provenance == nil or e.provenance == "fixed"
                or e.provenance == "predicted")
            and (e.group == nil or (type(e.group) == "string"
                and string.find(e.group, "^[%w_]+$") ~= nil))
            and (e.icon == nil or (type(e.icon) == "string" and e.icon ~= ""))
    elseif e.type == "timer" then
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

-- Ability vocabulary is declarative: observations name native events and
-- explicit patterns; no boss-specific handler functions or code in encounters.
local function CheckObservation(o)
    local i
    if o == nil then return true end
    if type(o) ~= "table" or (o.event ~= nil and o.events ~= nil)
        or (o.contains ~= nil and o.pattern ~= nil)
        or (type(o.contains) ~= "string" and type(o.pattern) ~= "string") then
        return false
    end
    if o.event then
        if type(o.event) ~= "string" or o.event == "" then return false end
    else
        if type(o.events) ~= "table" or table.getn(o.events) < 1 then return false end
        for i = 1, table.getn(o.events) do
            if type(o.events[i]) ~= "string" or o.events[i] == "" then return false end
        end
    end
    if o.pattern and not pcall(string.find, "", o.pattern) then return false end
    return true
end

-- Optional semantic grouping is metadata, not UI layout or NPC identity.
local function CheckRowGroup(value)
    return value == nil or IsId(value)
end

local function CheckAbility(a, seen, isGroup)
    local i, j, aura, found = 0, 0, nil, {}
    if type(a) ~= "table" or not IsId(a.id) or seen[a.id]
        or type(a.label) ~= "string" or a.label == ""
        or type(a.caster) ~= "string" or a.caster == ""
        or not CheckRowGroup(a.group)
        or (a.mode ~= "fixed" and a.mode ~= "priority"
            and a.mode ~= "opportunistic")
        or (a.firstDelay ~= nil and not IsDuration(a.firstDelay))
        or (a.repeatDelay ~= nil and not IsDuration(a.repeatDelay))
        or (a.castTime ~= nil and not IsDuration(a.castTime))
        or (a.startOffset ~= nil and (not IsFiniteNumber(a.startOffset) or a.startOffset < 0))
        or (a.resetOn ~= nil and a.resetOn ~= "start" and a.resetOn ~= "finish")
        or (a.repeatDelay ~= nil and a.resetOn == nil)
        or (a.ordinary ~= nil and type(a.ordinary) ~= "boolean")
        or (a.observedOnly ~= nil and type(a.observedOnly) ~= "boolean")
        or (a.observedOnly and a.repeatDelay ~= nil)
        or (a.icon ~= nil and (type(a.icon) ~= "string" or a.icon == ""))
        or (a.icons ~= nil and (not isGroup or type(a.icons) ~= "table"))
        or not CheckObservation(a.startRule)
        or not CheckObservation(a.finishRule)
        or not CheckObservation(a.interruptRule)
        or (a.auras ~= nil and type(a.auras) ~= "table") then
        return false
    end
    if isGroup then
        if type(a.names) ~= "table" or table.getn(a.names) == 0
            or not CheckObservation(a.startRule)
            or type(a.startRule) ~= "table" or not a.startRule.pattern
            or type(a.firstSlots) ~= "table" or table.getn(a.firstSlots) == 0
            or table.getn(a.firstSlots) > 2
            or (a.maxVisible ~= nil and (type(a.maxVisible) ~= "number"
                or a.maxVisible ~= 2)) then return false end
        for i = 1, table.getn(a.names) do
            if type(a.names[i]) ~= "string" or a.names[i] == ""
                or found[a.names[i]] then return false end
            found[a.names[i]] = true
        end
        for i = 1, table.getn(a.firstSlots) do
            if not IsDuration(a.firstSlots[i]) then return false end
        end
        -- Every named observed breath has its own valid texture.
        if a.icons then
            for name, texture in pairs(a.icons) do
                if not found[name] or type(texture) ~= "string"
                    or texture == "" then return false end
            end
            for name in pairs(found) do
                if not a.icons[name] then return false end
            end
        end
    elseif a.names or a.firstSlots or a.maxVisible then
        return false
    end
    found = {}
    for i, aura in ipairs(a.auras or {}) do
        if type(aura) ~= "table" or not IsId(aura.id)
            or (found[aura.id] and found[aura.id] ~= aura.label)
            or type(aura.label) ~= "string"
            or aura.label == ""
            or (aura.target ~= "capture" and aura.target ~= "player")
            or (aura.duration ~= nil and not IsDuration(aura.duration))
            or (aura.action ~= nil and aura.action ~= "kick")
            or not CheckRowGroup(aura.group)
            or (aura.icon ~= nil and (type(aura.icon) ~= "string"
                or aura.icon == ""))
            or (aura.kickLabel ~= nil and type(aura.kickLabel) ~= "string")
            or (aura.retainAfterBossDeath ~= nil
                and type(aura.retainAfterBossDeath) ~= "boolean")
            or (aura.retainAfterBossDeath and not IsDuration(aura.duration))
            or not CheckObservation(aura.gain) or not CheckObservation(aura.fade)
            or (aura.gain == nil and aura.fade == nil) then
            return false
        end
        found[aura.id] = aura.label
        if aura.target == "capture" then
            if aura.gain and not aura.gain.pattern then return false end
            if aura.fade and not aura.fade.pattern then return false end
        end
    end
    seen[a.id] = true
    return true
end

local function CheckCounter(c, seen)
    if type(c) ~= "table" or not IsId(c.id) or seen[c.id]
        or type(c.label) ~= "string" or c.label == ""
        or not IsFiniteNumber(c.maximum) or c.maximum < 1
        or c.maximum ~= math.floor(c.maximum)
        or (c.maximumKind ~= nil and c.maximumKind ~= "reference"
            and c.maximumKind ~= "observed")
        or not CheckRowGroup(c.group)
        or (c.icon ~= nil and (type(c.icon) ~= "string" or c.icon == ""))
        then return false end
    seen[c.id] = true
    return true
end

local function CheckObservedUnits(d)
    local seen, spec, i
    for _, kind in ipairs({ "hpUnits", "thresholds" }) do
        if d[kind] ~= nil and type(d[kind]) ~= "table" then return false end
        seen = {}
        for i, spec in ipairs(d[kind] or {}) do
            if type(spec) ~= "table" or not IsId(spec.id) or seen[spec.id]
                or type(spec.name) ~= "string" or spec.name == ""
                or type(spec.label) ~= "string" or spec.label == ""
                or not CheckRowGroup(spec.group)
                or (spec.icon ~= nil and (type(spec.icon) ~= "string" or spec.icon == "")) then
                return false
            end
            if kind == "hpUnits" then
                if (spec.hideOnDeath ~= nil and type(spec.hideOnDeath) ~= "boolean")
                    or (spec.clickTarget ~= nil and type(spec.clickTarget) ~= "boolean")
                    or spec.threshold ~= nil then return false end
            elseif not IsFiniteNumber(spec.threshold)
                or spec.threshold <= 0 or spec.threshold >= 1
                or spec.clickTarget ~= nil or spec.hideOnDeath ~= nil then
                return false
            end
            seen[spec.id] = true
        end
    end
    return true
end

local function CheckDeclaration(d)
    local i, j, w, rule, step, seen = 0, 0, nil, nil, nil, {}
    if type(d) ~= "table" or type(d.detect) ~= "table"
        or type(d.detect.zone) ~= "string" or d.detect.zone == ""
        or type(d.detect.boss) ~= "string" or d.detect.boss == ""
        or (d.detect.prepareInZone ~= nil
            and type(d.detect.prepareInZone) ~= "boolean")
        or type(d.mechanics) ~= "table" or type(d.triggers) ~= "table"
        or not CheckObservedUnits(d)
        or (d.detect.endOnBossDeath ~= nil
            and type(d.detect.endOnBossDeath) ~= "boolean") then
        return false, "missing detect, mechanics or triggers"
    end
    local aliases = {}
    if d.detect.aliases ~= nil then
        if type(d.detect.aliases) ~= "table" then return false, "invalid aliases" end
        for _, name in ipairs(d.detect.aliases) do
            if type(name) ~= "string" or name == ""
                or name == d.detect.boss or aliases[name] then
                return false, "invalid alias"
            end
            aliases[name] = true
        end
    end
    for i = 1, table.getn(d.mechanics) do
        w = d.mechanics[i]
        if type(w) ~= "table" or not IsId(w.id) or seen[w.id]
            or (w.when ~= "present" and w.when ~= "zone")
            or (w.when == "zone" and d.detect.prepareInZone ~= true)
            or w.type ~= "assignable_bot_action"
            or not CheckRowGroup(w.group)
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
    if d.counters ~= nil and type(d.counters) ~= "table" then
        return false, "invalid counters"
    end
    local counterIds = {}
    for i = 1, table.getn(d.counters or {}) do
        if not CheckCounter(d.counters[i], seen) then
            return false, "invalid counter"
        end
        counterIds[d.counters[i].id] = true
    end
    if d.abilities ~= nil and type(d.abilities) ~= "table" then
        return false, "invalid abilities"
    end
    if d.abilityGroups ~= nil and type(d.abilityGroups) ~= "table" then
        return false, "invalid ability groups"
    end
    for i = 1, table.getn(d.abilities or {}) do
        if not CheckAbility(d.abilities[i], seen, false) then
            return false, "invalid ability"
        end
    end
    for i = 1, table.getn(d.abilityGroups or {}) do
        if not CheckAbility(d.abilityGroups[i], seen, true) then
            return false, "invalid ability group"
        end
    end
    for i = 1, table.getn(d.triggers) do
        rule = d.triggers[i]
        if type(rule) ~= "table" or type(rule.effects) ~= "table"
            or table.getn(rule.effects) == 0
            or (type(rule.contains) ~= "string" and type(rule.pattern) ~= "string")
            or (rule.contains ~= nil and rule.pattern ~= nil)
            or (rule.event ~= nil and rule.events ~= nil)
            or not CheckRowGroup(rule.group) then
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
            if (rule.effects[j].type == "counter_hit"
                or rule.effects[j].type == "counter_reset")
                and not counterIds[rule.effects[j].id] then
                return false, "counter not declared"
            end
        end
    end
    return true
end

-- Pure Lua-table catalogue, e.g. { bwl = { razorgore = { ... } } }.
-- Registration is all-or-nothing; the caller owns loading encounters.lua.
function mechanics.RegisterDeclarativeEncounters(catalogue)
    local pending, raid, bosses, name, def, id, ok, why, count
    local zonePrep = {}
    if type(catalogue) ~= "table" then return false, "invalid catalogue" end
    for _, entry in pairs(encounters) do
        if entry.declarative and entry.declarative.detect.prepareInZone then
            zonePrep[entry.declarative.detect.zone] = true
        end
    end
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
            if def.detect.prepareInZone then
                if zonePrep[def.detect.zone] then
                    return false, "duplicate zone preparation"
                end
                zonePrep[def.detect.zone] = true
            end
            pending[id] = { events = {}, declarative = def }
            count = count + 1
        end
    end
    if count == 0 then return false, "empty catalogue" end
    for id, def in pairs(pending) do encounters[id] = def end
    return true, count
end

-- Source registry for the pre-existing SCB event frame. No extra frame
-- listens to combat text: the owner asks for precisely the events in BWL.
function mechanics.CanonicalBoss(zone, boss)
    for _, entry in pairs(encounters) do
        local d = entry.declarative
        if d and d.detect.zone == zone then
            if d.detect.boss == boss then return boss end
            for _, alias in ipairs(d.detect.aliases or {}) do
                if alias == boss then return d.detect.boss end
            end
        end
    end
    return boss
end

function mechanics.GetDetectableBosses(zone)
    local result, seen, entry, d = {}, {}, nil, nil
    for _, entry in pairs(encounters) do
        d = entry.declarative
        if d and d.detect.zone == zone then
            for _, name in ipairs({ d.detect.boss, unpack(d.detect.aliases or {}) }) do
                if not seen[name] then
                    table.insert(result, name)
                    seen[name] = true
                end
            end
        end
    end
    table.sort(result)
    return result
end

function mechanics.GetRequiredEvents(zone)
    local result, seen, entry, d, rule, spec, aura = {}, {}
    -- Native 1.12 creature melee observations complement spell casts. They
    -- can positively discover bosses with no configured special ability.
    local melee = {
        "CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS",
        "CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_MISSES",
        "CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS",
        "CHAT_MSG_COMBAT_CREATURE_VS_PARTY_MISSES",
        "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS",
        "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES",
    }
    for _, eventName in ipairs(melee) do
        seen[eventName] = true
        table.insert(result, eventName)
    end
    local function AddRule(observation)
        local i, eventName
        if not observation then return end
        if observation.event then
            if not seen[observation.event] then
                seen[observation.event] = true
                table.insert(result, observation.event)
            end
        else
            for i, eventName in ipairs(observation.events or {}) do
                if not seen[eventName] then
                    seen[eventName] = true
                    table.insert(result, eventName)
                end
            end
        end
    end
    for _, entry in pairs(encounters) do
        d = entry.declarative
        if d and d.detect.zone == zone then
            -- The SCB-owned event frame also needs reliable positive death
            -- evidence when the boss is no longer held in anyone's target.
            AddRule({ event = "CHAT_MSG_COMBAT_HOSTILE_DEATH" })
            for _, rule in ipairs(d.triggers) do AddRule(rule) end
            for _, spec in ipairs(d.abilities or {}) do
                AddRule(spec.startRule)
                AddRule(spec.finishRule)
                AddRule(spec.interruptRule)
                for _, aura in ipairs(spec.auras or {}) do
                    AddRule(aura.gain)
                    AddRule(aura.fade)
                end
            end
            for _, spec in ipairs(d.abilityGroups or {}) do
                AddRule(spec.startRule)
                AddRule(spec.finishRule)
                AddRule(spec.interruptRule)
            end
        end
    end
    table.sort(result)
    return result
end

-- Match source-bound native messages before starting an unseen encounter.
-- Boss names must be exact beginning-of-message sources (not victims or
-- substrings). Monster yells use the native author field and only declared
-- text patterns, so unrelated speech cannot start a boss encounter.
function mechanics.GetBossFromCombatEvidence(zone, eventName, message, speaker)
    local d, boss, suffix, matched
    if type(message) ~= "string" or message == "" then return nil end
    for _, entry in pairs(encounters) do
        d = entry.declarative
        if d and d.detect.zone == zone then
            for _, actor in ipairs({ d.detect.boss, unpack(d.detect.aliases or {}) }) do
                boss = d.detect.boss -- actor identity resolves to one encounter
                if eventName == "CHAT_MSG_MONSTER_YELL" and speaker == actor then
                    for _, rule in ipairs(d.triggers or {}) do
                        if rule.event == eventName and
                            ((rule.contains and string.find(message, rule.contains, 1, true))
                            or (rule.pattern and string.find(message, rule.pattern))) then
                            return boss, false
                        end
                    end
                elseif string.sub(message, 1, string.len(actor)) == actor then
                    suffix = string.sub(message, string.len(actor) + 1)
                    if string.find(eventName, "CHAT_MSG_COMBAT_CREATURE_VS_", 1, true) == 1 then
                        matched = string.find(suffix, "^ hits ")
                            or string.find(suffix, "^ crits ")
                            or string.find(suffix, "^ misses ")
                            or string.find(suffix, "^ attacks ")
                            or string.find(suffix, "^ is parried ")
                        if matched then return boss, true end
                    elseif string.find(eventName, "CHAT_MSG_SPELL_CREATURE_VS_", 1, true) == 1 then
                        matched = string.find(suffix, "^ begins to cast ")
                            or string.find(suffix, "^ casts ")
                            or string.find(suffix, "^'s ")
                        if matched then return boss, true end
                    end
                end
            end
        end
    end
    return nil
end

-- An explicit, zone-gated PREPARATION is not an NPC-alive observation.
-- It makes the eggbreaker available before any raid member targets the boss.
-- Command clicks still use the existing SCB action/roster owners. Only one
-- declarative preparation is permitted per zone, avoiding arbitrary selection.
function mechanics.PrepareZoneEncounter(zone)
    local id, entry, d, w, i, ok, why
    if active then return false, "encounter already active" end
    for id, entry in pairs(encounters) do
        d = entry.declarative
        if d and d.detect.zone == zone and d.detect.prepareInZone
            and not prepSuppressed[id] then
            ok, why = mechanics.StartEncounter(id)
            if not ok then return false, why end
            active.prepared = true
            active.bossVisible = false
            for i = 1, table.getn(d.mechanics) do
                w = d.mechanics[i]
                if w.when == "zone" then
                    mechanics.ShowBoundBotAction("presence:" .. w.id, w)
                end
            end
            return true
        end
    end
    return false, "no zone preparation"
end

-- Match documented native Vanilla combat-death messages exactly. Neither
-- losing a target nor guessing a raid lockout counts as a boss death.
function mechanics.ObserveBossDeathMessage(zone, eventName, message)
    local d, boss
    if eventName ~= "CHAT_MSG_COMBAT_HOSTILE_DEATH"
        or type(message) ~= "string" then return false end
    for _, entry in pairs(encounters) do
        d = entry.declarative
        if d and d.detect.zone == zone then
            boss = d.detect.boss
            if (message == boss .. " dies."
                or message == "You have slain " .. boss .. "!")
                and d.detect.endOnBossDeath ~= false then
                return mechanics.ObserveBoss(zone, boss, "dead")
            end
        end
    end
    return false
end

-- Only the SCB-owned, zone-gated observation pipeline may call this API.
-- A positively observed living boss unlocks its pre-pull action. Losing
-- target visibility does NOT prove absence or death and must not hide the
-- action while the player selects a bot. Confirmed death, a different boss,
-- or the SCB-owned zone reset ends the encounter and clears its actions.
function mechanics.ObserveBoss(zone, boss, state)
    local id, entry, d, w, i, ok, why
    if type(zone) ~= "string" or type(boss) ~= "string"
        or (state ~= "alive" and state ~= "absent" and state ~= "dead") then
        return false, "invalid observation"
    end
    boss = mechanics.CanonicalBoss(zone, boss)
    -- Track definitive death even if the target was lost before the message.
    -- Positive living observation can clear a prior suppression (e.g. reset).
    for id, entry in pairs(encounters) do
        d = entry.declarative
        if d and d.detect.zone == zone and d.detect.boss == boss
            and d.detect.prepareInZone then
            if state == "dead" then prepSuppressed[id] = true
            elseif state == "alive" then prepSuppressed[id] = nil end
        end
    end
    if active and active.definition.declarative
        and active.definition.declarative.detect.zone ~= zone then
        mechanics.StopEncounter("zone change")
    end
    if active and active.definition.declarative then
        d = active.definition.declarative
        if d.detect.zone == zone and d.detect.boss == boss then
            if active.postBossCleanup then
                -- Repeated corpse sightings cannot restart a dead encounter.
                if state == "alive" then return false, "boss already dead" end
                return true
            end
            if state == "dead" then
                if d.detect.endOnBossDeath == false then
                    active.bossVisible = false
                    return true
                end
                if BeginPostBossCleanup and BeginPostBossCleanup() then return true end
                mechanics.StopEncounter("confirmed boss death")
                return true
            elseif state == "absent" then
                -- Keep observed pre-pull actions clickable during temporary
                -- target loss (notably when selecting an eggbreaker bot).
                -- Only positive encounter termination clears the frame.
                active.bossVisible = false
                return true
            end
            if active.bossVisible then return true end
            active.bossVisible = true
        elseif state ~= "alive" then
            return false, "other boss observed"
        elseif active.engaged and not active.postBossCleanup then
            -- Encounter engagement is authoritative; a raid member targeting
            -- a later boss through the wall cannot replace this fight.
            return false, "engaged encounter locked"
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
        if w.when == "present" or w.when == "zone" then
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

local function RunDeclaredEffect(effect, captured, details)
    local key, name, binding, deadline, token, seen
    if not active then return end
    key = "decl:" .. effect.id
    if effect.type == "dev_interval" then
        mechanics.RecordDefenderHit(effect.ability, active.generation)
    elseif effect.type == "counter_hit" then
        mechanics.ObserveCounterHit(effect.id,
            details and details.observationId, active.generation)
    elseif effect.type == "counter_reset" then
        mechanics.ResetCounter(effect.id, active.generation)
    elseif effect.type == "timer_stage" then
        mechanics.SetTimerStage(effect.id, effect, active.generation)
    elseif effect.type == "timer" then
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
            mechanics.ShowTrackedAura(key, effect.label, name, deadline, binding,
                effect.retainAfterBossDeath, effect.icon, effect.group)
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

-- Match only explicit source-scoped native messages. An optional verified
-- spell ID in a future SCB event payload is additional evidence, not required.
local function MatchAbilityObservation(rule, eventName, message, details)
    local i, eventMatches, a, b, captured
    if not rule then return false end
    eventMatches = rule.event == eventName
    if rule.events then
        eventMatches = false
        for i = 1, table.getn(rule.events) do
            if rule.events[i] == eventName then eventMatches = true; break end
        end
    end
    if not eventMatches or type(message) ~= "string" then return false end
    if rule.spellId and (not details or details.spellId ~= rule.spellId) then
        return false
    end
    if rule.contains then
        return string.find(message, rule.contains, 1, true) ~= nil, nil
    end
    a, b, captured = string.find(message, rule.pattern)
    return a ~= nil, captured
end

function mechanics.DispatchAbilityEvent(session, eventName, message, details)
    local spec, aura, rule, name, matched, captured, state, count, i, j
    local key, effect, recipient, now, token
    if not session or active ~= session or not session.engaged then return 0 end
    if not session.abilities and not session.postBossCleanup then
        mechanics.InitializeAbilities(session.generation)
    end
    if not session.abilities then return 0 end
    count = 0
    local function Deliver(spec, isGroup)
        local observation, observedName
        if not session.postBossCleanup then
            matched, captured = MatchAbilityObservation(spec.startRule, eventName, message, details)
            if matched then
                observedName = isGroup and captured or nil
                if mechanics.ObserveAbilityStart(spec.id, observedName, session.generation) then
                    count = count + 1
                end
            end
            matched, captured = MatchAbilityObservation(spec.finishRule, eventName, message, details)
            if matched and mechanics.ObserveAbilityFinish(spec.id,
                isGroup and captured or nil, session.generation) then
                count = count + 1
            end
            matched, captured = MatchAbilityObservation(spec.interruptRule, eventName, message, details)
            if matched and mechanics.ObserveAbilityInterrupt(spec.id,
                isGroup and captured or nil, session.generation) then
                count = count + 1
            end
        end
        -- Per-recipient auras can arrive without any start event. An aura
        -- never implicitly resets the parent cooldown or asserts a cast.
        state = session.abilities[spec.id]
        for j, aura in ipairs(spec.auras or {}) do
            matched, captured = MatchAbilityObservation(aura.gain, eventName, message, details)
            if matched and not session.postBossCleanup then
                recipient = Recipient(aura, captured)
                if recipient then
                    effect = { type = "aura_apply", id = spec.id .. "_" .. aura.id,
                        target = aura.target, label = aura.label, duration = aura.duration,
                        action = aura.action, kickLabel = aura.kickLabel,
                        retainAfterBossDeath = aura.retainAfterBossDeath,
                        icon = aura.icon or spec.icon, group = aura.group or spec.group }
                    RunDeclaredEffect(effect, captured)
                    if state then
                        now = Now()
                        state.auras[aura.id .. ":" .. recipient] = { name = recipient, appliedAt = now,
                            expiresAt = aura.duration and now + aura.duration or nil,
                            occurrenceId = state.occurrence and state.occurrence.id }
                    end
                    count = count + 1
                end
            end
            matched, captured = MatchAbilityObservation(aura.fade, eventName, message, details)
            if matched and (not session.postBossCleanup or aura.retainAfterBossDeath) then
                recipient = Recipient(aura, captured)
                if recipient then
                    effect = { type = "aura_remove", id = spec.id .. "_" .. aura.id,
                        target = aura.target }
                    RunDeclaredEffect(effect, captured)
                    if state then state.auras[aura.id .. ":" .. recipient] = nil end
                    count = count + 1
                end
            end
        end
    end
    for i, spec in ipairs(session.definition.declarative.abilities or {}) do
        if active ~= session then break end
        Deliver(spec, false)
    end
    for i, spec in ipairs(session.definition.declarative.abilityGroups or {}) do
        if active ~= session then break end
        Deliver(spec, true)
    end
    if session.postBossCleanup and active == session then FinishPostBossCleanup() end
    return count
end

-- Aura housekeeping consumes the same roster owner as the existing aura UI.
-- No side-channel health roster or second frame-driven scan is introduced.
function mechanics.PruneAbilityAuras(now)
    local session = GetAbilitySession()
    local state, name, aura
    if not session or not session.abilities then return end
    if type(now) ~= "number" then now = Now() end
    for _, state in pairs(session.abilities) do
        for name, aura in pairs(state.auras) do
            if (aura.expiresAt and now >= aura.expiresAt)
                or TrackedMemberGone(aura.name) then
                state.auras[name] = nil
            end
        end
    end
end

-- Called ONLY through DispatchEvent on the currently active declaration.
-- The first Lua-pattern capture supplies a recipient for multi-aura tracking.
function mechanics.DispatchDeclarativeEvent(session, eventName, message, details)
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
                    RunDeclaredEffect(rule.effects[j], captured, details)
                end
                count = count + 1
            end
        end
    end
    count = count + mechanics.DispatchAbilityEvent(session, eventName, message, details)
    return count
end
