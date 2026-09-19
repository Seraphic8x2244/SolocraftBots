# SoloCraft Bots 0.8.38-dev performance audit

Date: 2026-09-18
Audited runtime: 0.8.38-dev
Runtime commit: `8e64161e2b2ab8218ace81ec4c508776e9f2146a`
Audit scope: all six Lua owner files, event registration, roster/live-state construction, Active Roster, preset UI, spawn/maintenance coordinators, communications and developer diagnostics.

This audit does not change runtime code.

## Executive summary

0.8.37 and 0.8.38 removed a large amount of roster-event amplification, but there are still several material efficiency gains available.

The highest-value remaining issue is a legacy finalization behaviour that survived the wrapper flatten exactly as written: after a raid tracker is already ready/reconciled, every PARTY_MEMBERS_CHANGED / RAID_ROSTER_UPDATE still calls `SCB_TryFinalizeRaidRoleTracking()`. Its ready path invokes post-finalization again. Because `SCB_ReconcileTrackerFromAssumedRoles()` returns true when it was already reconciled, that path re-establishes the Active Roster, forces additional Live Roster builds and refreshes physical layout again.

In a ready tracked raid, one Blizzard roster event can therefore still cause approximately:
1. the intended canonical `SCB_CollectGroupMembers()` + Live Roster build in `SCB_HandleRosterChange()`;
2. another fresh Live Roster build in `SCB_EstablishActiveRosterFromTracker()`;
3. another fresh Live Roster build through its unscoped Replace button refresh -> Active Roster sync;
4. another explicit `SCB_RefreshLiveRoster()` in post-finalize;
5. another direct raid scan in `SCB_RefreshTrackerLiveLayout()`.

The Active Roster is also rebuilt into fresh slot tables during that repeated post-finalize path. This is the first thing to fix before judging whether same-frame 40-man Kick All is safe.

The second large area is operation polling. Membership/subgroup readiness is still observed from OnUpdate at render-frame frequency in several places. A 40-man teardown can make the preset rebuild coordinator perform multiple full group scans per rendered frame while it waits for the roster to change. These observations should be revision/event-driven, with a slow fallback poll only where Vanilla event reliability requires it.

## Priority A — high payoff

### A1. Stop re-finalizing an already-finalized tracker

Current behaviour:
- the main roster-event dispatcher always calls `SCB_TryFinalizeRaidRoleTracking()`;
- when `tracker.ready == true`, that function still calls `SCB_PostFinalizeRaidRoleTracking()`;
- `SCB_ReconcileTrackerFromAssumedRoles()` returns true when `tracker.scbRoleIdentityReconciled` is already true;
- the post-finalize path consequently re-runs `SCB_EstablishActiveRosterFromTracker()`, `SCB_RefreshLiveRoster()`, and live-layout observation.

Fix:
- an already-ready/reconciled tracker should return true immediately;
- post-finalize work should execute only on the transition into ready and, if needed, once when identity reconciliation changes names;
- pass the current canonical observed roster into reconciliation/Active Roster establishment rather than forcing a new observation;
- establish Active Roster once after final names are known;
- refresh maintenance presentation once;
- layout observation remains the existing debounced roster consumer, not an immediate second pass.

Expected payoff: very high during every raid join/leave/subgroup mutation and especially mass Kick All.

Risk: low-medium. The key is to preserve one-time finalization semantics and not remove the initial identity reconciliation.

### A2. Make operation roster observation revision-driven instead of frame-driven

