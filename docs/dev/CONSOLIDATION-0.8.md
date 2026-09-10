# SoloCraftBots 0.8 Consolidation Plan

Status: source audit complete; architecture approval phase
Behavioural reference: 0.7.14
Implementation branch: dev

## Purpose

0.8.x is an architectural consolidation line. The goal is not merely fewer files: it is one obvious owner for each behaviour, explicit state transitions, and removal of load-order wrapper chains while preserving agreed 0.7.14 behaviour.

## Non-negotiable rules

- 0.7.14 remains the behaviour reference.
- Documentation/audit commits do not bump addon version.
- First functional consolidation commit starts 0.8.0-dev and bumps the TOC in the same commit.
- No broad new UX work during core consolidation unless separately agreed.
- Do not silently fix adjacent behaviour while moving code.
- Preserve SavedVariables compatibility unless a migration is explicitly designed.
- One authoritative implementation per public behaviour.
- Explicit coordinator/helper calls instead of wrapper interception where practical.
- Keep functional migration commits small and independently reviewable/revertible.
- When static audit says code is dead, verify before deleting if runtime ambiguity exists.
- Update these docs whenever architecture or a decision changes.

## Audit result

Phase A static/source audit is complete. The audit found four main architectural knots:

1. **Spawn lifecycle:** legacy scheduler definitions in Presets/RaidBurst/RaidRefill coexist with final authoritative scheduling in Spawn, while rebuild and survivor helpers remain split elsewhere.
2. **Identity:** one global pending FIFO is consumed by both system-message and roster-delta paths; identity metadata is then also mutated by layout reconciliation.
3. **Human layout:** group intent, persisted exact row, live Blizzard row and editor dirtiness cross Presets, RaidPlayers, RaidLayout and RaidPresentation.
4. **Role detection:** evidence, one-off Shield Slam extension, event sleeping/filtering, Active Roster enrichment and Options UI are spread across Detection, DetectionShieldSlam and DetectionLifecycle.

The complete flow and wrapper inventory is in `ARCHITECTURE.md`.

## Proposed final ownership

### `SoloCraftBots.lua` — shell/shared UI primitives
Own:
- addon bootstrap/global namespace
- shared widget helpers/tooltips
- top-level frame creation and high-level event dispatch
- generic control command sender

Do not let it become the owner of raid state machines. Existing broad UI construction can be split later only if useful; this is not a first-order 0.8 goal.

### `Presets.lua` — durable preset model + editor
Own:
- preset groups/presets and migrations
- bot class/role/extra intent
- human intended raid group
- player role/spec intent
- save/load/dirty semantics
- editor interactions/render data that represent intent

Should not own:
- live bot names
- raid conversion/summon scheduler
- maintenance state machine
- Blizzard live row ordering
- combat role scanner

### `RaidSnapshot.lua` or `PresetExecution.lua` — immutable execution DTO
Recommendation: keep the snapshot concept as a small boundary layer rather than folding it back into the giant Presets file.

Own:
- build immutable summon snapshot from editor + current human roster
- validate snapshot contract
- calculate occupied logical slots/role counts

No scheduling or live name binding.

### `RaidIdentity.lua` — spawn intent -> live bot identity
Own:
- per-burst pending identity object
- join-name binding
- exact logical assignment association
- name-bound requested role/class/extra metadata
- explicit completion/failure/abort of an identity burst

Target invariants:
- only one active identity burst may consume join identities at a time;
- next summon burst cannot arm until current identity burst is resolved or explicitly aborted;
- no stale intent can silently fall through into a later burst;
- a fallback, if retained, observes/reconciles the **same active burst**, never consumes an unrelated global queue.

### `RaidPlayers.lua` — human intent/live placement interface
Own:
- conversion between preset human identity keys and live names
- intended group
- live Blizzard group/row presentation
- player role/spec presentation controls
- live mismatch indicator used by editor

Canonical rule:
- intended group = durable semantic preset data;
- same-group live row = presentation state;
- subgroup change = semantic difference.

