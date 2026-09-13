# SoloCraftBots 0.8 Canonical Target

Status: approved architecture direction; implementation in progress
Baseline: 0.7.14
Current live build: 0.8.17-dev. The 0.8.14 rebuild handoff and 0.8.15 removal-settle placement are runtime-proven. 0.8.16 moved Spawn-owned abort/session cleanup out of late `RaidIdentity.lua`; normal 5-man summon and 5-man -> 5-man overwrite still passed, but Ctrl-aborting after add commands had already left the client exposed an in-flight summon race. 0.8.17 holds the replacement snapshot until those old add requests resolve, then tears down any bots that arrived and applies the normal removal-settle barrier. Further structural work remains blocked until this recovery path passes runtime testing. Architecture refinement on 2026-09-13 expands the final Spawn target from a preset-only state machine into one authoritative bot-lifecycle operation coordinator used by preset summon/rebuild and maintenance replacement execution.

This document is the concise canonical target for 0.8. Where an older audit or migration-plan wording differs, this target and `DECISIONS.md` win. Historical notes are retained as the project develops; completed migration items are struck through or recorded in `MIGRATION-LOG.md` rather than deleted.

## Core model

### Preset slots are logical composition identities
A logical preset slot owns the bot intent beneath it: class, role and extra. A human assigned to that slot suppresses that bot only while that human is present. The underlying bot assignment is never destroyed by human occupancy.

A human assignment is exact: player identity -> logical group + logical slot. This means the user chooses exactly which bot a human replaces, protecting key tank/healer/support slots from Blizzard's arbitrary within-subgroup row placement.

Saved humans who are present automatically snap back to their saved logical slot when the preset is loaded/reloaded. Saved humans who are absent do not suppress the underlying bot and require no manual cleanup. Unsaved present humans remain in the lower Other Players pool until assigned.

Implemented in 0.8.5-dev: raid human drag/drop targets exact logical rows; execution snapshots carry the exact human `slotIndex`; group is derived from that slot; group-only legacy assignments without an exact slot remain unassigned until the user chooses a specific slot.

### Logical slot is not Blizzard row
Blizzard raid roster/order remains the source of truth for live names, classes, subgroup membership and displayed within-group order. SCB must never assume logical GxSy equals Blizzard displayed GxSy.

During raid formation humans commonly appear at the top of a subgroup. Their live Blizzard row does not change which logical preset slot they replace.

Bot identity/order inside a subgroup is resolved while ignoring humans. The explicit burst plan and reliable bot-join messages establish bot name -> logical assignment. Blizzard roster then verifies that those names exist, their class, subgroup and live ordering. No hard-coded physical-row expectation is allowed.

Implemented in 0.8.5-dev: Blizzard layout reconciliation records `current*` live placement fields but no longer permutes tracker logical assignments or the preset editor. The 0.7.14 green-pulse/live-row presentation layer was removed as superseded. A three-human BWL runtime test passed with humans suppressing deliberately chosen logical Mage/Priest slots despite Blizzard's independent live row ordering.

### Identity
Primary identity source: explicit burst plan + SoloCraft join-message order.

Blizzard roster is reinforcement/verification and live-location authority, not a competing consumer of the next pending assignment. A mismatch should be surfaced/fail safely rather than silently shift later identities.

The 0.7.14 global pending FIFO and competing roster-delta consumption are not accepted as final architecture. Each burst must be isolated and explicitly completed/failed/aborted before the next can inherit identity state.

0.8.9-dev removed the separate `RaidLayout.lua` patch file by combining its late live-layout reconciliation with the already-late `RaidIdentity.lua` layer. In 0.8.16-dev the Spawn-owned abort/session cleanup wrappers were removed from that late layer and owned directly by `Spawn.lua`. The remaining identity/live-layout code stays transitional. Its migration into `Raid.lua` was deliberately postponed after the 0.8.16 Ctrl-abort test exposed an in-flight spawn/rebuild race; 0.8.17 must pass that recovery gate first.

### Roles
Keep requested/assumed and confirmed roles separately. Combat confirmation is optional and defaults OFF. When OFF, combat events remain unregistered. When ON, confirmed bots stop being scanned and the scanner sleeps when all relevant bots are confirmed.

Resolved role = confirmedRole when available, otherwise assumedRole. Maintenance may use resolved role, because confirmed role is considered more accurate once the evidence threshold has been reached. Never destructively erase assumedRole.

### Removal settle
Shared rule for every operation that removes a bot and then intends to add another bot: request removal -> observe removed bot absent from Blizzard roster -> wait 3.0 seconds -> permit the next replacement/addition.

The delay protects the remove -> next-add boundary. Conversion to raid, subgroup movement/parking, human arrangement and other work that does not add a bot may happen during the 3-second window. Pure removal with no following addition does not need the delay.

