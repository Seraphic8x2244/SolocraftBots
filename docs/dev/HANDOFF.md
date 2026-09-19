# SoloCraftBots Development Handoff

Current branch: `dev`
Current addon line: `0.8.41-dev`
Current functional addon head: `204b0b305168bc421f05bdd8bfc63c219f0a4b59`
Previous docs checkpoint: `54bc656272ca8220cd5e500f9fee164953eefbb8`
Behavioural reference: `main` 0.7.14 (`6170b1535dba83882ee55eb38c35160c8fec9ca2`)

## Current status override — 2026-09-19

The sections below preserve the earlier 0.8.28 consolidation handoff for historical context. Current development has moved on substantially:

- six-owner consolidation is complete: `SoloCraftBots.lua`, `Presets.lua`, `Roster.lua`, `Spawn.lua`, `Communication.lua`, `Options.lua`;
- current runtime is `0.8.39-dev` at `457b593eaca94a40f311c57b18c9417512c328be`;
- `0ade4746dbe2875016294cd81263c71bf632e130` documents the broad post-audit performance pass;
- 0.8.39 passed the practical 10-man Stockades runtime gate; the combat teardown edge case found during that gate is addressed in 0.8.40-dev;
- 0.8.40-dev is the current untested runtime;
- after the narrow 0.8.40 retest, deferred performance work includes same-frame 40-man Kick All A/B, mixed-group up-to-five maintenance bursts, proven-dead/low-value wrapper cleanup, and FIFO/micro-optimisation work.

## Runtime test update — 2026-09-19

0.8.39-dev practical 10-man Stockades gate passed:
- initial preset summon: pass;
- preset -> different preset rebuild: pass after resolving human logical-slot layout;
- paced Kick All: pass, survivor retained as designed;
- summon after Kick All: pass, survivor handled correctly;
- one dead replacement: pass with correct role;
- pfUI tank marking: pass;
- combat case exposed one behavioural issue: starting a normal preset summon while the group is in combat can destructively kick bots down to the survivor before the add phase blocks on combat.

Immediate next changes:
1. change the unresolved-player warning copy to: `Please place all human players in group slots to summon <PresetName> preset.`;
2. add a root preset-summon combat preflight before any destructive teardown on a normal click;
3. preserve Ctrl-click as the explicit force/destructive override, while keeping the existing add-time combat safety invariant unchanged.

## 0.8.40-dev — combat-safe preset rebuild entry

Runtime commit: `eb76b9e232d94169dd2c2403300bf83bc9b09d51`

Built after the 0.8.39 Stockades gate exposed destructive teardown beginning while the group was already in combat.

Changes:
- normal preset replacement now checks the existing aggressive group/pet combat predicate before any destructive teardown;
- if existing/pending bots mean teardown may be required and combat is detected, the operation is rejected before `SCB_KickBots(false)`;
- Ctrl-click is the explicit destructive override and may start teardown in combat, but the existing burst-level combat gate still prevents bot adds until combat is clear;
- if combat begins while a normal operation is waiting for an in-flight add to resolve, teardown waits rather than kicking during combat;
- unresolved-human wording now reads: `Please place all human players in group slots to summon <PresetName> preset.`;
- summon tooltip text documents the Ctrl teardown override.

Untested:
- 0.8.40 runtime behaviour itself.

Exact next test:
1. with existing preset bots and any relevant member in combat, normal Summon Preset must print the combat-teardown block and kick nobody;
2. Ctrl-click in the same condition may tear down, but no replacement bot may be added until combat clears;
3. trigger the unassigned-human case once and confirm the new preset-specific wording;
4. if these pass, resume deferred post-audit performance work (same-frame Kick All A/B first, then mixed-group maintenance bursts).

## 0.8.41-dev — same-frame Kick All A/B

Runtime commit: `204b0b305168bc421f05bdd8bfc63c219f0a4b59`

