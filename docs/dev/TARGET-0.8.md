# SoloCraftBots 0.8 Canonical Target

Status: approved architecture direction; implementation in progress
Baseline: 0.7.14

This document is the concise canonical target for 0.8. Where an older audit description differs, this target and `DECISIONS.md` win. Historical notes are retained as the project develops; completed migration items are struck through or recorded in `MIGRATION-LOG.md` rather than deleted.

## Core model

### Preset slots are logical composition identities
A logical preset slot owns the bot intent beneath it: class, role and extra. A human assigned to that slot suppresses that bot only while that human is present. The underlying bot assignment is never destroyed by human occupancy.

A human assignment is exact: player identity -> logical group + logical slot. This means the user chooses exactly which bot a human replaces, protecting key tank/healer/support slots from Blizzard's arbitrary within-subgroup row placement.

Saved humans who are present automatically snap back to their saved logical slot when the preset is loaded/reloaded. Saved humans who are absent do not suppress the underlying bot and require no manual cleanup. Unsaved present humans remain in the lower Other Players pool until assigned.

Implemented in 0.8.5-dev: raid human drag/drop targets exact logical rows; execution snapshots carry the exact human `slotIndex`; group is derived from that slot; group-only legacy assignments without an exact slot remain unassigned until the user chooses a specific slot.

### Logical slot is not Blizzard row
Blizzard raid roster/order remains the source of truth for live names, classes, subgroup membership and displayed within-group order. SCB must never assume logical GxSy equals Blizzard displayed GxSy.

During raid formation humans commonly appear at the top of a subgroup. Their live Blizzard row does not change which logical preset slot they replace.

Bot identity/order inside a subgroup is resolved while ignoring humans. The explicit burst plan and reliable bot-join messages establish bot name -> logical assignment. Blizzard roster then verifies that those names exist, their class, subgroup and live ordering. No hard-coded physical-row expectation is allowed.

Implemented in 0.8.5-dev: Blizzard layout reconciliation records `current*` live placement fields but no longer permutes tracker logical assignments or the preset editor. The 0.7.14 green-pulse/live-row presentation layer was removed as superseded.

### Identity
Primary identity source: explicit burst plan + SoloCraft join-message order.

Blizzard roster is reinforcement/verification and live-location authority, not a competing consumer of the next pending assignment. A mismatch should be surfaced/fail safely rather than silently shift later identities.

The 0.7.14 global pending FIFO and competing roster-delta consumption are not accepted as final architecture. Each burst must be isolated and explicitly completed/failed/aborted before the next can inherit identity state.

### Roles
Keep requested/assumed and confirmed roles separately. Combat confirmation is optional and defaults OFF. When OFF, combat events remain unregistered. When ON, confirmed bots stop being scanned and the scanner sleeps when all relevant bots are confirmed.

Resolved role = confirmedRole when available, otherwise assumedRole. Maintenance may use resolved role, because confirmed role is considered more accurate once the evidence threshold has been reached. Never destructively erase assumedRole.

### Removal settle
Shared rule for every operation that removes a bot and then intends to add another bot: request removal -> observe removed bot absent from Blizzard roster -> wait 3.0 seconds -> permit replacement/addition.

This applies to Replace Dead/Missing where removal occurs, preset-over-preset rebuild, survivor handoff, bootstrap handoff and future replacement operations. Pure removal with no following addition does not need this delay.

## Target file ownership

The goal is a small number of coherent files, not micro-modules. File count is secondary to clear ownership; Location and Comms are explicitly subject to a final sizing/cohesion review after non-preset runtime code has been removed from `Presets.lua`.

### `SoloCraftBots.lua`
- bootstrap/global namespace
- shared UI helpers
- top-level event dispatch
- direct bot commands and raid-mark controls where size remains reasonable

### `Presets.lua`
- preset groups/presets and migrations
- bot logical slot intent
- exact human logical-slot assignments and Other Players pool
- save/load/dirty/editor behaviour
- execution snapshot construction if still compact
- optionally preset communications/protocol if the resulting file remains coherent
- optionally location/capacity/runtime zone data and automatic preset-group switching if the resulting file remains coherent

Earlier target notes proposed folding Location and Comms into this file. That remains a preference, not a hard requirement. Reassess after runtime/scheduler/maintenance code has been extracted from `Presets.lua`; keep either as a separate file if merging would recreate an oversized mixed-responsibility module.

### `Spawn.lua`
- one authoritative preset summon state machine
- clean summon and rebuild-over-existing
- explicit burst planning/LIFO send order
- survivor/bootstrap safety-anchor lifecycle
- party->raid conversion and human arrangement barriers
- combat gate/retry/error abort
- shared 3-second removal-settle use
- interaction with isolated identity bursts

### `Raid.lua`
- observed Blizzard roster
- logical/live raid tracker
- Active Roster maintenance state
- bot identity binding/reconciliation
- Replace Dead / Replace Missing
- assumed/confirmed/resolved role state
- optional combat role detection lifecycle
- pfUI tank-role integration

This file may be internally sectioned. Split only if its real size/complexity proves a separate file has independent ownership; do not pre-fragment it.

### `Options.lua`
- options/settings UI
- chat filter/hide-SCB-chat behaviour and hooks
- user-facing combat-confirmation setting and explicit callback into the role-detection lifecycle

### `Debug.lua`
- developer diagnostics and debug UI

Supporting locale/assets/bindings remain separate as appropriate.

## Files/layers expected to disappear by consolidation
`PresetRebuild.lua`, `LocationZones.lua`, `Location.lua` (if merged), `RoleTracking.lua`, `Detection.lua`, ~~`DetectionShieldSlam.lua`~~, ~~`DetectionLifecycle.lua`~~, `RaidIdentity.lua`, `RaidPlayers.lua`, `RaidSnapshot.lua`, `RaidBurst.lua`, `RaidRefill.lua`, `RaidLayout.lua`, ~~`RaidPresentation.lua`~~, `Comms.lua` (if merged), `Commands.lua`, ~~`ChatFilter.lua`~~ and other patch-only layers should be absorbed into the owners above where practical.

Completed: `LocationZones.lua` was removed in 0.8.0-dev; `ChatFilter.lua` was absorbed into `Options.lua` in 0.8.1-dev; `DetectionShieldSlam.lua` was absorbed into `Detection.lua` in 0.8.2-dev; `DetectionLifecycle.lua` was absorbed into `Detection.lua`/`Options.lua` in 0.8.3-dev; `RaidPresentation.lua` was removed in 0.8.5-dev after the exact-logical-human-slot model superseded live-row editor mirroring. `RaidPlayers.lua` and `RaidLayout.lua` still exist as transitional owners and are expected to fold into final Presets/Raid ownership later. `Location.lua` and `Comms.lua` remain open pending the final Presets sizing/cohesion decision.

This is a target, not permission to delete code before its live responsibility is migrated and verified.

## Migration rule
0.7.14 remains the stable behavioural reference, except for explicitly approved 0.8 behavioural changes recorded in `DECISIONS.md`: exact logical human-slot semantics, resolved-role maintenance policy, non-competing identity binding, and universal 3-second remove-then-add settle.
