# SoloCraftBots Architecture Audit

Status: source-level audit complete for 0.7.14; runtime verification remains part of 0.8 migration
Baseline: 0.7.14
Branch: dev
Audit date: 2026-09-10

This document records how the 0.7.14 addon actually works before the 0.8.x consolidation. It is descriptive. Where a conclusion is inferred from load order or static code rather than observed at runtime, it is labelled **Deduction**.

## Executive summary

The addon is not fundamentally beyond recovery, but its raid/preset path is fragmented. The main problem is not file count by itself; it is that several behaviours are implemented by defining a function, wrapping it in later files, and then sometimes replacing that entire wrapper chain again farther down the TOC.

The strongest examples are:

- preset summon scheduling begins in `Presets.lua`, is augmented in `RaidBurst.lua` and `RaidRefill.lua`, then `Spawn.lua` deliberately installs a final authoritative scheduler that does not call the older scheduler chain;
- bot identity is shared across `RoleTracking.lua`, `RaidIdentity.lua`, `Detection.lua`, refill logic and tracker reconciliation;
- human placement is defined in `Presets.lua`, replaced by `RaidPlayers.lua`, mutated by `RaidLayout.lua`, then partly restored/interpreted by `RaidPresentation.lua`;
- role detection is implemented in `Detection.lua`, extended by `DetectionShieldSlam.lua`, then event lifecycle and Options integration are wrapped in `DetectionLifecycle.lua`;
- AQ40 runtime location correction is applied by `LocationZones.lua` mutating data originally declared in `Presets.lua` before `Location.lua` consumes it.

The 0.8 target should therefore be **single ownership with explicit calls/state transitions**, not simply fewer files.

## 0.7.14 load order

The major TOC order is:

1. `SoloCraftBots.lua`
2. `Presets.lua`
3. `PresetRebuild.lua`
4. `LocationZones.lua`
5. `Location.lua`
6. `Roster.lua`
7. `RoleTracking.lua`
8. `Detection.lua`
9. `DetectionShieldSlam.lua`
10. `RaidIdentity.lua`
11. `RaidPlayers.lua`
12. `RaidSnapshot.lua`
13. `RaidBurst.lua`
14. `RaidRefill.lua`
15. `Spawn.lua`
16. `RaidLayout.lua`
17. `RaidPresentation.lua`
18. `Comms.lua`
19. `Commands.lua`
20. `Options.lua`
21. `DetectionLifecycle.lua`
22. `ChatFilter.lua`
23. `Debug.lua`
24. `ChatFeedback.lua`
25. `Bindings.xml`

The order is semantically significant. Moving files without flattening wrappers would change behaviour.

## State model

### 1. Persistent preset intent

Primary owner today: `Presets.lua`, with exact-row additions in `RaidPlayers.lua`.

Persistent data:
- `SoloCraftBotsDB.presetGroups`
- each preset's `slots`
- each preset's `playerGroups`
- each preset's `playerRoles`
- `playerSlots` is also written by the late `RaidPlayers.lua` compatibility/exact-row layer

Working editor data:
- `SCB.presetEditorSlots`
- `SCB.presetEditorPlayers`
- `SCB.presetEditorPlayerRoles`
- `SCB.presetEditorPlayerSlots`
- `SCB.presetDirty`

0.7.14 semantic rule agreed for 0.8:
- raid subgroup is durable intent;
- within-subgroup Blizzard row is live presentation and must not make the preset dirty.

Architectural conflict: `RaidPlayers.lua` still persists exact human `playerSlots`, while `RaidPresentation.lua` treats same-group live row movement as presentation-only. This is transitional 0.7.x layering and should not be copied literally into the final 0.8 model.

### 2. Execution snapshot / spawn intent

`SCB_BuildPresetExecutionSnapshot()` freezes the current editor/roster into an execution DTO before a summon. `RaidSnapshot.lua` supplies the final 0.7.14 version and includes exact human slot information where available.