Changes:
- removed the 5-uninvite / 0.10-second Kick All queue and its idle frame;
- Kick All now computes the survivor/candidate snapshot once and issues every non-survivor `UninviteByName` request in that initiating frame;
- Kick Dead is unchanged;
- survivor selection/anchor handling is unchanged;
- Active Roster/tracker state remains intact and roster events still own observed departure/settling.

Untested:
- runtime/server behaviour of same-frame large Kick All, especially 20/40-player raids.

Exact next step:
- build mixed-group maintenance bursts of up to five assignments across groups, with exact identity binding, per-bot subgroup placement, one shared 1.0-second stabilization, and unchanged combat/removal safety.

## Deferred command/control ideas — later

These are intentionally deferred and must not be mixed into the current 0.8.39 performance test gate.

### Macro-safe single-target Stay / Move commands

Add slash-command entry points for the existing single-target Stay and Move behaviours so they can be used from player macros.

Requirements:
- operate on the current valid target only, matching the existing UI's One-target semantics;
- if there is no valid target, do nothing rather than falling through to an all/group command or emitting a malformed PartyBot command;
- preserve the existing UI safety rules and feedback where practical;
- exact slash-command names/syntax can be chosen when implemented.

### New Group command scope between All and One

Add a third command scope between `All` and `One`: `Group`.

Desired semantics:
- determine the current Blizzard party/raid subgroup of the player's target;
- resolve the bots currently in that same group from SCB's live roster;
- send the selected bot command to those bots only, not the whole raid;
- expose the scope in the command UI between All and One.

Implementation details to investigate:
- some PartyBot commands may require issuing commands to individual bot targets, which may mean temporarily taking over/changing the player's target;
- if target manipulation is required, preserve and restore the player's original target safely;
- command fan-out must be throttled/queued enough to avoid chat/server spam or mute protection;
- use current live subgroup membership rather than logical preset slot/group when deciding who receives a Group command;
- do not begin this feature until the current performance/refactor work is finished and runtime-approved.

## Status at handoff

The 0.8 line is still a consolidation/refactor branch. Do **not** promote to `main` yet. The user wants the refactor completed first, then a consolidated runtime regression pass, then stable promotion.

0.8.28 is a structural consolidation build and has **not yet been runtime-tested**. The runtime behaviour immediately beneath it is strongly proven through 0.8.27.

### Runtime-proven through 0.8.27

The user confirmed all of the following on the current coordinator architecture:
- completed 5-man party -> different 5-man preset: pass;
- fresh 10-man dungeon preset after zoning: pass;
- completed 10-man -> different 10-man preset: pass;
- Replace Dead across multiple dead bots spanning two raid groups: pass.

This means:
- the coordinator-owned preset rebuild path is proven in both party and raid topology;
- the 0.8.26 maintenance coordinator is proven for multiple simultaneous dead replacements across more than one raid group;
- `PresetRebuild.lua` retirement in 0.8.27 is runtime-proven;
- Missing + Dead together remains opportunistic/unproven, but does not need to be manufactured as a special test before continuing consolidation.

Important correction: **SoloCraft dungeons are 10-man by project rule.** A 10-man dungeon preset intentionally converts to raid after zoning. A 5-man preset/path is still supported, but do not describe dungeons generally as 5-man. UBRS is 15; raids are 20/40.

## 0.8.28-dev — current Git architecture

Commit: `d5934b484cff5f74c49ae57fd829d56a33af3eb4` (`Collapse refill bridge into burst transition layer`)

0.8.28:
- removed `RaidRefill.lua` from the repository and TOC;
- stripped obsolete pre-Spawn wrapper history from `RaidBurst.lua`;
- retained only the survivor/bootstrap helpers still consumed by `Spawn.lua` plus the proven 0.8.26 maintenance coordinator;
- preserved the maintenance coordinator's effective pre-`Spawn.lua` load position so this gate did not mix file retirement with a risky wrapper-order change;
- bumped the addon to `0.8.28-dev` in the same functional commit.

