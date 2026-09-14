# SoloCraftBots Development Handoff

Current branch: `dev`
Current addon line: `0.8.24-dev`
Behavioural reference: `main` 0.7.14

## Last runtime-verified point

0.8.24 unified bootstrap continuity is runtime-proven for both raid and 5-man party topology.

Verified by user on the raid side:
- completed 40-man -> different 40-man rebuild retained exactly one old bot instead of destroying the raid and manufacturing a new bootstrap;
- the retained bot was parked in Group 8;
- the other old bots were removed and the existing teardown + 3.0-second settle completed before new G1 began;
- once a genuine new G1 existed, the retained Group-8 bootstrap was removed;
- G2/G3/etc. continued on the normal one-second cadence while bootstrap disappearance/accounting settled in parallel;
- final roster exactly matched the requested 40-man preset and no bootstrap remained;
- a Ctrl-forced different 40-man preset during the retained-bootstrap rebuild also converged on the final requested preset correctly, with no stale bootstrap, wrong roster, second click or stuck state reported.

Verified by user on the 5-man dungeon side:
- completed 5-man -> different 5-man rebuild retained one party bot as bootstrap;
- party topology was preserved; no raid conversion occurred;
- the existing reserved-final-assignment handoff completed correctly;
- bootstrap removal respected the disappearance + 3.0-second capacity-reuse settle before the reserved final bot was added;
- final 5-man composition completed correctly.

The teardown message still reports the full logical number of old bots being replaced (for example 39) even though one of those bots is physically retained for a few seconds as bootstrap and removed later. This is accepted behavior: the message describes the logical old-roster teardown, not the first physical uninvite batch.

This closes the **0.8.24 unified-bootstrap gate**.

## Current architecture decision

`Spawn.lua` is the final owner of one authoritative bot-lifecycle operation coordinator for every workflow that physically adds/removes bots or waits on those consequences.

`Raid.lua` owns observation and maintenance decisions: Active Roster, dead/missing candidates, logical replacement identity/class/role/group and role resolution. Raid requests an operation from Spawn; it must not retain an independent physical replacement scheduler once migration is complete.

Ctrl-forced preset replacement replaces the desired operation handled by the same coordinator rather than starting a second top-level operation identity. Already-sent server commands remain physical facts that must resolve/expire before the coordinator can safely change direction.

Removal-settle rule is capacity-based: the 3.0-second roster-disappearance settle protects **reuse of capacity freed by a removed bot**. It is not a blanket ban on unrelated additions. Ordinary replacement and 5-man bootstrap handoff still gate the capacity-dependent replacement slot; raid-bootstrap removal may settle in parallel with earlier bursts that do not need that slot.

## Unified bootstrap model

`bootstrap` is the preferred umbrella term for a temporary bot occupant used to preserve required group/instance continuity while a preset transition is rebuilt. How the bot originated is secondary.

Possible origins:
- **fresh T3/raid bootstrap:** no suitable group exists, so SCB creates a temporary bot to form the party/raid and allow the raid-sized summon path;
- **existing raid bootstrap:** reuse one existing bot instead of kicking every bot and manufacturing another temporary member;
- **instance-continuity bootstrap:** retain an existing bot when removing it would risk losing the required party/raid/instance state;
- **5-man bootstrap:** retain an existing party bot while the other required bot slots are rebuilt.

A bot bootstrap should exist only when it is actually needed. If present humans already guarantee the required party/raid continuity, SCB does not need to retain an extra bot merely for topology.

Prefer reusing an existing bot when a bootstrap is needed. Manufacture a new bootstrap only when there is no suitable existing occupant and group formation requires one.

The **target preset determines topology and parking policy**:

### 5-man target
- remain a party; never convert to raid merely because bootstrap logic is active;
- the bootstrap stays in the party/G1 because parties have no subgroup parking;
- reserve exactly **one required final bot assignment** while the bootstrap occupies one party slot;
- fill every other required bot assignment that fits alongside the present humans and bootstrap;
- remove the bootstrap;
- observe it absent and wait the full 3.0-second capacity-reuse settle;
- summon the one reserved final bot assignment.

Do **not** hard-code “summon three, then the fourth”. With multiple humans, the number of pre-bootstrap-removal bot assignments is lower. The rule is one reserved final bot slot, not a fixed bot count.

### Raid-sized target (>5)
When a bot bootstrap is needed and a raid already exists, retain one existing bot rather than creating a new one. Park it in G8 when possible, remove the other old bots, observe their teardown and wait the normal 3.0-second settle before beginning the new G1 burst.

Once a genuine new G1 bot exists, remove the bootstrap. Its disappearance + 3.0-second accounting window may overlap later raid bursts while spare target capacity remains. The first burst that actually depends on the bootstrap's freed slot must wait if that settle is still incomplete.

For a normal 40-man build the bootstrap settle should naturally finish long before the final capacity-filling burst, so no visible extra pause is expected.

### Fresh raid start
If no existing group member can preserve/establish the required raid state, create a temporary bootstrap, convert/form the raid, then enter the same raid-bootstrap lifecycle above.

## Current implementation state — 0.8.24-dev

0.8.24 extends the proven 0.8.23 overlap behavior to retained preset-rebuild anchors:
- `SpawnBootstrap.lua` currently loads after `Commands.lua` so it can extend the existing safe Kick All policy without duplicating that implementation;
- while a preset rebuild is active, a bot bootstrap is retained whenever continuity requires one and no other human already preserves the group;
- raid-sized rebuilds reuse an existing bot bootstrap and classify it into the same coordinator safety state used by fresh T3 bootstrap;
- retained raid bootstraps use the proven G8 + post-G1 removal + overlap lifecycle;
- the existing 5-man queue math reserves one final logical bot assignment dynamically rather than assuming a one-human fixed count;
- manual Kick All and non-preset removals retain their existing policy.

Functional commit: `aa96f9136cee600cee0a09e50fe95fe6f606154f` (`Unify retained preset bootstrap continuity`).

`SpawnBootstrap.lua` remains intentionally transitional. Do not treat it as a permanent owner.

## Next functional gate — structural bootstrap absorption

The next build should be behavior-preserving only:

1. absorb the proven bootstrap classification/removal-overlap scheduler logic from `SpawnBootstrap.lua` into `Spawn.lua`;
2. keep the retained-bootstrap decision beside Commands' existing safe Kick All policy until survivor/removal policy itself is later moved into final Spawn ownership;
3. remove `SpawnBootstrap.lua` from the TOC/repository;
4. preserve the exact 0.8.24 capacity rule, raid G8 behavior, 5-man party topology and dynamic reserved-final-assignment behavior;
5. do **not** retire `PresetRebuild.lua` in the same build;
6. runtime-smoke at least one 5-man rebuild, one retained 40-man rebuild, and one Ctrl-forced replacement after the structural move.

Multi-human 5-man coverage remains desirable before main promotion, specifically to prove the already-dynamic pre-bootstrap-removal bot count against real human occupancy.

After the structural absorption passes, resume retirement of `PresetRebuild.lua`, then migration of Replace Missing/Dead physical execution into the same coordinator.

## Deferred UX / maintenance items

- Replace Dead: improve the no-match message and later consider Ctrl-click as a one-shot `dead OR valid zero-HP` fallback after Vanilla out-of-range health semantics are verified.
- Replace vague `Cannot resolve the current party layout` wording with an actionable message explaining that all present players must be assigned to explicit raid preset slots.

## Change-control reminder

Every functional addon change must bump the TOC version in the same commit. Documentation-only commits do not bump the addon version. Build candidate commits first, inspect the entire diff, and only then move `dev`.