This applies to Replace Dead/Missing where removal occurs, preset-over-preset rebuild, survivor handoff, bootstrap handoff and future replacement operations.

A client-side abort does not recall add commands already sent to SoloCraft. If a new preset is forced while old add requests are still in flight, SCB must first allow those requests to resolve or expire, remove any resulting old bots, observe their roster disappearance, and only then apply the normal 3-second remove -> next-add barrier before releasing the replacement preset. This recovery rule is implemented for runtime verification in 0.8.17-dev.

### One bot-lifecycle operation coordinator
There is one authoritative owner of bot roster mutation at runtime. `Spawn.lua` owns a single active operation coordinator/state machine for any workflow that sends bot add/remove commands or waits on the consequences of those commands.

Operation intents include at least:
- preset summon/rebuild;
- Replace Missing;
- Replace Dead;
- forced replacement of the current preset operation.

The coordinator may take different state paths depending on the starting situation, but those paths share one operation object and one set of lifecycle rules. Typical reusable states include resolving already-sent pending adds, combat gating, removal request, roster disappearance, the 3-second settle, conversion, survivor/bootstrap handling, human subgroup arrangement, spawn burst, join/identity verification and completion/abort.

A Ctrl-forced preset does not start a second independent pipeline. It replaces the desired operation handled by the same coordinator. Already-sent server commands remain physical facts that the coordinator must resolve before changing direction.

`Raid.lua` remains authoritative for deciding *what* maintenance action is needed: Active Roster state, dead/missing candidates, replacement class/role/slot identity and live roster facts. It requests an operation from Spawn; it does not independently own add/remove timing, settle timers or a second replacement scheduler.

**Supersedes/refines:** the earlier target wording in which Spawn owned one preset-summon state machine while Replace Dead/Missing retained a substantially separate execution pipeline. Maintenance decision ownership remains in Raid, but all physical bot lifecycle execution converges on Spawn.

## Target file ownership

The goal is a small number of coherent files, not micro-modules. File count is secondary to clear ownership; Location and Comms are explicitly subject to a final sizing/cohesion review after non-preset runtime code has been removed from `Presets.lua`.

### `SoloCraftBots.lua`
- bootstrap/global namespace
- shared UI helpers
- top-level event dispatch
- direct bot commands and raid-mark controls where size remains reasonable

### `Presets.lua`
- preset groups/presets and migrations
- bot logical slot intent
- exact human logical-slot assignments and Other Players pool
- save/load/dirty/editor behaviour
- execution snapshot construction if still compact
- optionally preset communications/protocol if the resulting file remains coherent
- optionally location/capacity/runtime zone data and automatic preset-group switching if the resulting file remains coherent

Earlier target notes proposed folding Location and Comms into this file. That remains a preference, not a hard requirement. Reassess after runtime/scheduler/maintenance code has been extracted from `Presets.lua`; keep either as a separate file if merging would recreate an oversized mixed-responsibility module.

### `Spawn.lua`
- one authoritative bot-lifecycle operation coordinator/state machine
- operation intents for preset summon/rebuild and maintenance replacement execution
- exactly one active physical add/remove lifecycle at a time
- forced-operation replacement without parallel scheduler ownership
- explicit burst planning/LIFO send order
- pending already-sent add resolution
- survivor/bootstrap safety-anchor lifecycle
- party->raid conversion and human arrangement barriers
- combat gate/retry/error abort
- shared 3-second removal-settle use at the actual remove -> next-add boundary
- Spawn-owned scheduler/session cleanup for operation state
- interaction with isolated identity bursts

Migration must be staged. First introduce the operation object/coordinator around proven behaviour; then move common pending-add/removal/settle/abort rules into it; then route rebuild/survivor/bootstrap through it; then route Replace Missing/Dead execution through it while Raid continues choosing maintenance records. Delete parallel scheduler state only after each migrated path passes runtime proof.

0.8.11-dev absorbed the former standalone `PresetRebuild.lua` transition barrier into `Spawn.lua`, so preset-over-preset teardown, conversion, post-removal settle and summon handoff temporarily lived in the intended owner. **Current-state correction:** 0.8.12-dev rolled that absorption back after a runtime client hang. The separate rebuild handoff was re-proven in 0.8.14-dev, and the corrected removal-settle placement passed in 0.8.15-dev. `PresetRebuild.lua` therefore remains separate as a transitional runtime layer. In 0.8.16-dev Spawn directly owns the scheduler-state cleanup previously supplied by late `RaidIdentity.lua` wrappers. In 0.8.17-dev the separate rebuild barrier additionally owns recovery from aborted add commands that are already server-side/in flight. Those proven behaviours are inputs to the coordinator migration; they must not be discarded by a wholesale rewrite.

