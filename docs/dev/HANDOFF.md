# SoloCraftBots Development Handoff

Current branch: `dev`
Current addon line: `0.8.20-dev`
Behavioural reference: `main` 0.7.14

## Last runtime-verified point

0.8.19 coordinator-owned rebuild lifecycle passed its runtime gate strongly.

Verified by user:
- normal 5-man summon remained good;
- 5-man -> 5-man overwrite remained good;
- 5-man -> 10-man survivor/conversion overwrite remained good;
- switching between different 10-man presets while one was still in flight correctly resolved to the latest requested preset;
- repeated deliberately unreasonable Ctrl-click summon interruptions with 10 bots in a dungeon produced no reported Lua errors, stuck/busy state, extra-click requirement or wrong final preset.

This is sufficient to treat the preset rebuild transition as coordinator-owned. Do not add more local Ctrl/rebuild patches to the old pipeline.

## Current architecture decision

`Spawn.lua` is the final owner of one authoritative bot-lifecycle operation coordinator for every workflow that physically adds/removes bots or waits on those consequences.

`Raid.lua` owns observation and maintenance decisions: Active Roster, dead/missing candidates, logical replacement identity/class/role/group and role resolution. Raid requests an operation from Spawn; it must not retain an independent physical replacement scheduler once migration is complete.

Ctrl-forced preset replacement replaces the desired operation handled by the same coordinator rather than starting a second top-level operation identity. Already-sent server commands remain physical facts that must resolve/expire before the coordinator can safely change direction.

## Current functional gate — 0.8.20-dev

0.8.20 moves survivor/bootstrap handoff state under the same operation object.

- `botOperation.safety` is now the persistent owner of the safety-member name, bootstrap name, raid park/remove flags, survivor-removal wait/settle state, and the five-player survivor handoff count/timestamp.
- The proven `Spawn.lua` / `RaidBurst.lua` physical sequencing is intentionally unchanged in this gate.
- A narrow compatibility bridge in `SpawnOperation.lua` hydrates the historical field names only while a scheduler frame executes, captures any mutations back into `botOperation.safety`, then clears the legacy fields again. They are no longer persistent owners between frames.
- Ctrl replacement and normal abort/session completion clear coordinator safety state so a later operation cannot inherit a previous survivor/bootstrap.
- The bridge explicitly preserves safety state created by the rebuild -> replacement-queue handoff inside the same frame; an off-branch candidate that could overwrite that newly-created state was caught and discarded before publication.
- `PresetRebuild.lua`, `RaidBurst.lua` and `RaidRefill.lua` remain present for this gate. No physical timing or identity-burst code moved in 0.8.20.

Functional commit: `86b408191fdd1e9bc0680d0da696a90c28d51a1a` (`Move survivor handoff state into coordinator`).

## 0.8.20 runtime gate

1. Normal 5-man preset summon.
2. 5-man -> 5-man overwrite.
3. 5-man -> 10-man overwrite with the retained survivor / Group-8 safety path.
4. Repeat aggressive Ctrl-switching between 10-man presets while adds/rebuilds are in flight; latest requested preset must still win without a stuck state or extra click.
5. Exercise a 5-man survivor replacement path if convenient, because its final-bot handoff now persists through `botOperation.safety` too.
6. Before removing the compatibility bridge, separately exercise the special empty-group raid bootstrap path in a location that actually uses it.

## Following functional steps

After 0.8.20 passes:

- absorb the temporary coordinator implementation into `Spawn.lua` and replace compatibility hydration with direct coordinator-state reads/writes, while preserving the proven next-frame rebuild handoff;
- retire `PresetRebuild.lua` only when its compatibility sentinel/busy checks have been replaced explicitly and runtime-proven;
- route Replace Missing / Replace Dead physical execution through the same coordinator while Raid continues choosing replacement records;
- remove redundant RaidBurst/RaidRefill scheduler wrappers only after their remaining identity/maintenance responsibilities have a clear owner;
- resume remaining RaidIdentity -> Raid consolidation once operation ownership is no longer ambiguous.

## Deferred UX / maintenance items

- Replace Dead: improve the no-match message and later consider Ctrl-click as a one-shot `dead OR valid zero-HP` fallback after Vanilla out-of-range health semantics are verified.
- Replace vague `Cannot resolve the current party layout` wording with an actionable message explaining that all present players must be assigned to explicit raid preset slots.

## Change-control reminder

Every functional addon change must bump the TOC version in the same commit. Documentation-only commits do not bump the addon version. Build candidate commits first, inspect the entire diff, and only then move `dev`.
