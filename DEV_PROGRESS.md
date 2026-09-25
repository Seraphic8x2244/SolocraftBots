# Development Progress

> Sole live handoff for SoloCraftBots development. Git history carries history; keep this file focused on current constraints, proven behaviour, unresolved questions and the next coherent step.

## Current
- Branch: `dev`
- TOC version: `0.8.94-dev`
- Current implementation head before this handoff update: `e8357eb4c7f7cea0c1d5cf4f6928a072a66f0655`
- Runtime-tested baseline for this slice: `f9760a20c176f5d0123b9f7829fbc5b32e6b93c6` (`0.8.92-dev`; runtime files correspond to implementation `8bd3b38f64a17372b884bf5d58a6a701e45ec84b`)
- Stable `main`: `0.8.78` at `87e61360ec36c2d9543b2e1bc8606b948b10d6bd`; tested dev source `0200cdb5ef59fc0cb4ef81016237d90ba16e22b9`
- `0.8.92-dev` passed the summon/logical-slot/subgroup gate. Do **not** ask the user to repeat the stuck-summon test; they explicitly tested two different 10-player presets and accepted it.
- `0.8.94-dev` contains only the follow-up presentation/combat-validation delta and is the next runtime candidate.
- Immediate goal: validate the targeted subgroup-row highlight and revised combat-role evidence UI. Do not reopen accepted summon/rebuild identity work unless a new regression appears.

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

## 0.8.94 implementation
### Full summon / rebuild identity — accepted baseline from 0.8.92
- `SCB_ArrangePresetHumanGroups()` preserves the proven subgroup-preparation rule: humans are resolved by name, moved only between subgroups, then subgroup membership is freshly verified. No row forcing exists.
- Full rebuild queues uncovered assignments group-by-group and uses `PRESET_WAIT_GROUP` between groups.
- `SCB_TryFinalizeRaidRoleTracking()` filters humans, obtains bots by Blizzard subgroup, requires exact per-group bot counts, then maps bot-only ordinal order to assignment order.
- `SCB_PostFinalizeRaidRoleTracking()` does not reconcile settled ordinal identity back through provisional join assumptions.
- `SCB_ReconcileTrackerFromAssumedRoles()` remains defined but has no call sites. Keep cleanup deferred until later.
- Active Roster settled identity outranks provisional `assumedRolesByName`; combat evidence never rewrites intended `slot.role`.

### Passive layout warning
- Party absolute-row mismatch logic remains removed.
- Raid mismatch classification is subgroup-only.
- 0.8.92 runtime: manually moving the user to the wrong raid subgroup correctly produced a warning and the next full Summon put them back into the configured subgroup.
- 0.8.92 presentation problem: the whole-group yellow pulse was so subtle that the user initially thought the build was stale.
- 0.8.93/0.8.94 presentation change: mismatch classification also returns the exact logical slot(s) whose known member is in the wrong subgroup. Only those character rows receive a stronger gold pulse; the whole group background no longer pulses. The group tooltip remains available.
- This is presentation only; it does not change subgroup correction or physical roster ownership.

### Combat-role validation semantics
- Intended role and combat-confirmed role remain separate state. Evidence never mutates the requested role/preset.
- Validation-eligible classes remain Warrior, Paladin, Shaman, Druid and Priest.
- Rogue/Hunter/Warlock remain excluded. Runtime 0.8.92 confirmed Rogue correctly receives no second validation indicator.
- Mage remains excluded because Fire/Frost are preset specs but both map to `rangedps`; the current role validator cannot honestly distinguish the spec.
- First green tick = SCB bound the bot to that logical assignment.
- Revised second-indicator semantics:
  - no role evidence yet: **no second marker**;
  - one recognised independent observation: yellow check;
  - two observations agreeing with intended role: green check;
  - confirmed different role: persistent red `X` plus active warning.
- The former red stage-0 marker was removed because it made “not yet observed” look like an error.
- A confirmed mismatch now opens a real `StaticPopup` (unless the user has explicitly hidden SCB screen warnings) and also writes the chat warning. The transient 2.4-second centre message is no longer the primary mismatch alert.
- Expanded frequent but role-specific evidence:
  - Warrior melee adds Sweeping Strikes and Death Wish alongside Mortal Strike/Bloodthirst/Whirlwind.
  - Druid bear adds Demoralizing Roar, Enrage, Frenzied Regeneration, Feral Charge and Bash.
  - Druid cat adds Claw, Rip, Pounce, Ravage and Tiger's Fury alongside existing cat abilities.
- `Faerie Fire (Feral)` is not role-specific by spell name, but 0.8.94 combines the observed cast with native `UnitPowerType(unit)`: rage = bear/tank evidence, energy = cat/melee evidence. It never consults the intended role to make that classification.
- Full rebuild still starts a fresh role-validation epoch by clearing prior evidence/recent-observation/mismatch-warning state.

