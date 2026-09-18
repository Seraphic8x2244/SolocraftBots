# SoloCraftBots 0.8 Consolidation Plan

Status: six-owner structural consolidation complete on dev; post-consolidation cleanup/regression remains
Behavioural reference: 0.7.14
Current development line: 0.8.34-dev

## Purpose

0.8.x is an architectural consolidation line. The goal is a small number of coherent owners, explicit state transitions, and removal of load-order wrapper chains while preserving the approved behaviour model.

## Non-negotiable rules

- 0.7.14 remains the stable behavioural reference.
- Functional code changes must bump the addon version in the same commit.
- Documentation-only commits do not bump the addon version.
- The repo docs are the development-direction source of truth.
- Do not silently fix adjacent behaviour while moving code.
- Preserve SavedVariables compatibility unless a migration is explicitly designed.
- One authoritative implementation per public behaviour.
- Prefer explicit coordinator/helper calls over wrapper interception.
- Keep migration commits small enough to identify and revert regressions.
- Update these docs as migrations land.
- Preserve historical audit/decision notes. Mark completed or superseded items rather than deleting the record.

## Approved canonical target

See `TARGET-0.8.md` for the concise target model. Key rules:

- preset slots are logical composition identities;
- humans are saved to exact logical preset slots, suppressing the underlying bot only while present;
- saved present humans snap back to those logical slots on preset load; absent saved humans do not suppress anything;
- Blizzard remains authoritative for live names, classes, subgroup membership and displayed row/order;
- logical slot must never be inferred from physical Blizzard row;
- bot ordering inside a subgroup ignores humans;
- explicit burst plan + SoloCraft join-message order is the primary identity source;
- Blizzard roster reinforces/verifies identity and live location, but does not compete to consume pending assignments;
- resolved role is `confirmedRole` when available, otherwise `assumedRole`, while assumed role is retained;
- the shared 3.0-second settle protects **capacity reuse** after observed roster disappearance; unrelated additions may overlap only while they do not depend on the freed slot;
- `bootstrap` is one temporary-continuity role whose origin may be fresh summon or retained old bot; target preset topology determines party/raid behavior;
- 5-man bootstrap handling must remain party-only and reserve one final required bot assignment dynamically from actual human occupancy;
- raid rebuild should reuse an existing bot bootstrap when one is needed rather than manufacture another temporary bot;
- a client-side abort cannot recall add commands already sent to SoloCraft; forced replacement must first resolve/expire those in-flight adds and reconcile physical state before consuming capacity for the replacement;
- target ownership should be coarse rather than micro-modular;
- `Location.lua` and `Comms.lua` are not mandatory merges into `Presets.lua`: decide after non-preset runtime code has been removed from Presets and the resulting size/cohesion is known.

## Source audit result

The 0.7.14 static/source audit is complete. The main architectural knots were:

1. preset summon scheduling has legacy definitions in Presets/RaidBurst/RaidRefill while Spawn installs the final authoritative runtime. The 0.8.11 direct absorption of PresetRebuild was rolled back after a client hang, so 0.8.18 introduced a staged operation coordinator instead. 0.8.19 moved pending-add recovery, rebuild teardown/settle and next-frame handoff state into `botOperation.rebuild`; 0.8.20 moved survivor/bootstrap state into `botOperation.safety`; 0.8.21 absorbed the temporary coordinator file into Spawn and proved the empty-group 40-man MC bootstrap plus combat-add retry; 0.8.22 removed the safety hydration bridge and passed large-raid destructive/forced replacement stress; 0.8.23 runtime-proved that raid-bootstrap removal settle can overlap unrelated earlier raid bursts. The next knot is to unify fresh bootstrap, retained raid bootstrap and 5-man bootstrap as target-topology policies of one continuity lifecycle;
2. bot identity is split across the current `Raid.lua` owner, the transitional `RaidIdentity.lua` layer, Detection/refill/tracker reconciliation and still uses a global pending FIFO with competing consumers. The former standalone `Roster.lua`, `RoleTracking.lua` and `RaidLayout.lua` layers have been reduced/absorbed. The in-flight summon race no longer blocks architecture work because coordinator replacement/retry has passed repeated forced-replacement and 40-man stress testing; remaining RaidIdentity consolidation is sequenced after Spawn/bootstrap ownership is flattened;
3. ~~human placement is spread across Presets/RaidPlayers/RaidLayout/RaidPresentation and mixes logical intent with Blizzard row presentation;~~ 0.8.5 establishes exact logical human slots and removes RaidPresentation; 0.8.6 absorbs the separate RaidSnapshot layer into RaidPlayers; 0.8.9 folds the remaining standalone RaidLayout implementation into the late identity layer, while RaidPlayers and the combined late identity/layout owner remain transitional;
4. ~~role detection is split across Detection/DetectionShieldSlam/DetectionLifecycle and wraps Options/roster functions late;~~ partially consolidated in 0.8.2/0.8.3: Shield Slam and lifecycle now live in `Detection.lua`, while the user-facing option bridge lives in `Options.lua`;
5. location data and runtime correction were split across Presets/LocationZones/Location.

