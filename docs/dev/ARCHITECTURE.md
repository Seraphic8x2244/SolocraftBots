# SoloCraftBots Architecture Audit

Status: audit in progress
Baseline: 0.7.14
Branch: dev

This document records how the addon actually works before the 0.8.x consolidation. It is descriptive, not aspirational. If code and this document disagree, the code wins until the discrepancy is resolved and this document is updated.

## Audit goals

1. Identify the authoritative implementation for every important workflow.
2. Trace trigger -> function chain -> state read -> state mutation -> downstream effects.
3. Find functions that are redefined or wrapped later in TOC load order.
4. Identify state that is written by multiple modules.
5. Separate durable intent from transient/live state.
6. Record hidden timing, event, and load-order dependencies.
7. Classify each area as Keep, Move/Merge, or Replace Structurally.

No intentional functional changes should be made while this audit is being built.

## Current load order relevant to audit

The 0.7.14 dev TOC currently loads the major systems in this order:

- `SoloCraftBots.lua`
- `Presets.lua`
- `PresetRebuild.lua`
- `LocationZones.lua`
- `Location.lua`
- `Roster.lua`
- `RoleTracking.lua`
- `Detection.lua`
- `DetectionShieldSlam.lua`
- `RaidIdentity.lua`
- `RaidPlayers.lua`
- `RaidSnapshot.lua`
- `RaidBurst.lua`
- `RaidRefill.lua`
- `Spawn.lua`
- `RaidLayout.lua`
- `RaidPresentation.lua`
- `Comms.lua`
- `Commands.lua`
- `Options.lua`
- `DetectionLifecycle.lua`
- `ChatFilter.lua`
- `Debug.lua`
- `ChatFeedback.lua`

This order is already known to be semantically important because several later files wrap or replace functions defined earlier.

## State model - current understanding

### Preset intent

Durable user intent lives in preset data and editor state.

Known structures:
- `SoloCraftBotsDB.presetGroups`
- current preset group/index
- `SCB.presetEditorSlots`
- `SCB.presetEditorPlayers`
- `SCB.presetEditorPlayerRoles`
- `SCB.presetEditorPlayerSlots` (exact-row state added later and now partly superseded by live presentation semantics)
- `SCB.presetDirty`

Important distinction established in 0.7.14:
- raid subgroup assignment is semantic preset intent;
- Blizzard reordering a player within the same subgroup is presentation state and should not dirty the preset.

### Spawn intent

A preset summon produces a snapshot/plan describing the requested bot composition before live names are known.

Known structures/functions to audit fully:
- preset summon snapshot
- burst plans
- assignment entries containing class/role/extra/slot/group
- survivor/bootstrap state
- conversion state

### Live bot identity

The addon binds random SoloCraft bot names to intended logical assignments after summoning.

Known structures:
- `SCB.pendingAssumedSpawns`
- `SCB.assumedRolesByName`
- raid role tracker assignment `botName`

Known architectural concern:
- `pendingAssumedSpawns` is currently a global queue and may allow cross-burst contamination if old intents remain when a later burst joins.
- roster-delta fallback can also consume pending identities and must be audited against system-message binding.

### Live raid tracker

Per-character raid tracking holds the active resolved raid composition and is used by maintenance and layout reconciliation.

Known structure:
- `SoloCraftBotsCharDB.raidRoleTracker`

Fields known to matter:
- ready/mode/size
- assignments
- players
- preset group/index
- layout revision/update time

### Blizzard live layout

`RaidLayout.lua` maps actual raid subgroup/order to tracked logical identities. Historically it also rewrote the working preset to match Blizzard row order and marked it dirty.

0.7.14 adds `RaidPresentation.lua`, which intercepts same-subgroup row changes and restores preset intent while retaining a separate live presentation map.

Known live presentation structures:
- `SCB.liveRaidPlayerSlots`
- `SCB.liveRaidPlayerSlotMismatch`
- tracked preset group/index for presentation

### Role state

The addon has two concepts:
- assumed role: role requested when bot was spawned / inferred from active slot;
- confirmed role: optional combat-text validation.

Resolved live role currently prefers `confirmedRole` over `assumedRole`.

0.7.13 changed combat confirmation into an optional diagnostic feature, default OFF. When enabled it should scan only unresolved bots and sleep once all tracked bots are confirmed.

## Known workflow maps

These are partial and must be expanded with exact function names and ownership during the audit.

### Preset summon

`Preset UI action`
-> create/normalize summon snapshot
-> decide clean summon vs rebuild-over-existing
-> optional removal/survivor handling
-> optional party-to-raid conversion
-> optional bootstrap/safety bot handling
-> arrange humans
-> group burst scheduling
-> send `add ...` commands
-> bind joined bot names to assignment intents
-> finalize/update tracker
-> live roster refresh
-> pfUI tank role refresh
-> preset/live presentation refresh

