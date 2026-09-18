# SoloCraftBots 0.8 Canonical Target

Status: approved architecture direction; implementation in progress
Baseline: 0.7.14
Current live build: 0.8.23-dev. The 0.8.14 rebuild handoff and 0.8.15 removal-settle placement remain runtime-proven. 0.8.18 introduced one top-level bot operation identity; 0.8.19 moved pending-add recovery, rebuild teardown/settle and next-frame handoff state into `botOperation.rebuild`; 0.8.20 moved survivor/bootstrap state into `botOperation.safety`; 0.8.21 absorbed the temporary coordinator into `Spawn.lua` and proved fresh solo Molten Core 40-man bootstrap plus combat-add retry recovery; 0.8.22 removed the safety hydration bridge and passed large-raid destructive/forced replacement stress, including recovery from a forced switch while 34 old bots were already live; 0.8.23 now allows temporary raid-bootstrap removal settle to overlap unrelated earlier raid bursts, and that behavior passed runtime testing. The next target is to unify fresh bootstrap, retained raid anchor, instance-continuity survivor and 5-man survivor handling into one bootstrap-continuity model before further scheduler retirement.

This document is the concise canonical target for 0.8. Where an older audit or migration-plan wording differs, this target and `DECISIONS.md` win. Historical notes are retained as the project develops; completed migration items are struck through or recorded in `MIGRATION-LOG.md` rather than deleted.

## Core model

### Preset slots are logical composition identities
A logical preset slot owns the bot intent beneath it: class, role and extra. A human assigned to that slot suppresses that bot only while that human is present. The underlying bot assignment is never destroyed by human occupancy.

A human assignment is exact: player identity -> logical group + logical slot. This means the user chooses exactly which bot a human replaces, protecting key tank/healer/support slots from Blizzard's arbitrary within-subgroup row placement.

Saved humans who are present automatically snap back to their saved logical slot when the preset is loaded/reloaded. Saved humans who are absent do not suppress the underlying bot and require no manual cleanup. Unsaved present humans remain in the lower Other Players pool until assigned.

Implemented in 0.8.5-dev: raid human drag/drop targets exact logical rows; execution snapshots carry the exact human `slotIndex`; group is derived from that slot; group-only legacy assignments without an exact slot remain unassigned until the user chooses a specific slot.

Post-consolidation extension approved 2026-09-18: expose the same exact logical-slot model in 5-man presets. A 5-man preset is five underlying bot/composition intents; dragging a player onto a slot chooses exactly which bot intent that player suppresses. This does **not** attempt to change Blizzard's physical party order. Bot intents should also be draggable between preset slots so the user can swap/reorganise the logical composition; in raid-sized presets, moving an intent across a five-slot group boundary changes its intended subgroup because the destination logical slot owns that group. Implement this only after structural consolidation is complete, then runtime-test it before the final 0.8 regression/main promotion.

### Logical slot is not Blizzard row
Blizzard raid roster/order remains the source of truth for live names, classes, subgroup membership and displayed within-group order. SCB must never assume logical GxSy equals Blizzard displayed GxSy.

During raid formation humans commonly appear at the top of a subgroup. Their live Blizzard row does not change which logical preset slot they replace.

Bot identity/order inside a subgroup is resolved while ignoring humans. The explicit burst plan and reliable bot-join messages establish bot name -> logical assignment. Blizzard roster then verifies that those names exist, their class, subgroup and live ordering. No hard-coded physical-row expectation is allowed.

Implemented in 0.8.5-dev: Blizzard layout reconciliation records `current*` live placement fields but no longer permutes tracker logical assignments or the preset editor. The 0.7.14 green-pulse/live-row presentation layer was removed as superseded. A three-human BWL runtime test passed with humans suppressing deliberately chosen logical Mage/Priest slots despite Blizzard's independent live row ordering.

### Identity
Primary identity source: explicit burst plan + SoloCraft join-message order.

Blizzard roster is reinforcement/verification and live-location authority, not a competing consumer of the next pending assignment. A mismatch should be surfaced/fail safely rather than silently shift later identities.

The 0.7.14 global pending FIFO and competing roster-delta consumption are not accepted as final architecture. Each burst must be isolated and explicitly completed/failed/aborted before the next can inherit identity state.

0.8.9-dev removed the separate `RaidLayout.lua` patch file by combining its late live-layout reconciliation with the already-late `RaidIdentity.lua` layer. In 0.8.16-dev Spawn-owned abort/session cleanup wrappers were removed from that late layer and owned directly by `Spawn.lua`. The remaining identity/live-layout code stays transitional. Its migration into `Raid.lua` is sequenced after the current Spawn/bootstrap ownership work so another load-order boundary is not recreated.

