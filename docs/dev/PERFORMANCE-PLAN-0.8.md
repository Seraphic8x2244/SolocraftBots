# SoloCraft Bots 0.8 performance / unnecessary tracking plan

Date: 2026-09-18
Baseline: 0.8.36-dev runtime `4381a87d909e888c753b80fb356c6fb2180357c1`

## Goal

Reduce unnecessary roster scans, UI refreshes and permanent per-frame polling without changing logical-slot, identity, maintenance, survivor or spawn-order semantics.

The core rule is:

> Observe each external state change once, publish/cache that observation, and let interested subsystems consume it. Do not let each subsystem independently rescan the raid or rebuild UI merely because a broad event fired.

Correctness gates remain more important than micro-optimisation. Each phase should be runtime-tested before the next phase changes another ownership boundary.

## Current confirmed amplification

A PARTY_MEMBERS_CHANGED / RAID_ROSTER_UPDATE currently reaches a layered SCB_HandleRosterChange chain and can cause several independent passes over the same state:

1. SCB_GetRosterNames().
2. SCB_ApplyAutoPromotePlayers() scans raid members.
3. SCB_RefreshLiveRoster() rebuilds the full Live Roster.
4. SCB_SyncActiveRosterFromObserved() calls SCB_GetLiveRoster(true), rebuilding it again.
5. SCB_RefreshRefillButton() -> SCB_RefreshReplaceDeadButton() -> SCB_GetActiveMaintenanceRecords() -> SCB_SyncActiveRosterFromObserved() -> another forced Live Roster rebuild.
6. The identity wrapper prunes assumptions using another SCB_GetRosterNames().
7. The Detection wrapper builds another current-name set, relinks assumptions, and refreshes all preset role indicators.
8. If optional role detection is enabled, SCB_RefreshRoleDetectionLifecycle() forces another Live Roster rebuild.
9. The layout wrapper rebuilds all live raid positions and walks the tracker.
10. SoloCraftBots.lua then refreshes preset players, attempts tracker finalization, and refreshes the Replace button again.

This means one physical roster mutation can be observed/recomputed many times before the next mutation arrives. During Kick All, dozens of intermediate roster mutations amplify that work.

0.8.36 already removed the worst pfUI-specific amplification: tank marking is now one-shot at authoritative identity bind, with no roster-wide pfUI RefreshUnit sweep.

## Phase 1 — 0.8.37: one authoritative roster snapshot per roster event

Owner: Roster.lua

High payoff / medium risk.

Create one canonical observation for each PARTY_MEMBERS_CHANGED / RAID_ROSTER_UPDATE handling pass:

- Build Live Roster once at the start of SCB_HandleRosterChange.
- Treat that snapshot as authoritative for the rest of that event.
- Add optional `observed` parameters to Active Roster synchronization / maintenance-state readers where needed.
- SCB_SyncActiveRosterFromObserved(observed) must consume the supplied snapshot rather than forcing SCB_GetLiveRoster(true).
- SCB_GetActiveMaintenanceRecords(observed, syncFirst) should be able to consume the same snapshot without rebuilding.
- Replace button refresh should accept precomputed maintenance counts/state when invoked from roster handling.
- Pruning assumed roles should consume snapshot.byName/current names instead of calling SCB_GetRosterNames again.
- Do not change spawn/maintenance polling sites that intentionally request a fresh observation while waiting for a server-side condition.

Target: one SCB_CollectGroupMembers / SCB_BuildLiveRoster pass per Blizzard roster event in the normal event path.

Runtime gate:
- 5-man join/leave.
- 10/40-man summon.
- Kick All teardown.
- one dead/missing replacement.
- verify Active Roster missing/dead state and Replace button remain correct.

## Phase 2 — 0.8.38: dirty/edge-triggered UI refreshes

Owners: Roster.lua + Presets.lua

High payoff during roster storms / low-medium risk.

Replace broad UI refresh calls with explicit dirty reasons.

Preset role indicators:
- Do not run the 40-row SCB_RefreshPresetRoleIndicators sweep on ordinary roster changes.
- Refresh when a spawn identity is bound, role evidence changes, confirmed role changes, tracker identity changes, preset editor slots change, player logical-slot state changes, or the Presets panel opens.
- If the Presets panel is hidden, mark it dirty and rebuild on next show rather than touching rows off-screen.

Replace Dead/Missing button:
- Separate maintenance-state calculation from button painting.
- Calculate state from the event snapshot once.
- Only repaint label/pulse/tooltip when the effective presentation state changed: missing count, dead count, available/unavailable state, operation active state.
- Do not run a new roster sync just because a button wants to repaint.

Preset player rows:
- During mass bot-only churn, do not rebuild human/player presentation unless the human set or relevant player-slot state changed.
- A bot leaving should not trigger a complete SCB_RefreshPresetPlayers pass when humans are unchanged.

Runtime gate:
- Presets open and closed during summon/Kick All.
- role-confirmation tick updates.
- human join/leave and logical-slot persistence.
- Replace button transitions Missing -> operation -> complete.

## Phase 3 — 0.8.39: coalesce observational raid-layout tracking

Owner: Roster.lua

Medium-high payoff in raids / medium risk.

SCB_RefreshTrackerLiveLayout currently rebuilds all raid positions for every intermediate roster event.

Change it to a queued/coalesced observation:
- Roster event marks live layout dirty.
- A small next-frame or short debounce worker performs one layout rebuild after clustered roster events.
- Further roster events while dirty only reset/coalesce the pending observation; they do not perform another full layout pass.
- Explicit subgroup/order operations that require immediate verification continue using direct fresh checks in Spawn.lua; do not make safety/order barriers depend on delayed cached layout.
- The stored live layout remains observational only and never becomes authoritative for logical human slots.