The snapshot contains:
- protocol
- preset group id/name/index context
- target size
- bot slot class/role/extra values
- present human names, group, slot and role
- calculated role counts

This snapshot-first concept is sound and should be retained. It prevents the active summon from depending directly on mutable editor controls after launch.

### 3. Preset summon runtime

Primary final owner at runtime: `Spawn.lua`.

Main state:
- `SCB.presetSpawnQueue`
- `SCB.presetGroupWaitRemaining`
- `SCB.presetCombatRetryWaitRemaining`
- `SCB.presetCombatPollRemaining`
- `SCB.presetLastBurstCommands`
- `SCB.presetLastBurstRequeued`
- `SCB.scbExplicitPresetOperation`
- `SCB.scbPresetBurstPlans`
- `SCB.scbArmedPresetPlan`
- survivor/bootstrap fields such as `presetSurvivorBotName`, `presetBootstrapBotName`, `scbParkSurvivorBeforeArrange`, `scbRemoveSurvivorAfterG1`

`PresetRebuild.lua` owns a separate pre-summon teardown state, `SCB.presetRebuildState`, and eventually hands into `SCB_StartPresetSummonSnapshot()`.

### 4. Identity state

Main structures:
- `SCB.pendingAssumedSpawns`: global FIFO of unbound spawn intents
- `SCB.assumedRolesByName`: live name -> intended assignment
- `SoloCraftBotsCharDB.raidRoleTracker.assignments[].botName`

The intended chain is:
planned assignment -> pending intent -> SoloCraft join name -> name-bound assumption -> tracker assignment -> Active Roster.

There are currently **two consumers/association mechanisms** for pending identity:
1. system membership message binding;
2. roster-delta fallback in `RoleTracking.lua`.

This is the most important structural correctness risk in 0.7.14.

### 5. Raid tracker

Persistent per-character structure: `SoloCraftBotsCharDB.raidRoleTracker`.

It bridges initial preset execution and later maintenance/live layout. Important fields include:
- mode / size / zone
- assignments with logical slot, group, class, role, extra, command, bot name
- human player entries
- ready / allowFinalize
- preset group/index association
- layout revision and update time

The tracker starts as intent and is later mutated to follow Blizzard's actual layout. In 0.8 this mutation needs to be clearly defined as live runtime identity/layout, not accidentally treated as stored preset intent.

### 6. Live roster

Owner: `Roster.lua`, then enriched by `RoleTracking.lua` and `Detection.lua` wrappers.

`SCB.liveRoster` is a disposable observed snapshot of current WoW units. It contains current subgroup, class, dead state and links to tracked preset identity where known.

This separation is good: observed WoW state should remain distinct from maintained intent.

### 7. Active Roster

Owner: `Roster.lua`, enriched by Detection.

Persistent structure: `SoloCraftBotsCharDB.activeRoster`.

Purpose: sticky bot slots selected for maintenance. A bot can disappear from the live roster while its Active Roster slot remains `missing`, allowing Replace Missing without consulting whichever preset happens to be selected.

Important distinction:
- Live Roster = observation now.
- Active Roster = bots/slots the player chose to maintain.
- Raid tracker = preset execution identity/layout history.

This distinction is useful and should survive consolidation, although interfaces between the three should become explicit.

### 8. Role evidence

Structures:
- `SCB.roleEvidenceByName`
- `SCB.roleEvidenceRecent`
- per-member/per-active-slot `assumedRole`, `confirmedRole`, evidence fields

Requested/assumed role is operationally sufficient. Combat confirmation is optional validation, default OFF.

A semantic coupling remains: Detection writes `slot.role = confirmedRole` in addition to retaining `assumedRole`. Thus the optional diagnostic can influence the replacement role stored in Active Roster. This deserves an explicit 0.8 decision rather than being preserved accidentally.

### 9. Human live presentation