Current hot polling includes:
- `SCB_PresetRebuildOnUpdate()`: while waiting for teardown it asks for the Kick All anchor and bot count every frame. `SCB_GetKickAllAnchorForFreshBuild()` itself calls `SCB_GroupHasName()`, `SCB_CountGroupBots()` and `SCB_CountOtherHumans()`; the coordinator then calls `SCB_CountGroupBots()` again. Each helper currently constructs a full `SCB_CollectGroupMembers()` snapshot.
- `SCB_ReplaceDeadNamesGone()`: forces `SCB_GetLiveRoster(true)` while maintenance waits for removals.
- maintenance/refill `waitgroup`: `SCB_GetNewRefillBots()` scans the live party/raid on every frame until arrivals settle and then scans again after stabilization.
- bootstrap removal: `SCB_GroupHasName()`, real-G1-bot checks and combat scans can run every frame.
- `PRESET_TRACK_ROSTER`: finalization can scan raid grouping every frame while parked at the queue barrier.
- `PRESET_WAIT_FINAL_ROSTER`, `WAIT_BOOTSTRAP`, `WAIT_REAL_RAID_START` and survivor-gone waits repeatedly scan membership.

Preferred design:
- increment a `SCB.rosterEventRevision` in the canonical roster handler;
- include raid index/subgroup/order metadata in the canonical Live Roster snapshot;
- operation states remember the last revision they examined;
- membership/subgroup checks run only when the roster revision changes;
- timeouts and settle timers still advance every frame, but they do no roster work if the revision is unchanged;
- optionally retain a low-frequency fallback fresh poll (for example 0.10-0.25s) only for any Vanilla transition proven not to emit a dependable roster event.

Expected payoff: very high during large summon/teardown/replacement operations.

Risk: medium. Physical safety barriers must remain authoritative; do not replace event observation with stale time-based caching.

### A3. Replace repeated full group-query helpers with one snapshot/summary

Current helpers `SCB_GroupHasBots`, `SCB_FindFirstGroupBotName`, `SCB_CountGroupBots`, `SCB_CountOtherHumans` and `SCB_GroupHasName` each construct a complete member table, including dead-state checks, even when the caller only needs one count/name/presence boolean.

`SCB_GetPresetStartBotState()` can perform three complete group collections. `SCB_GetKickAllAnchorForFreshBuild()` can perform three complete collections, and its caller often immediately performs another bot count.

Fix:
- consume the canonical Live Roster where membership freshness is event-defined: `botCount`, `humanCount`, `byName`, ordered `members`;
- or provide one lightweight `SCB_GetGroupSummary()` observation that returns bot count, other-human count, first bot and a name map in one pass;
- allow callers that already have `observed` to pass it through.

Expected payoff: high, especially in preset rebuild/teardown.

Risk: low-medium.

### A4. Remove quadratic work from Live Roster construction

Current `SCB_BuildLiveRoster()` does two linear-name lookups inside its per-member loop:
- `SCB_GetTrackedRosterAssociation(name, isBot)` scans tracker assignments/players and allocates a new association table;
- `SCB_GetActiveSlotByName(name)` scans Active Roster slots.

In a 40-member tracked raid these are O(n²) enrichments on top of the Blizzard API scan.

Fix:
- once per build, create transient maps for tracker bot assignments by name, tracker humans by name, and Active Roster slots by current name;
- enrich each raw member with O(1) lookups;
- avoid allocating a separate association table per member; read fields from the indexed tracker entry directly.

Expected payoff: high because every canonical roster observation benefits.

Risk: low.

### A5. Disable debug-only event traffic when developer debug is off

The main event frame permanently registers:
- `UNIT_COMBAT`;
- `UNIT_FLAGS`;
- `CHAT_MSG_PARTY`;
- `CHAT_MSG_RAID`;
- `CHAT_MSG_SAY`.

Those branches exist only for developer diagnostics. `UNIT_COMBAT` is particularly high-frequency in normal combat. The debug handlers return immediately when developer debug is disabled, but WoW still dispatches every event into SCB's Lua handler.

Fix:
- register debug-only events when developer debug/the relevant checkbox is enabled;
- unregister them when disabled;
- leave gameplay events permanently registered.

Expected payoff: high steady-state reduction during normal combat, essentially zero behavioural risk.

Risk: low.

### A6. Consolidate CHAT_MSG_SYSTEM routing

There are currently three independent frames receiving `CHAT_MSG_SYSTEM`:
- the main SCB event frame;
- RoleTracking identity frame;
- Communication spawn-failure frame.

Every system message is dispatched to all three. During bot joins/rejections this is unnecessary fan-out.