Target: a 39-bot Kick All should produce one or a small number of tracker-layout rebuilds, not one per disappearing bot.

Runtime gate:
- 40-man Kick All.
- bot subgroup placement during preset build.
- extra human join.
- player physical subgroup changes must still be observed eventually without changing logical-slot ownership.

## Phase 4 — 0.8.40: narrow event-specific bookkeeping

Owner: Roster.lua / bootstrap event dispatcher

Medium payoff / low-medium risk.

Auto-promote:
- Stop scanning/promoting all human raid members on every bot roster mutation.
- Run on PLAYER_ENTERING_WORLD, PARTY_LEADER_CHANGED, detected human join, and any explicit option enable.
- Cache already-promoted/assistant state where safe; never issue PromoteToAssistant repeatedly for unchanged humans.

Role-detection lifecycle:
- Maintain pending role-confirmation names incrementally from identity bind, role-confirmation, replacement and departure.
- Do not rebuild the pending set from a fresh Live Roster for every roster event.
- Existing combat-event registration already sleeps when there is nothing to detect; preserve that.

Assumed-role pruning:
- Remove departed identity entries from the authoritative event delta/snapshot rather than separately rebuilding current-name maps.
- Preserve pending spawn identity semantics and bootstrap exclusions.

Known-bot / pending-add accounting:
- Consume explicit added-name deltas from the roster snapshot rather than separately walking current and previous name maps in multiple wrappers.

Runtime gate:
- summon with auto-promote enabled and disabled.
- human joins while player is leader.
- role detection from assumed -> confirmed.
- replacement and Kick All identity cleanup.

## Phase 5 — 0.8.41: sleep idle OnUpdate workers

Owners: Spawn.lua / Presets.lua / Communication.lua / Options.lua

Medium general CPU payoff / low risk if lifecycle is explicit.

Preset/spawn scheduler:
- SoloCraftBotsPresetSpawnQueueFrame currently has an OnUpdate permanently attached.
- Arm/show/set OnUpdate only while preset queue, coordinator rebuild, maintenance, refill, combat retry, bootstrap wait or other timed spawn work exists.
- Disarm/hide it when all physical-operation state is idle.
- Every entry point that creates work must explicitly wake the scheduler.

Communications:
- SoloCraftBotsCommsFrame currently runs its OnUpdate every frame even with no outgoing transfer, offer, assembly or prompt timeout.
- Keep CHAT_MSG_ADDON event handling permanently registered, but attach/enable OnUpdate only while timed communications state exists.
- Wake on creation of timed comm state; sleep when the last item clears.

Debug:
- Debug update currently runs every frame and returns immediately when developer debug is disabled.
- Arm it only while developer debug polling/batch work is enabled.
- This is low priority because the early return is cheap.

Keep already-good timer patterns:
- Kick queue self-arms and removes its OnUpdate when complete.
- location refresh frame is hidden except while delayed refresh is pending.
- safety/tutorial/button pulse workers are transient/visibility-driven.

Runtime gate:
- idle addon for several minutes.
- preset summon and replacement.
- combat retry.
- communications send/receive/timeout.
- developer debug batch.

## Phase 6 — 0.8.42: collapse historical wrapper chains

Owner: primarily Roster.lua

Medium maintainability payoff; performance benefit depends on prior phases / higher regression risk.

After phases 1-5 are proven, flatten the layered `local Previous/Original...; function wrapper()` history around:
- SCB_HandleRosterChange
- SCB_HandleAssumedRoleSystemMessage
- SCB_TryFinalizeRaidRoleTracking
- SCB_BuildLiveRoster
- replacement binding / detection hooks

Replace wrapper stacking with one owner implementation and explicit helper calls in a documented order.

This is deliberately last. Wrapper flattening before behaviour has been separated into event-driven responsibilities would mix performance cleanup with semantic changes and make regressions harder to diagnose.

Runtime gate:
- full 5/10/40 preset regression.
- Kick All -> rebuild.
- Replace Dead/Missing across groups.
- survivor/bootstrap regression.
- role detection and pfUI tank marking.
- logical player-slot persistence.

## Guardrails

Do not optimise away authoritative observation needed by physical-operation barriers. Spawn/maintenance code is allowed to poll fresh state while explicitly waiting for arrivals, departures, subgroup placement, combat clear or freed capacity.

Do not make Live Roster caching time-based. It should be revision/event-based: fresh on authoritative roster event, reused by consumers of that revision.

Do not infer human logical slots from physical Blizzard raid placement.

Do not merge the 3-second removal-capacity settle with UI/performance debounce. They serve different purposes.

Do not reintroduce roster-wide pfUI tank reconciliation. Tank marking is an identity-bind edge action.

Do not bundle all phases into one build. The goal is measurable reduction with a regression boundary after each ownership change.

## Measurement / debug instrumentation

Before and during each phase, add developer-only counters rather than user-facing logging:
- roster events received;
- Live Roster builds;
- CollectGroupMembers passes;
- Active Roster syncs;
- maintenance-state calculations;
- preset role-indicator refreshes;
- preset player refreshes;
- tracker live-layout rebuilds;
- role-detection pending-set rebuilds;
- auto-promote scans;
- idle/active scheduler frames;
- communications OnUpdate frames.

A debug snapshot after a 40-man Kick All should make amplification obvious. Desired end state is approximately one roster build per roster event, with expensive UI/layout work coalesced and unrelated subsystems showing zero work for irrelevant changes.