0.7.14 adds:
- `SCB.liveRaidPlayerSlots`
- `SCB.liveRaidPlayerSlotMismatch`
- associated active preset ids

These are transient UI state. Same-group live Blizzard placement can differ from saved/editor placement without dirtying the preset. The current implementation achieves that by wrapping the older mutating layout path and restoring editor state afterward.

## End-to-end workflow maps

### Preset summon: user action to tracked roster

Final 0.7.14 path:

`SCB_PresetSummonOnClick()` in `Spawn.lua`
-> `SCB_BuildPresetExecutionSnapshot()` (final implementation supplied through `RaidSnapshot.lua`)
-> normalize visible editor slots
-> `SCB_StartPresetRebuild(snapshot)` from `Presets.lua`

If no existing bots:
-> begin Active Roster preset transition
-> `SCB_StartPresetSummonSnapshot(snapshot)` in `Spawn.lua`

If existing bots:
-> set `SCB.presetRebuildState`
-> `SCB_KickBots(false)`
-> preserve safety survivor where policy requires
-> `PresetRebuild.lua` final `SCB_PresetRebuildOnUpdate()` waits for teardown shape, performs party->raid conversion if required, then after its current settle calls `SCB_StartPresetSummonSnapshot(snapshot)`

`SCB_StartPresetSummonSnapshot()`:
-> validate snapshot and operation state
-> determine empty/survivor/party/raid/T3-bootstrap start
-> create raid role tracker
-> partition active bot assignments by logical group
-> build one queue plus parallel explicit burst plans
-> ordinary solo >5: first real G1 assignment can create party, then convert
-> T3 solo >5: temporary Warrior tank bootstrap creates party, then convert
-> survivor path: retain/park safety member until genuine G1 exists
-> arrange human players
-> queue each logical subgroup as `CHECK_COMBAT + reverse command burst`
-> insert exact 1.0s inter-group wait markers
-> queue tracker finalization

`SCB_PresetSpawnQueueOnUpdate()` in `Spawn.lua`:
-> also ticks rebuild, maintenance and refill state machines
-> checks combat gate
-> arms next `scbPresetBurstPlan`
-> `SCB_BeginAssumedSpawnBurst(plan)` appends intents to pending FIFO
-> sends validated `.partybot add ...` through final `SCB_SendSpawnCommand()`
-> handles conversion/barriers/survivor lifecycle
-> `SCB_TryFinalizeRaidRoleTracking()` once roster complete
-> Active Roster established
-> Live Roster / pfUI / presentation updates through final wrapped handlers

Important finding: `Spawn.lua` states and demonstrates that its `SCB_PresetSpawnQueueOnUpdate()` is authoritative and deliberately does **not** call the older Presets/RaidRefill scheduler wrapper chain. Therefore portions of earlier scheduler wrapping in `RaidRefill.lua` and `RaidBurst.lua` are legacy/dead for preset scheduling, although helpers from those files are still called by `Spawn.lua`.

### Identity binding

At CHECK_COMBAT boundary:
-> pop explicit burst plan
-> `SCB_BeginAssumedSpawnBurst(plan)`
-> append each assignment to global `SCB.pendingAssumedSpawns`
-> send burst in reverse command order because SoloCraft processes same-burst commands LIFO

On bot appearance, identity can be consumed by either:

A. system message:
`CHAT_MSG_SYSTEM`
-> final `SCB_HandleAssumedRoleSystemMessage()` wrapper chain
-> parse joined bot name
-> remove first pending intent
-> bind `SCB.assumedRolesByName[name] = intent`
-> link/reconcile tracker slot
-> refresh role/presentation lifecycle

B. roster delta:
`SCB_HandleRosterChange()` wrapper chain
-> `SCB_BindAssumptionsFromRosterDelta(previousNames)` in RoleTracking
-> detect new bot names
-> class-first match pending intents, then next unused intent
-> remove matched pending intents and bind names

