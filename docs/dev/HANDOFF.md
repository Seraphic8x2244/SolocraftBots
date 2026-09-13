# SoloCraftBots Development Handoff

Current branch: `dev`
Current addon line: `0.8.18-dev`
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

0.8.17's local pending-add recovery remains underneath the coordinator and should be treated as transitional implementation, not the final ownership model.

## Current architecture decision

`Spawn.lua` is the final owner of one authoritative bot-lifecycle operation coordinator for every workflow that physically adds/removes bots or waits on those consequences.

`Raid.lua` owns observation and maintenance decisions: Active Roster, dead/missing candidates, logical replacement identity/class/role/group and role resolution. Raid requests an operation from Spawn; it must not retain an independent physical replacement scheduler once migration is complete.

Ctrl-forced preset replacement replaces the desired operation handled by the same coordinator rather than starting a second top-level operation identity. Already-sent server commands remain physical facts that must resolve/expire before the coordinator can safely change direction.

## Current implementation state

0.8.18 introduced the coordinator foundation without changing the proven physical summon/rebuild sequencing underneath.

- Transitional `SpawnOperation.lua` currently loads immediately after `Spawn.lua`.
- One explicit active operation object tracks preset requests through requested / rebuild / summon / replacing / completion or abort states.
- Ctrl-forced preset requests preserve the same operation identity and replace its desired preset intent while the existing 0.8.17 abort/rebuild machinery still handles physical teardown and pending-add recovery.
- Existing `PresetRebuild.lua`, Spawn queue timing, survivor/bootstrap helpers, identity bursts and maintenance refill execution remain live underneath.
- `SpawnOperation.lua` is temporary and must ultimately be absorbed into `Spawn.lua`; it is not an additional final owner.

## Exact next functional step — 0.8.19-dev

Move the first real physical lifecycle responsibilities into the coordinator rather than adding more edge-case patches.

1. Make the coordinator own the preset rebuild transition state now held in `presetRebuildState`.
2. Move the pending already-sent add recovery decision into that operation state.
3. Move rebuild teardown / roster-gone observation / shared 3.0-second next-add settle state into the operation.
4. Preserve the proven 0.8.14 next-frame handoff semantics while changing ownership; do not reintroduce a same-frame queue transplant.
5. Preserve current survivor policy and 5 -> 10 conversion/parking behaviour exactly in this first physical migration.
6. Do not yet migrate Replace Missing / Replace Dead execution in the same commit.
7. Do not remove `RaidIdentity.lua`, `RaidBurst.lua` or `RaidRefill.lua` in this step.

Preferred shape: the operation coordinator should call/reuse proven helper functions where practical, but `PresetRebuild.lua` must stop being an independent top-level state owner. If a temporary compatibility shim is required for one gate, keep it narrow and record it explicitly.

## 0.8.19 runtime gate

Minimum regression set after the physical rebuild-state migration:

1. normal 5-man summon;
2. 5-man -> 5-man overwrite;
3. 5-man -> 10-man survivor/conversion overwrite;
4. force a second 10-man preset while the first is still in flight and confirm the latest requested preset wins automatically;
5. force another preset during the rebuild/removal-settle window and confirm there is no second parallel rebuild, no stuck busy state and no extra click required.

## Following functional steps

After 0.8.19 passes:

- migrate survivor/bootstrap handoff state fully into the coordinator and absorb the temporary coordinator layer into `Spawn.lua` when safe;
- route Replace Missing / Replace Dead execution through the same coordinator while Raid continues choosing replacement records;
- remove redundant parallel scheduler state and transitional files only after runtime proof;
- resume remaining RaidIdentity -> Raid consolidation once operation ownership is no longer ambiguous.

## Deferred UX / maintenance items

- Replace Dead: improve the no-match message and later consider Ctrl-click as a one-shot `dead OR valid zero-HP` fallback after Vanilla out-of-range health semantics are verified.
- Replace vague `Cannot resolve the current party layout` wording with an actionable message explaining that all present players must be assigned to explicit raid preset slots.

## Change-control reminder

Every functional addon change must bump the TOC version in the same commit. Documentation-only commits do not bump the addon version. Build candidate commits first, inspect the entire diff, and only then move `dev`.
