# SoloCraftBots 0.8 Consolidation Plan

Status: planning/audit phase
Behavioural reference: 0.7.14
Implementation branch: dev

## Purpose

0.8.x is primarily an architectural consolidation release. The goal is to make ownership explicit, remove patch-layer fragmentation, and reduce hidden TOC-order coupling without intentionally changing established 0.7.14 behavior.

## Non-negotiable rules

- 0.7.14 is the behavior reference.
- Audit before refactor.
- Documentation changes may land during audit without a version bump.
- Functional code changes require a version bump in the same commit.
- No broad UX feature work while consolidation is in progress unless separately agreed.
- Do not silently fix adjacent behavior while moving code.
- Preserve SavedVariables compatibility unless explicitly discussed.
- Prefer one authoritative implementation of each public behavior.
- Prefer explicit helpers/state transitions over wrapper chains and TOC-order interception.
- Keep commits small enough to identify and revert a broken consolidation stage.
- For non-trivial replacements, establish and verify the new path before deleting the old path when practical.

## Target module ownership - draft

This is provisional until the audit proves it.

### `Presets.lua`
Owns:
- preset data model
- preset editor state
- save/load/dirty semantics
- UI interaction with preset intent

Should not own:
- live bot identity
- raid conversion scheduler
- Blizzard live ordering
- combat role detection

### `RaidIdentity.lua`
Owns:
- spawn intent -> live bot name binding
- logical assignment identity
- per-burst identity lifecycle
- name-linked assumed-role source of truth

Goal:
- no cross-burst contamination
- no ambiguous double-consumption by parallel identity mechanisms

### `RaidPlayers.lua`
Owns:
- human assignment to preset raid groups
- player role/spec selection
- live-vs-intended human placement semantics
- UI-facing human placement helpers

Expected rule:
- group = durable preset intent
- within-group row = live presentation

### `RaidLayout.lua`
Owns:
- reading Blizzard raid subgroup/order
- reconciling tracker identity with current live raid layout
- explicit notification to player/presentation layer when live placement differs

Should not rewrite unrelated preset editor data as a side effect.

### `RaidSpawn.lua` (proposed consolidation)
Owns:
- preset summon operation/state machine
- clean start
- rebuild-over-existing
- survivor lifecycle
- bootstrap/safety-bot lifecycle
- party-to-raid conversion
- burst sequencing
- shared server-removal settle behavior

Likely absorbs behavior now split across `Spawn.lua`, `PresetRebuild.lua`, and parts of `RaidBurst.lua`/`RaidSnapshot.lua`, subject to audit.

### `RaidMaintenance.lua` (proposed)
Owns:
- Replace Dead
- Replace Missing
- maintenance-specific removal/replacement lifecycle
- interaction with authoritative identity/tracker APIs

### `RoleDetection.lua` (proposed consolidation)
Owns:
- assumed/confirmed role evidence model
- optional combat-text validation
- event registration lifecycle
- pending unresolved source set
- sleep/wake rules

Likely absorbs `Detection.lua`, `DetectionShieldSlam.lua`, and `DetectionLifecycle.lua` behavior where sensible.

### `Location.lua`
Owns:
- supported client zone strings
- preset-group mapping by location
- location refresh/signature handling
- automatic preset-group switching

`LocationZones.lua` should disappear once its correction is absorbed into the authoritative data source.

## Work phases

### Phase A - audit only

- [x] Create persistent audit documents.
- [ ] Inventory every Lua file and its responsibilities.
- [ ] Inventory every global/public SCB function definition.
- [ ] Find functions defined more than once or wrapped later.
- [ ] Inventory event frames and `OnUpdate` handlers.
- [ ] Inventory major shared state and every writer.
- [ ] Trace preset summon end-to-end.
- [ ] Trace Replace Dead/Missing end-to-end.
- [ ] Trace identity binding end-to-end.
- [ ] Trace raid layout/player presentation end-to-end.
- [ ] Trace role detection/pfUI integration end-to-end.
- [ ] Trace location switching end-to-end.
- [ ] Classify each subsystem: Keep / Move-Merge / Replace Structurally.

Exit criterion: we can explain the active 0.7.14 architecture without relying on historical chat context.

### Phase B - agree target architecture

- [ ] Resolve uncertain ownership discovered in audit.
- [ ] Agree final module names/boundaries.
- [ ] Agree canonical state model.
- [ ] Decide which legacy fallbacks are still required.
- [ ] Define verification cases for each migration phase.

Exit criterion: no significant refactor begins until target architecture is explicit enough to review.

### Phase C - 0.8.0-dev baseline

- [ ] Start 0.8.0-dev functional branch state from audited 0.7.14 behavior.
- [ ] Version bump only when first functional consolidation change lands.
- [ ] No intentional behavior change in baseline consolidation commits.

### Phase D - consolidate low-risk ownership first

Candidate order, subject to audit:

1. Location zone correction -> `Location.lua`
2. Role detection lifecycle -> role detection owner
3. Raid presentation semantics -> player/layout owner
4. Preset rebuild -> spawn owner

Each step:
- move behavior
- remove old wrapper/patch layer where safe
- verify baseline cases
- commit independently

### Phase E - summon / identity state machine

This is the highest-risk consolidation.

Goals:
- one explicit preset summon lifecycle
- one identity binding mechanism
- per-burst identity isolation
- one survivor/bootstrap abstraction after acquisition
- one shared bot-removal settle constant/policy
- eliminate obsolete parallel scheduler state

No implementation should begin until the exact current flow and failure modes are documented.

### Phase F - remove legacy fragmentation

- [ ] Remove wrapper chains made obsolete by new ownership.
- [ ] Remove dead scheduler state and compatibility shims proven unnecessary.
- [ ] Remove duplicate helpers/constants.
- [ ] Re-audit TOC order for genuine dependencies only.
- [ ] Update `ARCHITECTURE.md` to describe the final 0.8 architecture rather than the 0.7.14 baseline.

## Verification philosophy

Every consolidation stage should be checked against `BEHAVIOUR-BASELINE.md`.

When behavior differs, classify it explicitly:
- regression -> fix before proceeding
- intentional improvement -> discuss and document in `DECISIONS.md`
- previously undefined behavior -> discuss before choosing a policy

## Current known high-risk topics

- cross-burst identity contamination in global pending assumed-spawn queue
- roster-delta identity fallback racing system-message identity binding
- nested `SCB_HandleRosterChange` wrappers
- nested raid-finalization wrappers
- RaidLayout mutating editor state, then RaidPresentation restoring it
- rebuild-over-existing using a different settle model from Replace Dead
- old exact human-row persistence overlapping newer presentation-only semantics
- multiple state-reset wrappers clearing old scheduler flags

## Definition of done for consolidation

0.8 consolidation is complete when:
- important workflows have one obvious owner;
- public functions are not repeatedly redefined through load order except for deliberate extension points;
- live state and preset intent are distinct in the data model;
- summon/identity flow has one explicit state machine;
- patch-only files have been absorbed or justified;
- baseline behavior is preserved or every deviation is documented and approved;
- a fresh developer can understand the architecture from the repo documents and code without needing the original chat history.