Full historical details remain in `ARCHITECTURE.md`.

## Final target ownership

### `SoloCraftBots.lua`
Owns namespace/bootstrap, shared UI helpers, top-level event dispatch, direct bot commands and raid-mark controls where size remains reasonable.

### `Presets.lua`
Owns preset storage/editor semantics, bot logical slots, exact human logical-slot assignments and Other Players pool. Execution snapshot construction may remain here if compact. Location and preset communications may merge here only if the final file remains coherent after runtime code is extracted.

### `Spawn.lua`
Owns one authoritative bot-lifecycle operation coordinator: clean summon, rebuild, explicit LIFO bursts, unified bootstrap-continuity lifecycle, target-topology transitions, human arrangement, combat gate/retry/error abort, capacity-aware 3-second removal settle, forced replacement and maintenance replacement execution requested by Raid.

The migration remains deliberately staged. 0.8.18 introduced transitional `SpawnOperation.lua`; 0.8.19 moved rebuild/pending-add/settle state into `botOperation.rebuild`; 0.8.20 moved temporary safety-member state into `botOperation.safety`; 0.8.21 absorbed the coordinator into `Spawn.lua`; 0.8.22 removed the hydration bridge; 0.8.23 proved bootstrap-removal overlap. The next stage is to make fresh raid bootstrap, retained raid bootstrap and 5-man bootstrap explicit policies of one lifecycle before retiring further scheduler scaffolding.

### `Raid.lua`
Owns observed Blizzard roster, logical/live tracker, Active Roster, bot identity, Replace Dead/Missing decisions, role state/detection and pfUI tank integration. Split only if real size/complexity proves an independent ownership boundary.

`Raid.lua` was established in 0.8.7-dev from the former RoleTracking implementation. In 0.8.8-dev the separate `Roster.lua` implementation was folded into it ahead of the existing role-identity layer, so observed Live Roster and persistent Active Roster now have their intended final owner. In 0.8.9-dev the separate late `RaidLayout.lua` file was eliminated by folding its runtime into the already-late `RaidIdentity.lua`. In 0.8.16-dev that late layer stopped owning Spawn abort/session cleanup. The later coordinator stress tests resolve the earlier forced-retry blocker, but remaining explicit identity/live-layout code stays in RaidIdentity until Spawn/bootstrap ownership is stable enough to avoid recreating another late wrapper dependency.

### `Options.lua`
Owns options/settings UI, chat-filter/hide-chat hooks, and the user-facing combat-confirmation option/callback.

### `Debug.lua`
Owns developer diagnostics and debug UI.

## Migration phases

### Phase A — source audit
- [x] Complete 0.7.14 source-level architecture audit.
- [x] Record wrapper/redefinition chains, event/timer ownership and shared-state risks.
- [x] Establish behavioural regression baseline.