## Refill / maintenance contract — unchanged
- Refill intentionally differs from full rebuild: up to five missing/dead assignments may be mixed across destination groups in one burst.
- Keep exact burst intent records, reverse send, join-assumption identity, subgroup movement and Active Roster replacement binding.
- Do not redesign refill into group-by-group bursts; mixed-group refill saves meaningful time.
- Combat-role validation is an independent watchdog for mistaken mixed-burst identity assumptions, not a reason to remove that optimisation.

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

## Runtime results
Exact `0.8.92-dev` baseline:
1. **5-player logical-slot regression: PASS.**
   - User confirmed non-first logical player placement suppresses/replaces the correct underlying bot intent.
   - No invalid party row warning reported.
2. **10-player subgroup + deterministic summon: PASS.**
   - User tested two separate 10-player presets with the player in Group 1 in one preset and Group 2 in the other.
   - No stuck `Preset Summon is already in progress` state.
   - User explicitly does not want this re-tested.
3. **Passive subgroup detection/correction: LOGIC PASS; PRESENTATION SUPERSEDED.**
   - Manual wrong-subgroup move was detected.
   - Full Summon restored the configured subgroup.
   - 0.8.92 whole-group pulse was too subtle; 0.8.94 replaces only that presentation.
4. **Combat validation: PARTIAL.**
   - Rogue exclusion passed.
   - Two feral Druids and one DPS Warrior did not accumulate evidence at a reasonable rate while clearing roughly 25% of Stockades at level 60; one feral reached yellow, the others remained stage 0.
   - User observed repeated Feral Faerie Fire, which 0.8.92 ignored because the spell is shared by bear/cat.
   - User also clarified that a genuine mismatch must produce an obvious popup rather than relying on a passive icon/transient centre message.
   - 0.8.94 addresses these findings; its delta is untested.

## Static validation for 0.8.94
- Verified `dev` was still exactly at the documented head before each write; both updates were fast-forward only.
- Reviewed commit diffs for `f443d647acbf8bf5bfcc325fd67b04dfc8dedaa8` and `e8357eb4c7f7cea0c1d5cf4f6928a072a66f0655`.
- Confirmed the old red stage-0 colour entry and whole-group mismatch pulse path are gone.
- Confirmed Feral Faerie Fire is not blindly assigned a role from spell name; it is disambiguated only through live rage/energy power type.
- Confirmed `UnitPowerType(unit)` is native to Vanilla 1.12 and the first return is the integer power type; no ClassicAPI dependency is required.
- GitHub reports no CI/status checks for the implementation head.
- Canonical Lua 5.0.2 compiler pass is **not claimed**. The canonical `VanillaTemplate/tools/lua50` checker is visible through the GitHub connection and this shell has a working C compiler, but the connected private repository files cannot be materialized into the isolated shell and the shell has no DNS/network access. Static diff/call-site review is the available check in this environment.

## Focused runtime gate
Test only the new `0.8.94-dev` delta. **Do not repeat the accepted 5-man or stuck-10-man summon tests.**

1. **Targeted subgroup highlight**
   - With a completed 10-player preset, manually move one known member to the wrong raid subgroup.
   - Confirm the moved character's preset row/box gets a clearly visible gold pulse.
   - Confirm the whole group background no longer does the subtle pulse.
   - No need to re-prove Summon correction unless the new presentation somehow causes a regression.

2. **Combat indicator semantics**
   - Enable combat validation.
   - An eligible bot with zero evidence should show only the first binding tick — no red second marker/X.
   - First recognised role observation should add a yellow second check; second agreeing observation should turn it green.
   - Rogue/Hunter/Warlock/Mage exclusions are unchanged; Rogue was already runtime-cleared and need not be re-tested.

3. **Feral evidence**
   - Bear/cat Feral Faerie Fire should now count when the caster's live power type is rage/energy respectively.
   - Two separated valid observations should progress yellow -> green.
   - The spell must not validate a mana-form Druid.

4. **Mismatch alert**
   - If a genuine confirmed role disagreement occurs naturally, confirm the persistent red `X` is accompanied by an actual popup plus chat warning.
   - Do not spend time engineering an artificial mismatch solely for this gate; runtime proof can be opportunistic.

## Deferred / later
- Resummon Group through the existing maintenance/bot-operation lifecycle.
- Audit remaining All-row/server target sensitivity.
- Remove only proven-dead legacy refill/compatibility code after runtime proof.
- Add neutral read-only activity/status surface, then visualiser as a presentation-only consumer.
- Historical regression debt: dungeon -> 10-player scope retest; Replace Dead focused smoke; investigate dead-state observation only if the old omitted-dead-bot case recurs.

## Release note
Do not promote the current dev line. Stable remains `0.8.78` on `main`. Release preparation must compare `main` and `dev` rather than overwrite main because histories have diverged.