### Roles
Keep requested/assumed and confirmed roles separately. Combat confirmation is optional and defaults OFF. When OFF, combat events remain unregistered. When ON, confirmed bots stop being scanned and the scanner sleeps when all relevant bots are confirmed.

Resolved role = confirmedRole when available, otherwise assumedRole. Maintenance may use resolved role because confirmed role is considered more accurate once the evidence threshold has been reached. Never destructively erase assumedRole.

### Removal settle is about capacity reuse
The shared 3.0-second safety rule is:

**request removal -> observe the removed bot absent from Blizzard roster -> wait 3.0 seconds -> allow an addition that depends on that freed capacity.**

The delay protects capacity reuse, not every unrelated add. Conversion to raid, subgroup movement/parking, human arrangement, observation and additions that do not yet need the removed slot may happen during the 3-second window.

Ordinary maintenance replacement, destructive preset teardown and 5-man bootstrap final-slot replacement are capacity-dependent and therefore remain gated.

Temporary raid-bootstrap removal is different: after a genuine new G1 exists, bootstrap disappearance/accounting may settle in parallel with earlier later-group bursts while spare target capacity remains. The first burst that actually needs the bootstrap's freed slot must still wait. If no later bot burst exists, final roster tracking must not complete until the bootstrap has fully settled.

A client-side abort does not recall add commands already sent to SoloCraft. If a new preset is forced while old add requests are in flight, SCB first allows those requests to resolve or expire, tears down any resulting old bots, observes disappearance, and applies the capacity-reuse settle before the replacement operation consumes those slots.

### Bootstrap is one continuity concept
`bootstrap` is the target term for a temporary bot occupant used to establish or preserve required party/raid/instance continuity during a preset transition. Fresh T3 bootstrap, retained raid anchor, instance-ID survivor and 5-man survivor are different **origins/policies** for the same continuity role rather than separate long-term state machines.

A bot bootstrap should exist only when continuity actually requires one. If present humans already preserve the required topology, SCB does not need an extra bot solely to keep the group alive. When a bot bootstrap is required, prefer retaining an existing bot. Create a new bootstrap only when no suitable occupant exists and group formation requires one.

The target preset determines topology; bootstrap state itself never implies raid conversion.

#### 5-man target
- remain a party; never convert to raid for bootstrap handling;
- bootstrap stays in party/G1 because parties have no subgroup parking;
- reserve exactly one required final bot assignment while the bootstrap occupies one party slot;
- fill every other required bot assignment that fits beside the actual present humans and bootstrap;
- remove bootstrap;
- observe it absent and wait 3.0 seconds;
- summon the one reserved final assignment.

The count before bootstrap removal is dynamic. For the ordinary one-human case this is player + bootstrap + three new target bots, then bootstrap removal/settle, then the fourth target bot. With multiple humans fewer pre-removal bot summons fit. Never hard-code “three then fourth”; hard-code the invariant **one reserved final bot assignment**.

#### Raid-sized target (>5)
If a raid already exists and a bot bootstrap is required for continuity, retain one existing bot rather than manufacturing a new one. Park it in G8 when possible, remove the other old bots, observe teardown and wait 3.0 seconds before starting the new G1 because those removed slots are immediately reused.

Once a genuine new G1 bot exists, remove the bootstrap. Its disappearance + settle may overlap later raid bursts that still fit without consuming its slot. Gate only the first capacity-dependent burst if the bootstrap settle has not naturally completed.

For a normal 40-man build the settle should be finished long before the final capacity-filling burst, so there should be no visible bootstrap pause.

#### Fresh raid start
If no suitable existing member can establish/preserve the required raid state, create a temporary bootstrap, convert/form the raid, then converge on the same raid-bootstrap lifecycle above.

### One bot-lifecycle operation coordinator
There is one authoritative owner of bot roster mutation at runtime. `Spawn.lua` owns a single active operation coordinator/state machine for any workflow that sends bot add/remove commands or waits on the consequences of those commands.

Operation intents include at least:
- preset summon/rebuild;
- Replace Missing;
- Replace Dead;
- forced replacement of the current preset operation.

The coordinator may take different state paths depending on the starting situation, but those paths share one operation object and lifecycle policy for resolving already-sent pending adds, combat gating, removal request, roster disappearance, capacity-reuse settle, topology/bootstrap handling, human arrangement, spawn bursts, join/identity verification and completion/abort.

A Ctrl-forced preset does not start a second independent pipeline. It replaces the desired operation handled by the same coordinator. Already-sent server commands remain physical facts that the coordinator must resolve before changing direction.

`Raid.lua` remains authoritative for deciding *what* maintenance action is needed: Active Roster state, dead/missing candidates, replacement class/role/slot identity and live roster facts. It requests an operation from Spawn; it does not independently own add/remove timing, settle timers or a second replacement scheduler.

