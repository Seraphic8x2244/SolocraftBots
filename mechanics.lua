-- SoloCraft Bots - Boss Mods encounter engine (Lua 5.0.3).
-- Loaded after Communication.lua and before encounters.lua. Boss Mods events,
-- observations and ticks belong here; shared SCB commands/roster remain outside.
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
local moduleLifecycle = { raids = {}, current = nil }

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
    if active.moduleState then
        active.moduleState.attempt = active.moduleState.attempt + 1
        for _, sub in pairs(active.moduleState.combatModules) do
            sub.active, sub.retained = true, false
        end
    end
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
        postBossCleanup = active.postBossCleanup == true,
        retainingEffects = active.retainingEffects == true,
        attempt = active.moduleState and active.moduleState.attempt or 0 }
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
    if definition.moduleSpec then
        local runtime = { spec = definition.moduleSpec, attempt = 0,
            deaths = {}, passiveModules = {}, combatModules = {} }
        for _, sub in ipairs(definition.moduleSpec.passiveModules) do
            runtime.passiveModules[sub.id] = { spec = sub, active = true }
        end
        for _, sub in ipairs(definition.moduleSpec.combatModules) do
            runtime.combatModules[sub.id] = { spec = sub, active = false, retained = false }
        end
        active.moduleState = runtime
    end
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
    if session.postBossCleanup or (session.retainingEffects and not session.engaged) then
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
function mechanics.ScheduleTimer(name, delay, callback, kind, retainedActionKey)
    if not active or (active.postBossCleanup and
        not (retainedActionKey and active.retainedActions
            and active.retainedActions[retainedActionKey])) then
        return false, "no active encounter"
    end
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

-- Serviced by the single Boss Mods update frame below; callbacks can safely
-- reset, replace
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


-- Presentation templates are serviced by the Boss Mods update owner below.
-- This section itself does not create an event frame or tick.
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
        -- Sentinel kill priority follows the ORIGINAL observed ability.
        -- Unknown originals sort last, retaining acquisition order on ties.
        if active and active.id == "aq40.sentinels" then
            local order = {}
            for i, slot in ipairs(rows) do order[slot] = i end
            table.sort(rows, function(a, b)
                local ar = a.sentinelAbilities and a.sentinelAbilities.priority
                local br = b.sentinelAbilities and b.sentinelAbilities.priority
                ar, br = ar or 999, br or 999
                if ar ~= br then return ar < br end
                return order[a] < order[b]
            end)
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
        if frame.scbAttackAllButton then
            frame.scbAttackAllButton:SetWidth(rowHeight)
            frame.scbAttackAllButton:SetHeight(rowHeight)
            frame.scbAttackAllButton:SetFrameLevel(frame:GetFrameLevel() + 2)
            if slot.attackAll and not slot.dead then
                frame.scbAttackAllButton:Show()
            else
                frame.scbAttackAllButton:Hide()
            end
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
        -- Explicit all-bot attack button lives in the reserved right square.
        -- The main HP row retains its separate target-only click.
        local attackButton = CreateFrame("Button", nil, frame)
        attackButton:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        attackButton:SetWidth(group.height)
        attackButton:SetHeight(group.height)
        attackButton:SetFrameLevel(frame:GetFrameLevel() + 2)
        local attackIcon = attackButton:CreateTexture(nil, "OVERLAY")
        attackIcon:SetAllPoints(attackButton)
        attackIcon:SetTexture("Interface\\Icons\\Ability_Warrior_Charge")
        frame.scbAttackAllButton = attackButton
        attackButton:SetScript("OnEnter", function()
            if GameTooltip then
                GameTooltip:SetOwner(attackButton, "ANCHOR_RIGHT")
                GameTooltip:SetText("Start Attack - All Bots")
                GameTooltip:Show()
            end
        end)
        attackButton:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        attackButton:RegisterForClicks("LeftButtonUp")
        attackButton:SetScript("OnClick", function()
            local slot = frame.scbSlot
            if slot and slot.used then mechanics.AttackNPCAll(slot.key) end
        end)
        attackButton:Hide()
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
    slot.clickTarget, slot.hideOnDeath, slot.attackAll = nil, nil, nil
    slot.timerName = nil
    slot.progressKind, slot.progressState = nil, nil
    slot.startedAt = nil
    slot.frame.label:Show()
    slot.frame.detail:Show()
    slot.frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    slot.frame.icon:Show()
    if slot.frame.scbUseButton then slot.frame.scbUseButton:Hide() end
    if slot.frame.scbAttackAllButton then slot.frame.scbAttackAllButton:Hide() end
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
            slot.clickTarget, slot.hideOnDeath, slot.attackAll = nil, nil, nil
            slot.timerName = nil
            slot.progressKind, slot.progressState = nil, nil
            slot.generation = nil
            if slot.frame.scbOverlay then slot.frame.scbOverlay:Hide() end
            if slot.frame.scbUseButton then slot.frame.scbUseButton:Hide() end
            if slot.frame.scbAttackAllButton then slot.frame.scbAttackAllButton:Hide() end
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
        if not spec.submodule or mechanics.IsSubmoduleActive(spec.submodule) then
        local state = { count = 0, seen = {}, spec = spec, generation = active.generation }
        active.counters[spec.id] = state
        local slot, err = AcquirePresentation("timer", "counter:" .. spec.id)
        if not slot then return false, err end
        slot.progressKind, slot.progressState = "counter", state
        slot.label, slot.group = spec.label, spec.group
        if spec.icon then slot.frame.icon:SetTexture(spec.icon) end
        end
    end
    for _, spec in ipairs(active.definition.declarative.initialStages or {}) do
        local ok, err = mechanics.SetTimerStage(spec.id, spec, active.generation)
        if not ok then return false, err end
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

-- Optional GUID-attributed cast-stage evidence uses the existing SCB
-- event owner. Never associate a same-name replacement with this caster.
-- A missing source GUID simply withholds the transition on vanilla clients.
function mechanics.ObserveDeclaredCastEvent(casterGuid, castType, spellId,
    expectedGeneration)
    if not active or not active.engaged or active.postBossCleanup
        or (expectedGeneration and expectedGeneration ~= active.generation)
        or type(casterGuid) ~= "string" or casterGuid == ""
        or castType ~= "CAST" or type(spellId) ~= "number" then
        return false, "invalid or stale cast event"
    end
    local d = active.definition.declarative
    for _, spec in ipairs(d and d.castStages or {}) do
        if spec.spellId == spellId then
            for _, slot in ipairs(presentation.timer.pool) do
                if slot.used and slot.generation == active.generation
                    and slot.key == "threshold:" .. spec.sourceThreshold
                    and slot.progressKind == "threshold"
                    and slot.progressState
                    and slot.progressState.instanceID == casterGuid then
                    return mechanics.SetTimerStage(spec.id, spec, active.generation)
                end
            end
        end
    end
    return false, "cast source not positively identified"
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
        or (options.attackAll ~= nil and type(options.attackAll) ~= "boolean")
        or (options.attackAll and options.clickTarget ~= true)
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
    slot.attackAll = options.attackAll == true
    if slot.frame.scbAttackAllButton then
        if slot.attackAll and not slot.dead then
            slot.frame.scbAttackAllButton:Show()
        else
            slot.frame.scbAttackAllButton:Hide()
        end
    end
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


local hpAttackSerial = 0

-- Explicit button action for a GUID-bound hostile HP row. Every click
-- revalidates the exact instance both before and after SCB's established
-- target-propagation settle. No bot can receive an attack on a recycled token
-- or a player-selected different target.
function mechanics.AttackNPCAll(key)
    if not active or not active.engaged or active.postBossCleanup
        or type(key) ~= "string" then return false, "no active encounter" end
    local slot
    for _, candidate in ipairs(presentation.hp.pool) do
        if candidate.used and candidate.key == key
            and candidate.generation == active.generation then
            slot = candidate
            break
        end
    end
    if not slot or not slot.attackAll or slot.dead then
        return false, "attack widget unavailable"
    end
    local unit, guid = slot.unit, slot.instanceID
    if not unit or not guid or mechanics.NPCInstanceID(unit) ~= guid
        or not UnitExists or not UnitExists(unit)
        or not UnitIsDeadOrGhost or UnitIsDeadOrGhost(unit)
        or not TargetUnit or not SCB_RequestCommand
        or not SCB_GetTargetPropagationSettle then
        return false, "stale npc instance"
    end
    local command = SCB.commands and SCB.commands.attackstart
    if not command or not command.routes or not command.routes.all then
        return false, "attack owner unavailable"
    end
    TargetUnit(unit)
    if mechanics.NPCInstanceID("target") ~= guid then
        return false, "target selection failed"
    end
    local token, capturedKey = active.generation, key
    local delay = math.max(0.10, SCB_GetTargetPropagationSettle())
    hpAttackSerial = hpAttackSerial + 1
    return mechanics.ScheduleTimer(
        "hp-attack:" .. token .. ":" .. hpAttackSerial, delay, function()
            if not active or active.generation ~= token or not active.engaged
                or active.postBossCleanup then return end
            if mechanics.NPCInstanceID("target") ~= guid
                or mechanics.NPCInstanceID(unit) ~= guid
                or not UnitExists(unit) or not UnitExists("target")
                or UnitIsDeadOrGhost(unit) or UnitIsDeadOrGhost("target") then
                return
            end
            local valid = false
            for _, current in ipairs(presentation.hp.pool) do
                if current.used and not current.dead
                    and current.generation == token
                    and current.key == capturedKey
                    and current.instanceID == guid
                    and current.attackAll then valid = true; break end
            end
            if valid then SCB_RequestCommand("attackstart", "all") end
        end, "fixed")
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
                local matches = name == spec.name
                if not matches then
                    for _, alias in ipairs(spec.aliases or {}) do
                        if name == alias then matches = true; break end
                    end
                end
                if matches then
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

-- Positive GUID-bound Sentinel observations. Source callers must identify a
-- specific live unit token; text-only combat events are NOT adequate evidence.
-- Original identity cannot be inferred from abilities inherited later.
local function SentinelPriority(name)
    local declaration = SoloCraftBots.bossModDefinitions
    local group = declaration and declaration.aq40 and declaration.aq40.sentinels
    for _, tier in ipairs(group and group.initialAbilityPriority or {}) do
        for _, candidate in ipairs(tier.names or {}) do
            if candidate == name then return tier.rank end
        end
    end
    return nil