### Phase B — architecture agreement
- [x] Exact human logical-slot intent approved.
- [x] Saved present humans auto-activate; saved absent humans leave underlying bot active.
- [x] Blizzard live row remains observational only; no hard-coded physical-row expectation.
- [x] Confirmed role may drive resolved maintenance role while assumed role remains retained.
- [x] Join-message order is primary burst identity; roster is reinforcement/verification, not competing consumption.
- [x] Final ownership should be aggressively consolidated, but file count is not a goal by itself.
- [x] Shared 3-second removal settle approved.
- [x] Clarify settle placement: it protects capacity reuse after observed disappearance; non-capacity-dependent work/additions may overlap.
- [x] Clarify forced retry: old add commands already sent to the server must resolve/expire before replacement teardown/add sequencing can safely consume capacity.
- [x] Unify historical survivor/bootstrap/ID-anchor semantics under one bootstrap-continuity concept with target-specific topology policy.
- [x] Protect 5-man target topology: stay party, reserve one final required bot assignment, derive pre-removal bot count from actual human occupancy.
- [x] Prefer retaining an existing bot bootstrap over manufacturing a new one; skip bot bootstrap entirely where humans already preserve required continuity.
- [x] Location/Comms merge into Presets left open pending final Presets size/cohesion.

### Phase C — start 0.8.0-dev
- [x] First functional consolidation commit bumps TOC to `0.8.0-dev`.
- [x] Remove the standalone `LocationZones.lua` patch layer by absorbing the AQ40 runtime correction into the current location owner.

### Phase D — low-risk consolidation

1. **Location / Presets**
   - [x] Eliminate `LocationZones.lua` late correction layer.
   - [x] Move the remaining `Location.lua` implementation into `Presets.lua` in 0.8.34-dev after final ownership was settled.
   - [x] Centralize runtime zone strings/capacity policy in `Presets.lua`.
   - [ ] Make saved-raid safety consumers use canonical runtime location data rather than localized labels.

2. **Options / Chat filter**
   - [x] Absorb `ChatFilter.lua` into `Options.lua` in 0.8.1-dev.
   - [x] Preserve hide-SCB-chat behaviour and ensure filters do not prevent SCB's internal event observation.

3. **Role detection**
   - [x] Absorb the standalone Shield Slam patch into the main Warrior evidence catalogue in `Detection.lua` in 0.8.2-dev.
   - [x] Remove duplicate Shield Slam combat-source/name parsing by deleting `DetectionShieldSlam.lua`.
   - [x] Flatten `DetectionLifecycle.lua` into `Detection.lua` in 0.8.3-dev without changing OFF-by-default event sleeping behaviour.
   - [x] Move the user-facing role-confirmation option bridge into `Options.lua`, which explicitly calls the detector lifecycle on checkbox changes.
   - [ ] Remove the remaining self-wrapper style around role-detection UI/roster integration when those functions move into their final Raid/Options owners; do not treat the 0.8.3 move as final wrapper cleanup.

4. **Presets / Comms**
   - [ ] ~~Absorb `Comms.lua` into `Presets.lua` as an unconditional low-risk step.~~ Superseded: defer until final Presets size/cohesion is known.
   - [ ] Keep protocol/serialization behaviour unchanged regardless of final file placement.
   - [ ] Audit cross-version exact-human-slot compatibility; older clients must not silently degrade 0.8 logical-slot intent.

5. **Core / Commands**
   - [ ] Move direct commands/raid marks from `Commands.lua` into `SoloCraftBots.lua` if the resulting core remains readable.
   - [ ] Move bootstrap/removal policy out of Commands into Spawn/Raid ownership before deleting Commands.

### Phase E — Raid consolidation