Fix:
- expose the identity and spawn-rejection handlers;
- route the system message once from the main event frame in an explicit order;
- remove the two extra event frames.

Expected payoff: medium-high during summon/rebuild, small but permanent otherwise.

Risk: low if handler ordering is documented/preserved.

## Priority B — medium/high targeted gains

### B1. Maintenance records should only build replacement payloads for actionable slots

`SCB_GetActiveMaintenanceRecords()` currently calls `SCB_BuildActiveReplacementRecord(slot)` for every expected slot before it knows whether that slot is missing/dead. For a healthy 40-man roster this creates up to 40 temporary replacement tables and 40 spawn command strings that are immediately discarded.

Fix:
- determine missing/dead first;
- only build/validate the replacement record for a slot that is actually actionable.

Expected payoff: medium-high for every Replace button calculation.

Risk: very low.

### B2. Add fast name indexes for Active Roster/tracker lookups

`SCB_GetActiveSlotByName()` linearly scans up to 40 slots and is used by Live Roster enrichment and role detection.

Options:
- build transient maps once in consumers such as Live Roster construction;
- or maintain a transient `SCB.activeSlotByName` index and rebuild/update it whenever Active Roster bindings change.

Also, replacement binding currently searches tracker assignments for a known `slotIndex`; tracker assignments are already indexed by logical slot and can usually be accessed directly.

Expected payoff: medium-high.

Risk: low if a transient index is rebuilt on every owner mutation.

### B3. Use canonical Live Roster metadata for live layout

`SCB_RefreshTrackerLiveLayout()` currently performs a separate `GetRaidRosterInfo` scan after the roster handler has already built the current snapshot.

Fix:
- store `raidIndex` and group-row/order in canonical Live Roster members;
- let the debounced layout consumer read the newest Live Roster revision.

Expected payoff: medium, and moves closer to one physical observation per roster revision.

Risk: low-medium; subgroup/order metadata must correspond to the same revision.

### B4. Make combat checks shared/throttled while an operation is active

`SCB_PresetGroupHasCombat()` can check every raid member and every pet. Some operation paths can request combat state repeatedly while waiting.

Fix:
- cache a group-combat observation for a very short operation-local interval, or poll it on the existing bounded combat cadence;
- do not run the 40-member/pet scan multiple times in one frame;
- preserve the existing server-rejection fallback, which remains authoritative for summon races.

Expected payoff: medium-high while operations are blocked by combat.

Risk: low-medium.

### B5. Cross-group maintenance bursts (already planned)

The current maintenance coordinator still replaces one destination group at a time. Several single missing bots in different groups therefore require several separate bursts and separate one-second stabilization windows.

Implement the documented mixed-group up-to-five burst:
- take next up to five sorted assignment intents across groups;
- identity-bind each joining name to its queued intent;
- move each bot to its own intended subgroup;
- verify all destinations;
- perform one common post-arrival stabilization;
- continue with the next up-to-five.

Expected payoff: high operation throughput when missing/dead bots span groups.

Risk: medium; identity/order binding must be exact.

## Priority C — UI/rendering efficiency

### C1. Remove an unused human-roster scan from SCB_RefreshPresetSlots

`SCB_RefreshPresetSlots()` assigns `local present = SCB_GetPresentHumanMap()`, but `present` is not used anywhere in the function. The call performs a full human roster scan and allocations for no result.

Fix: delete the call and now-unused locals.

Expected payoff: medium for preset UI refreshes.

Risk: effectively none.

### C2. Stop double-refreshing preset role indicators

The current Detection compatibility wrappers do:
- `SCB_RefreshPresetSlots()` -> refresh role indicators;
- `SCB_RefreshPresetPlayers()` -> calls the wrapped `SCB_RefreshPresetSlots()`, then refreshes role indicators again.

One player refresh can therefore sweep role indicators twice.

Fix:
- make one explicit UI owner call;
- ideally separate static slot rendering, player overlay rendering and role-indicator rendering.

Expected payoff: medium.