end

function mechanics.ObserveSentinelAbility(unit, ability, provenance, expectedGeneration)
    if not active or active.id ~= "aq40.sentinels" or not active.engaged
        or active.postBossCleanup
        or (expectedGeneration and active.generation ~= expectedGeneration)
        or (provenance ~= "original" and provenance ~= "inherited")
        or type(ability) ~= "string" or not SentinelPriority(ability)
        or not UnitName or UnitName(unit) ~= "Anubisath Sentinel" then
        return false, "unverified sentinel observation"
    end
    local guid = mechanics.NPCInstanceID(unit)
    if not guid then return false, "unidentified sentinel" end
    local row
    for _, slot in ipairs(presentation.hp.pool) do
        if slot.used and not slot.dead and slot.instanceID == guid
            and slot.key == "sentinel:" .. guid then row = slot; break end
    end
    if not row then return false, "sentinel hp not tracked" end
    local state = row.sentinelAbilities
    if not state then state = { observed = {} }; row.sentinelAbilities = state end
    if provenance == "original" then
        if state.original and state.original ~= ability then
            return false, "conflicting original ability"
        end
        state.original = ability
    end
    state.observed[ability] = true
    state.priority = state.original and SentinelPriority(state.original) or nil
    LayoutPresentation("tracker")
    return true
end

function mechanics.GetSentinelAbilities(unit, expectedGeneration)
    if not active or active.id ~= "aq40.sentinels" or not active.engaged
        or (expectedGeneration and active.generation ~= expectedGeneration) then
        return nil
    end
    local guid = mechanics.NPCInstanceID(unit)
    if not guid or not UnitName or UnitName(unit) ~= "Anubisath Sentinel" then
        return nil
    end
    for _, row in ipairs(presentation.hp.pool) do
        if row.used and not row.dead and row.instanceID == guid
            and row.key == "sentinel:" .. guid then
            local state = row.sentinelAbilities
            local observed = {}
            if state then
                for ability in pairs(state.observed) do
                    table.insert(observed, ability)
                end
                table.sort(observed)
            end
            return { guid = guid, original = state and state.original,
                priority = state and state.original
                    and SentinelPriority(state.original) or nil,
                observed = observed }
        end
    end
    return nil
end

-- Defender pair selection is recorded only against an observed individual
-- GUID. No global combat-log hit selects a pair, and no readiness is inferred.
local defenderPairs = {
    meteor = 1, plague = 1,
    shadowstorm = 2, thunderclap = 2,
    firearcane = 3, frostshadow = 3,
}
function mechanics.ObserveDefenderAbility(unit, ability, expectedGeneration)
    if not active or active.id ~= "aq40.defender" or not active.engaged
        or active.postBossCleanup
        or (expectedGeneration and expectedGeneration ~= active.generation)
        or type(ability) ~= "string" or not defenderPairs[ability]
        or not UnitName or UnitName(unit) ~= "Anubisath Defender" then
        return false, "unverified defender observation"
    end
    local guid = mechanics.NPCInstanceID(unit)
    if not guid then return false, "unidentified defender" end
    for _, row in ipairs(presentation.hp.pool) do
        if row.used and not row.dead and row.instanceID == guid
            and row.key == "defender:" .. guid then
            local selected = row.defenderPairs or {}
            local pair = defenderPairs[ability]
            if selected[pair] and selected[pair] ~= ability then
                return false, "conflicting defender pair"
            end
            selected[pair] = ability
            row.defenderPairs = selected
            mechanics.UpdatePresentation()
            return true
        end
    end
    return false, "defender hp not tracked"
end

function mechanics.GetDefenderAbilities(unit, expectedGeneration)
    if not active or active.id ~= "aq40.defender" or not active.engaged
        or active.postBossCleanup
        or (expectedGeneration and expectedGeneration ~= active.generation)
        or not UnitName or UnitName(unit) ~= "Anubisath Defender" then
        return nil
    end
    local guid = mechanics.NPCInstanceID(unit)
    if not guid then return nil end
    for _, row in ipairs(presentation.hp.pool) do
        if row.used and not row.dead and row.instanceID == guid
            and row.key == "defender:" .. guid then
            local observedPairs = {}
            for pair, ability in pairs(row.defenderPairs or {}) do
                observedPairs[pair] = ability
            end
            return { guid = guid, pairs = observedPairs }
        end
    end
    return nil
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
    if not db or db.bossModDefenderRecord == false
        or not active or active.id ~= "aq40.defender" or not active.engaged
        or active.postBossCleanup
        or (expectedGeneration and expectedGeneration ~= active.generation) then
        return false, "recorder unavailable"
    end
    local allowed, i = false, 0
    for i = 1, table.getn(defenderSampleNames) do
        if defenderSampleNames[i] == ability then allowed = true; break end
    end
    if not allowed then return false, "invalid ability" end
    -- Attribution must remain unambiguous even when another live
    -- Defender is temporarily out of token range. Do not silently ignore
    -- such a tracked instance and attach its hit to the visible one.
    local id, candidate
    for _, slot in ipairs(presentation.hp.pool) do
        if slot.used and slot.key and string.find(slot.key, "^defender:")
            and not slot.dead then
            if id and id ~= slot.instanceID then
                return false, "ambiguous defender"
            end
            id = slot.instanceID
            candidate = slot
        end
    end
    if not id or not candidate or not candidate.unit
        or not UnitName or UnitName(candidate.unit) ~= "Anubisath Defender"
        or mechanics.NPCInstanceID(candidate.unit) ~= id then
        return false, "defender GUID unavailable"
    end
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

-- Native self-hit stopwatch for Defender pairs 1 and 2. It is elapsed
-- time since positive evidence, NEVER a claimed cooldown or cast duration.
-- The development recorder remains independently controlled by /scbdefender.
function mechanics.ObserveDefenderElapsed(ability, expectedGeneration)
    if not active or active.id ~= "aq40.defender" or not active.engaged
        or (expectedGeneration and expectedGeneration ~= active.generation) then
        return false
    end
    local labels = {
        meteor = "Meteor - since hit", plague = "Plague - since applied",
        shadowstorm = "Shadow Storm - since hit",
        thunderclap = "Thunderclap - since hit",
    }
    if not labels[ability] then return false end
    local slot = AcquirePresentation("timer", "defender-elapsed:" .. ability)
    if not slot then return false end
    slot.label = labels[ability]
    slot.progressKind = "elapsed"
    slot.progressState = { observedAt = Now() }
    mechanics.UpdatePresentation()
    return true
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
                (db.bossModDefenderRecord ~= false and "ON" or "OFF"))
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

function mechanics.RunBoundBotAction(bindingKey, action, expectedGeneration, actionKey)
    local name, member, i, step, info, route, capturedGeneration, timerName, settle
    if not active or (expectedGeneration and expectedGeneration ~= active.generation) then
        return false, "stale encounter"
    end
    if type(action) ~= "table" then return false, "invalid action" end
    if active.postBossCleanup then
        if not actionKey or not active.retainedActions
            or not active.retainedActions[actionKey] then
            return false, "post-boss action unavailable"
        end
        local valid = false
        for _, slot in ipairs(presentation.action.pool) do
            if slot.used and slot.key == actionKey
                and slot.generation == active.generation
                and slot.boundDefinition
                and slot.boundDefinition.binding == bindingKey then
                valid = true
                break
            end
        end
        if not valid then return false, "retained action no longer tracked" end
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
    end, "fixed", actionKey)
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
    -- A recipient action cannot borrow another member's observed aura.
    if condition.observedAura then
        if not name or not member then return false end
        local observed = false
        for _, auraSlot in ipairs(presentation.aura.pool) do
            if auraSlot.used and auraSlot.key == condition.observedAura
                and auraSlot.generation == active.generation
                and auraSlot.memberBinding == config.binding
                and auraSlot.target == name
                and (not auraSlot.expiresAt or Now() < auraSlot.expiresAt) then
                observed = true
                break
            end
        end
        if not observed then return false end
    end
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
            or (c.target ~= nil and c.target ~= "bound")
            or (c.observedAura ~= nil and (type(c.observedAura) ~= "string"
                or c.observedAura == "")) then
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
            if active.postBossCleanup and not
                (active.retainedActions and active.retainedActions[slot.key]) then
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
            ok, err = mechanics.RunBoundBotAction(cfg.binding, action,
                active.generation, slot.key)
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
            if slot.frame.scbAttackAllButton then slot.frame.scbAttackAllButton:Hide() end
            slot.generation = nil
            slot.timerName = nil
            slot.progressKind, slot.progressState = nil, nil
            slot.label = nil
            slot.target = nil
            slot.expiresAt = nil
            slot.memberBinding = nil
            slot.retainAfterBossDeath = nil
            slot.instanceID, slot.unit, slot.dead = nil, nil, nil
            slot.clickTarget, slot.hideOnDeath, slot.attackAll = nil, nil, nil
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

-- Retention belongs to combat SUBMODULES. Until BWL is migrated, the
-- existing aura flag continues to opt in using the same UI/action owner.
function moduleLifecycle.RetainsSlot(session, kind, slot)
    if kind == "aura" and slot.retainAfterBossDeath then return true end
    if not session.moduleState then return false end
    for _, sub in pairs(session.moduleState.combatModules) do
        local spec, tracker = sub.spec, sub.spec.tracker
        if spec.retainUntilResolved and tracker and tracker.kind == kind
            and string.sub(slot.key or "", 1, string.len(tracker.keyPrefix))
                == tracker.keyPrefix then return true end
    end
    return false
end

function moduleLifecycle.TrackerCount(session, trackerId)
    local state = session and session.moduleState
    if not state then return 0 end
    for _, sub in pairs(state.combatModules) do
        local tracker = sub.spec.tracker
        if tracker and tracker.id == trackerId then
            local count, now = 0, Now()
            for _, slot in ipairs(presentation[tracker.kind].pool) do
                if slot.used and slot.generation == session.generation
                    and string.sub(slot.key or "", 1, string.len(tracker.keyPrefix))
                        == tracker.keyPrefix
                    and (not slot.expiresAt or now < slot.expiresAt) then
                    count = count + 1
                end
            end
            return count
        end
    end
    return 0
