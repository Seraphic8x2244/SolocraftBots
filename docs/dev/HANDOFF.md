# SoloCraftBots Development Handoff

Current branch: `dev`
Current addon line: `0.8.19-dev`
Behavioural reference: `main` 0.7.14

## Last runtime-verified point

0.8.18 coordinator foundation passed its runtime gate.

Verified by user:
- normal 5-man preset summon passed;
- 5-man -> 5-man preset overwrite passed;
- 5-man -> 10-man survivor/conversion overwrite passed;
- forced switching between two different 10-man presets while the first preset was still in flight correctly produced the second requested preset;
- no Lua errors, permanent busy state or ordinary summon/rebuild regression were reported.

This is stronger evidence than the minimum 0.8.18 gate: the coordinator-level desired-intent replacement already improves the forced in-flight preset-switch case that motivated the architecture change.

## Current architecture decision

`Spawn.lua` is the final owner of one authoritative bot-lifecycle operation coordinator for every workflow that physically adds/removes bots or waits on those consequences.

`Raid.lua` owns observation and maintenance decisions: Active Roster, dead/missing candidates, logical replacement identity/class/role/group and role resolution. Raid requests an operation from Spawn; it must not retain an independent physical replacement scheduler once migration is complete.

Ctrl-forced preset replacement replaces the desired operation handled by the same coordinator rather than starting a second top-level operation identity. Already-sent server commands remain physical facts that must resolve/expire before the coordinator can safely change direction.

## Current functional gate — 0.8.19-dev

0.8.19 moves the first physical preset-rebuild lifecycle state into the coordinator.

- `botOperation.rebuild` now owns pending already-sent add recovery, old-bot teardown observation, conversion/parking during teardown, the shared 3.0-second removal -> next-add settle, and the proven next-frame replacement-queue handoff.
- `PresetRebuild.lua` remains loaded for one migration gate, but its final `SCB_StartPresetRebuild` / `SCB_PresetRebuildOnUpdate` functions are superseded by `SpawnOperation.lua`.
- `SCB.presetRebuildState` is now only an active-only compatibility sentinel while a coordinator rebuild is live, so older busy checks cannot start maintenance in parallel. It no longer owns snapshot/timer/conversion/handoff state.
- Normal fresh summons still use the existing Spawn queue directly under the same operation object.
- Survivor/bootstrap execution inside the Spawn queue remains unchanged in this step; only the rebuild transition around it moved ownership.
- Replace Missing / Replace Dead execution remains on the existing refill pipeline for now.
- `SpawnOperation.lua` is still temporary and must ultimately be absorbed into `Spawn.lua` after the coordinator migration is proven.

Functional commit: `d5a3a06f226d37d1e9941dfc6bb3ef000d6df6ac` (`Move preset rebuild state into coordinator`).

## 0.8.19 runtime gate

1. Normal 5-man preset summon.
2. 5-man -> 5-man preset overwrite.
3. 5-man -> 10-man survivor/conversion overwrite.
4. Force a second 10-man preset while the first is still in flight and confirm the latest requested preset wins automatically.
5. Force another preset during the rebuild/removal-settle window and confirm there is no second parallel rebuild, no stuck busy state and no extra click required.

If those pass, the rebuild transition is considered coordinator-owned and the next migration can move survivor/bootstrap lifecycle state itself.

## Following functional steps

After 0.8.19 passes:

- migrate survivor/bootstrap handoff state fully into the coordinator;
- absorb the temporary coordinator layer into `Spawn.lua` once doing so no longer recreates the 0.8.11 same-frame/load-order risk;
- route Replace Missing / Replace Dead execution through the same coordinator while Raid continues choosing replacement records;
- remove redundant parallel scheduler state and transitional files only after runtime proof;
- resume remaining RaidIdentity -> Raid consolidation once operation ownership is no longer ambiguous.

## Deferred UX / maintenance items

- Replace Dead: improve the no-match message and later consider Ctrl-click as a one-shot `dead OR valid zero-HP` fallback after Vanilla out-of-range health semantics are verified.
- Replace vague `Cannot resolve the current party layout` wording with an actionable message explaining that all present players must be assigned to explicit raid preset slots.

## Change-control reminder

Every functional addon change must bump the TOC version in the same commit. Documentation-only commits do not bump the addon version. Build candidate commits first, inspect the entire diff, and only then move `dev`.