Current non-locale Lua files and approximate sizes on 0.8.28:
- `Presets.lua` — 175,847 bytes (~171.7 KB)
- `SoloCraftBots.lua` — 66,806 bytes (~65.2 KB)
- `Spawn.lua` — 44,427 bytes (~43.4 KB)
- `Raid.lua` — 43,893 bytes (~42.9 KB)
- `Options.lua` — 34,035 bytes (~33.2 KB)
- `Detection.lua` — 30,812 bytes (~30.1 KB)
- `Comms.lua` — 29,918 bytes (~29.2 KB)
- `RaidBurst.lua` — 25,747 bytes (~25.1 KB)
- `Debug.lua` — 22,832 bytes (~22.3 KB)
- `Commands.lua` — 16,327 bytes (~15.9 KB)
- `RaidPlayers.lua` — 14,577 bytes (~14.2 KB)
- `RaidIdentity.lua` — 11,922 bytes (~11.6 KB)
- `ChatFeedback.lua` — 10,297 bytes (~10.1 KB)
- `Location.lua` — 8,479 bytes (~8.3 KB)

## Final architecture decision — six main Lua owners

The user explicitly wants the remaining transitional files collapsed into six coherent main Lua files. File count is not the goal by itself; each surviving file should represent a real subsystem.

Target:

```text
SoloCraftBots.lua
Presets.lua
Roster.lua
Spawn.lua
Communication.lua
Options.lua
```

Locale files remain separate.

### 1. `Raid.lua` + `RaidPlayers.lua` + `RaidIdentity.lua` + `Detection.lua` -> `Roster.lua`

`Roster.lua` is the preferred final name. `Raid.lua` is too topology-specific because the same owner describes parties and raids.

Final Roster ownership:
- observed current group membership;
- party vs raid topology and raid subgroup position;
- humans vs bots;
- alive/dead/missing state;
- persistent Active Roster;
- exact logical preset slot <-> observed member identity;
- intended group vs current group;
- human arrangement / exact logical player-slot observation;
- bot class/spec/role detection and evidence;
- role identity and pfUI role-state integration;
- logical maintenance candidate selection and replacement metadata.

Detection is not considered a separate subsystem anymore. It is evidence used to understand members in the current roster, so `Detection.lua` should ultimately fold into `Roster.lua`.

### 2. `RaidBurst.lua` -> `Spawn.lua`

Final Spawn ownership:
- authoritative physical bot-lifecycle coordinator (`botOperation`);
- spawn command validation/sending;
- preset summon scheduling;
- rebuild lifecycle;
- pending already-sent add recovery;
- bootstrap/survivor parking and removal;
- 3-second capacity-reuse settle enforcement;
- maintenance physical remove -> observe -> settle -> add -> move -> bind lifecycle;
- burst scheduling and assumed-spawn identity preparation.

After absorption, delete `RaidBurst.lua`.

### 3. `Comms.lua` + `Commands.lua` + `ChatFeedback.lua` -> `Communication.lua`

`Communication.lua` is the agreed final name.

Final Communication ownership:
- outbound player/bot commands;
- `/say` / `/party` command routing;
- SoloCraft / PartyBot command payloads that are not owned by Spawn's validated add sender;
- incoming chat/server feedback parsing;
- addon/preset communication;
- command-button execution and command-side safety policy where appropriate;
- communication feedback/state interpretation.

Do not call the final file `Commands.lua` or `Comms.lua`; both are too narrow for the bidirectional layer.

### 4. `Debug.lua` + tutorial/onboarding code -> `Options.lua`

Final Options ownership:
- user settings and option UI;
- tutorial/onboarding/help system;
- tutorial state and reset controls;
- future expanded tutorial/help features;
- developer/debug tooling as a clearly separated section at the end of the file;
- debug log/UI, debug toggles and developer probes.

The user accepts Debug being slightly conceptually distant from normal options because it can live as a distinct Developer/Debug section at the end. Tutorials are intentionally moving here because the user expects to expand them later.

