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

    if not state or not state.active then return end

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

    -- For raid-sized presets rebuilt from an existing party, conversion belongs
    -- to the rebuild transition itself. Verify the one-survivor state, convert,
    -- and wait until Blizzard exposes a raid roster before starting G1.
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
            state.readySeenAt = nil
            return
        end
    end

    state.scbConvertRequestedAt = nil
    if not state.readySeenAt then
        state.readySeenAt = now
        return
    end
    if now - state.readySeenAt < 1.0 then return end

    state.active = false
    ok, errorText = SCB_StartPresetSummonSnapshot(state.snapshot)
    if not ok then
        if errorText then SCB_Print(errorText) end
        if SCB_CancelActiveRosterPresetTransition then SCB_CancelActiveRosterPresetTransition() end
    end
    SCB.presetRebuildState = nil
end
