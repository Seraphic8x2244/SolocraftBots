# Development Progress

> Sole live handoff for SoloCraftBots development. Git history carries history; keep this file focused on current constraints, proven behaviour, unresolved questions and the next coherent step.

## Current
- Branch: `dev`
- TOC version: `0.8.92-dev`
- Current implementation head before this handoff update: `8bd3b38f64a17372b884bf5d58a6a701e45ec84b`
- Starting handoff for this slice: `532262e1f83075c15c7a1874d57600bd8c726526`
- Last runtime-tested implementation: `252f6f3acb33f755b0c6d5c34dedc68e0538b15e` (`0.8.88-dev`; failed the layout/summon gate)
- Last runtime-cleared implementation: `ff9725d0336ded2f406661bf9863d88719322124` (`0.8.87-dev`)
- Stable `main`: `0.8.78` at `87e61360ec36c2d9543b2e1bc8606b948b10d6bd`; tested dev source `0200cdb5ef59fc0cb4ef81016237d90ba16e22b9`
- `0.8.91-dev` is superseded and must not be runtime-tested as the acceptance candidate.
- Immediate goal: runtime-test this exact `0.8.92-dev` identity/layout/combat-validation slice before maintenance, visualiser or unrelated cleanup.

## Architecture / ownership
- `SoloCraftBots.lua`: bootstrap/core/shared UI/primitives.
- `Presets.lua`: configured preset intent, editor, snapshots, validation and raid-role tracker creation/finalization.
- `Roster.lua`: observed party/raid reality, human/bot classification, Active Roster, provisional spawn assumptions, combat-role evidence and passive layout classification.
- `Spawn.lua`: sole owner of physical roster mutation through `SCB.botOperation`: summon/rebuild, add, subgroup moves, maintenance/refill, bootstrap/survivor handling.
- `Communication.lua`: PartyBot command transport, command semantics, incoming chat/system feedback and preset communications.
- `Options.lua`: settings/help/debug.
- Preserve one physical-operation coordinator. Presentation code must not mutate roster state.

## Authoritative logical / physical model
- A preset slot is intent. A human assigned to logical slot N suppresses exactly that slot's bot class/role intent.
- Party physical order is client-relative and cannot represent shared logical identity. Never warn because a party human is not in their logical absolute row.
- Raid subgroup membership is enforceable with `SetRaidSubgroup()`; exact row/order inside a subgroup is not.
- During raid rebuild, configured humans must be moved to their intended subgroup by name before bot bursts continue. Re-resolve raid indices immediately before each move.
- Human absolute row is irrelevant to bot identity.
- Full rebuilds intentionally burst one logical group at a time. Human-covered assignments are omitted, so a group with two humans and three bot intents summons exactly three bots.
- Preserve the established reverse-send/LIFO behaviour and the existing per-group settle boundary. Do not pack full-rebuild assignments across groups merely to save a burst.
- Final identity is the settled subgroup's **bot-only ordinal order** mapped to uncovered logical assignments in ascending slot order. This is the proven pre-0.8.87 principle from `6bcc9949222513d4f8e38a90d43071149f162f31`.
- Join-line name -> intent binding is provisional/operational identity. It remains important for mixed-group refill, but it must not overwrite settled full-rebuild ordinal identity.

## 0.8.92 implementation
### Full summon / rebuild identity
- Audited current rebuild against pre-0.8.87 `6bcc994...`.
- Existing `SCB_ArrangePresetHumanGroups()` preserves the proven subgroup-preparation rule: humans are resolved by name, moved only between subgroups, then subgroup membership is freshly verified. No row forcing was added.
- Existing full rebuild still queues uncovered assignments group-by-group and uses `PRESET_WAIT_GROUP` between groups. Cross-group burst packing was deliberately not introduced.
- `SCB_TryFinalizeRaidRoleTracking()` already performs the correct final mapping: it filters humans by using only `initialActive` bot assignments, obtains bots by Blizzard subgroup, requires exact per-group bot counts, then maps bot-only ordinal order to assignment order.
- Fixed the actual identity handoff defect: `SCB_PostFinalizeRaidRoleTracking()` no longer calls `SCB_ReconcileTrackerFromAssumedRoles()` after ordinal finalization. The settled bot-only mapping is authoritative and `tracker.scbRoleIdentityReconciled` is marked complete.
- `SCB_ReconcileTrackerFromAssumedRoles()` remains defined but has no call sites. Do not delete it in this gate; dead/compatibility cleanup remains deferred until runtime proof.
- Once an Active Roster slot exists, live-roster role identity and combat validation prefer that settled slot over provisional `assumedRolesByName`.
- Preset role indicators prefer `assignment.botName` over `assignment.scbAssumedName`.
- Manual Add keeps `slot.role` as the intended requested role rather than replacing it with prior combat-confirmed state.

### Passive layout warning correction
- Removed the invalid `reordered` / absolute-row mismatch mode.
- Parties produce no layout mismatch warning.
- Raids compare expected vs observed **member sets by subgroup only**. A genuine wrong subgroup still produces `regrouped` and the existing slow yellow group pulse/tooltip.
- Within-subgroup Blizzard row differences remain observable in tracker layout data but are not treated as an error and do not warn.
- Removed the obsolete `TIP_PRESET_LAYOUT_REORDERED` locale text.

### Combat-role validation semantics
- Intended/assumed role and combat-confirmed role are now separate state. Combat evidence updates `confirmedRole` and evidence only; it never writes the detected role back into `slot.role`.
- Validation eligibility is derived from the class definition by counting **distinct SCB role values**:
  - meaningful role validation: Warrior, Paladin, Shaman, Druid, Priest;
  - no role validation: Rogue, Hunter, Warlock;
  - Mage is also excluded from the role validator because Fire/Frost are two preset specs but both are `rangedps`. The current role-only combat detector cannot honestly validate Mage spec.