Tutorial code currently buried in `Presets.lua` should move to `Options.lua`; do not leave preset-specific historical placement as permanent ownership.

### 5. `Location.lua` -> `Presets.lua`

Final Presets ownership:
- preset groups, preset data, save/load/editor UI;
- configured/desired logical group structure;
- location -> preset-group mapping;
- location capacity policy / valid challenge tiers;
- optional automatic preset-group switching;
- preset execution snapshots and preset-related validation where they logically belong.

The location subsystem is now considered preset-selection/capacity policy rather than a standalone runtime owner. This supersedes the earlier cautious migration-log note that Location should not be forced into Presets merely for file-count reduction.

Also remove old user-facing refill/maintenance compatibility machinery from `Presets.lua` once dependency audit proves no remaining callers need it:
- legacy `refillState` physical scheduler;
- legacy `replaceDeadState` physical scheduler;
- obsolete compatibility wrappers/entry points superseded by `botOperation`.

`Presets.lua` is currently the largest file (~172 KB). Large size is acceptable, but the cleanup must ensure it is genuinely preset/editor/location code rather than accumulated runtime archaeology.

### 6. `SoloCraftBots.lua` remains core

Keep as the core/bootstrap owner for addon setup, shared primitives, common UI/frame/event plumbing and base state that does not belong to one of the five functional subsystems above.

## Important distinction: preset groups vs live roster

Do not conflate these during the collapse.

`Presets.lua` owns the **desired/configured structure**:
- World / Dungeon / Black Rock Spire / raid preset groups;
- requested size and logical slots;
- location-to-preset-group policy.

`Roster.lua` owns the **real current group**:
- who is actually present;
- party/raid/subgroup position;
- bot/human/dead/missing state;
- observed identity and logical association.

## Canonical bot-operation / removal rules

`Spawn.lua` owns one authoritative top-level physical operation coordinator:

```text
SCB.botOperation = {
  id,
  kind,
  active,
  status,
  phase,
  revision,
  desiredIntent,
  startedAt,
  updatedAt,
  rebuild?,
  safety?,
  maintenance?
}
```

### Removal settle

Canonical rule:

> removal requested -> observe absent from Blizzard roster -> wait 3.0 seconds -> permit an add that depends on the freed capacity.

The delay protects **capacity reuse**, not harmless work.

Allowed during the settle when they do not consume the freed slot:
- party-to-raid conversion;
- subgroup movement / G8 parking;
- human arrangement;
- roster observation;
- unrelated raid bursts that still fit without the freed capacity.

Strict examples:
- Replace Dead/Missing removal -> replacement;
- old teardown -> new G1 when capacity depends on that teardown;
- 5-man bootstrap -> reserved final bot;
- final raid burst if it needs the bootstrap's freed slot.

### Bootstrap terminology

Preferred definition:

> bootstrap = temporary bot occupant used to establish or preserve required party/raid/instance continuity during a preset transition.

Origin is secondary. Existing survivor, saved-ID anchor and fresh raid bootstrap are variants of the same concept.

Rules:
- use a bootstrap only when continuity actually requires one;
- if humans already preserve topology, do not retain an extra bot merely for topology;
- prefer reusing an existing bot over manufacturing one;
- target preset topology is authoritative; bootstrap state alone never implies raid conversion;
- genuine 5-man target stays party and reserves exactly one final bot assignment while the bootstrap occupies a slot;
- raid target may park a retained bootstrap in G8 and overlap its later removal settle with unrelated bursts that do not need that capacity.

## Maintenance coordinator state

0.8.26 moved user-facing Replace Missing / Replace Dead physical lifecycle into `botOperation(kind="maintenance")`.

Logical maintenance selection remains roster-owned. Physical lifecycle is Spawn-owned.