end

-- Shared disengage/death transition: cease normal timers and attempt UI,
-- preserve unresolved aura rows AND their existing Kick action bindings.
-- Passive presence controls remain while the encounter is merely disengaged.
BeginPostBossCleanup = function(afterDeath)
    local session, now = active, Now()
    local retained = { aura = {}, hp = {}, action = {} }
    local keepBindings, hasRetained = {}, false
    if not session or session.postBossCleanup then return false end
    for _, kind in ipairs({ "aura", "hp", "action" }) do
        for _, slot in ipairs(presentation[kind].pool) do
            if slot.used and slot.generation == session.generation
                and moduleLifecycle.RetainsSlot(session, kind, slot)
                and (not slot.expiresAt or now < slot.expiresAt)
                and (not slot.memberBinding or not TrackedMemberGone(slot.target)) then
                retained[kind][slot.key] = true
                hasRetained = true
            end
        end
    end
    -- Link retained trackers to associated action keys by recipient suffix.
    -- VAEL uses kick:<aura-key>; generic submodules may name actionKeyPrefix.
    for _, slot in ipairs(presentation.aura.pool) do
        if slot.used and retained.aura[slot.key] then
            retained.action["kick:" .. slot.key] = true
        end
    end
    if session.moduleState then
        for _, sub in pairs(session.moduleState.combatModules) do
            local cfg = sub.spec.tracker
            if cfg and sub.spec.retainUntilResolved and cfg.actionKeyPrefix then
                for _, slot in ipairs(presentation[cfg.kind].pool) do
                    if slot.used and retained[cfg.kind][slot.key] then
                        local suffix = string.sub(slot.key, string.len(cfg.keyPrefix) + 1)
                        retained.action[cfg.actionKeyPrefix .. suffix] = true
                    end
                end
            end
            sub.retained = sub.spec.retainUntilResolved and cfg
                and moduleLifecycle.TrackerCount(session, cfg.id) > 0 or false
            sub.active = sub.retained
        end
    end
    session.retainingEffects = hasRetained
    session.postBossCleanup = afterDeath == true and hasRetained
    session.retainedActions = retained.action
    session.bossVisible = false
    ClearTimers()
    for _, kind in ipairs({ "timer", "hp", "aura", "action" }) do
        for _, slot in ipairs(presentation[kind].pool) do
            if slot.used then
                local passive = kind == "action" and not afterDeath
                    and string.sub(slot.key, 1, 9) == "presence:"
                local keep = retained[kind] and retained[kind][slot.key]
                if not keep and not passive then
                    ReleasePresentation(kind, slot.key)
                elseif kind == "action" and slot.boundDefinition
                    and slot.boundDefinition.binding
                    and bindings[slot.boundDefinition.binding] then
                    keepBindings[slot.boundDefinition.binding] =
                        bindings[slot.boundDefinition.binding]
                elseif kind == "aura" and slot.memberBinding
                    and bindings[slot.memberBinding] then
                    keepBindings[slot.memberBinding] = bindings[slot.memberBinding]
                end
            end
        end
    end
    bindings = keepBindings
    LayoutPresentation("timer")
    LayoutPresentation("tracker")
    return hasRetained
end

FinishPostBossCleanup = function()
    local session = active
    if not session or not session.retainingEffects then return end
    for _, kind in ipairs({ "aura", "hp", "action" }) do
        for _, slot in ipairs(presentation[kind].pool) do
            if slot.used and slot.generation == session.generation
                and moduleLifecycle.RetainsSlot(session, kind, slot)
                and (not slot.expiresAt or Now() < slot.expiresAt) then return end
        end
    end
    session.retainingEffects = false
    session.retainedActions = nil
    if session.moduleState then
        for _, sub in pairs(session.moduleState.combatModules) do
            sub.retained = false
            if not session.engaged then sub.active = false end
        end
    end
    if session.postBossCleanup then
        mechanics.CheckModuleSleeper(session.generation)
    end
end

-- The existing SCB owner supplies the tick; do not attach frame OnUpdate.
local RenderAbilityBar
-- The SCB 10 Hz owner handles ability transitions, roster checks and cleanup.
-- The faster UpdatePresentation below only interpolates visible bars.
-- Toxin Tracker uses the live SCB roster and the existing group Come owner.
-- It deliberately NEVER changes target to the poisoned bot.
function mechanics.ObserveViscidusToxin(name, expectedGeneration)
    if not active or active.id ~= "aq40.viscidus" or not active.engaged
        or (expectedGeneration and active.generation ~= expectedGeneration)
        or active.toxinFirst then return false end
    local member = ResolveBoundLive(name, true, true)
    if not member then return false end
    active.toxinFirst = { name = name, untilTime = Now() + 8 }
    return true
end

local function RefreshToxinTracker()
    if not active or active.id ~= "aq40.viscidus" or not active.engaged then return end
    local state = active.toxinFirst
    local member = state and ResolveBoundLive(state.name, true, true) or nil
    local role = member and (member.confirmedRole or member.assumedRole or member.role)
    local scope
    if role == "meleedps" or role == "tank" then scope = "melee"
    elseif role == "rangedps" or role == "healer" then scope = "rangedhealer" end
    local live = state and Now() < state.untilTime and member and scope
    local detail = "Awaiting first poisoned bot"
    if state then
        detail = state.name .. "  HP: "
        if member and UnitHealth and UnitHealthMax then
            detail = detail .. tostring(UnitHealth(member.unit)) ..
                "/" .. tostring(UnitHealthMax(member.unit))
        else detail = detail .. "unavailable" end
        if not live then detail = detail .. " (inactive)" end
    end
    local slot
    for _, candidate in ipairs(presentation.action.pool) do
        if candidate.used and candidate.key == "viscidus:toxin"
            and candidate.generation == active.generation then slot = candidate; break end
    end
    if not slot then
        mechanics.ShowBotAction("viscidus:toxin", "Toxin Tracker", detail, nil)
        for _, candidate in ipairs(presentation.action.pool) do
            if candidate.used and candidate.key == "viscidus:toxin"
                and candidate.generation == active.generation then slot = candidate; break end
        end
    end
    if not slot then return end
    slot.frame.detail:SetText(detail)
    slot.callback = live and function(_, gen)
        if not active or active.generation ~= gen
            or active.toxinFirst ~= state or Now() >= state.untilTime then return end
        local current = ResolveBoundLive(state.name, true, true)
        local currentRole = current and
            (current.confirmedRole or current.assumedRole or current.role)
        local route = (currentRole == "meleedps" or currentRole == "tank")
            and "melee" or ((currentRole == "rangedps" or currentRole == "healer")
                and "rangedhealer" or nil)
        if route and SCB_RequestCommand then
            SCB_RequestCommand("come", route)
        end
    end or nil
end

-- Native AQ40 observations use the existing encounter presentation tick.
local function AQ40VisibleBoss(name)
    if not UnitExists or not UnitName then return false end
    if UnitExists("target") and UnitName("target") == name then return true end
    local count = GetNumRaidMembers and GetNumRaidMembers() or 0
    for i = 1, count do
        local token = "raid" .. i .. "target"
        if UnitExists(token) and UnitName(token) == name then return true end
    end
    return false
end

local function AQ40SkeramMark()
    if not UnitExists or not UnitName or not UnitHealthMax
        or not SetRaidTarget or not GetNumRaidMembers then return end
    if not ((IsRaidLeader and IsRaidLeader())
        or (IsRaidOfficer and IsRaidOfficer())) then return end
    local count = GetNumRaidMembers()
    local minimum = count >= 20 and count <= 40
        and count * 10000 or (count < 20 and 200000 or nil)
    if not minimum then return end
    local tokens = { "target" }
    for i = 1, count do table.insert(tokens, "raid" .. i .. "target") end
    for _, token in ipairs(tokens) do
        if UnitExists(token) and UnitName(token) == "The Prophet Skeram"
            and UnitHealthMax(token) > minimum then
            local marker = GetRaidTargetIndex and GetRaidTargetIndex(token)
            if marker ~= 6 and not active.skeramMarked then
                SetRaidTarget(token, 6)
                active.skeramMarked = true
            elseif marker == 6 then
                active.skeramMarked = true
            end
            return
        end
    end
end

local function AQ40OuroSubmerge(now)
    if not active or not active.engaged or active.postBossCleanup
        or active.id ~= "aq40.ouro" then return end
    if AQ40VisibleBoss("Ouro") then
        active.ouroSeen = true
    elseif active.ouroSeen and active.ouroPhase ~= "submerged"
        and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
        active.ouroPhase = "submerged"
        mechanics.SetTimerStage("ourocycle", {
            label = "Next Emerge (reference)", minDelay = 27,
            provenance = "predicted",
            icon = "Interface\\Icons\\INV_Misc_Shovel_01",
        }, active.generation)
    end
end

