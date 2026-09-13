# SoloCraftBots Development Handoff

Current branch: `dev`
Current addon line: `0.8.18-dev`
Behavioural reference: `main` 0.7.14

## Last runtime-verified point

0.8.17 introduced recovery for Ctrl-forced replacement after old `.partybot add` commands had already left the client but before the resulting bots appeared.

Runtime testing found no new ordinary-path bugs. Normal summon/rebuild behaviour remained usable. Some highly timing-sensitive Ctrl-click/resummon cases still behaved awkwardly, especially while a rebuild/survivor transition was already in progress. These are treated as evidence of overlapping operation ownership rather than a reason to keep adding local patches to the 0.8.17 rebuild layer.

0.8.17 is therefore considered safe enough to leave the emergency race-fix stage, but not proof that every forced-replacement edge case is solved.

## Current architecture decision

`Spawn.lua` is the final owner of one authoritative bot-lifecycle operation coordinator for every workflow that physically adds/removes bots or waits on those consequences.

`Raid.lua` owns observation and maintenance decisions: Active Roster, dead/missing candidates, logical replacement identity/class/role/group and role resolution. Raid requests an operation from Spawn; it must not retain an independent physical replacement scheduler once migration is complete.

Ctrl-forced preset replacement replaces the desired operation handled by the same coordinator rather than starting a second top-level operation identity. Already-sent server commands remain physical facts that must resolve/expire before the coordinator can safely change direction.

## Current functional gate — 0.8.18-dev

0.8.18 introduces the coordinator foundation without changing the proven physical summon/rebuild sequencing underneath.

- New transitional `SpawnOperation.lua` loads immediately after `Spawn.lua`. It exists only to isolate this first ownership migration safely and must be absorbed into `Spawn.lua` after the coordinator path is runtime-proven.
- One explicit active operation object now tracks preset requests through requested / rebuild / summon / replacing / completion or abort states.
- Ctrl-forced preset requests preserve the same operation identity and replace its desired preset intent while the existing 0.8.17 abort/rebuild machinery still handles the physical teardown and pending-add recovery.
- Existing `PresetRebuild.lua`, Spawn queue timing, survivor/bootstrap helpers, identity bursts and maintenance refill execution remain unchanged in this foundation step.
- Normal abort/session reset now also closes the coordinator object so a stale top-level operation cannot survive after the underlying runtime is gone.

Runtime verification is pending.

## 0.8.18 test gate

Test only enough to prove that introducing the coordinator did not disturb the proven runtime:

1. Normal 5-man preset summon.
2. 5-man -> 5-man preset overwrite.
3. One raid-sized/survivor path if convenient (for example the previously proven 5 -> 10 overwrite).
4. Ctrl-click a replacement while a preset operation is visibly in progress. It may still show the known 0.8.17 timing edge-case behaviour; the important 0.8.18 gate is no Lua error, no permanent busy/stuck state, and no regression of the ordinary summon/rebuild path.

## Following functional steps

After the 0.8.18 foundation passes:

- absorb the temporary coordinator layer into `Spawn.lua` as the established owner;
- migrate preset rebuild / pending-add / survivor / bootstrap lifecycle state into the coordinator so forced replacement changes direction inside one physical pipeline rather than aborting one legacy pipeline and starting another;
- route Replace Missing / Replace Dead execution through the same coordinator while Raid continues choosing replacement records;
- only then remove redundant parallel scheduler state and transitional files;
- resume remaining RaidIdentity -> Raid consolidation once operation ownership is no longer ambiguous.

## Deferred UX / maintenance items

- Replace Dead: improve the no-match message and later consider Ctrl-click as a one-shot `dead OR valid zero-HP` fallback after Vanilla out-of-range health semantics are verified.
- Replace vague `Cannot resolve the current party layout` wording with an actionable message explaining that all present players must be assigned to explicit raid preset slots.

## Change-control reminder

Every functional addon change must bump the TOC version in the same commit. Documentation-only commits do not bump the addon version. Build candidate commits first, inspect the entire diff, and only then move `dev`.
