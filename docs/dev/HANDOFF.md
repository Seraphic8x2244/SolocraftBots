# SoloCraftBots Development Handoff

Current branch: `dev`
Current addon line: `0.8.22-dev`
Behavioural reference: `main` 0.7.14

## Last runtime-verified point

0.8.21 Spawn/coordinator absorption is runtime-proven, including the previously deferred empty-group 40-man bootstrap path.

Verified by user:
- the previously tested 5/10-man survivor paths remained stable through the coordinator consolidation;
- fresh 40-man preset summon while completely solo inside Molten Core correctly used the temporary bootstrap bot, converted/formatted the raid and completed the 40-man summon;
- during that fresh MC bootstrap, SoloCraft returned `Cannot add bots while any party member is in combat` five times; SCB recovered the rejected/failed group automatically and completed the operation rather than losing group identity or becoming stuck;
- a subsequent destructive 40-man preset summon in the same raid correctly detected the saved raid-ID context, kicked the existing bots and rebuilt the requested preset fresh **without** using the bootstrap path;
- no Lua errors, permanent busy state or manual second-click recovery were reported.

This closes the explicit empty-group T3/40-man bootstrap coverage gap that remained after 0.8.20. The combat rejection during that test is useful positive evidence that retry/burst state remains coherent under a real server-side add failure.

## Current architecture decision

`Spawn.lua` is the final owner of one authoritative bot-lifecycle operation coordinator for every workflow that physically adds/removes bots or waits on those consequences.

`Raid.lua` owns observation and maintenance decisions: Active Roster, dead/missing candidates, logical replacement identity/class/role/group and role resolution. Raid requests an operation from Spawn; it must not retain an independent physical replacement scheduler once migration is complete.

Ctrl-forced preset replacement replaces the desired operation handled by the same coordinator rather than starting a second top-level operation identity. Already-sent server commands remain physical facts that must resolve/expire before the coordinator can safely change direction.

## Current functional gate — 0.8.22-dev

0.8.22 removes the temporary 0.8.20 survivor/bootstrap hydration bridge and makes the live preset pipeline use `botOperation.safety` directly.

- `Spawn.lua` creates and consumes survivor/bootstrap state directly on the active preset operation.
- The Group-8 park/remove helpers in `RaidBurst.lua` now read/write that same coordinator safety table directly.
- The superseded preset-scheduler wrapper still present in `RaidRefill.lua` was updated to use the same safety API so no misleading legacy safety-field ownership remains there.
- The historical global fields such as `presetSurvivorBotName`, `scbParkSurvivorBeforeArrange`, `scbRemoveSurvivorAfterG1`, `scbSurvivorRemovalWaiting` and `scbPartySurvivorGoneAt` are no longer the live persistent handoff path.
- Operation completion, abort and forced replacement clear `operation.safety` directly; there is no per-frame hydrate/capture cycle.
- A survivor queue marker encountered without an active coordinator safety table now fails closed as invalid scheduler state instead of silently treating missing values as nil/zero.
- Pending-add recovery, burst identity, combat retry, conversion, Group-8 parking and the 3.0-second remove -> next-add boundary are intentionally unchanged.

Functional commit: `21cebdf1adc4d7366b89ff212ce7c7e244adb96c` (`Use coordinator safety state directly`).

## 0.8.22 runtime gate

This is the first build with no compatibility hydration layer, so re-check the paths that actually consume safety state:

1. 5-man -> 5-man overwrite with survivor handoff;
2. 5-man -> 10-man overwrite with survivor / conversion / Group-8 park-and-remove;
3. fresh empty-group 40-man summon in MC or another bootstrap-triggering raid when convenient; the bootstrap path is already proven on 0.8.21, so this is specifically the direct-state regression check;
4. one aggressive in-flight Ctrl overwrite to confirm replacement clears old safety state and the latest preset still wins;
5. if a real combat-add rejection occurs again, confirm the failed group retries without losing the safety member or operation state.

The fresh 40-man bootstrap does not need to be repeated immediately if travel is inconvenient; it is now proven on 0.8.21 and remains a promotion-level regression case.

## Following functional steps

After 0.8.22 passes:

- retire the superseded `PresetRebuild.lua` implementation once its remaining compatibility sentinel/busy-check dependency is replaced explicitly; its final public functions are already superseded by the Spawn coordinator;
- route Replace Missing / Replace Dead physical execution through the same coordinator while Raid continues choosing replacement records;
- remove redundant RaidBurst/RaidRefill scheduler wrappers only after their remaining identity/maintenance responsibilities have a clear owner;
- resume remaining RaidIdentity -> Raid consolidation once operation ownership is no longer ambiguous.

## Deferred UX / maintenance items

- Replace Dead: improve the no-match message and later consider Ctrl-click as a one-shot `dead OR valid zero-HP` fallback after Vanilla out-of-range health semantics are verified.
- Replace vague `Cannot resolve the current party layout` wording with an actionable message explaining that all present players must be assigned to explicit raid preset slots.

## Change-control reminder

Every functional addon change must bump the TOC version in the same commit. Documentation-only commits do not bump the addon version. Build candidate commits first, inspect the entire diff, and only then move `dev`.