## Target file ownership

The goal is a small number of coherent files, not micro-modules. File count is secondary to clear ownership; Location and Comms are explicitly subject to a final sizing/cohesion review after non-preset runtime code has been removed from `Presets.lua`.

### `SoloCraftBots.lua`
- namespace/bootstrap of the addon itself
- shared UI helpers
- top-level event dispatch
- direct bot commands and raid-mark controls where size remains reasonable

### `Presets.lua`
- preset groups/presets and migrations
- bot logical slot intent
- exact human logical-slot assignments and Other Players pool
- save/load/dirty/editor behaviour
- execution snapshot construction if still compact
- optionally preset communications/protocol if coherent
- optionally location/capacity/runtime zone data and automatic preset-group switching if coherent

### `Spawn.lua`
- one authoritative bot-lifecycle operation coordinator/state machine
- operation intents for preset summon/rebuild and maintenance replacement execution
- exactly one active physical add/remove lifecycle at a time
- forced-operation replacement without parallel scheduler ownership
- explicit burst planning/LIFO send order
- pending already-sent add resolution
- unified bootstrap-continuity lifecycle with target-specific topology policy
- party/raid conversion only when the target topology requires it
- human arrangement barriers
- combat gate/retry/error abort
- shared 3-second **capacity-reuse** settle
- Spawn-owned scheduler/session cleanup for operation state
- interaction with isolated identity bursts

Migration remains staged. 0.8.18 introduced the operation identity; 0.8.19 moved rebuild ownership into `botOperation.rebuild`; 0.8.20 moved temporary safety-member state into `botOperation.safety`; 0.8.21 absorbed the temporary coordinator file into `Spawn.lua`; 0.8.22 removed the hydration bridge; 0.8.23 proved that raid-bootstrap removal settle can overlap unrelated later bursts safely. The next stage is to make fresh bootstrap, retained raid bootstrap and 5-man bootstrap explicit policies of one lifecycle before deleting more historical scheduler layers.

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

Raid owns maintenance *decision and identity*, not the physical add/remove state machine.

### `Options.lua`
- options/settings UI
- chat filter/hide-SCB-chat behaviour and hooks
- user-facing combat-confirmation setting and callback into detection lifecycle

### `Debug.lua`
- developer diagnostics and debug UI

Supporting locale/assets/bindings remain separate as appropriate.

## Files/layers expected to disappear by consolidation
~~`PresetRebuild.lua`~~, `LocationZones.lua`, `Location.lua` (if merged), ~~`RoleTracking.lua`~~, `Detection.lua`, ~~`DetectionShieldSlam.lua`~~, ~~`DetectionLifecycle.lua`~~, `RaidIdentity.lua`, `RaidPlayers.lua`, ~~`RaidSnapshot.lua`~~, `RaidBurst.lua`, `RaidRefill.lua`, ~~`RaidLayout.lua`~~, ~~`RaidPresentation.lua`~~, `Comms.lua` (if merged), `Commands.lua`, ~~`ChatFilter.lua`~~ and patch-only layers should be absorbed into the owners above where practical.

Historical completion note: `PresetRebuild.lua` was crossed out when it was absorbed in 0.8.11-dev. That completion was explicitly rolled back in 0.8.12-dev; the file remains live during the current 0.8.23 line and the strike-through records the earlier migration rather than current file absence.

Completed consolidation so far includes `LocationZones.lua`, `ChatFilter.lua`, `DetectionShieldSlam.lua`, `DetectionLifecycle.lua`, `RaidPresentation.lua`, `RaidSnapshot.lua`, `RoleTracking.lua`, `Roster.lua`, `RaidLayout.lua`, Spawn-owned cleanup from `RaidIdentity.lua`, and temporary `SpawnOperation.lua` into `Spawn.lua`. `SpawnBootstrap.lua` is explicitly transitional from 0.8.23 and should be absorbed after the unified bootstrap lifecycle is proven rather than becoming another permanent patch owner.

Cross-version preset communications remain an explicit compatibility concern: an older client was observed to mishandle a newly sent exact-slot preset, while the alternate request flow produced the expected composition. Before main promotion, 0.8 must either preserve exact-slot intent across supported protocol versions or reject incompatible transfers clearly rather than silently degrading them.

This is a target, not permission to delete code before its live responsibility is migrated and verified.

## Migration rule
0.7.14 remains the stable behavioural reference except for explicitly approved 0.8 changes recorded in `DECISIONS.md`: exact logical human-slot semantics, resolved-role maintenance policy, non-competing identity binding, capacity-aware removal settle, unified bootstrap continuity, and one authoritative Spawn-owned bot-lifecycle operation coordinator with Raid-owned maintenance decisions.