Risk: both paths mutate the same pending FIFO. Missing/late messages or a preceding burst that does not fully reconcile can leave intents available for later bots. The global queue has burst ids for metadata, but consumption is not isolated by an active burst boundary.

### Tracker finalization

Base/finalization logic originates in `Presets.lua` and is subsequently wrapped by RoleTracking, RaidLayout and RaidPresentation.

Party/5-man:
-> require exact target member count
-> filter humans
-> ordinal-map actual bot names to active expected assignments.

Raid:
-> group observed bots by Blizzard subgroup
-> require expected bot count per subgroup
-> ordinal-map names to assignments
-> mark tracker ready
-> establish Active Roster
-> apply pfUI tank state

Exact assumed name links can repair/override ordinal assumptions through later identity reconciliation.

### Blizzard raid layout reconciliation

Final call stack is layered:
roster/finalization event
-> prior handler(s)
-> `RaidLayout.lua` `SCB_SyncTrackerToRaidOrder()`
-> `RaidPresentation.lua` guard around the complete prior call.

`RaidLayout`:
- maps live names to source tracker slots;
- derives target slot from Blizzard subgroup + ordinal;
- reorders tracker assignment objects;
- changes assignment `slotIndex` and `group`;
- updates name-bound assumption slot/group;
- updates human tracker slot/group;
- historically permutes editor rows and marks preset dirty;
- re-establishes Active Roster and refreshes live/pfUI state.

`RaidPresentation`:
- captures editor/tracker state before prior handler;
- if only within-group human row changed, keeps the tracker live mutation but restores editor slots/groups/exact rows/dirty state;
- overlays the current live human row in `SCB_GetPresetHumanLayout()`;
- adds green pulse and tooltip for live mismatch.

Conclusion: behaviour is acceptable as 0.7.14 baseline, architecture is not. The final model should compute `intentGroup/intentSlot` and `liveGroup/liveSlot` explicitly rather than mutate then undo.

### Replace Dead / Missing

User action:
`SCB_MaintenanceReplaceOnClick()` in `Presets.lua`
-> get maintenance candidates from Active Roster, not selected preset
-> construct replacement records from maintained slot class/role/extra
-> remove dead/stale names when required
-> set `SCB.replaceDeadState`

`SCB_MaintenanceReplaceOnUpdate()` is defined in Presets and wrapped by RoleTracking to impose removal-settle behaviour.

RoleTracking wrapper:
-> during `waitremoved` / `waitsurvivorremoved`, require removed names absent from refreshed live roster
-> record disappearance time
-> require `SCB.REPLACE_REMOVAL_SETTLE_DELAY = 3.0`
-> only then permit underlying maintenance state machine to continue

Replacement summon:
-> refill/maintenance assignment flow
-> explicit identity plan prepared by `RaidRefill.lua` wrapper around `SCB_RefillOnUpdate`
-> summon
-> new name is rebound to Active Roster slot/tracker where applicable
-> pfUI/live roles refresh.

Known inconsistency: preset rebuild has its own settle timing rather than one shared removal-settle policy.

### Role confirmation and pfUI

Detection transport:
-> Vanilla `CHAT_MSG_SPELL_*` events
-> `DetectionLifecycle.lua` first-stage source filter when enabled
-> main `Detection.lua` parsing/class lookup/spell mapping
-> `SCB_AddBotRoleEvidence`
-> threshold 2, strongest role wins, assumed role tie-break
-> update evidence/Active Roster
-> refresh live roster/pfUI/preset indicators

`DetectionShieldSlam.lua` wraps `SCB_HandleRoleCombatText` solely to recognize Shield Slam using duplicated source-normalization/roster scanning logic.

`DetectionLifecycle.lua`:
- defaults option OFF;
- unregisters all high-volume combat text events when off;
- when on, maintains normalized pending-name set for unresolved tracked bots;
- rejects confirmed/unrelated sources before invoking expensive detector;
- unregisters events and sleeps when all relevant bots are confirmed;
- re-arms on roster/identity/evidence changes;
- also wraps Options creation/refresh/click handlers because it loads after `Options.lua`.