Risk: low.

### C3. Remove O(40x40) tracker search from role indicators

For each preset row, `SCB_FindTrackerAssignmentForIndicator(slotIndex)` loops all tracker assignments. Tracker assignments are already indexed by logical slot.

Fix: direct `tracker.assignments[slotIndex]` lookup plus the existing validation.

Expected payoff: medium.

Risk: very low.

### C4. Stop recalculating role-indicator geometry twice per row

`SCB_CreatePresetRoleIndicatorPair(row)` calls geometry update when the pair already exists, and `SCB_RefreshPresetRoleIndicators()` calls geometry update again immediately afterwards.

The geometry also only changes when layout/role button sizing changes, not when role evidence changes.

Fix:
- create geometry once;
- refresh geometry only from layout changes;
- role-evidence refresh should only change visibility/color.

Expected payoff: medium UI gain.

Risk: low.

### C5. Cache unchanged art-button state

`SCB_SetArtButtonTexture()` and `SCB_SetArtButtonAvailable()` always write texture/blend/alpha/vertex-color state even when the requested value is already active.

Fix:
- compare cached normal/highlight texture and availability first;
- skip WoW UI API writes when unchanged.

Expected payoff: medium on 40-row preset refreshes.

Risk: low if invalidation is explicit when theme/layout changes.

### C6. Split static slot paint from dynamic player overlay

`SCB_RefreshPresetPlayers()` calls a full `SCB_RefreshPresetSlots()` even when only human presence/assignment changed. This rebuilds class/role textures/tooltips across the whole preset.

Fix:
- static composition rows repaint only when preset slot/class/role/extra/layout changes;
- human join/leave only repaints player overlays/pool and affected logical rows.

Expected payoff: medium.

Risk: medium due editor state interactions.

### C7. Gate target-row painting while UI is hidden

`PLAYER_TARGET_CHANGED` is permanently registered and updates target-command button alpha on every target change even when SCB is hidden.

Fix:
- only refresh on target change while the main frame is visible;
- refresh once from `SCB_MainFrameOnShow()`.

Expected payoff: medium steady-state during normal combat.

Risk: very low.

## Priority D — optional combat-role detection

Role detection is already correctly event-gated when disabled/all roles are confirmed, but when enabled its per-message path is heavier than needed.

Current relevant path:
- parse/normalize the combat source to check `roleDetectionPendingNames`;
- call the older handler, which parses the source again;
- resolve the source by constructing/scanning the current group and normalizing member names;
- scan class spell evidence;
- add evidence;
- refresh the full preset role-indicator UI;
- the wrapper refreshes the whole detection lifecycle after every observation, even when confirmed state did not change.

Improvements:
- make pending detection a normalized-name -> {canonical name, class} map built from Live Roster;
- parse source once and resolve O(1);
- avoid `SCB_CollectGroupMembers()` on combat messages;
- only rebuild/disable lifecycle when confirmation status changes;
- debounce or target the one affected role indicator row;
- periodically prune `SCB.roleEvidenceRecent`, which currently retains name+spell duplicate-suppression keys for the whole session.

Expected payoff: high when combat-role confirmation is enabled, zero impact when disabled.

Risk: medium because Vanilla combat-text parsing is compatibility-sensitive.

## Priority E — debug-mode overhead

Even after 0.8.37 put the debug OnUpdate frame to sleep when developer mode is off, developer mode itself is intentionally expensive:
- combat state is collected every 0.25s even when the combat debug checkbox is not selected;
- pet traces are checked every frame;
- every `SCB_DebugLog` rebuilds the entire log string/editbox;
- once the log exceeds 2000 entries, head removal shifts the whole array.

Also, many normal runtime sites check only `if SCB_DebugLog then`. Because the function always exists, their debug message concatenation/string.format work occurs even when developer debug is off before `SCB_DebugLog` returns.