function mechanics.UpdatePresentationState(now)
    local session = active
    if not session then return end
    if type(now) ~= "number" then now = Now() end
    if not session.postBossCleanup then mechanics.UpdateAbilityStates(now) end
    if session.id == "aq40.viscidus" then RefreshToxinTracker() end
    if session.engaged and session.id == "aq40.skeram" then AQ40SkeramMark() end
    if session.engaged and session.id == "aq40.ouro" then AQ40OuroSubmerge(now) end
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
                or (session.retainingEffects and slot.expiresAt
                    and now >= slot.expiresAt)) then
            RetireTrackedMemberAura(slot)
        end
    end
    mechanics.PruneAbilityAuras(now)
    if actionVisibilityChanged then LayoutPresentation("tracker") end
    FinishPostBossCleanup()
    if active == session and session.postBossCleanup then
        mechanics.CheckModuleSleeper(session.generation)
    end
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
                if slot.progressKind == "elapsed" then
                    frame.label:SetText(slot.label)
                    frame.detail:SetText(string.format("%.1fs elapsed",
                        math.max(0, now - state.observedAt)))
                    frame.bar:SetValue(0)
                    frame.bar:SetStatusBarColor(0.22, 0.55, 0.94)
                elseif slot.progressKind == "counter" then
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
                local label = slot.label
                if session.id == "aq40.sentinels" and slot.sentinelAbilities then
                    local seen = {}
                    for spell in pairs(slot.sentinelAbilities.observed) do
                        table.insert(seen, spell)
                    end
                    table.sort(seen)
                    if table.getn(seen) > 0 then
                        label = label .. " [" .. table.concat(seen, ", ") .. "]"
                    end
                elseif session.id == "aq40.defender" and slot.defenderPairs then
                    local seen = {}
                    for pair = 1, 3 do
                        if slot.defenderPairs[pair] then
                            table.insert(seen, slot.defenderPairs[pair])
                        end
                    end
                    if table.getn(seen) > 0 then
                        label = label .. " [" .. table.concat(seen, ", ") .. "]"
                    end
                end
                slot.frame.label:SetText(label)
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
        if not spec.submodule or mechanics.IsSubmoduleActive(spec.submodule) then
            AddAbilityState(session, spec, nil, false)
        end
    end
    -- Unconfirmed first slots are visual predictions, never named breaths.
    for i, group in ipairs(session.definition.declarative.abilityGroups or {}) do
        session.firstSlotHints[group.id] = {}
        for j, duration in ipairs(group.firstSlots or {}) do
            if not group.submodule or mechanics.IsSubmoduleActive(group.submodule) then
            session.firstSlotHints[group.id][j] = {
                id = "first:" .. group.id .. ":" .. j,
                label = group.label .. " " .. j, startedAt = AbilityClock(),
                readyAt = AbilityClock() + duration, speculative = true,
                group = group.group,
                provenance = "predicted",
            }
            end
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
function mechanics.ObserveAbilityFinish(id, spellName, expectedGeneration, observationId)
    local session, state, occurrence, now
    session = GetAbilitySession()
    if not session or (expectedGeneration and session.generation ~= expectedGeneration)
        or not session.engaged then return false, "stale encounter" end
    state = ResolveAbility(id, spellName)
    if not state then return false, "unknown ability" end
    -- A confirmed event identity can de-duplicate repeated recipient lines
    -- without guessing an AoE cooldown or merging distinct occurrences.
    if observationId ~= nil and (type(observationId) ~= "string"
        and type(observationId) ~= "number") then
        return false, "invalid observation identity"
    end
    if observationId ~= nil and state.lastFinishObservationId == observationId then
        return true, "duplicate observation"
    end
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
    state.lastFinishObservationId = observationId
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

-- The interruption itself is positive evidence. The lockout duration is
-- an explicitly declared estimate tied to the observed interrupting spell.
-- A random silence, missing cast or stale event never starts a Heal timer.
function mechanics.ObserveAbilityLockout(id, seconds, expectedGeneration)
    local session = GetAbilitySession()
    if not session or not session.engaged or session.postBossCleanup
        or (expectedGeneration and session.generation ~= expectedGeneration)
        or type(seconds) ~= "number" or seconds <= 0
        or seconds ~= seconds or seconds == math.huge then
        return false, "invalid ability lockout"
    end
    local state = session.abilities and session.abilities[id]
    local now = AbilityClock()
    if not state or not state.occurrence
        or (state.phase ~= "casting" and state.phase ~= "unresolved")
        or state.occurrence.finished or not state.occurrence.observedStart
        or type(state.occurrence.startedAt) ~= "number"
        or now < state.occurrence.startedAt
        or now - state.occurrence.startedAt >
            (state.spec.castTime or 0) + 1 then
        return false, "no recent observed cast to interrupt"
    end
    state.occurrence.finished = true
    state.occurrence.interrupted = true
    state.phase, state.startedAt, state.readyAt = "cooldown", now, now + seconds
    state.uncertainty = "interrupt school lockout estimated"
    if session.casterCasts[state.caster] == state then
        session.casterCasts[state.caster] = nil
    end
    if mechanics.ShowAbilityBars then mechanics.ShowAbilityBars() end
    return true
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
        if state and state.phase ~= "unstarted"
            and not (session.id == "aq40.cthun" and session.cthunPhase == 2
                and key == "darkglare") then
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
    frame.label:SetText(state and phase == "ready"
        and state.spec.readyLabel or slot.label)
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

-- Declarative engine. The dedicated Boss Mods frame below registers the
-- catalogue and forwards zone-scoped observations and events.
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
    if e.type == "viscidus_toxin" then
        return (e.target == nil or e.target == "player")
            and (e.target == "player" or hasPattern)
    elseif e.type == "viscidus_phase" then
        return e.phase == "frost" or e.phase == "melee"
    elseif e.type == "cthun_glare" or e.type == "cthun_phase2"
        or e.type == "cthun_weakened" then
        return true
    elseif e.type == "ability_lockout" then
        return type(e.ability) == "string" and IsId(e.ability)
            and IsDuration(e.duration)
    elseif e.type == "dev_interval" then
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
        or (a.readyLabel ~= nil and (type(a.readyLabel) ~= "string"
            or a.readyLabel == ""))
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
                if spec.aliases ~= nil then
                    if type(spec.aliases) ~= "table" then return false end
                    local aliasSeen = { [spec.name] = true }
                    for _, alias in ipairs(spec.aliases) do
                        if type(alias) ~= "string" or alias == ""
                            or aliasSeen[alias] then return false end
                        aliasSeen[alias] = true
                    end
                end
                if (spec.hideOnDeath ~= nil and type(spec.hideOnDeath) ~= "boolean")
                    or (spec.clickTarget ~= nil and type(spec.clickTarget) ~= "boolean")
                    or (spec.attackAll ~= nil and type(spec.attackAll) ~= "boolean")
                    or (spec.attackAll and spec.clickTarget ~= true)
                    or spec.threshold ~= nil then return false end
            elseif not IsFiniteNumber(spec.threshold)
                or spec.threshold <= 0 or spec.threshold >= 1
                or spec.clickTarget ~= nil or spec.hideOnDeath ~= nil
                or spec.attackAll ~= nil then
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
    if d.castStages ~= nil then
        if type(d.castStages) ~= "table" then
            return false, "invalid cast stages"
        end
        local castIds = {}
        for _, stage in ipairs(d.castStages) do
            if type(stage) ~= "table"
                or type(stage.spellId) ~= "number"
                or stage.spellId <= 0
                or stage.spellId ~= math.floor(stage.spellId)
                or not IsId(stage.sourceThreshold)
                or castIds[stage.spellId] then
                return false, "invalid cast stage"
            end
            local foundSource = false
            for _, threshold in ipairs(d.thresholds or {}) do
                if threshold.id == stage.sourceThreshold then
                    foundSource = true
                    break
                end
            end
            if not foundSource or not CheckEffect({
                id = stage.id, type = "timer_stage",
                label = stage.label, minDelay = stage.minDelay,
                maxDelay = stage.maxDelay, provenance = stage.provenance,
                icon = stage.icon, group = stage.group }, false) then
                return false, "invalid cast stage"
            end
            castIds[stage.spellId] = true
        end
    end
    if d.initialStages ~= nil then
        if type(d.initialStages) ~= "table" then
            return false, "invalid initial stages"
        end
        local initialIds = {}
        for _, stage in ipairs(d.initialStages) do
            if type(stage) ~= "table" then
                return false, "invalid initial stage"
            end
            if not CheckEffect({
                id = stage.id, type = "timer_stage", label = stage.label,
                minDelay = stage.minDelay, maxDelay = stage.maxDelay,
                provenance = stage.provenance, icon = stage.icon,
                group = stage.group }, false)
                or initialIds[stage.id] then
                return false, "invalid initial stage"
            end
            initialIds[stage.id] = true
        end
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


-- RAIDMODULE -> ENCOUNTERMODULE -> SUBMODULE. These declarations share the
-- existing engine/event frame/timers/actions; no second scheduler or scanner.
local function CheckModuleWaker(w, detect)
    if w == nil then
        local result = { detect.boss }
        for _, alias in ipairs(detect.aliases or {}) do
            table.insert(result, alias)
        end
        return result
    end
    if type(w) == "string" and w ~= "" then return { w } end
    if type(w) ~= "table" then return nil end
    local result, seen = {}, {}
    if w.name then
        if type(w.name) ~= "string" or w.name == "" then return nil end
        table.insert(result, w.name)
        seen[w.name] = true
        if w.aliases ~= nil and type(w.aliases) ~= "table" then return nil end
        for _, name in ipairs(w.aliases or {}) do
            if type(name) ~= "string" or name == "" or seen[name] then return nil end
            table.insert(result, name)
            seen[name] = true
        end
    else
        for _, name in ipairs(w) do
            if type(name) ~= "string" or name == "" or seen[name] then return nil end
            table.insert(result, name)
            seen[name] = true
        end
    end
    if table.getn(result) == 0 then return nil end
    return result
end

