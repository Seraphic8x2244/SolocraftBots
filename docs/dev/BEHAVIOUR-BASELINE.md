# SoloCraftBots 0.7.14 Behaviour Baseline

Purpose: preserve known-good behaviour while 0.8.x consolidates architecture.

This is a regression baseline, not a complete user manual. Items labelled **Known defect/ambiguity** describe 0.7.14 reality that must not be silently turned into a design requirement.

## Presets

- Supported preset sizes: 5 / 10 / 15 / 20 / 40.
- Presets store bot class/role/extra intent and human raid-group assignments.
- Save button shows Saved when editor intent matches stored preset; meaningful edits show Unsaved Changes.
- Human raid subgroup is semantic preset intent.
- Blizzard moving a human to a different row within the same subgroup is presentation-only and must not dirty the preset.
- When same-group live row differs from preset row, the live character slot is shown in Blizzard's position with a pulsing green background and tooltip: `Not in preset location due to Blizzard raid handling`.
- Moving a human to a different raid subgroup is a meaningful preset change and may make the preset Unsaved.
- Reselecting/reloading a preset restores saved preset intent.
- A human covering a preset row hides/inactivates the underlying bot for editor occupancy/extras but does not delete the bot assignment stored underneath.

**Known ambiguity:** 0.7.14 still has `playerSlots` exact-row persistence through `RaidPlayers.lua` even though same-group Blizzard row movement is now treated as presentation-only by `RaidPresentation.lua`. 0.8 must resolve this explicitly rather than blindly preserve both meanings.

## Preset group/location rules

- World: 5-man.
- Dungeons may be run as 10-man raids after entering an instance.
- Blackrock Spire supports 15.
- ZG / AQ20: 20.
- MC / Onyxia / BWL / AQ40 / Naxx: 40.
- AQ40 client runtime zone string is `Ahn'Qiraj`; user-facing group label may remain `Temple of Ahn'Qiraj`.
- Automatic location-based preset-group switching must not overwrite a dirty preset silently.
- Location refresh is debounced after zone events rather than continuously polled.

**Known implementation ambiguity:** runtime zone identity is not yet centralized; some safety code compares localized display names. Consolidation may correct the source of truth while preserving conservative safety behaviour.

## Summoning

- Summoning always sends `.partybot add ...` through SAY.
- The final 0.7.14 outbound spawn sender validates command syntax/assignment before sending.
- SoloCraft same-burst command processing is reverse/LIFO; SCB sends a logical burst in reverse command order so resulting join order matches intended logical order.
- Normal preset burst is one logical subgroup, maximum 5 bot summons.
- There is an exact 1.0 second boundary between logical five-slot groups in the current final scheduler.
- A combat check occurs before a planned burst; active combat can defer/retry according to the existing retry ladder.
- Exact SoloCraft error `Cannot add bots right now.` hard-aborts the active spawn operation.
- Preset execution is snapshot-based: the composition is frozen before the operation begins.

Internal reference: the **final authoritative 0.7.14 preset scheduler is the implementation in `Spawn.lua`**. Older scheduler definitions/wrappers remain loaded earlier but are superseded for preset queue processing.

## Party-to-raid conversion

- For presets larger than 5, conversion to raid occurs before later raid groups are filled where required.
- Ordinary solo >5 can summon the first real G1 bot to establish a party, convert to raid, arrange humans, then continue remaining bursts.
- T3 raid-zone solo starts may use a temporary bootstrap/safety bot because a party must exist before `ConvertToRaid()`.
- A retained survivor or bootstrap is treated as temporary safety membership during handoff; genuine requested bots replace it once the operation is safely established.
- Survivor/bootstrap removal waits for required roster conditions rather than removing the safety member immediately.

## Rebuild over an existing summon

- Existing unwanted bots are removed before the replacement preset proceeds.
- If survivor safety is required, the rebuild waits until the roster has reached the expected survivor shape before continuing.
- For >5 with a survivor while not yet in raid, rebuild conversion waits until raid state is actually observed before handing into preset summon.
- 0.7.14 `PresetRebuild.lua` uses its own current post-ready settle before starting the new snapshot.

**Known desired change, not 0.7.14 baseline:** user wants preset-over-preset rebuild to use the same 3-second server-removal settle concept as Replace Dead. Implement only as an explicit 0.8 decision/change.

## Replace Dead / Missing

- Maintenance uses the persistent Active Roster, not whichever preset is merely selected in the editor.
- A missing Active Roster slot remains maintainable even though its live bot is absent.
- Replacement record preserves the slot's maintainable class/role/extra fields.
- Replace Dead waits for removed bot name(s) to disappear, then waits a 3-second server-removal settle before continuing.
- Combat remains a hard gate where the existing maintenance flow requires it.
- A replacement can update the original tracker assignment's `botName` when the Active Roster slot remains linked to a tracker slot.
- Unidentified/unmaintainable dead or missing slots are surfaced rather than silently guessed.

## Live Roster / Active Roster

- `SCB.liveRoster` is an observed snapshot and may be rebuilt frequently.
- `SoloCraftBotsCharDB.activeRoster` is the sticky list of bot slots the player is maintaining.
- Human players are not replaceable Active Roster slots.
- Manual/unbound observed bots can be adopted into Active Roster when no preset transition/refill replacement owns the arrival.
- During loading-screen continuity reconciliation, saved names are not immediately trusted until roster state settles.
- Normal runtime sync does not resurrect a missing slot simply because a later bot happens to receive the same random name; saved-session reconciliation is the special continuity boundary.

## Bot identity