Improvements:
- guard expensive debug message construction with `SCB.developerDebugEnabled`;
- only poll combat when its checkbox is enabled;
- only scan pet traces while at least one trace exists;
- only run debug OnUpdate while a timed debug activity is actually active;
- append to the log data immediately but debounce editbox reconstruction, and skip editbox painting while the debug frame is hidden;
- use a ring/head index or batch trimming for the debug line buffer.

Expected payoff: small-to-medium in normal play from avoiding debug-string allocations; large while actively debugging.

Risk: low.

## Priority F — metadata / location allocations

`SCB_UpdateActiveRosterLocation()` runs during Active Roster synchronization and currently:
- calls `SCB_GetLocationContext()`, creating a new context table and reading multiple zone APIs;
- computes the signature again;
- `SCB_ResolveLocationExpectedCap()` allocates a capacity-tier table;
- `SCB_GetLocationMaxCapacity()` allocates the same tier table again.

Location state is already maintained by the debounced zone-event handler.

Fix:
- use `SCB.locationContext` / `SCB.lastLocationSignature` when available;
- make capacity tier lists static constants or direct scalar policy rather than newly allocated tables;
- only recompute expected capacity when location changes, explicit preset size changes, or observed count crosses the current cap.

Expected payoff: medium-small but applies to every Active Roster sync.

Risk: low.

## Priority G — queue/data-structure cleanup

Several FIFO structures remove from index 1:
- preset spawn queue;
- pending assumed-spawn intents;
- preset burst plans;
- some maintenance arrays.

Lua shifts the remaining array on each `table.remove(t, 1)`. At current queue sizes this is not a dominant cost, but a 40-man summon does needless array movement during the same busy period as roster churn.

Fix:
- use a head index for FIFO queues, compact/reset when exhausted;
- preserve front-insertion/retry semantics explicitly.

Expected payoff: low-medium.

Risk: medium if queue ordering is changed accidentally. Do after higher-payoff observation work.

## Priority H — startup/memory/dead implementation cleanup

The six owner files still contain many superseded definitions from the pre-consolidation era.

Static audit found 37 SCB global names with multiple definitions (78 definitions total). Not all are dead: several are deliberate compatibility/editor wrappers. However a substantial subset is unconditionally superseded later in TOC load order and is never the runtime implementation.

Concrete examples include older versions of:
- pfUI tank application in Presets.lua;
- maintenance replacement in Presets.lua;
- preset scheduler/rebuild/summon implementation in Presets.lua;
- tracker/snapshot helpers later owned by Roster.lua;
- early Roster identity/reconcile/link helpers superseded by the exact-slot implementations later in the same file;
- earlier manual summon feedback implementations superseded by Communication.lua.

Benefits of deleting proven-dead implementations:
- lower parse/load memory;
- less bytecode/function allocation;
- easier auditing;
- lower risk of accidentally calling/capturing an obsolete implementation during later refactors.

This should be a separately reviewed cleanup after the hot-path fixes. Do not mechanically delete every duplicate: some remaining wrappers intentionally preserve editor or compatibility behaviour.

## Startup UI allocation

`SCB_CreateUI()` eagerly creates the Preset and Options UI at login, including the 8x5 preset row grid and its controls, even though the main SCB window starts hidden.

Possible later optimisation:
- keep the main frame/toggle controls eager;
- lazily build heavy Preset/Options panels on first open;
- debug UI is already lazy.

Expected payoff: startup/load-time and memory only, not raid performance.

Risk: medium because layout and persisted editor state currently assume panels exist.

## Additional low-risk cleanups

- `SCB_CollectGroupMembers()` can use the name returned by `GetRaidRosterInfo(i)` instead of making a separate `UnitName("raid"..i)` call for the same raid member.
- cache/precompute raid/party unit token strings if operation polling remains direct.
- cache class-colour conversions instead of allocating/converting a color table on each UI request.
- world-reconcile should pass its already-fresh observed roster into `SCB_SyncActiveRosterFromObserved()` and saved-session validation rather than observing again.
- auto-loot retry need not arm when auto-loot is configured off.
- remove obviously unused locals/calls left by earlier logical-slot transitions.

## Recommended next runtime build

Before the same-frame 40-man Kick All A/B, one combined post-audit performance build is justified.