local function ValidateModuleSpec(id, def)
    local wakers = CheckModuleWaker(def.moduleWaker, def.detect)
    local seen, trackers = {}, {}
    if not wakers then return nil, "invalid moduleWaker" end
    local spec = { id = id, requiredZone = def.requiredZone or def.detect.zone,
        moduleWaker = wakers, passiveModules = {}, combatModules = {} }
    if type(spec.requiredZone) ~= "string" or spec.requiredZone == ""
        or spec.requiredZone ~= def.detect.zone then
        return nil, "required zone mismatch"
    end
    for _, group in ipairs({ "passiveModules", "combatModules" }) do
        if def[group] ~= nil and type(def[group]) ~= "table" then
            return nil, "invalid " .. group
        end
        for _, sub in ipairs(def[group] or {}) do
            if type(sub) ~= "table" or not IsId(sub.id) or seen[sub.id]
                or (sub.retainUntilResolved ~= nil
                    and type(sub.retainUntilResolved) ~= "boolean")
                or (group == "passiveModules" and sub.retainUntilResolved) then
                return nil, "invalid submodule"
            end
            seen[sub.id] = true
            local part = { id = sub.id,
                retainUntilResolved = sub.retainUntilResolved == true,
                tracker = sub.tracker }
            if sub.tracker then
                local t = sub.tracker
                if group ~= "combatModules" or type(t) ~= "table"
                    or not IsId(t.id) or trackers[t.id]
                    or (t.kind ~= "aura" and t.kind ~= "hp"
                        and t.kind ~= "action")
                    or type(t.keyPrefix) ~= "string" or t.keyPrefix == ""
                    or (t.actionKeyPrefix ~= nil
                        and (type(t.actionKeyPrefix) ~= "string"
                            or t.actionKeyPrefix == "")) then
                    return nil, "invalid submodule tracker"
                end
                trackers[t.id] = true
            end
            if part.retainUntilResolved and not part.tracker then
                return nil, "retained submodule requires tracker"
            end
            table.insert(spec[group], part)
        end
    end
    -- Existing declaration consumers stay with this engine. A submodule
    -- annotation routes a feature through its actual active lifecycle.
    for _, group in ipairs({ "mechanics", "triggers", "abilities",
        "abilityGroups", "counters", "hpUnits", "thresholds" }) do
        for _, feature in ipairs(def[group] or {}) do
            if feature.submodule ~= nil and not seen[feature.submodule] then
                return nil, "unknown submodule for " .. group
            end
        end
    end
    local sleeper = def.moduleSleeper
    if sleeper == nil and def.detect.endOnBossDeath ~= false then
        sleeper = { npcdead = { name = def.detect.boss, count = 1 } }
    end
    if sleeper ~= nil then
        if type(sleeper) ~= "table" then return nil, "invalid moduleSleeper" end
        local conditions = {}
        if sleeper.npcdead ~= nil then
            local deaths = sleeper.npcdead
            if type(deaths) ~= "table" then return nil, "invalid npcdead" end
            if deaths.name then deaths = { deaths } end
            if table.getn(deaths) == 0 then return nil, "invalid npcdead" end
            conditions.npcdead = {}
            for _, death in ipairs(deaths) do
                if type(death) ~= "table" or type(death.name) ~= "string"
                    or death.name == "" or type(death.count) ~= "number"
                    or death.count < 1 or death.count ~= math.floor(death.count)
                    or conditions.npcdead[death.name] then
                    return nil, "invalid npcdead"
                end
                conditions.npcdead[death.name] = death.count
            end
        end
        if sleeper.trackerEmpty ~= nil then
            local ids = sleeper.trackerEmpty
            if type(ids) == "string" then ids = { ids } end
            if type(ids) ~= "table" or table.getn(ids) == 0 then
                return nil, "invalid trackerEmpty"
            end
            conditions.trackerEmpty = {}
            for _, trackerId in ipairs(ids) do
                if not trackers[trackerId] then return nil, "unknown trackerEmpty" end
                table.insert(conditions.trackerEmpty, trackerId)
            end
        end
        if not conditions.npcdead and not conditions.trackerEmpty then
            return nil, "empty moduleSleeper"
        end
        spec.moduleSleeper = conditions
    end
    return spec
end

function mechanics.GetRequiredZones()
    local result = {}
    for zone in pairs(moduleLifecycle.raids) do table.insert(result, zone) end
    table.sort(result)
    return result
end

function mechanics.EnterRaidZone(zone)
    if not zone or not moduleLifecycle.raids[zone] then
        moduleLifecycle.current = nil
        return false
    end
    moduleLifecycle.current = moduleLifecycle.raids[zone]
    return true
end

function mechanics.GetRaidModuleState()
    local raid = moduleLifecycle.current
    if not raid then return nil end
    return { requiredZone = raid.requiredZone, active = true }
end

function mechanics.IsSubmoduleActive(id, expectedGeneration)
    if not active or not active.moduleState
        or (expectedGeneration and expectedGeneration ~= active.generation) then
        return false
    end
    local state = active.moduleState
    local sub = state.passiveModules[id] or state.combatModules[id]
    return sub and sub.active == true or false
end

function mechanics.GetEncounterModuleState()
    if not active or not active.moduleState then return nil end
    local state, result = active.moduleState, {
        id = active.id, requiredZone = active.moduleState.spec.requiredZone,
        awake = true, inCombat = active.engaged == true,
        attempt = active.moduleState.attempt, deaths = {},
        passiveModules = {}, combatModules = {},
    }
    for name, count in pairs(state.deaths) do result.deaths[name] = count end
    for id, sub in pairs(state.passiveModules) do
        result.passiveModules[id] = sub.active == true
    end
    for id, sub in pairs(state.combatModules) do
        result.combatModules[id] = {
            active = sub.active == true, retained = sub.retained == true }
    end
    return result
end

-- All npcdead counts AND every trackerEmpty condition must be satisfied.
function mechanics.CheckModuleSleeper(expectedGeneration)
    local session = active
    if not session or not session.moduleState
        or (expectedGeneration and session.generation ~= expectedGeneration) then
        return false
    end
    local sleeper = session.moduleState.spec.moduleSleeper
    if not sleeper then return false end
    for name, required in pairs(sleeper.npcdead or {}) do
        if (session.moduleState.deaths[name] or 0) < required then return false end
    end
    for _, tracker in ipairs(sleeper.trackerEmpty or {}) do
        if moduleLifecycle.TrackerCount(session, tracker) > 0 then return false end
    end
    return mechanics.StopEncounter("moduleSleeper resolved", session.generation)
end

-- Native corpse tokens without unique identity may satisfy one death only;
-- multi-NPC packs count separately observed death messages until Chunk 6 adds
-- individual marker/last-known-health attribution.
function mechanics.ObserveModuleNPCDeath(zone, name, source)
    local session = active
    if not session or not session.moduleState
        or session.moduleState.spec.requiredZone ~= zone then return false end
    local state, sleeper = session.moduleState, session.moduleState.spec.moduleSleeper
    local needed = sleeper and sleeper.npcdead and sleeper.npcdead[name]
    if not needed then return false end
    local old = state.deaths[name] or 0
    if old >= needed then return true end
    if needed > 1 and source ~= "message" then return false end
    state.deaths[name] = old + 1
    if mechanics.CheckModuleSleeper(session.generation) then return true end
    local allDead = true
    for mob, count in pairs(sleeper.npcdead or {}) do
        if (state.deaths[mob] or 0) < count then allDead = false end
    end
    if allDead then
        BeginPostBossCleanup(true)
        mechanics.CheckModuleSleeper(session.generation)
    end
    return true
end

function mechanics.DisengageEncounter(reason, expectedGeneration)
    local session = active
    if not session or not session.engaged or session.postBossCleanup
        or (expectedGeneration and session.generation ~= expectedGeneration) then
        return false
    end
    -- A new pull reuses the loaded encounter, but never the old attempt.
    BeginPostBossCleanup(false)
    session.engaged = false
    local state = session.moduleState
    if state then
        state.deaths = {}
        for _, sub in pairs(state.combatModules) do
            sub.retained = sub.spec.retainUntilResolved
                and sub.spec.tracker
                and moduleLifecycle.TrackerCount(session, sub.spec.tracker.id) > 0
                or false
            sub.active = sub.retained
        end
    end
    session.abilities, session.abilityOrder = nil, nil
    session.casterCasts, session.castSerial = nil, nil
    session.firstSlotHints, session.counters = nil, nil
    session.stageTimers, session.observedAbilities = nil, nil
    session.defenderLastHits, session.toxinFirst = nil, nil
    session.skeramMarked, session.ouroSeen, session.ouroPhase = nil, nil, nil
    session.cthunPhase, session.viscPhase = nil, nil
    session.prepared = false
    return true
end

-- The deliberate target observer and (later) shared scanner call this entry.
function mechanics.WakeEncounter(zone, name, inCombat)
    local raid = moduleLifecycle.current
    if not raid or raid.requiredZone ~= zone then return false end
    local id = raid.wakers[name]
    if not id or not raid.encounterModules[id] then return false end
    local boss = raid.encounterModules[id].detectBoss
    local ok, why = mechanics.ObserveBoss(zone, boss, "alive")
    if not ok then return false, why end
    if inCombat then
        local state = mechanics.GetEncounterState()
        if state and state.id == id then
            return mechanics.MarkEncounterEngaged(state.generation)
        end
    end
    return true
end

-- Pure Lua-table catalogue, e.g. { bwl = { razorgore = { ... } } }.
-- Registration is all-or-nothing; the TOC loads encounters.lua.
function mechanics.RegisterDeclarativeEncounters(catalogue)
    local pending, raid, bosses, name, def, id, ok, why, count, spec
    local zones, zonePrep = {}, {}
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
            spec, why = ValidateModuleSpec(id, def)
            if not spec then return false, id .. ": " .. why end
            local zone = zones[spec.requiredZone]
            if not zone then
                zone = { requiredZone = spec.requiredZone,
                    encounterModules = {}, wakers = {} }
                zones[spec.requiredZone] = zone
            end
            spec.detectBoss = def.detect.boss
            for _, waker in ipairs(spec.moduleWaker) do
                if zone.wakers[waker] and zone.wakers[waker] ~= id then
                    return false, "duplicate moduleWaker: " .. waker
                end
                zone.wakers[waker] = id
            end
            zone.encounterModules[id] = spec
            pending[id] = { events = {}, declarative = def, moduleSpec = spec }
            count = count + 1
        end
    end
    if count == 0 then return false, "empty catalogue" end
    for id, def in pairs(pending) do encounters[id] = def end
    for zone, raidState in pairs(zones) do
        moduleLifecycle.raids[zone] = raidState
    end
    return true, count
end

