# SoloCraftBots 0.8 Consolidation Plan

Status: source audit complete; architecture direction approved
Behavioural reference: 0.7.14 plus explicit deviations in `DECISIONS.md`
Implementation branch: dev

## Goal
0.8.x removes wrapper/load-order fragmentation and establishes a small set of coherent owners. Fewer files are useful only when ownership becomes clearer; do not create giant miscellaneous modules without internal structure.

## Non-negotiable process
- Documentation-only commits do not bump addon version.
- First functional consolidation commit starts `0.8.0-dev` and bumps TOC in that same commit.
- Every later functional code change bumps version in the same commit.
- Preserve SavedVariables compatibility or provide explicit migration.
- Migrate and verify behaviour before deleting old paths.
- Static dead-code deductions are not enough to delete runtime code without proof.
- Update docs as decisions change.

## Audit findings to eliminate
1. Final preset scheduling is in `Spawn.lua`, while older Presets/RaidBurst/RaidRefill scheduler layers still exist.
2. `SCB_HandleRosterChange` and related paths are wrapper chains across multiple files.
3. Identity has competing consumers of global pending intent.
4. Human logical intent and Blizzard physical row were conflated/mutate-then-restored.
5. Role detection is spread across Detection, ShieldSlam and Lifecycle wrappers.
6. Runtime location identity is split across maps/patch files/localized labels.
7. Rebuild and maintenance use inconsistent removal-settle concepts.

## Approved final ownership

### `SoloCraftBots.lua`
Bootstrap, namespace, shared UI helpers, top-level event dispatch, direct command/raid-mark controls where compact. Do not put raid state machines here.

### `Presets.lua`
Preset storage/migrations/editor/dirty state; bot logical-slot intent; exact human logical-slot assignments; Other Players pool; saved-player snap semantics; snapshot building if compact; preset comms; canonical location/capacity/runtime zone data and auto preset-group selection.

### `Spawn.lua`
One authoritative preset operation: clean summon, rebuild, explicit burst/LIFO planning, combat retry/error abort, party->raid conversion, human subgroup arrangement, survivor/bootstrap safety anchor, identity-burst barriers, shared 3-second remove-then-add settle.

### `Raid.lua`
Observed Blizzard roster; live tracker; Active Roster; isolated bot identity binding/reconciliation; Replace Dead/Missing; assumed/confirmed/resolved roles; optional combat scanner; pfUI tank integration. Use clear internal sections and split only if later size proves a truly independent owner.

### `Options.lua`
Options/settings plus chat filter/hide-message hooks.

### `Debug.lua`
Developer diagnostics/debug UI.

Locales/assets/bindings remain supporting files.

## Canonical state model

### Logical bot slot
- logicalSlot / logicalGroup
- desiredClass
- desiredRole
- desiredExtra

### Human preset assignment
- stable player identity/name
- logicalGroup
- logicalSlot
- optional player role/spec metadata

If saved player is present: activate assignment and suppress underlying bot. If absent: underlying bot remains active. Unsaved player: Other Players pool.

### Live Blizzard observation
- name
- class
- liveGroup
- liveRow/order
- dead/present state

Blizzard observation never rewrites logical slot merely because its physical row differs.

### Bot identity
- active burst id
- expected ordered logical assignments
- ordered join-message bindings
- verified live roster records
- explicit complete/failed/aborted state

No global cross-burst consumable FIFO in final design.

### Roles
- assumedRole
- confirmedRole
- resolvedRole = confirmedRole or assumedRole

### Preset operation
One operation object should contain phase, snapshot, target size, safety anchor/bootstrap, current logical group/burst, active identity burst, retry/deadline/settle state and abort reason.