- [x] Establish `Raid.lua` as the coherent target owner: 0.8.7-dev renames the former RoleTracking implementation into `Raid.lua` at the same runtime position, deliberately without behaviour changes.
- [x] Move observed roster + Active Roster ownership from `Roster.lua` into `Raid.lua` in 0.8.8-dev, retaining base-roster-before-role-wrapper ordering inside the combined owner.
- [x] Remove `RaidIdentity.lua`'s post-Spawn scheduler/session cleanup wrappers in 0.8.16-dev; Spawn now owns that state cleanup directly while preserving the old effective ordering.
- [x] Verify ordinary 0.8.16 paths: normal 5-man summon passed and 5-man -> 5-man overwrite passed. `/reload` is not an addon-update mechanism and is not counted as a code-update test.
- [x] Resolve the failed 0.8.16 Ctrl-Summon blocker: 0.8.17 introduced pending-add recovery, 0.8.18 established one operation identity, and 0.8.19 moved rebuild recovery into the coordinator; repeated aggressive 10-bot Ctrl-switch testing passed without a stuck state or wrong final preset.
- [x] Treat forced-retry recovery as runtime-proven at the coordinator level; do not reopen the old 0.8.17-specific gate unless a regression appears.
- [ ] Move the remaining tracker/assumption/identity/live-layout behaviour from `RaidIdentity.lua` into `Raid.lua` after current Spawn/bootstrap migration is stable, then remove the transitional file.
- [x] Remove standalone `RaidLayout.lua` in 0.8.9-dev by folding live layout observation into the same late identity layer, preserving its late runtime position rather than moving wrappers earlier unsafely.
- [ ] Move maintenance decision/execution split out of `RaidRefill.lua`/Presets wrappers: Raid decides records, Spawn coordinator executes physical mutation.
- [ ] Deferred Replace Dead UX/API fallback: keep normal click conservative on `UnitIsDeadOrGhost`; improve the no-match message to make clear that no dead bot was detected; later consider Ctrl-click as a one-shot stronger scan using dead OR a valid roster unit reporting `UnitHealth == 0` with `UnitHealthMax > 0`. Verify Vanilla out-of-range health behaviour before enabling the zero-HP fallback.
- [ ] **Replace Dead/Missing while player is dead:** keep removal/kick actions available where safe, but do not attempt replacement summons while the local player is dead. Surface a clear message such as `Replacement cannot be summoned while you are dead; resurrect, then try Replace Dead/Missing again.` Preserve already-valid maintenance records only while the same location context remains active so the user can retry after resurrection. If release/spirit movement changes zone/location context before retry, abort/bin the pending replacement intent and require a fresh maintenance scan in the new context.
- [ ] **Maintenance burst batching:** Replace Dead/Missing currently processes one destination group at a time. Refactor maintenance to queue up to five replacement intents per summon burst even when those intents span subgroup boundaries. Keep assignments sorted by logical group/slot; identity plans already carry per-assignment `slotIndex` + `group`, so bind each arriving bot to its exact intent before subgroup movement, move each bot to its own destination group, verify all destinations/order, then commit Active Roster bindings. Do not use one shared `state.group` for a mixed burst. Preserve capacity/removal-settle and safety-survivor rules; batch size is at most five and may be smaller when available capacity requires it.
- [ ] Move role evidence/lifecycle from `Detection.lua` into the final Raid owner if size remains coherent.
- [ ] Move pfUI role integration fully into the final Raid implementation; current pfUI integration already resides in Raid.
- [ ] Replace roster wrapper chain with one explicit coordinator.
- [x] Absorb `RaidSnapshot.lua` into the tested exact-slot transitional owner in 0.8.6-dev, removing one late snapshot wrapper layer before final Presets/Raid placement.
- [ ] Remove superseded raid patch files only after runtime proof.

### Phase F — human logical-slot model

