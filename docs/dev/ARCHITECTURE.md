# SoloCraftBots Architecture Audit

Status: 0.7.14 source audit complete; 0.8 target decisions approved
Branch: dev
Date: 2026-09-10

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
Final runtime is `Spawn.lua`, using queue/burst plans plus survivor/bootstrap/conversion flags. `PresetRebuild.lua` owns a separate teardown state before handing to Spawn. 0.8 will combine these into one operation object/state machine.

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
Replace Dead/Missing uses Active Roster. Replace Dead already waits for removed names to disappear then waits 3.0 seconds before replacement. Preset rebuild uses separate timing. 0.8 makes remove-then-add settle universal.

### Role detection
Vanilla combat-text events -> lifecycle source filter -> Detection parsing/evidence -> confirmed role -> live/pfUI refresh. Shield Slam is a separate extension in 0.7.14. Lifecycle defaults scanner OFF and sleeps when all relevant bots are confirmed.

### Location
Preset data declares mappings, LocationZones patches AQ40 to `Ahn'Qiraj`, Location builds reverse lookup and handles debounced auto-switch. 0.8 folds canonical runtime location data into Presets.

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

### 5. Universal remove-then-add barrier
Whenever an operation removes a bot and then intends to add another: request removal -> observe absent from Blizzard roster -> wait 3.0 seconds -> allow add. Applies across maintenance, preset rebuild, survivor and bootstrap handoffs.

## Approved target ownership
### `SoloCraftBots.lua`
Bootstrap, namespace, shared UI helpers, top-level event dispatch, direct commands/raid marks if compact.

### `Presets.lua`
Preset model/editor/migrations, bot logical intent, exact human logical assignments and pool, save/load/dirty, snapshot if compact, preset comms, canonical location/capacity/auto preset-group logic.

### `Spawn.lua`
One summon/rebuild state machine: bursts, LIFO send, conversion, human arrangement barriers, combat retry/error abort, survivor/bootstrap, shared removal settle, identity-burst sequencing.

### `Raid.lua`
Observed roster, tracker, Active Roster, bot identity, maintenance, role state/detection, pfUI integration. Internally sectioned; split later only if a responsibility proves independently large/cohesive.

### `Options.lua`
Settings/options plus chat filtering.

### `Debug.lua`
Diagnostics/debug UI.

Supporting locales/assets/bindings remain separate.

## Patch/legacy files expected to be absorbed
PresetRebuild, LocationZones/Location, RoleTracking, Detection/ShieldSlam/Lifecycle, RaidIdentity/Players/Snapshot/Burst/Refill/Layout/Presentation, Comms, Commands and ChatFilter are migration sources, not desired permanent architecture. Do not delete any until its live responsibility has moved and relevant tests pass.

## High-risk migration points
- SavedVariables migration for exact human logical slot semantics.
- Keeping Blizzard live row truth without allowing it to overwrite logical composition.
- Correct bot-only ordinal reconciliation when humans occupy arbitrary physical rows.
- Eliminating roster-delta identity consumption without losing useful roster verification.
- Replacing scattered spawn flags with one operation object without changing conversion/safety behaviour.
- Ensuring universal 3-second settle begins after observed roster disappearance, not merely after uninvite request.
- Preserving combat scanner OFF performance and ON sleep/wake lifecycle.

## Audit confidence
Facts above about 0.7.14 ownership are based on the source audit. Claims that older definitions are runtime-dead/superseded are load-order deductions and should be proven during migration before deletion. Approved 0.8 semantics are design decisions, not claims about current 0.7.14 runtime.