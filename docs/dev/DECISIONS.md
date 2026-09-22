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

## 2026-09-18 - Party and raid presets share one logical-slot editor, with different player/bot placement semantics
**Decision:** After structural consolidation, use the same logical-slot editor at every supported preset size. A preset is N underlying bot/composition intents. Dragging a player onto a slot selects exactly which bot intent that player suppresses; dragging a bot intent swaps/reorganises the bot composition/order.

Player logical placement and bot logical placement are not equivalent. SCB cannot rely on or meaningfully control a human's physical row: in party UI every player sees themselves as member 1, and raid human placement may land unpredictably. A player's logical slot therefore records suppression/composition intent only. Bot order, however, is controllable through SCB's summoner, so bot logical order within a group is a real enforced property and should remain deterministic.

**Supersedes:** the earlier same-day correction that treated both player and bot physical placement as equally non-enforceable. That overcorrected the model. The non-enforceable limitation applies to player placement; controlled bot order remains part of SCB behaviour.

**Reason:** This keeps the editor concept uniform without discarding a capability SCB actually has. 5-man still teaches the raid composition model: humans choose which bot intents they replace, while the remaining bots retain controlled summon/order semantics.

**Timing:** Implement after the current ownership/file consolidation and before the final 0.8 regression/main promotion, so the feature lands in final owners instead of adding more transitional wrappers.

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

## 2026-09-13 - One coordinator owns physical bot lifecycle execution
**Decision:** `Spawn.lua` will own one authoritative active operation coordinator/state machine for every workflow that physically mutates the bot roster by sending bot add/remove commands or waiting on the consequences of those commands.

The coordinator accepts different operation intents rather than starting independent pipelines. At minimum these intents include preset summon/rebuild, Replace Missing, Replace Dead and Ctrl-forced replacement of the current preset operation. Different situations may take different state paths, but they share one operation object and one lifecycle policy for pending already-sent adds, combat gates, removals, roster disappearance, 3-second settle, conversion, survivor/bootstrap handling, burst sending, join/identity verification and completion/abort.

**Raid/Spawn boundary:** `Raid.lua` owns observation and maintenance decisions: Active Roster, dead/missing candidates, logical replacement identity/class/role/group and role resolution. Raid requests an operation from Spawn. Raid does not retain an independent physical replacement scheduler, removal timer or add/settle pipeline once migration is complete.

**Forced replacement rule:** Ctrl-click while an operation is active replaces the desired operation handled by the same coordinator. It must not create a second parallel scheduler. Add commands that already reached SoloCraft cannot be recalled; they remain facts that the coordinator must resolve/expire before teardown and the new desired operation can proceed.

**Migration rule:** do not rewrite the working summon system in one step. Introduce the operation object around proven paths first; centralize shared abort/pending-add/removal/settle rules; migrate preset rebuild/survivor/bootstrap; then route Replace Missing/Dead execution through the same coordinator; delete the superseded parallel scheduler state only after runtime proof at each gate.

**Supersedes/refines:** the earlier architectural wording that Spawn owns one authoritative *preset* summon state machine while Replace Dead/Missing may keep a separate execution pipeline in Raid/refill code. The coarse file ownership decision remains valid; this change clarifies the boundary between Raid decision-making and Spawn execution.

**Reason:** recent forced-resummon testing exposed exactly the class of race created by overlapping pipeline ownership: local state can be aborted/restarted while server-side adds, survivor/rebuild state or another scheduler remain active. One physical-operation owner makes current intent, already-issued commands and remove/add safety boundaries explicit.

## 2026-09-13 - Bootstrap settle protects capacity reuse, not unrelated bursts
**Decision:** retain the 3.0-second roster-disappearance settle as the safety boundary for reusing capacity freed by a removed bot, but do not interpret it as a blanket requirement to stop every unrelated bot add.

For ordinary replacement and survivor handoff, the next replacement add directly depends on the removed bot's capacity, so the established rule remains: observe the removed bot absent, wait 3.0 seconds, then add the replacement.