-- Source registry for the pre-existing SCB event frame. No extra frame
-- listens to combat text: the owner asks for precisely the events in BWL.
function mechanics.CanonicalBoss(zone, boss)
    local raid = moduleLifecycle.raids[zone]
    local id = raid and raid.wakers[boss]
    if id and raid.encounterModules[id] then
        return raid.encounterModules[id].detectBoss
    end
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
    local raid = moduleLifecycle.raids[zone]
    if raid then
        for waker in pairs(raid.wakers) do table.insert(result, waker) end
        table.sort(result)
        return result
    end
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
    if zone == "Ahn'Qiraj" then
        for _, entry in pairs(encounters) do
            local d = entry.declarative
            if d and d.detect.zone == zone and d.castStages
                and table.getn(d.castStages) > 0
                and not seen.UNIT_CASTEVENT then
                seen.UNIT_CASTEVENT = true
                table.insert(result, "UNIT_CASTEVENT")
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
                if w.when == "zone"
                    and (not w.submodule or mechanics.IsSubmoduleActive(w.submodule)) then
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
                return mechanics.ObserveBoss(zone, boss, "dead", "message")
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
function mechanics.ObserveBoss(zone, boss, state, deathSource)
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
                if active.moduleState then
                    mechanics.ObserveModuleNPCDeath(zone, boss, deathSource or "unit")
                    return true
                end
                if BeginPostBossCleanup and BeginPostBossCleanup(true) then return true end
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
        if (w.when == "present" or w.when == "zone")
            and (not w.submodule or mechanics.IsSubmoduleActive(w.submodule)) then
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
    if effect.type == "viscidus_phase" then
        if active.id ~= "aq40.viscidus" then return end
        if effect.phase == "melee" and active.viscPhase ~= "melee" then
            active.viscPhase = "melee"
            mechanics.ResetCounter("meleehits", active.generation)
        elseif effect.phase == "frost" and active.viscPhase ~= "frost" then
            active.viscPhase = "frost"
            mechanics.ResetCounter("frosthits", active.generation)
        end
    elseif effect.type == "cthun_glare" then
        if active.id ~= "aq40.cthun" or active.cthunPhase == 2 then return end
        local currentGeneration = active.generation
        mechanics.SetTimerStage("glare_cast", {
            label = "Dark Glare casting", minDelay = 3,
            provenance = "predicted",
        }, currentGeneration)
        mechanics.ScheduleTimer("cthun-glare-active", 3, function()
            if not active or active.generation ~= currentGeneration
                or active.cthunPhase == 2 then return end
            mechanics.SetTimerStage("glare_active", {
                label = "Dark Glare active", minDelay = 39,
                provenance = "predicted",
            }, currentGeneration)
        end, "predicted")
    elseif effect.type == "viscidus_toxin" then
        mechanics.ObserveViscidusToxin(captured, active.generation)
    elseif effect.type == "cthun_phase2" then
        if active.id ~= "aq40.cthun" or active.cthunPhase == 2 then return end
        active.cthunPhase = 2
        mechanics.CancelTimer("cthun-glare-active")
        mechanics.HidePresentation("timer", "stage:glare_cast")
        mechanics.HidePresentation("timer", "stage:glare_active")
        -- Eye-death is a native event; do not keep the phase-one Dark Glare.
        for _, slot in ipairs(presentation.timer.pool) do
            if slot.used and slot.key == "ability:darkglare" then
                mechanics.HidePresentation("timer", slot.key)
            end
        end
        mechanics.SetTimerStage("giant_claw_next", {
            label = "First Giant Claw (reference)", minDelay = 12,
            provenance = "predicted",
        }, active.generation)
        mechanics.SetTimerStage("small_eye_next", {
            label = "First Small Eyes (reference)", minDelay = 42,
            provenance = "predicted",
        }, active.generation)
    elseif effect.type == "cthun_weakened" then
        if active.id ~= "aq40.cthun" or active.cthunPhase ~= 2 then return end
        local currentGeneration = active.generation
        -- BigWigs schedules these relative to WeakenedOver (45s later).
        mechanics.ScheduleTimer("cthun-after-weakened", 45, function()
            if not active or active.generation ~= currentGeneration
                or active.cthunPhase ~= 2 then return end
            mechanics.SetTimerStage("giant_claw_next", {
                label = "Giant Claw after Weakened (reference)",
                minDelay = 8, provenance = "predicted",
            }, currentGeneration)
            mechanics.SetTimerStage("small_eye_next", {
                label = "Small Eyes after Weakened (reference)",
                minDelay = 38, provenance = "predicted",
            }, currentGeneration)
        end, "predicted")
    elseif effect.type == "ability_lockout" then
        mechanics.ObserveAbilityLockout(effect.ability,
            effect.duration, active.generation)
    elseif effect.type == "dev_interval" then
        mechanics.RecordDefenderHit(effect.ability, active.generation)
        mechanics.ObserveDefenderElapsed(effect.ability, active.generation)
    elseif effect.type == "counter_hit" then
        -- BigWigs observes separate frost/frozen melee windows; native
        -- message presence alone must not mix the two Viscidus counters.
        local permitted = true
        if active.id == "aq40.viscidus" then
            if effect.id == "frosthits" then
                permitted = active.viscPhase ~= "melee"
            elseif effect.id == "meleehits" then
                permitted = active.viscPhase == "melee"
            end
        end
        if permitted then mechanics.ObserveCounterHit(effect.id,
            details and details.observationId, active.generation) end
    elseif effect.type == "counter_reset" then
        mechanics.ResetCounter(effect.id, active.generation)
    elseif effect.type == "timer_stage" then
        if active.id == "aq40.ouro" and effect.id == "ourocycle" then
            active.ouroPhase = "emerged"
            active.ouroSeen = false
        end
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
                effect.label, name, nil, nil, nil, effect.icon)
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
    if not session or active ~= session
        or (not session.engaged and not session.retainingEffects) then return 0 end
    if session.engaged and not session.abilities and not session.postBossCleanup then
        mechanics.InitializeAbilities(session.generation)
    end
    count = 0
    local function Deliver(spec, isGroup)
        local observation, observedName
        if session.engaged and not session.postBossCleanup then
            matched, captured = MatchAbilityObservation(spec.startRule, eventName, message, details)
            if matched then
                observedName = isGroup and captured or nil
                if mechanics.ObserveAbilityStart(spec.id, observedName, session.generation) then
                    count = count + 1
                end
            end
            matched, captured = MatchAbilityObservation(spec.finishRule, eventName, message, details)
            if matched and mechanics.ObserveAbilityFinish(spec.id,
                isGroup and captured or nil, session.generation,
                details and details.observationId) then
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
        state = session.abilities and session.abilities[spec.id]
        for j, aura in ipairs(spec.auras or {}) do
            matched, captured = MatchAbilityObservation(aura.gain, eventName, message, details)
            if matched and session.engaged and not session.postBossCleanup then
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
            if matched and ((session.engaged and not session.postBossCleanup)
                or (session.retainingEffects and aura.retainAfterBossDeath)) then
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
        if not spec.submodule or mechanics.IsSubmoduleActive(spec.submodule) then
            Deliver(spec, false)
        end
    end
    for i, spec in ipairs(session.definition.declarative.abilityGroups or {}) do
        if active ~= session then break end
        if not spec.submodule or mechanics.IsSubmoduleActive(spec.submodule) then
            Deliver(spec, true)
        end
    end
    if session.retainingEffects and active == session then FinishPostBossCleanup() end
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
        local eventMatches = (not rule.submodule
            or mechanics.IsSubmoduleActive(rule.submodule))
            and rule.event == eventName
        if rule.events then
            eventMatches = false
            if not rule.submodule or mechanics.IsSubmoduleActive(rule.submodule) then
                for j = 1, table.getn(rule.events) do
                    if rule.events[j] == eventName then eventMatches = true; break end
                end
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

-- Boss Mods event/observation/update ownership (Chunk 1 extraction).
local bossModsFrame = CreateFrame("Frame", "SoloCraftBotsBossModsEventFrame", UIParent)
-- Boss Mods options are initialized here, not in the general SCB initializer.
local function SCB_BossModsEnsureOptions()
    if not SoloCraftBotsDB then return end
    SoloCraftBotsDB.options = SoloCraftBotsDB.options or {}
    local options = SoloCraftBotsDB.options
    if options.bossModsShowPlayerName == nil then options.bossModsShowPlayerName = true end
    if options.bossModsShowAuraName == nil then options.bossModsShowAuraName = true end
    if options.bossModsTimersExpandUp == nil then options.bossModsTimersExpandUp = false end
    if options.bossModsTrackerExpandUp == nil then options.bossModsTrackerExpandUp = false end
end

-- Boss Mods owns one dedicated event/update frame. Shared bot commands,
-- roster services and general UI event handling remain unchanged.
local bossModsZone = nil
local bossModsZoneActive = false
local bossModsElapsed = 0
local bossModsVisualElapsed = 0
local bossModsPollElapsed = 0
local bossModsEvents = {}
local bossModsGroupCombatGeneration = nil
local bossModsCalmSamples = 0

-- Chunk 3: one demand-driven observer, serviced by the existing Boss Mods
-- OnUpdate. The older broad 0.4-second path deliberately remains until Chunk 5.
-- A request belongs to the active zone, and optionally to one encounter attempt.
local raidTargetScanner = {
    requests = {}, index = 0, elapsed = 0, sideElapsed = 0,
    inCombat = false, calm = 0,
}

-- Request format:
-- { observations={identity=true, marker=true, hp=true, buffs=true},
--   duration="fixed", seconds=5, names={"NPC"}, encounter="raid.boss",
--   submodule="tracker", onObservation=function(snapshot) ... end,
--   dispatchDeclaredHP=true }
-- duration="combat" instead expires on group disengagement / attempt end.
-- A callback receives a positive, immediately usable token snapshot. It must
-- not retain a token as a stable NPC identity or mutate the shared snapshot.
function mechanics.RequestRaidTargetObservations(key, options)
    if type(key) ~= "string" or key == "" or type(options) ~= "table"
        or not bossModsZoneActive or not moduleLifecycle.current then
        return false, "scanner unavailable"
    end
    local flags, count = {}, 0
    if type(options.observations) ~= "table" then
        return false, "missing observations"
    end
    for kind, enabled in pairs(options.observations) do
        if kind ~= "identity" and kind ~= "marker"
            and kind ~= "hp" and kind ~= "buffs" then
            return false, "invalid observation"
        end
        if type(enabled) ~= "boolean" then
            return false, "invalid observation flag"
        end
        if enabled then flags[kind] = true; count = count + 1 end
    end
    if count == 0 then return false, "empty observations" end
    if options.duration ~= "fixed" and options.duration ~= "combat" then
        return false, "invalid scan duration"
    end
    if options.duration == "fixed"
        and (type(options.seconds) ~= "number" or options.seconds <= 0
            or options.seconds ~= options.seconds or options.seconds == math.huge) then
        return false, "invalid scan window"
    end
    if options.duration == "combat" and not raidTargetScanner.inCombat
        and not (active and active.engaged) then
        return false, "combat not active"
    end
    if options.onObservation ~= nil and type(options.onObservation) ~= "function" then
        return false, "invalid scan consumer"
    end
    if options.dispatchDeclaredHP ~= nil
        and type(options.dispatchDeclaredHP) ~= "boolean" then
        return false, "invalid hp dispatch"
    end
    if options.dispatchDeclaredHP and not flags.hp then
        return false, "hp observation required"
    end
    local names = nil
    if options.names ~= nil then
        if type(options.names) ~= "table" or table.getn(options.names) == 0 then
            return false, "invalid scan names"
        end
        names = {}
        for _, name in ipairs(options.names) do
            if type(name) ~= "string" or name == "" then
                return false, "invalid scan name"
            end
            names[name] = true
        end
    end
    local owner, attempt, token
    if options.encounter ~= nil then
        if type(options.encounter) ~= "string" or not active
            or active.id ~= options.encounter then
            return false, "encounter not loaded"
        end
        if options.submodule ~= nil
            and (type(options.submodule) ~= "string"
                or not mechanics.IsSubmoduleActive(options.submodule)) then
            return false, "submodule inactive"
        end
        owner = active.generation
        attempt = active.moduleState and active.moduleState.attempt or 0
        token = options.encounter
    elseif options.submodule ~= nil then
        return false, "submodule needs encounter"
    end
    raidTargetScanner.requests[key] = {
        zone = bossModsZone, observations = flags, names = names,
        duration = options.duration,
        expiresAt = options.duration == "fixed" and (Now() + options.seconds) or nil,
        encounter = token, generation = owner, attempt = attempt,
        submodule = options.submodule, onObservation = options.onObservation,
        dispatchDeclaredHP = options.dispatchDeclaredHP == true,
    }
    return true
