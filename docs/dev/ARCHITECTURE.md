# SoloCraftBots Architecture Audit

Status: 0.7.14 source audit complete; 0.8 target decisions approved
Branch: dev
Date: 2026-09-13

This document separates **0.7.14 observed architecture** from **0.8 approved architecture**. Historical 0.7.14 behaviour is not automatically the 0.8 target. `DECISIONS.md` is authoritative for semantic decisions; `TARGET-0.8.md` is the concise target map.

## 0.7.14 audit summary
The addon is functional but fragmented by load-order interception. Several behaviours are defined, wrapped in later files, and sometimes replaced again farther down the TOC.

Key findings:
- final authoritative preset scheduler is `Spawn.lua`; older Presets/RaidBurst/RaidRefill scheduler definitions remain around it;
- bot identity crosses RoleTracking/RaidIdentity/Detection/refill/tracker logic;
- humans cross Presets/RaidPlayers/RaidLayout/RaidPresentation with mutate-then-restore presentation behaviour;
- role detection crosses Detection/DetectionShieldSlam/DetectionLifecycle plus Options wrappers;
- AQ40/runtime location correction is split between Presets/LocationZones/Location and some localized-label safety comparisons;
- roster handling is one of the deepest wrapper chains;
- Active Roster, live roster and tracker are useful distinct concepts but their writers are too distributed.

## 0.7.14 major state
### Preset/editor intent
`SoloCraftBotsDB.presetGroups`, editor slots/players/player roles/player slots and dirty state. 0.7.14 exact-row persistence conflicts with its newer presentation overlay; this is superseded by the 0.8 exact **logical** human-slot model below.

### Execution snapshot
A snapshot freezes preset bot intent and present-human context before summon. This boundary is sound and should survive, even if its code is absorbed into Presets.

### Spawn runtime
Final runtime is `Spawn.lua`, using queue/burst plans plus survivor/bootstrap/conversion flags. `PresetRebuild.lua` owns a separate teardown state before handing to Spawn. 0.8 combines these responsibilities under one operation object/state machine in stages rather than treating every historical safety-member path as a separate scheduler.

### Identity
0.7.14 has `pendingAssumedSpawns`, name-bound assumptions and tracker bot names. Both system join messages and roster-delta logic can associate/consume pending identity. This is the primary structural correctness risk.

### Tracker / Live Roster / Active Roster
- Blizzard/live roster: observation now.
- tracker: logical summon identity plus evolving live raid information.
- Active Roster: sticky bot assignments chosen for maintenance even when a bot is missing.

The conceptual separation is worth retaining; ownership/writes should consolidate into Raid.

### Roles
Assumed/requested and combat-confirmed evidence exist. Confirmation is optional/default OFF. 0.7.14 can let confirmed role mutate maintenance role state; 0.8 resolves this by retaining both and computing `resolvedRole`.

## 0.7.14 workflow maps
### Preset summon
Summon button -> execution snapshot -> rebuild decision -> Active Roster transition -> `SCB_StartPresetSummonSnapshot()` -> tracker/assignment grouping -> conversion/bootstrap/survivor setup -> human arrangement -> explicit logical subgroup bursts -> finalization.

`SCB_PresetSpawnQueueOnUpdate()` in Spawn is authoritative and also ticks related operation states. Older scheduler wrappers are not the desired source for 0.8.

### Identity binding
At a burst boundary SCB arms an explicit plan and appends pending intents. Commands are sent in reverse because SoloCraft receives same-burst summons LIFO.

0.7.14 can then bind through:
1. parsed SoloCraft/system bot-join message; or
2. roster delta detecting a new bot.

Both touch pending identity, allowing a race/stale offset. 0.8 removes competing consumption.

### Raid layout/humans
0.7.14 RaidLayout mutates tracker/editor state toward Blizzard order, while RaidPresentation can restore editor intent and overlay live row presentation. This produced acceptable visual behaviour but conflated composition identity with Blizzard row.

### Maintenance
Replace Dead/Missing uses Active Roster. Replace Dead already waits for removed names to disappear then waits 3.0 seconds before replacement. Preset rebuild uses separate timing. 0.8 consolidates the physical mutation policy under Spawn and refines the settle rule around actual capacity reuse.

### Role detection
Vanilla combat-text events -> lifecycle source filter -> Detection parsing/evidence -> confirmed role -> live/pfUI refresh. Shield Slam is a separate extension in 0.7.14. Lifecycle defaults scanner OFF and sleeps when all relevant bots are confirmed.

### Location
Preset data declares mappings, LocationZones patches AQ40 to `Ahn'Qiraj`, Location builds reverse lookup and handles debounced auto-switch. 0.8 centralizes canonical runtime location data in one coherent owner.

## Approved 0.8 semantic architecture

### 1. Exact logical human slot
A human saved in a preset owns an exact logical group+slot and suppresses precisely the bot underneath that logical slot while present. This is composition intent, not Blizzard row.

Saved present humans snap automatically on preset load/reload. Saved absent humans do not suppress bots. Unsaved present humans remain in Other Players until assigned.

### 2. Blizzard roster remains live truth
Blizzard is authoritative for current name, class, subgroup and displayed within-group order. SCB must read/respect it. But logical GxSy must never be inferred from physical Blizzard GxSy.

Humans can be placed at the top of a subgroup by Blizzard while logically replacing lower/key slots. Bot ordinal mapping inside a subgroup ignores humans, so human insertion cannot shift bot logical identities.