The raid bootstrap is different because it is a temporary extra member used only to create/convert the raid. Once a real Group 1 bot exists, SCB may request bootstrap removal and let its disappearance + 3.0-second accounting window run in parallel with earlier preset bursts while spare target capacity still exists. SCB must still block before the **final preset bot burst that fills the intended composition**, or before final roster tracking if no later bot burst exists, until bootstrap removal has been observed and the 3.0-second settle has completed.

The bootstrap may remain parked in Group 8 for this refinement. Moving it to the eventual final logical subgroup is not required to obtain the overlap and is deferred unless runtime evidence gives that move a separate benefit.

**Refines:** the 2026-09-10 universal remove-then-add wording above. That earlier rule remains correct for capacity-dependent replacement, but was too broad when applied to unrelated additions that do not yet reuse the removed bootstrap's capacity.

**Reason:** a 15/20/40-player preset can continue building earlier groups during the bootstrap's server-accounting window. Stalling G2 immediately after bootstrap removal creates dead time without increasing safety; the actual safety requirement is that the operation must not consume the final freed slot before SoloCraft has settled the removal.

## 2026-09-13 - Bootstrap is a continuity role, not an origin-specific mechanism
**Decision:** use `bootstrap` as the semantic umbrella for a temporary bot occupant whose purpose is to preserve or establish required party/raid/instance continuity while a preset transition is rebuilt. Whether the bot was newly summoned or retained from the old group is an origin detail, not a different lifecycle concept.

A bot bootstrap should exist only when continuity actually needs one. If existing humans already preserve the required party/raid state, SCB does not need to retain an extra bot solely for topology. When a bot bootstrap is required, prefer reusing an existing bot over manufacturing a new one. A new bootstrap is created only when no suitable existing occupant exists and group formation requires one.

**Target topology owns bootstrap policy:** bootstrap state must never imply raid conversion by itself.

For a **5-man target**:
- remain a party; never convert to raid for bootstrap handling because Vanilla 1.12.1 has no safe raid -> party conversion path;
- the bootstrap remains in the party/G1 because a party has no subgroup parking;
- while the bootstrap occupies one slot, reserve exactly one required final bot assignment;
- fill every other required bot assignment that fits alongside present humans and the bootstrap;
- remove the bootstrap, observe it absent, wait the full 3.0-second capacity-reuse settle, then summon that one reserved assignment.

The implementation must derive the pre-removal bot count from the actual preset/human occupancy. Do not hard-code the solo-player case as “summon three, then the fourth”: with multiple humans, fewer bots fit before bootstrap removal. The invariant is **one reserved final bot assignment**, not a fixed number of earlier summons.

For a **raid-sized target**:
- if an existing raid requires a bot bootstrap to preserve continuity, retain one existing bot, park it in G8 when possible, and remove the other old bots;
- observe the old-bot teardown and wait 3.0 seconds before beginning the new G1, because those removed slots are immediately being reused;
- once a genuine new G1 bot exists, remove the bootstrap;
- allow bootstrap disappearance + settle to overlap later raid bursts that do not need its capacity, but gate the first capacity-dependent burst if the settle is still incomplete.

For a **fresh solo raid start**, manufacture a temporary bootstrap only because there is no existing occupant available to establish the required raid state. After raid formation, the path should converge on the same raid-bootstrap lifecycle rather than remain a separate mechanism.

**Supersedes/refines:** long-term architectural distinctions between “survivor”, “T3 bootstrap”, “saved-ID anchor” and similar temporary safety members. Historical field/function names may remain during migration, but the target model is one bootstrap-continuity concept with target-specific topology/capacity policy.

**Reason:** the safety problem is continuity plus one temporarily occupied roster slot. Treating each origin as a separate mechanism duplicates timing/state logic and makes multi-human capacity reasoning error-prone. One bootstrap model lets the coordinator reason from the target preset and actual human occupancy instead.

## Change-control rule
Every functional addon change bumps version in the same commit. Documentation-only audit/decision commits do not bump addon version. Any future semantic reversal must be logged here with both old and new rule.