end

function mechanics.CancelRaidTargetObservations(key)
    if raidTargetScanner.requests[key] then
        raidTargetScanner.requests[key] = nil
        return true
    end
    return false
end

function mechanics.ClearRaidTargetObservations()
    raidTargetScanner.requests = {}
    raidTargetScanner.index = 0
    raidTargetScanner.elapsed = 0
    raidTargetScanner.sideElapsed = 0
    raidTargetScanner.inCombat = false
    raidTargetScanner.calm = 0
end

function mechanics.GetRaidTargetScannerState()
    local requests = {}
    for key in pairs(raidTargetScanner.requests) do
        table.insert(requests, key)
    end
    table.sort(requests)
    return { running = table.getn(requests) > 0,
        inCombat = raidTargetScanner.inCombat, requests = requests }
end

-- Expire individual requests without affecting other subscribers. A combat
-- request is bound to its encounter attempt, not simply a timer since wake.
local function SCB_BossModsPruneScanRequests()
    local now = Now()
    for key, request in pairs(raidTargetScanner.requests) do
        local stale = request.zone ~= bossModsZone
            or (request.expiresAt and now >= request.expiresAt)
            or (request.duration == "combat" and not raidTargetScanner.inCombat
                and not (active and active.engaged))
        if request.encounter then
            stale = stale or not active or active.id ~= request.encounter
                or active.generation ~= request.generation
                or (active.moduleState and
                    active.moduleState.attempt ~= request.attempt)
                or (request.submodule
                    and not mechanics.IsSubmoduleActive(request.submodule,
                        request.generation))
            if request.duration == "combat" and not active.engaged then
                stale = true
            end
        end
        if stale then raidTargetScanner.requests[key] = nil end
    end
end

-- One token is inspected once per visit regardless of consumer count.
-- Build each requested field once, then fan out the same observation.
local function SCB_BossModsVisitScanToken(unit)
    if not UnitExists or not UnitName or not UnitExists(unit) then return end
    local name = UnitName(unit)
    if type(name) ~= "string" or name == "" then return end
    local raid = moduleLifecycle.current
    if raid and raid.wakers[name] then
        mechanics.WakeEncounter(bossModsZone, name,
            raidTargetScanner.inCombat or
                (UnitAffectingCombat and UnitAffectingCombat(unit)) and true or false)
    end
    local marker, hp, buffs, hpDispatch = false, false, false, false
    local selected = {}
    for key, request in pairs(raidTargetScanner.requests) do
        if not request.names or request.names[name] then
            table.insert(selected, { key = key, request = request })
            if request.observations.marker then marker = true end
            if request.observations.hp then hp = true end
            if request.observations.buffs then buffs = true end
            if request.dispatchDeclaredHP then hpDispatch = true end
        end
    end
    if table.getn(selected) == 0 then return end
    local snapshot = { unit = unit, name = name,
        dead = (UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit))
            or (UnitIsDead and UnitIsDead(unit)) or false,
        combat = UnitAffectingCombat and UnitAffectingCombat(unit) and true or false,
    }
    if marker and GetRaidTargetIndex then
        snapshot.marker = GetRaidTargetIndex(unit)
    end
    if hp and UnitHealth and UnitHealthMax then
        snapshot.hp = UnitHealth(unit)
        snapshot.hpMax = UnitHealthMax(unit)
    end
    -- Native 1.12 UnitBuff exposes buff textures. Enhanced clients may expose
    -- more, but no spell-name/ID inference is fabricated from a texture.
    if buffs and UnitBuff then
        snapshot.buffs = {}
        for i = 1, 32 do
            local texture = UnitBuff(unit, i)
            if not texture then break end
            table.insert(snapshot.buffs, texture)
        end
    end
    if hpDispatch and active and active.engaged then
        mechanics.ObserveDeclaredUnits({ unit }, active.generation)
    end
    for _, subscriber in ipairs(selected) do
        if raidTargetScanner.requests[subscriber.key] == subscriber.request
            and subscriber.request.onObservation then
            subscriber.request.onObservation(snapshot)
        end
    end
end

function mechanics.TickRaidTargetScanner(elapsed)
    SCB_BossModsPruneScanRequests()
    if not bossModsZoneActive or not next(raidTargetScanner.requests) then
        raidTargetScanner.elapsed = 0
        raidTargetScanner.sideElapsed = 0
        return
    end
    -- Approximately one raid-member target every 25ms, subject to client
    -- frame rate. No second frame, ticker or per-request unit traversal.
    raidTargetScanner.elapsed = raidTargetScanner.elapsed + elapsed
    local n = GetNumRaidMembers and GetNumRaidMembers() or 0
    local party = 0
    if n == 0 then
        party = GetNumPartyMembers and GetNumPartyMembers() or 0
    end
    while raidTargetScanner.elapsed >= 0.025 do
        raidTargetScanner.elapsed = raidTargetScanner.elapsed - 0.025
        if n > 0 or party > 0 then
            local total = n > 0 and n or party
            raidTargetScanner.index = math.mod(raidTargetScanner.index, total) + 1
            local base = (n > 0 and "raid" or "party")
                .. raidTargetScanner.index
            SCB_BossModsVisitScanToken(base .. "target")
            SCB_BossModsVisitScanToken(base .. "targettarget")
        end
    end
    -- Preserve the non-raid target/mouseover/target-of-target paths for new
    -- consumers too. The legacy poll retains its full set until Chunk 5.
    raidTargetScanner.sideElapsed = raidTargetScanner.sideElapsed + elapsed
    if raidTargetScanner.sideElapsed >= 0.20 then
        raidTargetScanner.sideElapsed = math.mod(raidTargetScanner.sideElapsed, 0.20)
        SCB_BossModsVisitScanToken("target")
        SCB_BossModsVisitScanToken("mouseover")
        SCB_BossModsVisitScanToken("targettarget")
    end
end

-- Combat onset must be recognised even when the player never targets the
-- boss. Group combat edges come from the existing group observation path;
-- PLAYER_REGEN_DISABLED can start the same discovery immediately.
local function SCB_BossModsTrackCombatState(inCombat)
    if inCombat == true then
        raidTargetScanner.calm = 0
        if not raidTargetScanner.inCombat and bossModsZoneActive then
            raidTargetScanner.inCombat = true
            mechanics.RequestRaidTargetObservations("__combat_discovery", {
                observations = { identity = true },
                duration = "fixed", seconds = 5,
            })
        end
    elseif inCombat == false then
        raidTargetScanner.calm = raidTargetScanner.calm + 1
        if raidTargetScanner.calm >= 2 then
            raidTargetScanner.inCombat = false
            for key, request in pairs(raidTargetScanner.requests) do
                if request.duration == "combat" then
                    raidTargetScanner.requests[key] = nil
                end
            end
        end
    end
end

local function SCB_BossModsInitialize()
    local engine = SCB.mechanics
    local ok, why, eventNames, i, zoneName
    if not engine or not SCB.bossModDefinitions or SCB.bossModsInitialised then return end
    ok, why = engine.RegisterDeclarativeEncounters(SCB.bossModDefinitions)
    if not ok then
        -- Registration is all-or-nothing. Fail closed; never enable partial
        -- encounters or interfere with unrelated SCB features.
        SCB.bossModsRegistrationError = why
        return
    end
    SCB.bossModsInitialised = true
    for _, zoneName in ipairs(engine.GetRequiredZones()) do
        eventNames = engine.GetRequiredEvents(zoneName)
        bossModsEvents[zoneName] = {}
        for i = 1, table.getn(eventNames) do
            bossModsEvents[zoneName][eventNames[i]] = true
        end
    end
end

local function SCB_BossModsRefreshZone()
    local engine, zone, enabled, eventName
    engine = SCB.mechanics
    if not SCB.bossModsInitialised or not engine then return end
    zone = GetRealZoneText and GetRealZoneText() or ""
    enabled = engine.EnterRaidZone(zone)
    if (enabled and bossModsZone == zone)
        or (not enabled and not bossModsZone) then return end
    if bossModsZone then
        for eventName in pairs(bossModsEvents[bossModsZone] or {}) do
            if eventName == "UNIT_CASTEVENT" then
                -- Vanilla clients may not recognise this optional SuperWoW event.
                pcall(bossModsFrame.UnregisterEvent, bossModsFrame, eventName)
            else
                bossModsFrame:UnregisterEvent(eventName)
            end
        end
        engine.Reset("zone exit")
    end
    engine.ClearRaidTargetObservations()
    bossModsZone = enabled and zone or nil
    bossModsZoneActive = enabled
    if enabled then
        for eventName in pairs(bossModsEvents[zone] or {}) do
            if eventName == "UNIT_CASTEVENT" then
                -- Optional extension: absence must never break ordinary SCB.
                pcall(bossModsFrame.RegisterEvent, bossModsFrame, eventName)
            else
                bossModsFrame:RegisterEvent(eventName)
            end
        end
        -- Register observations only; entering the zone does not prove
        -- a boss is alive or authorize an encounter action.
    end
    bossModsPollElapsed = 0
    bossModsElapsed = 0
    bossModsVisualElapsed = 0
    bossModsGroupCombatGeneration = nil
    bossModsCalmSamples = 0