pfUI:
`RoleTracking.lua` final live role resolution is `confirmedRole or assumedRole`.
`SCB_ApplyLivePfUITankRoles()` only clears names previously written by SCB, preserving unrelated manual pfUI tank flags.

### Location switching

`Presets.lua` declares `SCB.INSTANCE_ZONE_BY_GROUP`, including historical AQ40 display/runtime mismatch.
`LocationZones.lua` mutates AQ40 to runtime string `Ahn'Qiraj`.
`Location.lua` then builds its reverse zone lookup at file load.

Zone events:
main event frame
-> `SCB_QueueLocationRefresh(0.20/0.25)`
-> debounce OnUpdate
-> derive context/signature
-> when auto-swap enabled and signature changed, locate matching default preset group
-> if `SCB.presetDirty`, print skip warning and do not load
-> otherwise `SCB_LoadPreset()`.

Separate concern: `Commands.lua` saved-raid safety logic compares current zone against localized raid group labels. Runtime location identifiers should ultimately come from the canonical Location module, not UI localization strings.

## Wrapper/redefinition inventory - important runtime functions

This list records the known significant chains, not harmless same-name local helpers.

### `SCB_SendSpawnCommand`
- `RaidIdentity.lua`: simple SAY sender/register intent.
- `Spawn.lua`: replaces it with validated authoritative sender.
Final owner: **Spawn.lua**.
Action: remove earlier public definition; Identity should not own transport.

### `SCB_StartPresetSummonSnapshot`
- base in `Presets.lua`.
- wrapper in `RaidBurst.lua` for explicit burst/survivor behaviour.
- direct replacement in `Spawn.lua` with authoritative snapshot planner.
Final owner: **Spawn.lua**.
Deduction: the earlier wrapper implementation is dead for new calls after TOC load; exported helper functions from RaidBurst remain live.

### `SCB_PresetSpawnQueueOnUpdate`
- base scheduler in `Presets.lua`.
- wrapper in `RaidRefill.lua`.
- direct replacement in `Spawn.lua`, explicitly bypassing previous chain.
Final owner: **Spawn.lua**.
Action: delete superseded scheduler code after equivalence review.

### `SCB_PresetRebuildOnUpdate`
- base in `Presets.lua`.
- replacement in `PresetRebuild.lua`.
Final owner: **PresetRebuild.lua**.
Action: fold into RaidSpawn state machine.

### `SCB_GetPresetHumanLayout`
- base group-oriented renderer in `Presets.lua`.
- direct replacement in `RaidPlayers.lua` adding exact row persistence.
- wrapper in `RaidPresentation.lua` overlaying live Blizzard row.
Final behaviour: **RaidPresentation over RaidPlayers**.
Action: one player-layout resolver with separate intent and live fields.

### `SCB_LoadPreset`, `SCB_SaveCurrentPreset`, `SCB_AcceptPresetName`, `SCB_AssignPresetPlayer`, `SCB_PresetPlayerOnClick`
- base/editor behaviour in Presets.
- wrapped in RaidPlayers to maintain exact row state.
Action: fold required persistence/migration policy into Presets/Players explicitly.

### `SCB_HandleRosterChange`
- base in `Roster.lua`.
- RoleTracking wrapper adds roster-delta assumption binding, prune and pfUI.
- Detection wrapper links assumptions, prunes evidence, refreshes indicators.
- RaidLayout wrapper runs live layout reconciliation.
- RaidPresentation wrapper captures/restores presentation-vs-intent state.
- DetectionLifecycle wrapper refreshes combat scanner lifecycle after prior chain.
Final function is therefore a nested cross-subsystem dispatcher whose behaviour depends on TOC order.
Action: **replace structurally** with one roster event coordinator and explicit subsystem calls.