Open decision before implementation:
- whether an exact row can ever be an explicit user-authored `preferredSlot`. If yes, it must be a distinct field from `liveSlot`; if no, stop persisting exact rows after migration.

### `RaidLayout.lua` — observed Blizzard layout reconciliation
Own:
- read raid roster subgroup/order
- calculate live slot/group for known identities
- update runtime tracker/live layout
- report semantic subgroup changes separately from row-only presentation changes

Must not:
- mutate preset editor rows and rely on a later file to restore them;
- write UI dirtiness directly except through an explicit semantic-change API.

### `RaidSpawn.lua` — one preset summon state machine
Build from the proven final `Spawn.lua` runtime, not from the older Presets scheduler.

Own:
- clean summon
- rebuild-over-existing
- server removal settle
- survivor/safety-anchor lifecycle
- T3 bootstrap acquisition
- party->raid conversion
- human arrangement barriers
- logical group burst sequencing
- combat gate/retry
- identity burst arming/completion barrier
- final tracker handoff
- complete operation abort/reset

Absorb:
- `PresetRebuild.lua`
- live survivor helpers from `RaidBurst.lua`
- authoritative parts of `Spawn.lua`
- any still-live preset scheduler support from `RaidRefill.lua` only where it belongs to preset summon

Do not mechanically preserve superseded scheduler implementations.

### `RaidMaintenance.lua` — Active Roster maintenance
Own:
- Replace Dead / Missing UI action logic
- choose maintainable Active Roster records
- removal/wait/settle/replacement state machine
- request replacement spawn through shared spawn/identity API
- update Active Roster/tracker binding after replacement

It may share low-level `spawn one burst` and removal-settle helpers with RaidSpawn, but should not duplicate the preset summon state machine.

### `Roster.lua` — observed + maintained roster models
Own:
- group observation (`SCB_CollectGroupMembers`)
- Live Roster construction
- persistent Active Roster schema/lifecycle
- explicit APIs for adoption, missing state, replacement binding
- post-loading-screen continuity reconciliation

Change:
- remove post-hoc wrappers from RoleTracking/Detection; instead call explicit enrichers or include clearly defined fields in one builder pass.

### `RoleDetection.lua` — optional diagnostic role evidence
Own:
- role spell catalogue including Shield Slam
- source parsing/normalization
- evidence scoring and confirmed role
- combat event frame registration lifecycle
- pending unresolved-name set
- early source filtering
- sleep/wake rules

Options ownership:
- `Options.lua` should render/settings-write the checkbox explicitly or use a small registration mechanism; RoleDetection must not wrap four Options functions after load.

Open decision:
- `confirmedRole` currently can overwrite Active Roster `slot.role`. Decide whether replacement uses requested role, confirmed role, or a computed resolved role. Default architectural recommendation: preserve `requestedRole` and `confirmedRole` separately and compute `resolvedRole` without destructive overwrite.

### `Location.lua` — sole runtime location authority
Own:
- canonical, non-localized client zone strings
- group id -> runtime zone mapping
- capacity policy
- context/signature
- auto preset-group switching

Absorb `LocationZones.lua`.

UI labels remain localized and must not be used as runtime identifiers. Saved-raid safety logic in Commands should query this canonical module.

### `Commands.lua` — direct bot commands/raid marks
Keep:
- command matrix
- target validation
- Come/Move behaviour
- spread toggle
- raid mark controls

Move:
- survivor/removal policy that belongs to raid spawn/maintenance.

### `Comms.lua`
Keep cohesive protocol ownership. It consumes/produces snapshot DTOs; update only if snapshot field names/migrations change.

### `Options.lua`
Keep one authoritative Options UI/settings owner. Feature-specific callbacks should be explicit rather than late wrapper patches.

### `ChatFilter.lua`, `ChatFeedback.lua`, `Debug.lua`, `Bindings.xml`, `Locale/*`
Keep as supporting modules. Update references during consolidation, but do not turn them into architecture owners.

