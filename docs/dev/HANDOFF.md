# SoloCraftBots Development Handoff

Current branch: `dev`
Current addon line: `0.8.23-dev`
Behavioural reference: `main` 0.7.14

## Last runtime-verified point

0.8.23 bootstrap-removal overlap is runtime-proven in Molten Core.

Verified by user:
- fresh solo -> 40-man bootstrap summon completed correctly;
- after real G1 formed, the temporary bootstrap was removed without forcing an otherwise unnecessary 3-second pause before G2;
- normal one-second raid burst cadence continued while bootstrap disappearance/accounting settled in parallel;
- final 40-man composition was correct and no bootstrap remained;
- 0.8.22 had already passed completed-40 -> different-40 destructive rebuild, a forced 40-man replacement while 34 old bots were already live, and a later fresh bootstrap re-run without Lua errors, stale safety state, extra-click recovery or wrong final preset.

This closes the 0.8.23 overlap gate. The next architecture work should unify the different historical survivor/bootstrap cases into one explicit bootstrap-continuity model before retiring more scheduler scaffolding.

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

## Current implementation state — 0.8.23-dev

0.8.23 implements only the raid-bootstrap removal-overlap refinement:
- bootstrap remains parked in the proven G8 location;
- bootstrap removal begins after real G1 exists;
- removal disappearance + settle are polled during ordinary group waits;
- earlier raid bursts may continue while spare capacity remains;
- the final capacity-filling preset burst/final tracking remains gated by unfinished bootstrap settle;
- ordinary survivor/5-man handoff still uses the older strict path.

Functional commit: `a0df882da609dffb2be1a916d8f6b36941ac5cb7` (`Overlap bootstrap removal settle with raid bursts`).

`SpawnBootstrap.lua` is intentionally transitional. Do not treat it as a new permanent owner.

## Next functional gate

The next step should implement the unified bootstrap-continuity rules rather than immediately deleting `PresetRebuild.lua`.

Primary requirements:
1. existing raid + bots: if a bot bootstrap is actually needed, reuse one existing bot, park it in G8, kick the other old bots, observe teardown + 3.0 seconds, then start new G1; do not manufacture another bootstrap;
2. after real G1 exists, remove the raid bootstrap and reuse the proven 0.8.23 overlap rule for later bursts;
3. 5-man target: remain party, reserve one required final bot assignment dynamically, rebuild all other required bot assignments, remove bootstrap, observe absent + 3.0 seconds, then summon the reserved final assignment;
4. human count must drive how many bot assignments can be filled before bootstrap removal; never hard-code a solo-player count;
5. do not retain/create a bot bootstrap when existing humans already preserve the required topology/continuity;
6. never convert a 5-man target to raid because Vanilla 1.12.1 has no safe raid -> party conversion path.

After this unified lifecycle is runtime-proven, absorb the proven `SpawnBootstrap.lua` logic into `Spawn.lua`, then resume retirement of `PresetRebuild.lua` and migration of Replace Missing/Dead execution into the same coordinator.

## Deferred UX / maintenance items

- Replace Dead: improve the no-match message and later consider Ctrl-click as a one-shot `dead OR valid zero-HP` fallback after Vanilla out-of-range health semantics are verified.
- Replace vague `Cannot resolve the current party layout` wording with an actionable message explaining that all present players must be assigned to explicit raid preset slots.

## Change-control reminder

Every functional addon change must bump the TOC version in the same commit. Documentation-only commits do not bump the addon version. Build candidate commits first, inspect the entire diff, and only then move `dev`.
