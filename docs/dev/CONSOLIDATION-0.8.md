# SoloCraftBots 0.8 Consolidation Plan

Status: implementation in progress on dev
Behavioural reference: 0.7.14
Current development line: 0.8.2-dev

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
- every remove-then-add lifecycle waits for roster disappearance plus a shared 3.0-second settle;
- target ownership should be coarse rather than micro-modular;
- `Location.lua` and `Comms.lua` are not mandatory merges into `Presets.lua`: decide after non-preset runtime code has been removed from Presets and the resulting size/cohesion is known.

## Source audit result

The 0.7.14 static/source audit is complete. The main architectural knots are:

1. preset summon scheduling has legacy definitions in Presets/RaidBurst/RaidRefill while Spawn installs the final authoritative runtime;
2. bot identity is split across RoleTracking/RaidIdentity/Detection/refill/tracker reconciliation and uses a global pending FIFO with competing consumers;
3. human placement is spread across Presets/RaidPlayers/RaidLayout/RaidPresentation and mixes logical intent with Blizzard row presentation;
4. role detection is split across Detection/DetectionShieldSlam/DetectionLifecycle and wraps Options/roster functions late;
5. location data and runtime correction were split across Presets/LocationZones/Location.

Full details remain in `ARCHITECTURE.md`.

## Final target ownership

### `SoloCraftBots.lua`
Owns bootstrap, shared UI helpers, top-level event dispatch, direct bot commands and raid-mark controls where size remains reasonable.

### `Presets.lua`
Owns preset storage/editor semantics, bot logical slots, exact human logical-slot assignments and Other Players pool. Execution snapshot construction may remain here if compact. Location and preset communications may merge here only if the final file remains coherent after runtime code is extracted.

### `Spawn.lua`
Owns the single preset summon state machine: clean summon, rebuild, explicit LIFO bursts, survivor/bootstrap lifecycle, conversion, human arrangement, combat gate/retry/error abort, shared 3-second removal settle, and interaction with isolated identity bursts.

### `Raid.lua`
Owns observed Blizzard roster, logical/live tracker, Active Roster, bot identity, Replace Dead/Missing, role state/detection and pfUI tank integration. Split only if real size/complexity proves an independent ownership boundary.

### `Options.lua`
Owns options/settings UI and chat-filter/hide-chat hooks.

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
   - [ ] Flatten `DetectionLifecycle.lua` without breaking OFF-by-default event unregistration or introducing hidden TOC-order dependencies.
   - [ ] Replace late Options wrappers with explicit option ownership/callbacks during that lifecycle consolidation.

4. **Presets / Comms**
   - [ ] ~~Absorb `Comms.lua` into `Presets.lua` as an unconditional low-risk step.~~ Superseded: defer until final Presets size/cohesion is known.
   - [ ] Keep protocol/serialization behaviour unchanged regardless of final file placement.

5. **Core / Commands**
   - [ ] Move direct commands/raid marks from `Commands.lua` into `SoloCraftBots.lua` if the resulting core remains readable.
   - [ ] Move survivor/removal policy out of Commands into Spawn/Raid ownership before deleting Commands.

### Phase E — Raid consolidation

- [ ] Establish `Raid.lua` as the coherent owner.
- [ ] Move observed roster + Active Roster ownership from `Roster.lua`.
- [ ] Move tracker/assumption/identity behaviour from `RoleTracking.lua` and `RaidIdentity.lua`.
- [ ] Move maintenance from `RaidRefill.lua`/Presets wrappers.
- [ ] Move role evidence/lifecycle from Detection files.
- [ ] Move pfUI role integration into Raid.
- [ ] Replace roster wrapper chain with one explicit coordinator.
- [ ] Remove superseded raid patch files only after runtime proof.

### Phase F — human logical-slot model

- [ ] Replace group-only/current-row editor semantics with exact human logical-slot ownership.
- [ ] Unassigned present humans appear in Other Players pool.
- [ ] Saved present humans snap to exact logical slots on preset load.
- [ ] Saved absent humans do not suppress underlying bots.
- [ ] Arrange humans into intended Blizzard subgroup, but never expect them to appear at the saved physical row.
- [ ] Resolve bot logical order within subgroup while ignoring humans.
- [ ] Remove `RaidPresentation.lua` green-pulse/live-row-as-editor-location model once superseded.

### Phase G — Spawn consolidation

- [ ] Keep final `Spawn.lua` scheduler as the proven base.
- [ ] Absorb `PresetRebuild.lua`.
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
- pfUI tank marks bound to the correct named identities immediately after summon.

## Definition of done

0.8 consolidation is complete when important workflows have one obvious owner; preset intent, live identity and Blizzard presentation are distinct; bot identity is burst-isolated; every replacement path uses the shared removal-settle policy; high-volume combat scanning is optional/dormant by construction; the patch files listed in `TARGET-0.8.md` are absorbed or explicitly justified; final Presets/Location/Comms ownership is chosen by actual size/cohesion rather than an arbitrary file-count target; historical migration notes remain recoverable; and the repo docs are enough for a fresh development session to continue safely.