Suggested 0.8.39-dev scope:
1. fix ready-tracker re-finalization;
2. make operation membership/subgroup waits roster-revision driven with a safe fallback cadence;
3. convert group count/name helpers to canonical snapshot/one-pass summary;
4. pre-index Live Roster tracker/Active Roster associations;
5. remove the healthy-slot maintenance replacement allocations;
6. use Live Roster metadata for debounced layout;
7. dynamically register debug-only events and gate hidden target UI work;
8. consolidate CHAT_MSG_SYSTEM routing;
9. apply the low-risk preset UI quadratic/dead-scan fixes;
10. guard normal-play debug string construction.

Keep unchanged in that build:
- Kick All pacing at 5 / 0.10s;
- 3-second removal-capacity settle;
- spawn order and identity rules;
- survivor/bootstrap invariant;
- logical human-slot semantics;
- one-second post-arrival stabilization;
- existing combat/server rejection safety.

Runtime gate for this combined build:
- large preset build/rebuild;
- normal paced Kick All;
- one Replace Dead/Missing flow;
- pfUI tank marking;
- human join/leave if convenient.

If that gate passes and performance is at least as good as 0.8.38, the next isolated A/B should restore same-frame mass Kick All.

## Expected end state

During a 40-man Kick All:
- each Blizzard roster event produces one canonical observation;
- no already-finalized tracker reconstruction occurs;
- operation coordinators consume the newest roster revision rather than scanning every rendered frame;
- UI/detection/layout consumers remain coalesced;
- debug-only events do not fire in normal play;
- no pfUI-wide refresh occurs;
- Kick pacing becomes the only remaining artificial limiter, making the subsequent same-frame mass-kick test meaningful.

## Non-negotiable SoloCraft combat-safety invariant

SoloCraft cannot summon bots while any relevant party/raid member is in combat. Combat safety is therefore intentionally more aggressive than ordinary roster observation and must not be weakened by performance work.

Rules:
- combat state is independent of roster revision; a unit can enter or leave combat without any roster event;
- before any bot-add burst, SCB must continue to verify that summoning is combat-safe;
- while a spawn-sensitive phase is blocked by combat, SCB may poll combat state aggressively; this is deliberate safety work, not the redundant roster polling targeted by the performance audit;
- local-player combat remains an absolute block where already defined by the maintenance coordinator;
- existing stale-remote-combat handling remains unchanged unless separately redesigned and runtime-proven;
- server-side summon rejection remains the final authority for races where combat changes between the client check and the command being processed;
- optimisation may share/deduplicate identical combat scans within the same frame or bounded poll interval, but it must not make combat checks roster-event-driven or otherwise create a window where SCB knowingly attempts to summon while observed combat is active.

The performance target is therefore: make membership/identity/subgroup observation revision-driven while keeping combat observation independently aggressive.

## 0.8.39-dev implementation status

Runtime commit: `457b593eaca94a40f311c57b18c9417512c328be`

Implemented as one broad performance build:
- ready trackers now return immediately once role identity is reconciled; unreconciled ready trackers retry only the identity reconciliation and rebuild Active Roster/layout only when reconciliation actually completes;
- canonical roster events now carry an explicit event revision;
- active physical operations consume event-driven Live Roster membership/subgroup state and use one bounded 0.25-second fallback refresh when no roster event arrives; combat polling is independent and unchanged;
- group-presence/count/anchor helpers now consume one Live Roster observation instead of each constructing a full group snapshot;
- Live Roster construction pre-indexes tracker bot/human associations and Active Roster name bindings rather than performing per-member linear scans;
- raid collection captures raid index and group-row metadata in the canonical pass; live-layout observation consumes that metadata instead of performing another raid API scan;
- finalization raid-bot grouping and bootstrap real-G1 detection consume the canonical roster instead of polling GetRaidRosterInfo every frame;
- maintenance-state calculation builds replacement command records only for actually missing/dead slots;
- delayed world reconciliation reuses its one fresh observation for Active Roster/session/button consumers;
- normal mode no longer registers UNIT_COMBAT, UNIT_FLAGS, CHAT_MSG_PARTY, CHAT_MSG_RAID or CHAT_MSG_SAY solely for developer diagnostics; those events wake only when developer debug is enabled;
- CHAT_MSG_SYSTEM is routed once through the main event frame to identity binding, spawn rejection and existing server-safety handling;
- hidden target changes no longer repaint command controls; the target row refreshes when the SCB frame opens;
- preset slot rendering no longer performs an unused human-roster scan;
- role indicators build one logical-slot assignment index per visible refresh, avoid duplicate player-triggered sweeps, and skip geometry writes when role size is unchanged;
- role evidence uses the cached Live Roster, queues UI painting, only rebuilds the role-detection lifecycle on a confirmation transition, and periodically prunes duplicate-observation keys;
- unchanged art-button texture/availability writes are skipped;
- location capacity tier tables are reused rather than allocated per query;
- normal-play debug message strings are not constructed when developer debug is off.