- Removed Mage/Rogue/Hunter/Warlock spell tables from the role sniffer; those classes never enter the pending-name validation lifecycle.
- First tick still means SCB has bound/inferred the bot to the logical assignment.
- The second role-validation indicator is shown only for validation-eligible classes. Existing red/yellow/green evidence progression is retained.
- If combat evidence confirms a different role from the intended assignment, the second tick is replaced by a persistent red `X` for that assignment.
- A confirmed disagreement emits one chat warning plus the existing centre-screen SCB warning, identifying bot name, group, logical slot, intended role, detected role and the last role-unique spell evidence. It is de-duplicated per bot/current assignment disagreement rather than repeated for every spell.
- Full rebuild starts a fresh role-validation epoch by clearing prior combat evidence/recent-observation/mismatch-warning state.

## Refill / maintenance contract — unchanged
- Refill intentionally differs from full rebuild: up to five missing/dead assignments may be mixed across destination groups in one burst.
- Keep exact burst intent records, reverse send, join-assumption identity, subgroup movement and Active Roster replacement binding.
- Do not redesign refill into group-by-group bursts; mixed-group refill saves meaningful time.
- Combat-role validation is a later independent watchdog for any mistaken mixed-burst identity assumption, not a reason to remove that optimisation.

## Other preserved invariants
- Active Roster keeps logical identity/expected state separate from observation. Human-covered bot slots remain dormant intents; if the human leaves before replacement they become missing; if the human returns before replacement they become covered again.
- After a missing human slot has been replaced by a bot, do not auto-kick/free capacity when the human returns.
- Capacity reuse remains: removal observed absent -> 3.0s settle -> dependent add.
- Bootstrap is continuity-only; reuse an existing bot when possible.
- Maintenance remains `botOperation(kind="maintenance")`; player combat is an absolute block and the existing stale-remote-combat allowance remains.
- Manual Add remains coordinated through `botOperation(kind="manual-add")`.
- Raw user-typed `.partybot add ...` remains outside SCB coordinator ownership.
- Taxi safety remains action-time only through `SCB_CanOperateBots(showError)`.
- Never use `UnitHealth()==0` as a dead-state fallback.
- Preset protocol remains `SCBPRESET` protocol 2; snapshots carry logical composition/human slot intent, never generated bot names.
- Command semantics and tested Ctrl-Come/Move/Stay behaviour are unchanged.

## Validation performed for 0.8.92
- Verified `dev` started exactly at handoff `532262e1f83075c15c7a1874d57600bd8c726526`.
- Reviewed the changed call sites and commit diffs after implementation.
- Confirmed no remaining `reordered` warning path / `TIP_PRESET_LAYOUT_REORDERED` reference.
- Confirmed no remaining combat path assigns `confirmedRole` back into `slot.role`.
- Confirmed `SCB_ReconcileTrackerFromAssumedRoles()` has no remaining caller.
- GitHub reports no CI/status checks for the implementation head.
- Canonical Lua 5.0.2 compiler pass is **not claimed**: this shell has no `lua`/`luac`, and the private `VanillaTemplate/tools/lua50` checker could not be materialized into the execution shell. Static diff/call-site review is the available validation here.
- Runtime status: **untested**. This is the next acceptance candidate.

## Focused runtime gate
Test the exact current `0.8.92-dev` build, not 0.8.91:

1. **5-player logical-slot regression**
   - Put the player in a non-first logical preset slot.
   - Summon/re-summon.
   - Confirm the exact underlying bot intent is suppressed/replaced correctly.
   - Confirm no yellow layout warning appears merely because party physical row differs.

2. **10-player subgroup + deterministic identity**
   - Use a preset with at least one human logically in Group 2; starting from a wrong physical subgroup is useful.
   - Summon/re-summon and confirm SCB moves the human into the configured subgroup and completes normally with no stuck `Preset Summon is already in progress`.
   - Prefer the historical repeated Druid-role pattern (tank / melee / healer / ranged) if convenient; it is a strong check that final bot order still matches preset bot-relative order.
   - A within-subgroup row difference must not produce a yellow warning.

3. **Passive actionable warning**
   - After completion, manually move a human to the wrong raid subgroup.
   - Confirm the affected group(s) get the yellow `Group rearranged in Blizzard Raid tab.` warning.
   - Next full Summon/rebuild should correct the subgroup again.

4. **Combat-role indicators**
   - Enable combat role validation.
   - Warrior/Paladin/Shaman/Druid/Priest bots should receive the second evidence indicator and turn green after two recognised role-unique observations.
   - Rogue/Hunter/Warlock should retain only the first binding tick; they should not be scanned for role confirmation.
   - Mage should also retain only the first binding tick for now because this detector does not validate Fire vs Frost spec.
   - If a real binding disagreement is encountered, confirm the role indicator becomes a red `X` and one chat + centre-screen warning names the bot, group/slot, intended role, detected role and evidence.

Do not begin maintenance changes, visualiser work, or unrelated cleanup until this runtime gate is explicitly accepted.

## Deferred / later
- Resummon Group through the existing maintenance/bot-operation lifecycle.
- Audit remaining All-row/server target sensitivity.
- Remove only proven-dead legacy refill/compatibility code after runtime proof.
- Add neutral read-only activity/status surface, then visualiser as a presentation-only consumer.
- Historical regression debt: dungeon -> 10-player scope retest; Replace Dead focused smoke; investigate dead-state observation only if the old omitted-dead-bot case recurs.

## Release note
Do not promote the current dev line. Stable remains `0.8.78` on `main`. Release preparation must compare `main` and `dev` rather than overwrite main because histories have diverged.