## Canonical state model proposed for 0.8

### Preset bot assignment
- `logicalSlot`
- `intendedGroup`
- `requestedClass`
- `requestedRole`
- `requestedExtra`

### Human preset intent
- stable identity key/name
- `intendedGroup`
- role/spec intent
- optional `preferredSlot` only if explicitly approved

### Live identity/layout
- live name
- assignment id/logicalSlot
- `liveGroup`
- `liveSlot`

### Detection
- `requestedRole` / `assumedRole`
- `confirmedRole`
- `resolvedRole` calculated by one documented policy

### Operation
One preset summon operation object should contain:
- phase
- snapshot
- target size
- safety anchor/bootstrap state
- current logical group/burst
- active identity burst
- timing/deadlines/retry counters
- abort reason

Avoid a constellation of unrelated `SCB.preset*`, `scb*`, and compatibility flags where one operation object can express the state.

## Migration phases

### Phase A — audit only

- [x] Create persistent audit documents.
- [x] Inventory all major Lua files/responsibilities.
- [x] Trace authoritative preset summon path.
- [x] Trace identity binding path.
- [x] Trace tracker/Live Roster/Active Roster path.
- [x] Trace raid layout/human presentation path.
- [x] Trace Replace Dead/Missing path.
- [x] Trace role detection/pfUI path.
- [x] Trace location switching.
- [x] Inventory important wrapper/redefinition chains.
- [x] Inventory high-risk shared state writers.
- [x] Inventory important event/OnUpdate ownership.
- [x] Classify modules/subsystems.

Exit criterion met for source-level architecture understanding. Runtime behaviour still must be used to prove each migration.

### Phase B — architecture agreement

Before first 0.8 code change resolve these decisions:

- [ ] Is exact human row ever durable user intent (`preferredSlot`), or is only group saved?
- [ ] Does combat `confirmedRole` influence replacement, or remain diagnostic only?
- [ ] Is roster-delta identity fallback required as a reconciliation observer? If retained, define exact non-competing semantics.
- [ ] Confirm final file names (`RaidSpawn.lua`, `RaidMaintenance.lua`, `RoleDetection.lua`).
- [ ] Confirm whether snapshot stays `RaidSnapshot.lua` or is renamed.

Exit criterion: target ownership + state semantics approved.

### Phase C — begin `0.8.0-dev`

First functional consolidation commit:
- bump TOC to `0.8.0-dev` in same commit;
- no intentional UX behaviour change;
- preserve SavedVariables schemas or add explicit migration.

### Phase D — low-risk consolidation

Recommended order:

1. **Location**
   - absorb `LocationZones.lua`;
   - create canonical runtime zone data;
   - remove locale-string runtime comparison from saved-raid policy where possible;
   - verify location warning/auto-swap/AQ40.

2. **RoleDetection**
   - merge Shield Slam catalogue;
   - merge Lifecycle event/filter logic;
   - remove Options wrappers using explicit option ownership;
   - preserve OFF-by-default and sleep behaviour.

3. **Human layout/presentation**
   - flatten Presets -> RaidPlayers -> RaidLayout -> RaidPresentation semantics;
   - introduce explicit intent/live fields;
   - remove mutate-then-restore behaviour.

4. **Roster enrichment**
   - flatten BuildLiveRoster and Active Roster detection wrappers;
   - establish one roster coordinator per roster event.

### Phase E — maintenance extraction

- extract Replace Dead/Missing from giant Presets/runtime wrappers into RaidMaintenance;
- introduce shared removal-settle helper/policy;
- preserve current 3-second maintenance settle;
- prove Active Roster semantics independently of selected preset.

### Phase F — preset summon/state machine

Highest risk. Do after preceding concepts have clear ownership.

