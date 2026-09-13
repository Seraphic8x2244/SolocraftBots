# SoloCraftBots Development Handoff

Current branch: `dev`
Current addon line: `0.8.17-dev`
Behavioural reference: `main` 0.7.14

## Last runtime-verified point

0.8.17 introduced recovery for Ctrl-forced replacement after old `.partybot add` commands had already left the client but before the resulting bots appeared.

Runtime testing found no new ordinary-path bugs. Normal summon/rebuild behaviour remained usable. Some highly timing-sensitive Ctrl-click/resummon cases still behave awkwardly, especially while a rebuild/survivor transition is already in progress. These are now treated as evidence of overlapping operation ownership rather than a reason to keep adding local patches to the 0.8.17 rebuild layer.

0.8.17 is therefore considered safe enough to leave the emergency race-fix stage, but not proof that every forced-replacement edge case is solved.

## Current architecture decision

`Spawn.lua` will own one authoritative bot-lifecycle operation coordinator for every workflow that physically adds/removes bots or waits on those consequences.

`Raid.lua` owns observation and maintenance decisions: Active Roster, dead/missing candidates, logical replacement identity/class/role/group and role resolution. Raid requests an operation from Spawn; it must not retain an independent physical replacement scheduler once migration is complete.

Ctrl-forced preset replacement must replace the desired operation handled by the same coordinator rather than starting a second pipeline. Already-sent server commands remain physical facts that must resolve/expire before the coordinator can safely change direction.

## Exact next functional step — 0.8.18-dev

Introduce the coordinator foundation without deleting or rewriting proven runtime sequencing yet.

1. Add one explicit active operation object owned by `Spawn.lua`.
2. Give it stable lifecycle helpers for begin / replace intent / phase / complete / abort.
3. Route the existing preset summon/rebuild entry point through that object while retaining the current `PresetRebuild.lua`, queue, survivor and burst implementations underneath.
4. Ensure forced preset requests replace the coordinator's desired intent instead of creating a second independent top-level operation identity.
5. Keep all current physical timing and remove -> roster-gone -> 3.0 s -> next-add behaviour unchanged in this first foundation step.
6. Do not remove `RaidIdentity.lua`, `PresetRebuild.lua`, `RaidBurst.lua` or `RaidRefill.lua` in 0.8.18.

## Following gates

After the coordinator foundation passes ordinary summon/rebuild and Ctrl smoke tests:

- migrate preset rebuild/survivor/bootstrap lifecycle state into the coordinator;
- route Replace Missing / Replace Dead execution through the same coordinator while Raid continues choosing replacement records;
- only then remove redundant parallel scheduler state and transitional files;
- resume remaining RaidIdentity -> Raid consolidation once operation ownership is no longer ambiguous.

## Deferred UX / maintenance items

- Replace Dead: improve the no-match message and later consider Ctrl-click as a one-shot `dead OR valid zero-HP` fallback after Vanilla out-of-range health semantics are verified.
- Replace vague `Cannot resolve the current party layout` wording with an actionable message explaining that all present players must be assigned to explicit raid preset slots.

## Change-control reminder

Every functional addon change must bump the TOC version in the same commit. Documentation-only commits do not bump the addon version. Build candidate commits first, inspect the entire diff, and only then move `dev`.