### `SCB_TryFinalizeRaidRoleTracking`
- base in Presets.
- RoleTracking wrapper reconciles assumptions/pfUI.
- RaidLayout wrapper synchronizes live order after ready.
- RaidPresentation wrapper guards same-group presentation semantics.
Action: flatten into tracker finalization + explicit layout/presentation follow-up.

### `SCB_BuildLiveRoster`
- base in Roster.
- RoleTracking wrapper attaches assumed role/identity information.
- Detection wrapper attaches confirmed evidence and resolved role.
Action: keep one builder and explicit enrichment helpers, or build complete member model in Roster from query APIs.

### `SCB_EstablishActiveRosterFromTracker`
- base in Roster.
- Detection wrapper seeds assumed/confirmed evidence fields.
Action: make the Active Roster schema explicit in Roster rather than post-processing it.

### `SCB_BindReplacementToActiveSlot`
- base in Roster.
- Detection wrapper resets/sets assumed/confirmed fields.
Action: same as above.

### `SCB_HandleAssumedRoleSystemMessage`
- base fallback in RoleTracking.
- direct replacement in RaidIdentity with exact explicit FIFO intent.
- Detection wrapper links assumptions/refreshes indicators.
- DetectionLifecycle wrapper refreshes scanner lifecycle.
Action: Identity owns binding once; publish a single explicit `identity changed` follow-up call.

### `SCB_AbortBotSpawnOperations` / `SCB_ResetSessionState`
- base definitions in older core modules.
- RoleTracking, Spawn and RaidLayout add cleanup layers for their own state.
Action: operation object/session owner should clean its own complete state in one place.

### `SCB_HandleRoleCombatText`
- base Detection parser.
- DetectionShieldSlam wrapper adds one spell with duplicated parsing.
- DetectionLifecycle wrapper adds pending-source prefilter.
Action: one RoleDetection pipeline and one spell catalogue.

### Options functions
`SCB_EnsureOptionsDB`, `SCB_OptionCheckOnClick`, `SCB_RefreshOptionsUI`, `SCB_CreateOptionsUI` are wrapped by DetectionLifecycle to inject one option after Options loads.
Action: Options owns UI; feature modules should register schema/callbacks or Options should explicitly know the option.

## Event / OnUpdate ownership

### Main event frame (`SoloCraftBots.lua`)
Registers lifecycle, zone, target, party/raid roster, leader, unit combat/flags, chat and logout events. It currently acts as a broad dispatcher into modules.

Important roster events:
- `PARTY_MEMBERS_CHANGED`
- `RAID_ROSTER_UPDATE`
These eventually invoke the nested final `SCB_HandleRosterChange` chain.

### Preset spawn queue frame
Created by `SCB_CreateUI()` and has continuous `OnUpdate = SCB_PresetSpawnQueueOnUpdate`.
The final Spawn implementation also ticks:
- preset rebuild
- maintenance replace
- refill
before handling its own explicit preset queue.

Thus one frame is effectively the timer pump for several state machines.

### Location refresh frame
Debounced/polled short-lived OnUpdate in Location; 0.20/0.25s typical delay.

### Role detection frame
Detection creates the combat-event frame. DetectionLifecycle dynamically registers/unregisters high-volume events. This should stay event-driven and dormant when disabled/resolved.

### Miscellaneous short-lived OnUpdates
- auto-loot retry in Roster (0.25s, bounded attempts)
- delayed command helper in SoloCraftBots
- safety warning fade/pulse
- preset tutorial animation
- UI button pulses/live-row pulse
- comm timeout/retry mechanism
These are local UI/transport timers and are not the primary consolidation problem.

## Shared-state writer risks

### High risk

`SCB.pendingAssumedSpawns`
- RoleTracking fallback binding
- RaidIdentity explicit binding/clear
- refill/preset burst preparation
Risk: competing consumers and burst leakage.