## Critical invariants
1. Logical preset slot is not Blizzard row.
2. Blizzard roster is authoritative for live names/classes/subgroups/order.
3. Bot ordinal mapping inside subgroup ignores human rows.
4. Join-message order binds explicit burst identity; roster verifies/reinforces and cannot race-consume the next assignment.
5. A new burst cannot inherit unresolved stale identity from a previous burst.
6. Human saved logical slot determines exactly which bot is suppressed.
7. Absent saved human never suppresses their underlying bot.
8. Every remove-then-add operation waits for roster disappearance + 3.0s.
9. Combat confirmation OFF means no persistent combat scanner.
10. Confirmed role never destroys assumed role.

## Migration sequence

### Phase A — audit [complete]
Source maps, wrapper inventory, state writers, event/OnUpdate ownership and regression baseline documented.

### Phase B — architecture agreement [complete]
Resolved:
- exact human logical slots are durable intent;
- saved present humans auto-snap; absent saved humans do not suppress bots;
- Blizzard row remains live truth but not logical identity;
- confirmed role may drive resolved maintenance role without overwriting assumed;
- join messages primary, roster non-competing verification;
- aggressive final module consolidation approved;
- universal 3-second remove-then-add settle approved.

### Phase C — start `0.8.0-dev`
First functional commit bumps TOC. Prefer introducing canonical shared data/state structures before deleting compatibility layers.

### Phase D — low-risk ownership consolidation
1. Fold location/capacity/auto-group into Presets; remove `LocationZones.lua` patch semantics and localized runtime comparisons.
2. Fold chat filter into Options without changing filtering behaviour.
3. Fold direct Commands into core if size remains reasonable.
4. Fold Comms into Presets while preserving protocol exactly.

### Phase E — human logical-slot model
- migrate saved human group+slot representation compatibly;
- present known saved humans at logical preset slots;
- absent saved humans leave bot active;
- unsaved humans remain in pool;
- stop editor chasing Blizzard physical rows;
- retain Blizzard live roster/order separately;
- bot order reconciliation explicitly ignores humans.

### Phase F — Raid consolidation
Build `Raid.lua` from proven pieces rather than rewriting blind:
- observed roster + Active Roster;
- tracker/live identity;
- role state/pfUI;
- optional detection lifecycle;
- maintenance.
Flatten wrapper chains into explicit coordinator calls.

### Phase G — Spawn/state-machine consolidation
Start from final 0.7.14 `Spawn.lua`, absorb PresetRebuild and live survivor/bootstrap helpers, create one operation state object, implement shared removal-settle barrier and remove superseded scheduler paths only after tests.

### Phase H — identity hardening
Can overlap Spawn work where necessary:
- one active burst object;
- join-message ordered binding;
- roster verification only;
- mismatch/timeout fails visibly/safely;
- explicit close before next burst;
- no cross-burst stale queue.

### Phase I — cleanup/re-audit
Remove absorbed patch files/wrapper variables/dead scheduler code; search for repeated public function definitions; verify TOC order reflects dependencies rather than interception; update `ARCHITECTURE.md` to final 0.8 implementation.

## Verification gates
After each phase run affected tests plus smoke: load/reload, preset save/reselect, 5-man summon, abort/reset, direct commands.

Before main promotion run the full matrix in `BEHAVIOUR-BASELINE.md`, especially:
- ordinary and T3 conversion;
- preset-over-preset survivor flow;
- repeated 40-man bursts;
- exact identity with humans occupying arbitrary Blizzard rows;
- saved-player present/absent behaviour;
- all remove-then-add 3-second barriers;
- confirmation OFF performance and ON sleep behaviour;
- pfUI exact named tank roles;
- AQ40 location;
- comm protocol.

## Definition of done
- six-ish coherent runtime owners rather than patch-layer sprawl;
- one obvious owner per important workflow;
- no mutate-then-restore preset presentation hack;
- no competing identity consumers;
- no cross-burst stale identity;
- one shared remove-then-add settle policy;
- exact human logical replacement slots work independently of Blizzard physical rows;
- optional combat detection is dormant by construction when unused;
- docs allow a fresh session/developer to recover architecture and decisions.