### 3. Identity is explicit and isolated
Primary binding is explicit burst plan + ordered SoloCraft join messages. Blizzard roster verifies/reinforces those names/classes/groups/order; it does not independently consume the next assignment. Each burst closes complete/failed/aborted before another can inherit identity state.

### 4. Role model
Retain `assumedRole` and `confirmedRole`; calculate `resolvedRole = confirmedRole or assumedRole`. Confirmation defaults OFF and events are unregistered. When enabled, confirmed bots are skipped and scanner sleeps when all are resolved. Maintenance may use resolved role; assumed role is never destroyed.

### 5. Removal settle protects capacity reuse
The 3.0-second server-accounting safety rule is attached to **reuse of a removed bot's capacity**, not to every unrelated addition.

Capacity-dependent sequence:
1. request removal;
2. observe the removed bot absent from Blizzard roster;
3. wait 3.0 seconds;
4. allow an addition that depends on that freed slot/capacity.

Ordinary replacement and destructive rebuild remain strict. Raid-bootstrap removal may settle in parallel with later bursts while those bursts still fit without the bootstrap's slot. Final capacity fill/final tracking must not cross an unfinished bootstrap settle.

### 6. Bootstrap is a continuity role
`bootstrap` is the target semantic term for a temporary bot occupant used to establish or preserve party/raid/instance continuity during a transition. Fresh T3 bootstrap, retained raid survivor, instance-ID safety member and 5-man survivor are origin/policy variants of this one role.

A bootstrap is only needed when continuity requires it. If present humans already keep the required topology alive, no extra bot is needed solely for that purpose. When a bot bootstrap is needed, retain an existing bot before manufacturing a new one.

The target preset owns topology:

#### 5-man target
Stay party. Do not convert to raid. Bootstrap stays in the party/G1. Reserve one final required bot assignment while bootstrap occupies one slot, fill every other required bot slot that fits with the actual humans present, remove bootstrap, observe absent + wait 3.0 seconds, then summon the reserved final assignment.

The count before removal is dynamic. With one human this commonly means three target bots before bootstrap removal and the fourth after; with multiple humans fewer pre-removal bot summons fit. The implementation invariant is one reserved final bot assignment, never a hard-coded solo count.

#### Raid-sized target
If a raid already exists and a bot bootstrap is required, retain one existing bot, park it in G8 when possible, remove the other old bots, observe teardown + wait 3.0 seconds, then start the new G1. Once a genuine new G1 bot exists, remove bootstrap and let its disappearance/settle overlap later non-capacity-dependent bursts. Gate only the first burst that actually needs its freed slot.

#### Fresh raid start
Only when no suitable existing member can establish/preserve the raid, manufacture a temporary bootstrap and then converge on the same raid-bootstrap lifecycle.

### 7. One physical-operation coordinator
`Spawn.lua` owns one active bot-lifecycle operation. Preset summon/rebuild, Ctrl-forced replacement and eventually Replace Missing/Dead share one operation identity and lifecycle policy for pending adds, combat gates, removals, capacity-reuse settle, bootstrap/topology handling, burst sending, identity verification and completion/abort.

`Raid.lua` owns observation and maintenance decisions, not a second physical mutation scheduler.

## Approved target ownership
### `SoloCraftBots.lua`
Namespace/bootstrap, shared UI helpers, top-level event dispatch, direct commands/raid marks if compact.

### `Presets.lua`
Preset model/editor/migrations, bot logical intent, exact human logical assignments and pool, save/load/dirty, snapshot if compact, and optionally comms/location if the resulting file remains coherent.

### `Spawn.lua`
One bot-lifecycle state machine: bursts, LIFO send, target-topology transitions, unified bootstrap continuity, human arrangement barriers, combat retry/error abort, capacity-aware removal settle, forced replacement, maintenance execution and identity-burst sequencing.

### `Raid.lua`
Observed roster, tracker, Active Roster, bot identity, maintenance decisions, role state/detection and pfUI integration. Internally sectioned; split later only if a responsibility proves independently large/cohesive.

### `Options.lua`
Settings/options plus chat filtering.

### `Debug.lua`
Diagnostics/debug UI.

Supporting locales/assets/bindings remain separate.

## Patch/legacy files expected to be absorbed
PresetRebuild, LocationZones/Location, RoleTracking, Detection/ShieldSlam/Lifecycle, RaidIdentity/Players/Snapshot/Burst/Refill/Layout/Presentation, Comms, Commands, ChatFilter and transitional `SpawnBootstrap.lua` are migration sources, not desired permanent architecture. Do not delete any until its live responsibility has moved and relevant tests pass.

## High-risk migration points
- SavedVariables migration for exact human logical slot semantics.
- Keeping Blizzard live row truth without allowing it to overwrite logical composition.
- Correct bot-only ordinal reconciliation when humans occupy arbitrary physical rows.
- Eliminating roster-delta identity consumption without losing useful roster verification.
- Replacing scattered spawn flags with one operation object without changing conversion/continuity behaviour.
- Ensuring capacity-dependent settle begins after observed roster disappearance, not merely after uninvite request.
- Correctly deriving bootstrap capacity from **actual human occupancy**, especially 5-man multi-human groups.
- Never converting a 5-man target to raid merely because bootstrap logic is active.
- Reusing an existing raid bot as bootstrap where continuity requires one instead of manufacturing an unnecessary extra bot.
- Preserving combat scanner OFF performance and ON sleep/wake lifecycle.

## Audit confidence
Facts above about 0.7.14 ownership are based on the source audit. Claims that older definitions are runtime-dead/superseded are load-order deductions and should be proven during migration before deletion. Approved 0.8 semantics are design decisions, not claims about current 0.7.14 runtime.
