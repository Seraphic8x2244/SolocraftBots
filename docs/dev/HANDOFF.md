# SoloCraftBots Development Handoff

Current branch: `dev`
Current addon line: `0.8.21-dev`
Behavioural reference: `main` 0.7.14

## Last runtime-verified point

0.8.20 coordinator-owned survivor/bootstrap state passed every currently available survivor-path test.

Verified by user:
- 5-man -> 5-man overwrite passed with survivor handling;
- 5-man -> 10-man overwrite passed with survivor / conversion / Group-8 handling;
- repeated 10-man -> 10-man -> 10-man Ctrl-overwrite stress testing passed with survivor handling;
- no Lua errors, stuck/busy state, extra-click requirement or wrong final preset were reported.

The special empty-group raid bootstrap path has **not** yet been runtime-tested because the user was not near a 40-man raid location. Record that as deferred coverage, not as a blocker for structural consolidation that leaves the bootstrap code/order unchanged.

## Current architecture decision

`Spawn.lua` is the final owner of one authoritative bot-lifecycle operation coordinator for every workflow that physically adds/removes bots or waits on those consequences.

`Raid.lua` owns observation and maintenance decisions: Active Roster, dead/missing candidates, logical replacement identity/class/role/group and role resolution. Raid requests an operation from Spawn; it must not retain an independent physical replacement scheduler once migration is complete.

Ctrl-forced preset replacement replaces the desired operation handled by the same coordinator rather than starting a second top-level operation identity. Already-sent server commands remain physical facts that must resolve/expire before the coordinator can safely change direction.

## Current functional gate — 0.8.21-dev

0.8.21 removes the temporary `SpawnOperation.lua` file by absorbing its complete coordinator implementation into the end of `Spawn.lua` at the same effective load position.

- `SpawnOperation.lua` is removed from the TOC and repository.
- The operation coordinator still wraps the same authoritative Spawn scheduler in the same order as 0.8.20.
- `botOperation.rebuild` and `botOperation.safety` ownership is unchanged.
- The 0.8.20 safety hydration/capture compatibility bridge is intentionally retained unchanged for this gate; direct coordinator-state reads/writes are deferred to the next functional step.
- No physical summon/rebuild/survivor timing, pending-add recovery, identity-burst ordering, maintenance execution or removal-settle policy is intentionally changed.
- Existing `Spawn.lua` executable lines were preserved; only comments were trimmed while the former coordinator file was appended.

Functional commit: `e9be73637d84655227900d9af11ed94af52acb63` (`Absorb SpawnOperation into Spawn`).

## 0.8.21 runtime gate

Because this is intended to be structural/load-order preserving, use a compact regression set:

1. normal 5-man summon;
2. 5-man -> 5-man overwrite with survivor;
3. 5-man -> 10-man survivor/conversion overwrite;
4. one aggressive Ctrl-switch between 10-man presets while an operation is in flight;
5. confirm ordinary summoning still works after the Ctrl test and no permanent busy state appears.

The empty-group 40-man bootstrap remains deferred coverage and must be exercised before the compatibility safety bridge is finally deleted or before main promotion.

## Following functional steps

After 0.8.21 passes:

- replace the 0.8.20 safety hydration/capture bridge with direct coordinator-state access in a separate runtime-gated change;
- retire `PresetRebuild.lua` only when its compatibility sentinel/busy checks have been replaced explicitly and runtime-proven;
- route Replace Missing / Replace Dead physical execution through the same coordinator while Raid continues choosing replacement records;
- remove redundant RaidBurst/RaidRefill scheduler wrappers only after their remaining identity/maintenance responsibilities have a clear owner;
- resume remaining RaidIdentity -> Raid consolidation once operation ownership is no longer ambiguous.

## Deferred UX / maintenance items

- Replace Dead: improve the no-match message and later consider Ctrl-click as a one-shot `dead OR valid zero-HP` fallback after Vanilla out-of-range health semantics are verified.
- Replace vague `Cannot resolve the current party layout` wording with an actionable message explaining that all present players must be assigned to explicit raid preset slots.

## Change-control reminder

Every functional addon change must bump the TOC version in the same commit. Documentation-only commits do not bump the addon version. Build candidate commits first, inspect the entire diff, and only then move `dev`.