- [x] Replace group-only/current-row editor semantics with exact human logical-slot ownership in 0.8.5-dev.
- [x] Unassigned present humans appear in Other Players pool.
- [x] Saved present humans snap to exact logical slots on preset load.
- [x] Saved absent humans do not suppress underlying bots.
- [x] Historical implementation arranged humans toward a subgroup derived from logical slot, without expecting a saved physical row.
- [ ] **Superseding design clarification (2026-09-18):** human logical slots are suppression/composition intent only; do not treat a player's Blizzard party/raid row as editor-controlled. Bot order is different: SCB's summoner can control bot order within a group, so logical bot ordering remains an enforceable/deterministic part of the preset model.
- [x] Preserve bot logical order resolution within subgroup while ignoring humans.
- [x] Remove `RaidPresentation.lua` green-pulse/live-row-as-editor-location model as superseded.
- [x] Runtime-test the exact-slot model with multiple humans before folding RaidPlayers/RaidLayout into final owners: three-human BWL test passed on 0.8.5-dev.
- [ ] Improve raid-layout validation wording: replace the vague `Cannot resolve the current party layout` message with text that explains the actionable requirement — all present players must be assigned to explicit raid preset slots before SCB can resolve/summon the raid layout.
- [ ] **Post-consolidation:** use exact human logical-slot placement at every preset size. Dragging a player chooses which underlying bot intent is suppressed; party versus raid changes slot count only.
- [ ] **Post-consolidation:** add bot-intent drag/drop so logical preset slots can be swapped/reorganised at all supported sizes. For bots this changes the controlled summon/order; for humans the slot still means only which bot intent they suppress, not a controllable Blizzard row.
- [ ] **UI state cleanup:** moving a human between logical preset slots already changes composition intent and marks the preset dirty internally; ensure the Save/button colour/status immediately reflects that unsaved change.
- [ ] **Bootstrap invariant:** a Kick All/safety survivor is temporary continuity infrastructure only and must never satisfy a final preset bot assignment. In raid-sized builds, isolate/park the survivor before normal preset bursts, build deterministic bot order from the requested preset, then remove the survivor. Do not add survivor role/class recycling logic; retaining it as a final bot complicates identity and can change controlled bot order.
- [ ] **Observed regression to investigate:** after Kick All in a 10-man Stockades test, a retained G1 rogue appeared to remain the same named/buffed bot in G1 after summoning an otherwise like-for-like preset. A second test with a no-rogue target correctly moved the rogue survivor to G8 and replaced it. Treat the first outcome as bootstrap-lifecycle/order drift, not intended reuse.

### Phase G — Spawn consolidation

