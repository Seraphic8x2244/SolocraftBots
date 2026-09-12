# SoloCraftBots 0.8 Consolidation Plan

Status: implementation in progress on dev
Behavioural reference: 0.7.14
Current development line: 0.8.15-dev

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
- every remove-then-add lifecycle waits for roster disappearance plus a shared 3.0-second settle before the next add; conversion, subgroup movement and non-add observation may occur during that settle;
- target ownership should be coarse rather than micro-modular;
- `Location.lua` and `Comms.lua` are not mandatory merges into `Presets.lua`: decide after non-preset runtime code has been removed from Presets and the resulting size/cohesion is known.

## Source audit result

The 0.7.14 static/source audit is complete. The main architectural knots were:

1. preset summon scheduling has legacy definitions in Presets/RaidBurst/RaidRefill while Spawn installs the final authoritative runtime; 0.8.11 absorbed the separate preset-rebuild transition layer into Spawn, but 0.8.12 explicitly rolled that absorption back after a runtime client hang. The separate 0.8.14 next-frame rebuild handoff and the 0.8.15 remove -> next-add settle placement are now runtime-proven, so future re-absorption may be reconsidered carefully rather than remaining blocked. Burst/survivor helpers and older scheduler definitions still remain to consolidate;
2. bot identity is split across the current `Raid.lua` owner, the transitional late `RaidIdentity.lua` layer, Detection/refill/tracker reconciliation and still uses a global pending FIFO with competing consumers; the former standalone `Roster.lua`, `RoleTracking.lua` and `RaidLayout.lua` layers have now been reduced/absorbed;
3. ~~human placement is spread across Presets/RaidPlayers/RaidLayout/RaidPresentation and mixes logical intent with Blizzard row presentation;~~ 0.8.5 establishes exact logical human slots and removes RaidPresentation; 0.8.6 absorbs the separate RaidSnapshot layer into RaidPlayers; 0.8.9 folds the remaining standalone RaidLayout implementation into the late identity layer, while RaidPlayers and the combined late identity/layout owner remain transitional;
4. ~~role detection is split across Detection/DetectionShieldSlam/DetectionLifecycle and wraps Options/roster functions late;~~ partially consolidated in 0.8.2/0.8.3: Shield Slam and lifecycle now live in `Detection.lua`, while the user-facing option bridge lives in `Options.lua`;
5. location data and runtime correction were split across Presets/LocationZones/Location.

Full historical details remain in `ARCHITECTURE.md`.

## Final target ownership

### `SoloCraftBots.lua`
Owns bootstrap, shared UI helpers, top-level event dispatch, direct bot commands and raid-mark controls where size remains reasonable.

### `Presets.lua`
Owns preset storage/editor semantics, bot logical slots, exact human logical-slot assignments and Other Players pool. Execution snapshot construction may remain here if compact. Location and preset communications may merge here only if the final file remains coherent after runtime code is extracted.

### `Spawn.lua`
Owns the single preset summon state machine: clean summon, rebuild, explicit LIFO bursts, survivor/bootstrap lifecycle, conversion, human arrangement, combat gate/retry/error abort, shared 3-second removal settle, and interaction with isolated identity bursts.

0.8.11-dev absorbed the standalone `PresetRebuild.lua` transition barrier into `Spawn.lua`, but that specific migration was rolled back in 0.8.12-dev after the runtime client hang. The separate rebuild handoff itself passed runtime testing in 0.8.14-dev, and 0.8.15-dev then verified that conversion/parking may overlap the settle while the next add remains gated. `PresetRebuild.lua` remains the live transition owner for now. Final ownership remains Spawn; re-absorption is now eligible for a future careful consolidation step, but it is not required immediately. Remaining Spawn consolidation also includes the still-live burst/survivor helper layer and older superseded scheduler definitions.

### `Raid.lua`
Owns observed Blizzard roster, logical/live tracker, Active Roster, bot identity, Replace Dead/Missing, role state/detection and pfUI tank integration. Split only if real size/complexity proves an independent ownership boundary.

`Raid.lua` was established in 0.8.7-dev from the former RoleTracking implementation. In 0.8.8-dev the separate `Roster.lua` implementation was folded into it ahead of the existing role-identity layer, so observed Live Roster and persistent Active Roster now have their intended final owner. In 0.8.9-dev the separate late `RaidLayout.lua` file was eliminated by folding its runtime into the already-late `RaidIdentity.lua`; that combined layer remains transitional because its wrappers still depend on post-Spawn load order.

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
- [x] Universal 3-second remove-then-add settle approved.
- [x] Clarify settle placement: it blocks the next add after roster disappearance; non-add conversion/subgroup movement may overlap the timer.
- [x] Location/Comms merge into Presets left open pending final Presets size/cohesion.

### Phase C — start 0.8.0-dev
- [x] First functional consolidation commit bumps TOC to `0.8.0-dev`.
- [x] Remove the standalone `LocationZones.lua` patch layer by absorbing the AQ40 runtime correction into the current location owner.