### `Raid.lua`
- observed Blizzard roster
- logical/live raid tracker
- Active Roster maintenance state
- bot identity binding/reconciliation
- decide Replace Dead / Replace Missing candidates and replacement records
- request maintenance execution from the Spawn operation coordinator
- assumed/confirmed/resolved role state
- optional combat role detection lifecycle
- pfUI tank-role integration

Raid owns maintenance *decision and identity*, not the physical add/remove state machine. It should not retain independent removal timers, add sequencing or a parallel replacement scheduler once the Spawn coordinator migration is complete.

This file may be internally sectioned. Split only if its real size/complexity proves a separate file has independent ownership; do not pre-fragment it.

Established in 0.8.7-dev: the former `RoleTracking.lua` implementation was moved intact to `Raid.lua` at the same TOC position. 0.8.8-dev then absorbed the former `Roster.lua`, giving observed Live Roster and persistent Active Roster their intended final owner. 0.8.9-dev removed the standalone RaidLayout file by combining its live-layout runtime with RaidIdentity. In 0.8.16-dev RaidIdentity stopped owning Spawn abort/session cleanup. Moving its remaining explicit identity/live-layout responsibilities into Raid remains valid, but the immediate post-0.8.17 structural priority is now to establish the single operation-coordinator boundary before continuing deeper scheduler consolidation.

### `Options.lua`
- options/settings UI
- chat filter/hide-SCB-chat behaviour and hooks
- user-facing combat-confirmation setting and explicit callback into the role-detection lifecycle

### `Debug.lua`
- developer diagnostics and debug UI

Supporting locale/assets/bindings remain separate as appropriate.

## Files/layers expected to disappear by consolidation
~~`PresetRebuild.lua`~~, `LocationZones.lua`, `Location.lua` (if merged), ~~`RoleTracking.lua`~~, `Detection.lua`, ~~`DetectionShieldSlam.lua`~~, ~~`DetectionLifecycle.lua`~~, `RaidIdentity.lua`, `RaidPlayers.lua`, ~~`RaidSnapshot.lua`~~, `RaidBurst.lua`, `RaidRefill.lua`, ~~`RaidLayout.lua`~~, ~~`RaidPresentation.lua`~~, `Comms.lua` (if merged), `Commands.lua`, ~~`ChatFilter.lua`~~ and other patch-only layers should be absorbed into the owners above where practical.

Historical completion note: `PresetRebuild.lua` was crossed out when it was absorbed in 0.8.11-dev. That completion was explicitly rolled back in 0.8.12-dev; the file is live again in 0.8.17-dev and the strike-through above records the earlier migration rather than current file absence.

Completed: `LocationZones.lua` was removed in 0.8.0-dev; `ChatFilter.lua` was absorbed into `Options.lua` in 0.8.1-dev; `DetectionShieldSlam.lua` was absorbed into `Detection.lua` in 0.8.2-dev; `DetectionLifecycle.lua` was absorbed into `Detection.lua`/`Options.lua` in 0.8.3-dev; `RaidPresentation.lua` was removed in 0.8.5-dev after the exact-logical-human-slot model superseded live-row editor mirroring; `RaidSnapshot.lua` was absorbed into `RaidPlayers.lua` in 0.8.6-dev so snapshot construction/validation no longer depends on a separate late override layer; `RoleTracking.lua` became the initial `Raid.lua` owner in 0.8.7-dev; `Roster.lua` was absorbed into Raid in 0.8.8-dev; `RaidLayout.lua` was absorbed into the transitional late `RaidIdentity.lua` owner in 0.8.9-dev; `PresetRebuild.lua` was absorbed into `Spawn.lua` in 0.8.11-dev before that specific absorption was rolled back in 0.8.12-dev; and Spawn-owned abort/session cleanup was removed from `RaidIdentity.lua` and returned to `Spawn.lua` in 0.8.16-dev. `RaidPlayers.lua`, `PresetRebuild.lua`, `RaidBurst.lua`, `RaidRefill.lua` and the remaining identity/live-layout part of RaidIdentity remain transitional. `Location.lua` and `Comms.lua` remain open pending the final Presets sizing/cohesion decision.

Cross-version preset communications are now an explicit compatibility concern: an older client was observed to mishandle a newly sent exact-slot preset, while the alternate request flow produced the expected composition. Before main promotion, 0.8 must either preserve exact-slot intent across supported protocol versions or reject incompatible transfers clearly rather than silently degrading them.

This is a target, not permission to delete code before its live responsibility is migrated and verified.

## Migration rule
0.7.14 remains the stable behavioural reference, except for explicitly approved 0.8 behavioural/architectural changes recorded in `DECISIONS.md`: exact logical human-slot semantics, resolved-role maintenance policy, non-competing identity binding, universal 3-second remove-then-add settle at the next-add boundary, and one authoritative Spawn-owned bot-lifecycle operation coordinator with Raid-owned maintenance decisions.