- [x] Keep final `Spawn.lua` scheduler as the proven base.
- [x] Absorb `PresetRebuild.lua` in 0.8.11-dev, preserving the 3-second rebuild settle and party-to-raid transition barrier. **Historical completion; rolled back in 0.8.12-dev after runtime hang.**
- [x] Re-prove the separate `PresetRebuild.lua` handoff after the 0.8.12 rollback. 0.8.14-dev passed clean 5-man, 5-man overwrite, 5 -> 10 survivor/conversion, and repeated A -> B -> C overwrite tests without a second click.
- [x] Verify 0.8.15 settle placement: during 5 -> 10 overwrite, the survivor moved to G8 promptly once raid conversion was visible while the original teardown settle continued; after the parked safety bot was kicked, the following burst respected the removal -> next-add delay.
- [x] Move Spawn scheduler cleanup ownership out of late `RaidIdentity.lua` and into `Spawn.lua` in 0.8.16-dev.
- [x] Add 0.8.17 recovery for aborted-but-already-sent bot adds.
- [x] Introduce one active bot operation object in 0.8.18 and route preset requests/forced intent replacement through it without changing proven physical sequencing.
- [x] Runtime-prove the 0.8.18 foundation: normal 5-man, 5 -> 5, 5 -> 10, and in-flight 10-man -> different 10-man all passed.
- [x] Move rebuild/pending-add/teardown/settle/next-frame-handoff state into `botOperation.rebuild` in 0.8.19.
- [x] Runtime-prove 0.8.19 with repeated unreasonable Ctrl-click interruptions of 10-bot dungeon operations; latest requested preset won and no stuck state/extra click was reported.
- [x] Move persistent survivor/bootstrap handoff state into `botOperation.safety` in 0.8.20 while preserving old physical timing through a one-gate hydration bridge.
- [x] Runtime-prove the 0.8.20 safety migration on 5 -> 5, 5 -> 10 and repeated 10-man Ctrl overwrite survivor paths.
- [x] Absorb `SpawnOperation.lua` into `Spawn.lua` in 0.8.21 at the same effective load position while retaining the bridge for one structural gate.
- [x] Runtime-prove the empty-group 40-man bootstrap on 0.8.21 in Molten Core; recover a group after five combat-related add rejections, then verify a saved-ID destructive 40-man rebuild correctly skips fresh bootstrap.
- [x] Remove the hydration/capture bridge in 0.8.22 and route Spawn/RaidBurst safety reads/writes directly through `botOperation.safety`.
- [x] Runtime-prove 0.8.22 direct safety state with large-raid bootstrap, destructive rebuild and forced replacement while 34 old bots were already live; final requested preset still converged correctly.
- [x] Refine raid-bootstrap removal in 0.8.23 so disappearance + 3.0-second settle can overlap unrelated earlier raid bursts; runtime test passed with normal G2+ cadence and exact final 40-man roster.
- [ ] Unify bootstrap continuity in the next functional gate: fresh raid bootstrap, retained existing-raid bootstrap and 5-man bootstrap become explicit policies of one lifecycle.
- [ ] Existing raid rebuild: when a bot bootstrap is actually needed, retain one existing bot in G8, remove the other old bots, observe teardown + 3.0 seconds, start new G1, then remove bootstrap and overlap its settle using the proven 0.8.23 rule.
- [ ] 5-man bootstrap rebuild: remain party, reserve one required final bot assignment, fill all other required bot assignments allowed by **actual human occupancy**, remove bootstrap, observe absent + 3.0 seconds, then fill reserved assignment. Never hard-code “three then fourth”.
- [ ] Skip bot bootstrap where present humans already preserve required topology/continuity.
- [ ] Never convert a 5-man target to raid because Vanilla 1.12.1 has no safe raid -> party conversion.
- [ ] Absorb transitional `SpawnBootstrap.lua` into `Spawn.lua` once the unified bootstrap lifecycle passes runtime.
- [ ] Retire `PresetRebuild.lua` once its compatibility sentinel/busy checks are explicitly replaced and unified Spawn coordinator path passes runtime.
- [ ] Route Replace Missing / Replace Dead physical execution through the coordinator while Raid continues selecting replacement records.
- [ ] Absorb still-live burst/bootstrap helpers after their state/timing responsibilities have direct Spawn ownership.
- [ ] Apply one shared `BOT_REMOVAL_SETTLE_DELAY = 3.0` policy to every **capacity-dependent** remove -> reuse boundary.
- [ ] Remove superseded scheduler definitions after proof.

### Phase H — identity hardening

- [ ] One active identity burst object at a time.
- [ ] Join-message order binds names to explicit assignments.
- [ ] Roster confirms the same names/classes/subgroups/order without independently consuming pending assignments.
- [ ] Failed/mismatched burst surfaces an error and closes safely instead of shifting later identities.
- [ ] Next burst cannot inherit stale intents.
- [ ] Combat confirmation remains optional and normally OFF.

### Phase I — cleanup/re-audit

- [ ] Remove obsolete wrapper variables, compatibility state and patch-only files.
- [ ] Search again for repeated public function definitions.
- [ ] Verify TOC order reflects true dependencies only.
- [ ] Reassess final Presets size before deciding Location/Comms merge.
- [ ] Update `ARCHITECTURE.md` from 0.7.14 audit description to the final 0.8 architecture while retaining historical audit sections.
- [ ] Run the full regression baseline before any main promotion.

## Verification priorities

After each relevant phase, test only affected systems plus a small smoke set. Before main promotion, run full baseline.