end

-- Immediate deliberate targeting uses existing unit evidence, not a scan.
local function SCB_BossModsPlayerTargetChanged()
    if not bossModsZoneActive or not UnitExists or not UnitName
        or not UnitExists("target") then return end
    local name = UnitName("target")
    if not name then return end
    SCB.mechanics.WakeEncounter(bossModsZone, name,
        UnitAffectingCombat and UnitAffectingCombat("target") and true or false)
end

-- Read the current player's *group* combat states, not only the local
-- PLAYER_REGEN_ENABLED event (which says nothing about another raid member).
-- No roster cache: use native units within the existing 0.4-second owner scan.
local function SCB_BossModsGroupCombat()
    if not UnitExists or not UnitAffectingCombat then return nil end
    local tokens = { "player" }
    local i, token, count = 0, nil, 0
    for i = 1, 40 do table.insert(tokens, "raid" .. i) end
    for i = 1, 4 do table.insert(tokens, "party" .. i) end
    for _, token in ipairs(tokens) do
        if UnitExists(token) then
            count = count + 1
            if UnitAffectingCombat(token) then return true end
        end
    end
    if count == 0 then return nil end
    return false
end

-- Native 1.12 cannot enumerate arbitrary world NPCs. Supplement friendly
-- raid targets with mouseover and target-of-target, without changing the
-- player's target. A missing observation is never a death confirmation.
local function SCB_BossModsObserveTargets()
    local engine, names, lookup, state, selected, observed, dead
    local tokens, name, token, i, groupCombat
    if not bossModsZoneActive or not SCB.mechanics then return end
    groupCombat = SCB_BossModsGroupCombat()
    SCB_BossModsTrackCombatState(groupCombat)
    engine = SCB.mechanics
    names = engine.GetDetectableBosses(bossModsZone)
    lookup = {}
    for i = 1, table.getn(names) do lookup[names[i]] = true end
    tokens = { "mouseover", "target", "targettarget" }
    for i = 1, 40 do
        table.insert(tokens, "raid" .. i .. "target")
        table.insert(tokens, "raid" .. i .. "targettarget")
    end
    for i = 1, 4 do
        table.insert(tokens, "party" .. i .. "target")
        table.insert(tokens, "party" .. i .. "targettarget")
    end
    observed = {}
    for i = 1, table.getn(tokens) do
        token = tokens[i]
        if UnitExists and UnitExists(token) and UnitName then
            name = UnitName(token)
            if lookup[name] then
                dead = (UnitIsDeadOrGhost and UnitIsDeadOrGhost(token))
                    or (UnitIsDead and UnitIsDead(token))
                selected = observed[name]
                -- A live observation takes priority over an earlier stale
                -- corpse token; accumulate combat when either sees it.
                if not selected or (selected.dead and not dead) then
                    observed[name] = { dead = dead and true or false,
                        combat = UnitAffectingCombat
                            and UnitAffectingCombat(token) and true or false }
                elseif not dead and not selected.dead and UnitAffectingCombat
                    and UnitAffectingCombat(token) then
                    selected.combat = true
                end
            end
        end
    end
    state = engine.GetEncounterState()
    if state and state.engaged and not state.postBossCleanup then
        engine.ObserveDeclaredUnits(tokens, state.generation)
    end
    -- Once the raid actually entered combat, require two consecutive complete
    -- group-out-of-combat scans before declaring a reset. Do not infer a wipe
    -- from missing targets, death of one player or another boss's presence.
    -- Positive boss-in-combat evidence also vetoes the reset.
    if state and state.engaged and not state.postBossCleanup then
        local bossObserved = observed[state.boss]
        if groupCombat then
            bossModsGroupCombatGeneration = state.generation
            bossModsCalmSamples = 0
        elseif groupCombat == false
            and bossModsGroupCombatGeneration == state.generation
            and not (bossObserved and bossObserved.combat) then
            bossModsCalmSamples = bossModsCalmSamples + 1
            if bossModsCalmSamples >= 2 then
                engine.DisengageEncounter("raid disengaged", state.generation)
                bossModsGroupCombatGeneration = nil
                bossModsCalmSamples = 0
                state = nil
            end
        else
            bossModsCalmSamples = 0
        end
    else
        bossModsCalmSamples = 0
    end
    if state and state.boss then
        -- Preserve the active encounter even when nobody targets its boss.
        -- Engaged sessions are protected against unrelated bosses being
        -- targeted through geometry or via combat logs.
        selected = observed[state.boss]
        if selected then
            if selected.dead then
                engine.ObserveBoss(bossModsZone, state.boss, "dead")
            else
                engine.ObserveBoss(bossModsZone, state.boss, "alive")
                if selected.combat then engine.MarkEncounterEngaged(state.generation) end
                return
            end
        else
            engine.ObserveBoss(bossModsZone, state.boss, "absent")
        end
    end
    for i = 1, table.getn(names) do
        name = names[i]
        selected = observed[name]
        if selected and not selected.dead then
            engine.ObserveBoss(bossModsZone, name, "alive")
            state = engine.GetEncounterState()
            if state and state.boss == engine.CanonicalBoss(bossModsZone, name) then
                if selected.combat then
                    engine.MarkEncounterEngaged(state.generation)
                end
                return
            end
        end
    end
end

local function SCB_BossModsOnCombatEvent(eventName, message, speaker,
    castType, spellId)
    local engine, state, observedBoss, isCombat
    if not bossModsZoneActive or not (bossModsEvents[bossModsZone]
        and bossModsEvents[bossModsZone][eventName]) then return end
    engine = SCB.mechanics
    if not engine then return end
    if eventName == "UNIT_CASTEVENT" then
        -- SuperWoW: arg1 casterGUID, arg2 targetGUID, arg3 cast type,
        -- arg4 spellID. Only matched observed caster GUIDs may change stages.
        local current = engine.GetEncounterState()
        if current and current.engaged then
            engine.ObserveDeclaredCastEvent(message, castType,
                spellId, current.generation)
        end
        return
    end
    if eventName == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
        engine.ObserveBossDeathMessage(bossModsZone, eventName, message)
        return
    end
    observedBoss, isCombat = engine.GetBossFromCombatEvidence(
        bossModsZone, eventName, message, speaker)
    state = engine.GetEncounterState()
    if observedBoss then
        -- No transition to a later boss while one is already engaged.
        if state and state.engaged and not state.postBossCleanup
            and state.boss ~= observedBoss then return end
        engine.ObserveBoss(bossModsZone, observedBoss, "alive")
        state = engine.GetEncounterState()
        if state and state.boss == observedBoss and isCombat then
            engine.MarkEncounterEngaged(state.generation)
        end
    end
    if not state then return end
    -- Unscoped aura messages are only consumed by the current encounter,
    -- never used to discover a boss or assert engagement.
    engine.DispatchEvent(eventName, message, nil, state.generation)
end

local function SCB_BossModsOnUpdate(elapsed)
    local engine = SCB.mechanics
    if not SCB.bossModsInitialised or not engine then return end
    bossModsPollElapsed = bossModsPollElapsed + elapsed
    if bossModsPollElapsed >= 0.4 then
        bossModsPollElapsed = 0
        SCB_BossModsRefreshZone()
        if bossModsZoneActive then SCB_BossModsObserveTargets() end
    end
    if not bossModsZoneActive then return end
    engine.TickRaidTargetScanner(elapsed)
    if not engine.GetEncounterState() then return end
    -- Existing SCB owner: 10 Hz state/timer tick and 30 Hz presentation tick.
    bossModsElapsed = bossModsElapsed + elapsed
    if bossModsElapsed >= 0.10 then
        bossModsElapsed = math.mod(bossModsElapsed, 0.10)
        local now = GetTime and GetTime() or 0
        engine.UpdateTimers(now)
        engine.UpdatePresentationState(now)
    end
    bossModsVisualElapsed = bossModsVisualElapsed + elapsed
    if bossModsVisualElapsed >= (1 / 30) then
        bossModsVisualElapsed = math.mod(bossModsVisualElapsed, 1 / 30)
        engine.UpdatePresentation(GetTime and GetTime() or 0)
    end
end

-- encounters.lua loads after this file; defer catalogue registration until
-- PLAYER_LOGIN, after all addon files and SavedVariables initialization.
bossModsFrame:RegisterEvent("ADDON_LOADED")
bossModsFrame:RegisterEvent("PLAYER_LOGIN")
bossModsFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
bossModsFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
bossModsFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
bossModsFrame:RegisterEvent("ZONE_CHANGED")
bossModsFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
bossModsFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
bossModsFrame:SetScript("OnEvent", function()
    if bossModsZoneActive and bossModsEvents[bossModsZone]
        and bossModsEvents[bossModsZone][event] then
        SCB_BossModsOnCombatEvent(event, arg1, arg2, arg3, arg4)
    end
    if event == "ADDON_LOADED" and arg1 == "SoloCraftBots" then
        SCB_BossModsEnsureOptions()
    elseif event == "PLAYER_LOGIN" then
        SCB_BossModsEnsureOptions()
        SCB_BossModsInitialize()
        SCB_BossModsRefreshZone()
    elseif event == "PLAYER_TARGET_CHANGED" then
        SCB_BossModsPlayerTargetChanged()
    elseif event == "PLAYER_REGEN_DISABLED" and bossModsZoneActive then
        SCB_BossModsTrackCombatState(true)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
        SCB_BossModsRefreshZone()
        SCB_BossModsPlayerTargetChanged()
    end
end)
bossModsFrame:SetScript("OnUpdate", function()
    SCB_BossModsOnUpdate(arg1 or 0)
end)