Important current behaviour:
- click collects Missing + Dead together via `SCB_GetActiveMaintenanceRecords()`;
- dead bots are removed together except for a required safety survivor;
- already-missing assignments and removed-dead assignments are combined and sorted by group/slot;
- replacement bursts are prepared with explicit assumed-spawn identity plans;
- each full replacement burst waits 1 second after final subgroup placement before binding authoritative order;
- bounded timeouts replace silent hangs: removal 15s, burst arrival 12s, subgroup move 15s;
- local player combat is an absolute block;
- stale remote member/pet combat may be overridden after 10s only when the player is personally clear;
- maintenance abort must not fall through the old global abort path that destroys persistent preset tracker state.

Runtime proof: multiple dead bots across two groups were replaced successfully in a 10-man dungeon raid.

## Known observation issue

Historical intermittent issue: a genuinely dead bot was once omitted from Replace Missing/Dead in Naxx.

Current leading hypothesis is transient Vanilla `UnitIsDeadOrGhost` observation or an unavailable replacement record, not the maintenance lifecycle itself. Do not use `UnitHealth()==0` as an automatic death fallback because out-of-range/unknown Vanilla health semantics can produce unsafe false positives and kick live bots.

If the issue recurs after consolidation, investigate dead-state observation/classification specifically.

## Current migration sequence recommendation

Do not collapse all remaining files in one unreviewable commit. Preserve proven ordering and gate meaningful ownership moves.

Suggested order:
1. finish physical lifecycle ownership: absorb `RaidBurst.lua` into `Spawn.lua`, then runtime smoke preset rebuild + multi-group maintenance;
2. consolidate roster ownership: fold `RaidPlayers.lua`, `RaidIdentity.lua` and `Detection.lua` into the current Raid owner, remove dead wrappers, then rename the final owner `Roster.lua` when the merged behaviour is stable;
3. merge `Comms.lua` + `Commands.lua` + `ChatFeedback.lua` into `Communication.lua` with no behaviour change;
4. move `Debug.lua` and tutorial/onboarding code into `Options.lua`, keeping clear sections;
5. move `Location.lua` into `Presets.lua` and delete old preset-local refill/maintenance compatibility machinery only after call-site audit;
6. run a consolidated regression pass, then consider stable `main` promotion.

The exact version numbers for each step are not precommitted. Use the next `0.8.x-dev` number for each functional build and bump the TOC in that same commit.

## Current commit chain of interest

- 0.8.24: `aa96f9136cee600cee0a09e50fe95fe6f606154f` — unified retained preset bootstrap continuity
- 0.8.25: `b38acce40c3f6447acb878324dcd7859e74671d3` — absorb bootstrap continuity into permanent owners
- 0.8.25 docs: `73b7edc15a7dfc8379421317fa57dd23d0f54add`
- 0.8.26: `2bf114e66f407ec9193287009e7db367693ac503` — route maintenance through bot coordinator
- 0.8.27: `cbf370074edea2f4615e1cd97f93e5a019675fdc` — retire superseded preset rebuild layer
- 0.8.28: `d5934b484cff5f74c49ae57fd829d56a33af3eb4` — collapse refill bridge into burst transition layer

## Change-control / Git process — mandatory

- Current repo/docs/Git state is source of truth over old chat assumptions.
- Every actual addon/runtime change bumps the TOC version in the same commit.
- Docs-only commits do **not** bump the TOC version.
- Stage candidate commits off-branch without moving `dev`.
- Use low-level Git data operations: `create_blob` -> `create_tree` -> `create_commit`.
- Inspect candidate file content/diff and `compare_commits` base -> candidate.
- Recheck `dev` head immediately before promotion.
- Promote only by non-force `update_ref` (`force=false`).
- **Never use `create_file` for staging experiments.** This rule exists because it has already caused repeated process mistakes even when the calls happened to fail harmlessly.
- No Lua/luac interpreter is available in the working environment; static review is not a substitute for user runtime testing.

## Promotion rule

Do not move `main` merely because the file consolidation is complete. Stable promotion should contain the exact runtime-tested consolidated code, with dev-only title/version adjusted appropriately and no unrelated cleanup mixed into the promotion commit.