Explicitly unchanged safety/behaviour:
- `SCB_PresetGroupHasCombat()` is byte-for-byte unchanged from 0.8.38;
- maintenance combat-block logic is byte-for-byte unchanged from 0.8.38;
- Kick All remains 5 uninvites per 0.10 seconds;
- removal-capacity settle remains 3.0 seconds;
- post-arrival stabilization remains 1.0 second;
- survivor/bootstrap and logical-slot semantics are unchanged;
- pfUI tank marking remains event-driven with no roster-wide `RefreshUnit` sweep.

Still deferred after this gate:
- same-frame 40-man Kick All A/B;
- mixed-group up-to-five maintenance replacement bursts;
- broader proven-dead implementation cleanup / remaining low-value wrapper cleanup;
- FIFO head-index conversion and other lower-priority micro-optimisations.


## Post-gate implementation status — 0.8.42-dev

The two high-value items intentionally deferred after the 0.8.39 gate have now been built as isolated rollback points:

- `0.8.41-dev` runtime `204b0b305168bc421f05bdd8bfc63c219f0a4b59`: removed the 5 / 0.10s Kick All pacing and restored same-frame mass removal requests from one stable candidate snapshot.
- `0.8.42-dev` runtime `856a38c16e59a99d35462bd61a3f8e201f7fbcbf`: maintenance now sends mixed-group bursts of up to five, binds each joined bot through explicit burst/slot identity, places each bot into its own intended subgroup, and shares one 1.0-second stabilization across the burst.

Combat-safety policy remains unchanged: combat observation stays independent/aggressive and neither build weakens add-time combat checks. 0.8.40 additionally prevents a normal preset rebuild from beginning destructive teardown when combat is already observed; Ctrl-click is the explicit teardown override while bot additions remain combat-gated.

Still deferred after 0.8.42:
- broader proven-dead implementation / remaining low-value wrapper cleanup;
- FIFO head-index conversion and other lower-priority micro-optimisations;
- optional startup/lazy-UI and deeper debug-buffer work.

Runtime status: 0.8.39 passed the practical 10-man gate; 0.8.40-0.8.42 are statically reviewed and intentionally stacked for natural-play testing rather than separate deep gates.


### Runtime result: same-frame Kick All rejected

The 0.8.41 A/B was tested in a 40-player raid and caused a disconnect. This optimization is rejected for the current Vanilla/SoloCraft client-server environment. The safe baseline remains paced Kick All at 5 `UninviteByName` calls per 0.10 seconds. Future removal optimization should not retry same-frame 40-player mass uninvite without a materially different mechanism.


### Shared removal follow-up — 0.8.44-dev

After the same-frame Kick All disconnect, removal pacing is now centralized rather than being a Kick All-only special case. `SCB_KickBots("all"|"dead", options)` owns the 5-per-0.10s queue, and both maintenance dead removal and user-facing Kick All/Kick Dead enter through it. This keeps the tested client/server safety limit consistent across multi-bot removal workflows while preserving the existing maintenance settle and combat rules.