### Phase D — low-risk consolidation

1. **Location / Presets**
   - [x] Eliminate `LocationZones.lua` late correction layer.
   - [ ] ~~Move the remaining `Location.lua` implementation into `Presets.lua` immediately.~~ Superseded as a mandatory step: reassess after Presets sheds non-preset runtime code.
   - [ ] Centralize runtime zone strings/capacity policy in one final owner, whether that is Presets or a retained Location file.
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
   - [ ] Move survivor/removal policy out of Commands into Spawn/Raid ownership before deleting Commands.

### Phase E — Raid consolidation

- [x] Establish `Raid.lua` as the coherent target owner: 0.8.7-dev renames the former RoleTracking implementation into `Raid.lua` at the same runtime position, deliberately without behaviour changes.
- [x] Move observed roster + Active Roster ownership from `Roster.lua` into `Raid.lua` in 0.8.8-dev, retaining base-roster-before-role-wrapper ordering inside the combined owner.
- [ ] Move remaining tracker/assumption/identity behaviour from the combined late `RaidIdentity.lua` into `Raid.lua` once post-Detection/post-Spawn wrapper dependencies are removed.
- [x] Remove standalone `RaidLayout.lua` in 0.8.9-dev by folding live layout observation into the same late identity layer, preserving its late runtime position rather than moving wrappers earlier unsafely.
- [ ] Move maintenance from `RaidRefill.lua`/Presets wrappers.
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
- [x] Arrange humans into intended Blizzard subgroup derived from logical slot, without expecting them to appear at the saved physical row.
- [x] Preserve bot logical order resolution within subgroup while ignoring humans.
- [x] Remove `RaidPresentation.lua` green-pulse/live-row-as-editor-location model as superseded.
- [x] Runtime-test the exact-slot model with multiple humans before folding RaidPlayers/RaidLayout into final owners: three-human BWL test passed on 0.8.5-dev.

### Phase G — Spawn consolidation

- [x] Keep final `Spawn.lua` scheduler as the proven base.
- [x] Absorb `PresetRebuild.lua` in 0.8.11-dev, preserving the 3-second rebuild settle and party-to-raid transition barrier. **Historical completion; rolled back in 0.8.12-dev after runtime hang.**
- [x] Re-prove the separate `PresetRebuild.lua` handoff after the 0.8.12 rollback. 0.8.14-dev passed clean 5-man, 5-man overwrite, 5 -> 10 survivor/conversion, and repeated A -> B -> C overwrite tests without a second click.
- [x] Verify 0.8.15 settle placement: during 5 -> 10 overwrite, the survivor moved to G8 promptly once raid conversion was visible while the original teardown settle continued; after the parked safety bot was kicked, the following summon burst respected the removal -> next-add delay.
- [ ] Re-absorb `PresetRebuild.lua` into Spawn if/when doing so can preserve the now-proven separate-barrier sequencing; this is eligible again, not mandatory as the immediate next step.
- [ ] Absorb still-live burst/survivor helpers.
- [ ] One explicit operation object/state machine for conversion/bootstrap/survivor/bursts/abort.
- [ ] Apply one shared `BOT_REMOVAL_SETTLE_DELAY = 3.0` policy to every remove-then-add operation.
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
- [ ] Update `ARCHITECTURE.md` from 0.7.14 audit description to the final 0.8 architecture while retaining the historical audit sections.
- [ ] Run the full regression baseline before any main promotion.

## Verification priorities

After each relevant phase, test only affected systems plus a small smoke set. Before main promotion, run full baseline.

Highest-risk scenarios:
- 10-man dungeon from solo using first-real conversion;
- T3 raid-zone bootstrap start;
- preset-over-preset teardown/survivor handoff;
- multiple consecutive LIFO bursts with duplicated class/role assignments;
- humans occupying arbitrary Blizzard rows while suppressing exact intended logical slots;
- saved recurring players present vs absent across repeated preset reloads;
- Replace Dead/Missing with shared 3-second removal settle;
- combat confirmation OFF during a 40-man raid;
- combat confirmation ON still recognizes Shield Slam and sleeps after all tracked bots are confirmed;
- toggling combat confirmation ON/OFF from Options immediately arms/sleeps the detector correctly;
- pfUI tank marks bound to the correct named identities immediately after summon;
- cross-version preset send/request behavior preserves or explicitly rejects exact human-slot intent rather than silently changing it.

## Definition of done

0.8 consolidation is complete when important workflows have one obvious owner; preset intent, live identity and Blizzard presentation are distinct; bot identity is burst-isolated; every replacement path uses the shared removal-settle policy at the actual remove -> next-add boundary; high-volume combat scanning is optional/dormant by construction; the patch files listed in `TARGET-0.8.md` are absorbed or explicitly justified; final Presets/Location/Comms ownership is chosen by actual size/cohesion rather than an arbitrary file-count target; historical migration notes remain recoverable; and the repo docs are enough for a fresh development session to continue safely.
