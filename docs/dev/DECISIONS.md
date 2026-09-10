# SoloCraftBots Architectural Decisions

This is the durable decision log. If a decision changes, record the superseded rule explicitly rather than rewriting history.

## 2026-09-10 - 0.7.14 is the behavioural reference
- `main` stable is 0.7.14.
- 0.8 consolidation develops on `dev`.
- Source audit precedes functional refactoring; runtime tests prove each migration.

## 2026-09-10 - Repository docs are project memory
Maintain `ARCHITECTURE.md`, `CONSOLIDATION-0.8.md`, `BEHAVIOUR-BASELINE.md`, `TARGET-0.8.md` and this file so a fresh session/developer can recover without chat history.

## 2026-09-10 - Explicit burst identity replaces timestamp inference
Same-burst identity/order comes from explicit burst plans. SoloCraft processes same-burst summon commands reverse/LIFO, so SCB sends reversed commands to produce desired receive order. Timestamps are debug/timeouts only.

## 2026-09-10 - Combat confirmation is optional
Assumed/requested role is sufficient for normal operation. Combat confirmation defaults OFF. OFF means combat listeners are unregistered. ON means confirmed bots are skipped and scanning sleeps when all relevant bots are confirmed; new unresolved bots wake it.

## 2026-09-10 - Source audit completed before 0.8 functional work
The 0.7.14 source audit identified authoritative Spawn scheduling, wrapper chains, competing identity consumers, human layout layering, detection layering and split location authority. Static deductions about dead code still require migration/runtime proof before deletion.

## 2026-09-10 - Human assignment is an exact logical preset slot
**Decision:** A human saved in a preset owns a specific logical group + logical slot and therefore explicitly suppresses the bot assignment underneath that slot while present.

Saved present humans automatically snap to their saved logical slot when the preset loads/reloads. Saved absent humans do not suppress the underlying bot and require no cleanup. New/unsaved humans remain in the lower Other Players pool until assigned.

**Supersedes:** the earlier 0.7.14 rule that durable human intent was primarily subgroup and the preset editor should chase Blizzard's same-group live row with a green mismatch pulse.

**Reason:** real raids contain key slots and filler slots. Blizzard can place humans arbitrarily within a subgroup; allowing that physical row to choose the suppressed bot can consume a key role. The user must control exactly which logical bot slot each human replaces.

## 2026-09-10 - Blizzard row remains live truth, never logical-slot identity
**Decision:** Blizzard roster/order is authoritative for live names, classes, subgroup membership and displayed within-group order. SCB must respect/read it, but must never assume logical GxSy equals Blizzard displayed GxSy.

Humans may appear at subgroup rows 1/2 during formation even when assigned to logical lower slots. Bot order within a subgroup is interpreted while ignoring humans, preserving the useful existing property that human insertion does not shift bot logical identity.

**Reason:** logical preset composition and Blizzard presentation are different coordinate systems.

## 2026-09-10 - Saved named players reactivate only when present
A preset may save named humans such as Valkyries or Gaiamania to exact logical slots. If present, they snap into those logical assignments. If absent, their underlying bot assignments are active and summon normally. Attendance must not require editing the preset.

## 2026-09-10 - Join messages are primary identity; roster reinforces
**Decision:** explicit burst plan + SoloCraft bot-join message order is the primary name-binding mechanism. Blizzard roster verifies existence/class/subgroup/live order and remains live-location authority.

Roster-delta must not independently consume the next pending assignment and race the join-message path. The 0.7.14 global FIFO/competing consumer design is not accepted for 0.8. A mismatch should fail/surface safely rather than silently offset later bots.

**Changes recommendation:** an earlier proposal retained roster-delta as a timeout consumer. We now prefer no competing consumer because wrong identity is worse than an obvious failed bind, especially with combat confirmation normally OFF.

## 2026-09-10 - Confirmed role may drive maintenance without destroying assumed role
Keep `assumedRole` and `confirmedRole` separately. Compute `resolvedRole = confirmedRole or assumedRole`. Once confirmation reaches threshold, resolved role may be used for maintenance/replacement because confirmed behaviour is considered more accurate. Never overwrite/lose the original assumed role.

## 2026-09-10 - Universal remove-then-add server settle
Whenever SCB removes a bot and intends to add another as part of the operation:
1. request removal;
2. observe the removed bot absent from Blizzard roster;
3. wait 3.0 seconds;
4. permit the next addition.

Applies to Replace Dead/Missing where removal occurs, preset rebuild, survivor handoff, bootstrap handoff and future replacement flows. Pure removal does not require the delay.

**Behaviour change from 0.7.14:** 0.7.14 already does this for Replace Dead but preset rebuild has separate timing. 0.8 will make it one shared policy.

## 2026-09-10 - Consolidate aggressively into coherent owners
Approved target is intentionally smaller than the earlier proposed module map:
- `SoloCraftBots.lua`: bootstrap/shared UI/events/direct commands where compact.
- `Presets.lua`: preset/editor/human exact slots/comms/location.
- `Spawn.lua`: complete summon/rebuild/conversion/burst/safety-anchor lifecycle.
- `Raid.lua`: observed roster, tracker, identity, Active Roster maintenance, role detection/resolution, pfUI integration.
- `Options.lua`: options plus chat filter.
- `Debug.lua`: diagnostics.

Supporting locale/assets/bindings remain separate. Split a large owner later only when a genuinely independent responsibility justifies it; do not pre-fragment.

**Supersedes:** earlier proposed separate `Location.lua`, `PresetPlayers.lua`/`RaidPlayers.lua`, `RaidIdentity.lua`, `RaidMaintenance.lua`, `RoleDetection.lua`, `Comms.lua`, `Commands.lua` and pfUI/options separation as the desired final structure.

## Change-control rule
Every functional addon change bumps version in the same commit. Documentation-only audit/decision commits do not bump addon version. Any future semantic reversal must be logged here with both old and new rule.