- Name-bound identity is authoritative after binding.
- Same-burst identity order is based on explicit burst plans, not timestamp equality.
- Timestamps are diagnostics/timeouts only, not ordering truth.
- Exact `slotIndex` is preferred in the newer raid identity reconciliation; older command/group matching remains as fallback/compatibility in parts of the code.
- Explicit burst plans include burst ids and assignment slot/group metadata.

**Known defect candidate:** pending assumed spawns are stored in a global FIFO and are not hard-isolated by burst at consumption time. A stale prior intent can theoretically be consumed by a later bot.

**Known defect candidate:** roster-delta binding and system membership-message binding both consume/associate pending identity. Their overlap must not be treated as intended architecture.

## Roles

- `assumedRole` represents requested/intended role.
- `confirmedRole` represents optional combat-derived observation.
- Resolved live role currently prefers `confirmedRole` over `assumedRole`.
- Combat confirmation is OFF by default in 0.7.14.
- When confirmation is OFF, the high-volume combat-text events are unregistered after addon load/lifecycle initialization.
- When confirmation is ON, already-confirmed tracked bots are skipped by the lifecycle filter.
- When no relevant unresolved tracked bots remain, the combat event frame unregisters/goes dormant.
- New/replacement/unconfirmed tracked bots can wake the scanner while the option is enabled.

**Known semantic ambiguity:** confirmed combat evidence can currently update the Active Roster's resolved `slot.role` while also retaining `assumedRole`. Therefore the supposedly diagnostic feature may affect replacement semantics. 0.8 must choose this policy explicitly.

## Combat evidence

- Confirmation threshold is 2 recognized observations.
- Duplicate same-name/same-spell evidence within 0.30 seconds is suppressed; later repeats can count.
- Strongest role score wins; assumed role is a tie-breaker where applicable.
- Paladin tank evidence is deliberately restricted to strong indicators: Righteous Fury and Holy Shield. Do not casually reintroduce Consecration, Seal of Righteousness or Blessing of Sanctuary.
- Shield Slam counts as Warrior tank evidence in 0.7.14 through a separate extension file; consolidation should preserve the evidence while removing duplicate parsing code.

## pfUI tank roles

- Live role resolution is confirmed role first, otherwise assumed role.
- SCB clears only tank-role names that SCB itself previously wrote.
- Manual pfUI tank assignments outside the SCB-owned set must remain untouched.
- Bootstrap/safety identities are excluded from genuine tracked role treatment.
- pfUI/group/raid refresh is triggered after relevant role/tracker changes so tank icons update.

## Human player editor behaviour

- 5-man placement follows actual party layout.
- Raid presets assign human players to raid groups.
- Dragging a player between groups is an explicit preset edit.
- Player role/spec controls are class-aware and separate from the bot assignment underneath a human-covered slot.
- Blizzard same-group row movement is shown live but is not an edit.
- Blizzard subgroup movement is treated as semantic.

## Commands / communications

- Direct control commands use PARTY chat so they remain available while dead.
- ONE/Target commands require a friendly bot target and otherwise do nothing rather than falling through to an all-bot command.
- Ctrl-click Come sends the corresponding Move first, then Come.
- Preset communication uses addon RAID transport (with Vanilla-compatible targeting inside the payload) and serializes a snapshot contract. Consolidation should not change protocol accidentally.

## UX / safety principles

- Preserve player agency.
- Block impossible/unsupported actions, not merely unusual choices.
- Do not silently correct user data.
- Visual warnings are acceptable.
- Do not use hidden TargetByName probing for maintenance.
- Summoning remains SAY; normal controls remain PARTY.
- Survivor handling is conservative where saved-instance state is uncertain.

## Regression scenarios for 0.8 consolidation

Run relevant subsets after each phase and the full set before promoting 0.8 to main.

1. Addon login/reload: no Lua errors; options/presets/session state load.
2. Preset edit/save/reselect: Saved/Unsaved semantics correct.
3. 5-man preset from solo.
4. 10-man dungeon preset from solo using first-real party->raid conversion.
5. 10-man preset over an existing 5-man summon with survivor retained.
6. 20/40-man T3 raid-zone start from solo requiring bootstrap/conversion.
7. Start >5 while already in party.
8. Start >5 while already in raid.
9. Consecutive logical group bursts preserve intended name/slot/class/role mapping.
10. A burst with repeated identical class/role commands still binds each identity correctly.
11. No pending identity from G1 can be inherited by G2 after successful completion.
12. Server combat retry does not duplicate identity intents.
13. Exact `Cannot add bots right now.` abort clears operation state safely.
14. Replace Dead preserves intended maintainable assignment and observes the 3-second settle.
15. Replace Missing preserves Active Roster slot identity without consulting selected preset.
16. Combat confirmation OFF leaves combat scanner dormant.
17. Combat confirmation ON ignores confirmed/unrelated bots and sleeps when complete.
18. New/replacement bot wakes scanner when enabled.
19. Shield Slam remains Warrior-tank evidence.
20. pfUI tank icons match intended/resolved roles immediately after spawn; unrelated manual pfUI flags survive.
21. Blizzard within-group human row reorder changes display only, leaves Saved, and shows green pulse/tooltip.
22. Human subgroup change is a real preset difference.
23. Reselecting a preset restores its intended editor state.
24. Location auto-swap does not discard dirty editor changes.
25. AQ40 runtime context resolves `Ahn'Qiraj` correctly.
26. Survivor saved-instance safety remains conservative if raid-ID APIs are absent/ambiguous.
27. Direct command matrix, target validation and Ctrl-Come behaviour unaffected.
28. Preset send/request communications still serialize/validate the expected snapshot contract.

Any intentional change to this baseline must be logged in `DECISIONS.md` with the old behaviour and the new behaviour.