- start from final Spawn scheduler;
- absorb PresetRebuild and live RaidBurst safety helpers;
- represent survivor/bootstrap as one safety-anchor lifecycle after acquisition;
- integrate identity burst completion as an explicit barrier;
- use shared removal settle for rebuild-over-existing as separately approved behaviour change;
- remove superseded Presets/RaidBurst/RaidRefill preset scheduler code only after proof.

### Phase G — identity hardening

Can be done alongside Phase F if necessary, but keep commit boundaries reviewable.

Target:
- one active burst object;
- expected assignment count;
- system message primary binding;
- optional roster reconciliation cannot consume outside active burst;
- completed/failed/aborted burst explicitly closes;
- next burst cannot inherit stale identities.

### Phase H — cleanup/re-audit

- remove obsolete wrapper variables and 0.7.x scheduler state;
- remove patch-only files now absorbed;
- consolidate constants and naming;
- ensure TOC order reflects true dependency, not interception;
- search again for repeated public function definitions;
- update `ARCHITECTURE.md` from 0.7.14 audit to final 0.8 architecture.

## Verification matrix

Every phase should run only the scenarios affected by it plus a small smoke set; before main promotion run full baseline.

Core smoke after any state/lifecycle change:
- addon loads/reloads without Lua error;
- preset panel load/save/dirty works;
- 5-man summon from solo;
- abort/forced retry leaves no stuck operation;
- direct commands unaffected.

Location phase:
- world/10man/BRS/raid zones;
- AQ40 resolves from `Ahn'Qiraj`;
- dirty preset blocks auto-swap;
- saved raid survivor policy still behaves conservatively.

Detection phase:
- OFF => combat events dormant;
- ON => only unresolved tracked bots processed;
- confirmation sleeps when complete;
- replacement/new bot re-arms;
- Shield Slam still counts;
- pfUI manual tank flags untouched.

Human/layout phase:
- same-group Blizzard row move => display moves, Saved remains, green pulse/tooltip;
- subgroup move => semantic difference/Unsaved;
- bot identity/role moves with actual live identity;
- reselect preset restores intended state.

Maintenance phase:
- dead only;
- missing only;
- dead+missing;
- unidentified/unmaintainable slot;
- 3-second removal settle;
- replacement bound to correct Active Roster/tracker slot;
- combat gate.

Spawn/identity phase:
- 5-man solo;
- 10-man dungeon solo;
- >5 ordinary solo first-real conversion;
- T3 solo bootstrap conversion;
- rebuild over existing with survivor;
- already-party and already-raid starts;
- multiple consecutive logical groups;
- duplicate class/role commands in same burst;
- server combat retry;
- exact `Cannot add bots right now.` abort;
- verify no pending identities remain after each burst/operation;
- immediate pfUI tank icons match intended roles.

## Known 0.7.14 defects/ambiguities: do not accidentally canonize

- global pending identity queue can leak across bursts;
- roster-delta identity binding can compete with membership-message binding;
- preset-over-preset rebuild has different settle semantics from Replace Dead;
- exact human row persistence overlaps newer presentation-only rule;
- optional confirmed role can alter Active Roster role/replacement semantics;
- runtime zone identity is split between canonical-ish map and localized labels;
- old scheduler definitions remain in files despite final Spawn scheduler superseding them.

These are not all automatically approved behavioural fixes. Each semantic change still requires an explicit decision.

## Definition of done

0.8 consolidation is complete when:
- important workflows have one obvious owner;
- one roster event does not traverse a stack of feature wrappers;
- preset intent, live identity and live presentation are distinct fields/models;
- one preset summon state machine owns conversion/survivor/bootstrap/bursts;
- one identity mechanism owns each active burst;
- Active Roster maintenance is independent and explicit;
- RoleDetection is optional/dormant by construction, not by late patching;
- canonical runtime zones are separate from localized display labels;
- patch-only files are absorbed or intentionally justified;
- no known superseded scheduler remains executable without reason;
- baseline behaviour is preserved or deviations are documented/approved;
- repo docs are sufficient for a fresh developer/session to continue safely.