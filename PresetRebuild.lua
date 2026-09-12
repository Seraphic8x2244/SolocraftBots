-- SoloCraft Bots - preset rebuild transition barrier.
-- Keeps the old-group teardown, party-to-raid conversion, and new preset
-- summon handoff deterministic.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

function SCB_PresetRebuildOnUpdate()
    local state = SCB.presetRebuildState
    local now = GetTime and GetTime() or 0
    local anchorName, botCount, ready, raidCount, partyCount
    local ok, errorText

    if not state then return end

    -- A completed rebuild creates the replacement queue during this updater,
    -- after Spawn has already captured the current queue for this OnUpdate.
    -- Release the new explicit operation on the following frame so Spawn sees
    -- the replacement queue as its normal frame-local queue from the start.
    if state.handoffQueued then
        SCB.scbExplicitPresetOperation = true
        SCB.presetRebuildState = nil
        if SCB_DebugLog then
            SCB_DebugLog("Spawn", "Preset rebuild released replacement queue on next frame")
        end
        return
    end

    if not state.active then return end

    anchorName = SCB_GetKickAllAnchorForFreshBuild and SCB_GetKickAllAnchorForFreshBuild() or nil
    botCount = SCB_CountGroupBots and SCB_CountGroupBots() or 0

    -- A named survivor is not enough: kicked bots can remain in the roster for
    -- a server tick. Do not hand off until the survivor is the ONLY bot left.
    ready = botCount == 0 or (anchorName ~= nil and botCount == 1)
    if not ready then
        state.readySeenAt = nil
        state.scbConvertRequestedAt = nil
        return
    end

    -- The removal-settle clock starts when the removed bots are actually gone.
    -- Conversion and safety parking do not add membership, so they can happen
    -- during this clock instead of creating extra dead time before the next add.
    if not state.readySeenAt then state.readySeenAt = now end

    -- For raid-sized presets rebuilt from an existing party, conversion belongs
    -- to the rebuild transition itself. Convert as soon as the survivor is the
    -- only bot, then park it in G8 as soon as Blizzard exposes the raid roster.
    if state.snapshot and (state.snapshot.size or 0) > 5 and anchorName and botCount == 1 then
        raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
        if raidCount == 0 then
            partyCount = (GetNumPartyMembers and GetNumPartyMembers()) or 0
            if partyCount > 0 and ConvertToRaid then
                if not state.scbConvertRequestedAt or (now - state.scbConvertRequestedAt) >= 1.0 then
                    ConvertToRaid()
                    state.scbConvertRequestedAt = now
                    if SCB_DebugLog then
                        SCB_DebugLog("Spawn", "Preset rebuild requested party-to-raid conversion with survivor " .. tostring(anchorName))
                    end
                end
            end
            return
        end

        if SCB.scb072TryParkSurvivorInGroupEight
            and not SCB.scb072TryParkSurvivorInGroupEight(anchorName) then
            return
        end
    end

    state.scbConvertRequestedAt = nil

    -- Any rebuild that removed bots must allow SoloCraft's instance accounting
    -- to settle before the next add. Non-add work above is intentionally allowed
    -- to overlap this timer; the safety boundary is removal -> next summon pass.
    if now - state.readySeenAt < (SCB.REPLACE_REMOVAL_SETTLE_DELAY or 3.0) then return end

    state.active = false
    ok, errorText = SCB_StartPresetSummonSnapshot(state.snapshot)
    if ok then
        -- SCB_StartPresetSummonSnapshot creates the new queue and marks it as an
        -- explicit operation. Suppress that mark for the remainder of this
        -- already-running scheduler frame; the handoff branch above restores it
        -- next frame, when Spawn captures the new queue normally.
        state.handoffQueued = true
        SCB.scbExplicitPresetOperation = nil
        if SCB_DebugLog then
            SCB_DebugLog("Spawn", "Preset rebuild prepared replacement queue; deferring scheduler release one frame")
        end
        return
    end

    if errorText then SCB_Print(errorText) end
    if SCB_CancelActiveRosterPresetTransition then SCB_CancelActiveRosterPresetTransition() end
    SCB.presetRebuildState = nil
end