Highest-risk scenarios:
- 5-man bootstrap rebuild remains party-only and reserves exactly one final required bot assignment;
- multi-human 5-man bootstrap derives pre-removal bot count from actual occupancy rather than solo assumptions;
- existing raid rebuild reuses an old bot bootstrap rather than manufacturing another when continuity requires one;
- present humans already preserving topology do not cause an unnecessary bot bootstrap to be retained solely for topology;
- 10-man dungeon from solo using first-real conversion;
- T3 raid-zone fresh bootstrap start;
- preset-over-preset teardown/bootstrap handoff;
- Ctrl-forced replacement after one or more old add commands have left the client but before their bots join;
- multiple consecutive LIFO bursts with duplicated class/role assignments;
- humans occupying arbitrary Blizzard rows while suppressing exact intended logical slots;
- saved recurring players present vs absent across repeated preset reloads;
- Replace Dead/Missing with capacity-dependent 3-second removal settle;
- combat confirmation OFF during a 40-man raid;
- combat confirmation ON still recognizes Shield Slam and sleeps after all tracked bots are confirmed;
- toggling combat confirmation ON/OFF from Options immediately arms/sleeps the detector correctly;
- pfUI tank marks bound to the correct named identities immediately after summon;
- cross-version preset send/request behavior preserves or explicitly rejects exact human-slot intent rather than silently changing it.

## Definition of done

0.8 consolidation is complete when important workflows have one obvious owner; preset intent, live identity and Blizzard presentation are distinct; bot identity is burst-isolated; bootstrap continuity is one target-aware lifecycle rather than origin-specific survivor/bootstrap schedulers; every capacity-dependent replacement path uses the shared disappearance + 3.0-second settle; forced retries cannot race already-sent old add commands; high-volume combat scanning is optional/dormant by construction; patch files listed in `TARGET-0.8.md` are absorbed or explicitly justified; final Presets/Location/Comms ownership is chosen by actual size/cohesion rather than arbitrary file-count targets; historical migration notes remain recoverable; and the repo docs are enough for a fresh development session to continue safely.

## Post-consolidation roster-event hot-path audit — 2026-09-18

- [x] **pfUI tank marking:** 0.8.36-dev removes the live-roster-wide tank reconciliation/raid-frame refresh loop. A bot is marked in `pfUI.uf.raid.tankrole` when its authoritative spawn identity is bound as a tank; tracker calls are idempotent fallback only. Ordinary roster changes do not touch pfUI tank state.
- [ ] **Single Live Roster snapshot per roster revision:** `SCB_HandleRosterChange()` currently refreshes the Live Roster, then `SCB_SyncActiveRosterFromObserved()` forces another `SCB_GetLiveRoster(true)`. The subsequent Replace button refresh calls `SCB_GetActiveMaintenanceRecords()`, which syncs again and forces another fresh Live Roster build. Collapse these consumers onto one authoritative snapshot/revision instead of rebuilding the raid several times for one Blizzard event.
- [ ] **Role-indicator UI invalidation:** the Detection wrapper calls `SCB_RefreshPresetRoleIndicators()` on every roster event. That walks up to 40 preset rows, resets tick visibility/geometry and resolves role state even when no relevant identity/role/preset UI state changed. Refresh only on role/identity/editor changes, or coalesce while roster mutations are in flight.
- [ ] **Live-layout coalescing:** `SCB_RefreshTrackerLiveLayout()` rebuilds all raid positions and walks tracked players/assignments on every roster event. Keep live layout observational, but coalesce burst roster changes to one final/next-frame update rather than processing every intermediate removal/add state.
- [ ] **Auto-promote trigger scope:** `SCB_ApplyAutoPromotePlayers()` scans the raid on every roster event. Re-evaluate only when a human joins/rank state can have changed, not for every bot removal/subgroup mutation.
- [ ] **Role-detection lifecycle invalidation:** when combat-role confirmation is enabled, every roster event rebuilds pending detection names from a freshly rebuilt Live Roster. Maintain/refresh that set only when tracked bot identity/confirmation state changes, or consume the already-built event snapshot.
- [ ] **Roster hot-path target:** one roster observation/build per Blizzard roster revision, then pass/cache that snapshot for Active Roster sync, maintenance button state, identity cleanup, detection and live-layout consumers. UI work should be dirty/edge-triggered, not repeated for each unrelated member mutation.