Audit questions:
- Which function owns each transition?
- Which scheduler is authoritative?
- Which old scheduler state still exists only for cleanup compatibility?
- Where are exact delays defined?
- Which transitions are event-driven versus polled?

### Replace Dead / Missing

maintenance action
-> identify missing/dead tracked slot(s)
-> remove stale bot where needed
-> wait for bot disappearance
-> server settle delay
-> summon replacement using intended slot role/class/extra
-> bind replacement name
-> restore tracker/pfUI/live role state

Known current removal settle for Replace Dead: 3 seconds.

Known unresolved consistency task:
- preset-over-preset rebuild should use the same shared removal settle concept rather than its separate shorter delay.

### Raid layout reconciliation

raid roster event/finalization
-> determine Blizzard subgroup + ordinal for each raid member
-> map live names back to tracked source identities
-> reorder tracker identities to current Blizzard layout
-> refresh Active Roster / Live Roster / pfUI
-> if human changed subgroup: semantic preset change/Unsaved
-> if human changed row only within same subgroup: 0.7.14 presentation-only handling, preset remains Saved

Current complexity:
- `RaidLayout.lua` performs mutation first;
- `RaidPresentation.lua` wraps later and restores preset/editor state for same-group row changes.

This is functionally useful but is a prime Move/Merge candidate for 0.8.x.

### Role confirmation

combat chat event
-> parse source name
-> reject unrelated/human/already-confirmed sources early
-> inspect recognized role spell evidence
-> update evidence state
-> resolve strongest role above threshold
-> mark confirmed
-> refresh detection lifecycle
-> unregister combat events when no unresolved tracked bots remain

When option is OFF, combat event listeners should be unregistered and assumed roles remain authoritative.

## Known wrapper / override hotspots

These are confirmed areas to inspect first:

- `PresetRebuild.lua` overrides/patches preset rebuild behavior from `Presets.lua`.
- `LocationZones.lua` mutates instance zone mapping before `Location.lua` consumes it.
- `RaidPlayers.lua` replaces preset human-layout behavior defined in `Presets.lua` and wraps preset load/save/assignment functions.
- `RaidLayout.lua` wraps raid finalization and roster-change handlers.
- `RaidPresentation.lua` wraps human layout, preset-player refresh, raid finalization, and roster-change handling again.
- `DetectionLifecycle.lua` wraps role detection/evidence, roster handling, and Options functions after `Options.lua` loads.
- `DetectionShieldSlam.lua` extends role evidence separately from the main detection file.

Audit must enumerate every redefinition, not just these known ones.

## Known cross-module state writers

Must be traced precisely:

- `SCB.presetDirty`
- `SCB.presetEditorSlots`
- `SCB.presetEditorPlayers`
- `SCB.presetEditorPlayerSlots`
- `SoloCraftBotsCharDB.raidRoleTracker`
- `SCB.pendingAssumedSpawns`
- `SCB.assumedRolesByName`
- active/live roster state
- pfUI auto tank maps
- preset summon/rebuild scheduler state
- survivor/bootstrap state
- detection pending-name set

## Preliminary classification

### Keep / probably keep

- Explicit distinction between assumed and confirmed roles.
- Optional combat confirmation lifecycle and sleeping behavior.
- Preset-group-as-intent / within-group-row-as-presentation rule.
- Snapshot-first preset summon concept.
- Name-bound bot identity once correctly established.
- Active tracker as the basis for maintenance.

### Move / merge

- `RaidPresentation.lua` -> likely absorb into player/layout ownership.
- `LocationZones.lua` -> absorb into `Location.lua` or authoritative zone data source.
- `DetectionLifecycle.lua` -> absorb into role detection/options ownership.
- `PresetRebuild.lua` -> absorb into authoritative spawn/rebuild lifecycle.
- exact human-row compatibility logic in `RaidPlayers.lua` -> simplify around current intent/presentation model.

### Replace structurally / requires proof before change

- global pending identity queue crossing burst boundaries.
- multiple wrappers around `SCB_HandleRosterChange` and raid finalization.
- parallel or legacy scheduler state cleared defensively in later modules.
- any duplicate roster-delta + system-message identity binding that can race or consume the same intent.

## Audit order

1. Presets + player editor state
2. Snapshot / summon / rebuild / bootstrap / survivor
3. Identity binding
4. Tracker / roster derivation
5. Raid layout + live presentation
6. Replace Dead / Missing
7. Role detection + lifecycle + pfUI integration
8. Location switching
9. Events / OnUpdate / timers
10. Full wrapper/redefinition inventory
11. Full shared-state writer inventory
12. Target architecture proposal

## Recovery rule

Any future developer or ChatGPT session should read this document together with:
- `CONSOLIDATION-0.8.md`
- `BEHAVIOUR-BASELINE.md`
- `DECISIONS.md`

before making 0.8.x architectural changes.