`SCB.assumedRolesByName`
- RoleTracking binding/pruning/reset
- RaidIdentity binding/reconciliation
- RaidLayout changes slot/group metadata
- Detection reads/links it
Risk: identity and live layout responsibilities mixed in one mutable record.

`raidRoleTracker.assignments`
- creation/finalization in Presets/raid helpers
- identity linking
- replacement rebinding
- RaidLayout physically reorders and changes slot/group
Risk: assignment intent and current layout are conflated.

`presetEditor*`
- Presets editor
- RaidPlayers exact-row wrappers
- RaidLayout permutation
- RaidPresentation restoration
Risk: user intent and observed layout mixed.

### Medium risk

Active Roster role fields
- Roster owns slot lifecycle
- Detection can alter `role`, `assumedRole`, `confirmedRole`
Risk: optional validation can change maintained replacement semantics.

Spawn scheduler flags
- legacy/base Presets fields
- RaidBurst/RaidRefill compatibility layers
- final Spawn runtime
- cleanup wrappers in several files
Risk: stale/obsolete state and hard-to-prove reset completeness.

### Low/contained risk

- `SCB.liveRoster`: rebuilt snapshot by design.
- `SCB.pfuiAutoTanks`: one-purpose ownership in live role layer.
- UI pulse/tutorial state: local presentation state.

## File responsibility/classification inventory

### Keep largely as-is
- `Locale/*.lua`: localization data. Move dynamically injected DetectionLifecycle strings here.
- `Comms.lua`: cohesive preset-transfer protocol; depends on snapshot contract but does not need raid lifecycle ownership.
- `ChatFilter.lua`: isolated chat filtering.
- `ChatFeedback.lua`: isolated user feedback/server error interpretation; review only its spawn-abort hooks when Spawn API changes.
- `Debug.lua`: diagnostic consumer; update function/state names as consolidation proceeds.
- `Bindings.xml`: isolated binding declaration.
- direct command matrix/raid marks portion of `Commands.lua`.

### Keep concept, tighten ownership
- `Location.lua`: becomes sole runtime zone/capacity/auto-swap authority.
- `Roster.lua`: remains observed Live Roster + persistent Active Roster owner. Move feature-specific post-processing out of wrappers into explicit interfaces.
- snapshot concept from `RaidSnapshot.lua`: retain immutable execution plan; final file location can be Presets or RaidSpawn.
- `Spawn.lua` validated outbound spawn gate and explicit queue/plan construction: use as starting point for RaidSpawn, not old Presets scheduler.
- `RaidLayout.lua`: retain ability to read/reconcile Blizzard live layout, but stop mutating editor intent.

### Move / merge
- `PresetRebuild.lua` -> RaidSpawn.
- `LocationZones.lua` -> Location canonical mapping.
- `DetectionShieldSlam.lua` -> main role spell catalogue.
- `DetectionLifecycle.lua` -> RoleDetection plus explicit Options integration.
- `RaidPresentation.lua` -> RaidPlayers/RaidLayout presentation model.
- exact-row compatibility/migration parts of `RaidPlayers.lua` -> explicit Presets/RaidPlayers policy.
- survivor/safety helper functions currently exported by `RaidBurst.lua` -> RaidSpawn.
- maintenance-specific removal/survivor policy from `Commands.lua`/Presets -> RaidMaintenance/RaidSpawn as appropriate.

### Replace structurally
- global cross-burst identity FIFO policy.
- dual system-message + roster-delta consumption of identity intents.
- nested roster-change wrapper chain.
- nested tracker-finalization wrapper chain.
- mutate-editor-then-restore raid presentation architecture.
- multiple superseded preset schedulers retained in executable files.
- distributed spawn-operation cleanup wrappers.

## Dead/superseded code deductions requiring verification before deletion

Static load order establishes that:

1. the base `SCB_StartPresetSummonSnapshot` in Presets and its RaidBurst wrapper are superseded by Spawn's later direct definition;
2. the Presets `SCB_PresetSpawnQueueOnUpdate` and RaidRefill wrapper are superseded by Spawn's later direct definition;
3. RaidBurst helpers referenced by Spawn (`scb072TryParkSurvivorInGroupEight`, `scb072TryRemoveParkedSurvivor`) remain live even though its scheduler wrapper is superseded;
4. RaidRefill's wrapper around `SCB_RefillOnUpdate` remains live because Spawn calls the final global refill updater and does not redefine it.

Do not delete based solely on these deductions. First add temporary debug/assertion instrumentation or perform focused runtime tests during the relevant 0.8 migration step.

## Performance findings

1. Always-on combat parsing was the largest known hot path; 0.7.14 already disables it by default and unregisters events when dormant.
2. When enabled, Detection's full roster lookup/UnitClass work is guarded by DetectionLifecycle's pending-name source filter. Consolidation should preserve this ordering.
3. `SCB_HandleRosterChange` can currently trigger multiple complete live-roster rebuilds and pfUI refreshes through nested wrappers. This is a clear opportunity to compute one observed snapshot per event and pass it to explicit consumers.
4. Raid layout synchronization can rebuild Active Roster and then Live Roster again. In 0.8, a coordinator can batch downstream refreshes after reconciliation.
5. UI pulse OnUpdates are small and local; they are not priority performance work compared with roster/detection duplication.

## Important correctness findings

### Identity queue is the highest-risk defect area
The global pending FIFO allows an unresolved prior burst to contaminate the next burst. Burst ids are recorded but not used as a hard consumption boundary. Roster-delta fallback can also consume from the same queue before/around system messages.

Target: one active burst identity object with expected count and explicit completion/failure. Do not arm the next burst until the current identity burst is resolved or deliberately failed/aborted.

### Role confirmation is not purely diagnostic in stored state
Although the UI/feature is now described as optional validation, confirmed evidence can write `slot.role` in Active Roster. That can influence replacement commands. Decide explicitly whether 0.8 replacement should preserve requested role, confirmed role, or expose a resolved role without destroying either source.

### AQ40/runtime zone data is duplicated and semantically mixed
Runtime zone ids/strings and translated UI labels are used in different places. Canonical location data must be non-localized runtime data; UI labels should be separate.

### Human exact row has two meanings in current code
`RaidPlayers.lua` treats exact row as persistable state; 0.7.14 presentation policy says same-group Blizzard row is transient. 0.8 must define fields so these meanings cannot collide.

## Recommended canonical 0.8 data vocabulary

Use explicit naming rather than overloaded `slot/group/role` fields:

Preset human intent:
- `intendedGroup`
- optional durable `preferredSlot` only if we deliberately decide exact row is user-authored intent

Live human layout:
- `liveGroup`
- `liveSlot`

Bot assignment intent:
- `logicalSlot`
- `intendedGroup`
- `requestedClass`
- `requestedRole`
- `requestedExtra`

Live bot identity:
- `name`
- `liveGroup`
- `liveOrdinal/liveSlot`

Detection:
- `assumedRole/requestedRole`
- `confirmedRole`
- `resolvedRole` as a computed value, not a destructive overwrite unless explicitly decided.

## Audit conclusion

The source-level audit is complete enough to begin Phase B architecture agreement. We can explain the active 0.7.14 flow without relying on chat history, and the high-risk ownership conflicts are identified.

The next step is **not code movement yet**. First approve/refine the target ownership and the unresolved semantic decisions listed in `CONSOLIDATION-0.8.md`. Runtime tests will then be used as proof points while each consolidation phase removes superseded paths.

## Recovery instruction

A future developer/session should read, in order:
1. `BEHAVIOUR-BASELINE.md`
2. this `ARCHITECTURE.md`
3. `DECISIONS.md`
4. `CONSOLIDATION-0.8.md`

Then inspect the current `dev` diff before making any functional change.