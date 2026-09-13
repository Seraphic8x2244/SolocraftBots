# SoloCraftBots Development Handoff

Current branch: `dev`
Current addon line: `0.8.23-dev`
Behavioural reference: `main` 0.7.14

## Last runtime-verified point

0.8.22 direct coordinator safety-state migration passed its available runtime gate strongly, including large-raid bootstrap/rebuild/forced-replacement stress.

Verified by user in Molten Core:
- fresh solo -> 40-man bootstrap summon completed correctly;
- completed 40-man -> different 40-man destructive rebuild completed correctly without bootstrap in the saved-ID context;
- Ctrl-forcing a different 40-man while the first operation already had 34 bots live in the raid still converged automatically on the correct final requested preset; both already-materialized and still-in-flight old state were recovered without a second click;
- after the destructive/forced tests, returning completely solo and running a fresh bootstrap summon again worked normally;
- the bootstrap reliably remained able to force formation of the T3 raid group;
- no Lua errors, permanent busy state, stale-safety leak or wrong final preset were reported.

Earlier 0.8.22 small-group survivor regression tests were already proven through the 0.8.20/0.8.21 line; the next small-group pass remains useful before promotion, but the direct-safety migration itself is considered passed.

## Current architecture decision

`Spawn.lua` is the final owner of one authoritative bot-lifecycle operation coordinator for every workflow that physically adds/removes bots or waits on those consequences.

`Raid.lua` owns observation and maintenance decisions: Active Roster, dead/missing candidates, logical replacement identity/class/role/group and role resolution. Raid requests an operation from Spawn; it must not retain an independent physical replacement scheduler once migration is complete.

Ctrl-forced preset replacement replaces the desired operation handled by the same coordinator rather than starting a second top-level operation identity. Already-sent server commands remain physical facts that must resolve/expire before the coordinator can safely change direction.

Removal-settle rule is now refined: the 3.0-second roster-disappearance settle protects **capacity reuse**, not every unrelated add. Ordinary replacement/survivor handoff still gates the next replacement add. Temporary bootstrap removal may settle in parallel with earlier preset bursts while spare target capacity remains, but the final capacity-filling preset bot burst (or final roster tracking) must not cross that settle boundary.

## Current functional gate — 0.8.23-dev

0.8.23 implements the bootstrap-only settle refinement without changing ordinary survivor/replacement behavior.

- Bootstrap remains parked in the proven Group-8 location; moving it to the eventual final logical group is deliberately deferred because it is not required for the timing gain.
- As soon as a real Group-1 bot exists and combat permits, SCB requests bootstrap removal.
- Bootstrap roster disappearance and the 3.0-second accounting window are polled every scheduler frame, including during normal one-second group waits.
- Earlier preset bot bursts may continue while that bootstrap settle is still running.
- The final remaining preset bot burst is treated as the capacity-filling burst and must wait until bootstrap disappearance + 3.0 seconds are complete. This is derived from the remaining explicit burst plans rather than hard-coded group numbers, so human-heavy later groups remain safe.
- If no later bot burst exists, final roster tracking waits for bootstrap settle instead.
- Ordinary survivor removal continues to delegate to the unchanged 0.8.22 strict next-add barrier.
- Combat retry, explicit burst identity, forced-replacement recovery and the ordinary 1.0-second inter-group cadence are otherwise unchanged.

Functional commit: `a0df882da609dffb2be1a916d8f6b36941ac5cb7` (`Overlap bootstrap removal settle with raid bursts`).

Implementation note: `SpawnBootstrap.lua` is intentionally a one-gate transitional extension loaded immediately after `Spawn.lua`. If runtime proof passes, absorb it into Spawn before further scheduler-file retirement; do not let it become a permanent parallel owner.

## 0.8.23 runtime gate

The most useful test is a fresh empty-group 40-man bootstrap in MC while the character is already there:

1. start completely solo and summon the 40-man preset;
2. bootstrap should join, raid conversion/Group-8 parking should occur, then real G1 should begin normally;
3. bootstrap should be kicked once a real G1 bot exists;
4. **G2 must not pause for the bootstrap's 3-second removal settle** — normal one-second group cadence should continue through the earlier groups;
5. by the final 40-man burst the bootstrap settle should naturally be complete, so there should normally be no visible extra pause at all;
6. final roster must contain the exact requested preset with no bootstrap left behind;
7. if combat delays bootstrap removal, earlier groups may continue, but the final bot burst must wait rather than overrun capacity.

For a later 15/20-player bootstrap-capable path, expected behavior is equivalent: the final capacity-filling bot burst is the only burst that can be delayed by unfinished bootstrap accounting.

## Following functional steps

After 0.8.23 passes:

- absorb the proven `SpawnBootstrap.lua` refinement into `Spawn.lua` rather than retaining another late patch layer;
- retire the superseded `PresetRebuild.lua` implementation once its remaining compatibility sentinel/busy-check dependency is replaced explicitly; its final public functions are already superseded by the Spawn coordinator;
- route Replace Missing / Replace Dead physical execution through the same coordinator while Raid continues choosing replacement records;
- remove redundant RaidBurst/RaidRefill scheduler wrappers only after their remaining identity/maintenance responsibilities have a clear owner;
- resume remaining RaidIdentity -> Raid consolidation once operation ownership is no longer ambiguous.

## Deferred UX / maintenance items

- Replace Dead: improve the no-match message and later consider Ctrl-click as a one-shot `dead OR valid zero-HP` fallback after Vanilla out-of-range health semantics are verified.
- Replace vague `Cannot resolve the current party layout` wording with an actionable message explaining that all present players must be assigned to explicit raid preset slots.

## Change-control reminder

Every functional addon change must bump the TOC version in the same commit. Documentation-only commits do not bump the addon version. Build candidate commits first, inspect the entire diff, and only then move `dev`.
