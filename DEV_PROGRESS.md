# Development Progress

## Current
- Branch: `dev`
- Version: `0.8.81-dev`
- Current runtime commit: `893bd5decaec458047114a6a9098e984f4f6de68` (0.8.81-dev)
- Branch head before this docs-only update: `893bd5decaec458047114a6a9098e984f4f6de68` — persistent taxi-transition polling fix.
- Latest status commit before this update: `5948d69aaf8d9333c8ffa351d8317187fc35a888`
- Stable release: `0.8.78` on `main`, promotion commit `87e61360ec36c2d9543b2e1bc8606b948b10d6bd`.
- Goal: correct the still-failing taxi watcher lifetime now that direct runtime proof shows `UnitOnTaxi("player") == 1` mid-flight, then runtime-clear taxi safety plus item 2.1 manual Add before item 2.2. Received-slot work remains item 2.3; visualiser remains deferred.

## Recent Commits
- `893bd5decaec458047114a6a9098e984f4f6de68` — 0.8.81-dev: keep polling taxi state through control-lost/gained transitions so delayed `UnitOnTaxi` updates cannot leave the UI active during flight.
- `ddde3789f75c7cabafaea2baa72733a06ea1d5c9` — 0.8.80-dev: disable bot-affecting UI/execution while `UnitOnTaxi("player")` is true and handle the exact flying spawn rejection.
- `46ac48b01f9b701abe0b9151124a1e225a44a262` — 0.8.79-dev: route addon manual Add through a tracked one-assignment `manual-add` bot operation with explicit identity, join/timeout ownership and a 1.0-second minimum floor.
- `87e61360ec36c2d9543b2e1bc8606b948b10d6bd` (`main`) — promote tested 0.8.78-dev runtime to stable 0.8.78; release tree differs only by stable TOC metadata and removal of top-level dev status files.
- `0200cdb5ef59fc0cb4ef81016237d90ba16e22b9` — 0.8.78-dev: make `/scb move` and `/scb stay` combat-first conditional macros: friendly bot target -> Single, otherwise explicit All.
- `0090afc78c801a5ac3a7f61ce3d07b0d75bf6b1a` — 0.8.77-dev: make unavailable command buttons truly disabled; its target-only silent macro policy was superseded by 0.8.78 before runtime test.
- `96781f32a40b5956051274affdc939913d76c54a` — 0.8.76-dev: centralize command requests behind declarative target semantics and one request front door.
- `2b19431de271906ae99d67b55e779488d8ca14d0` — 0.8.75-dev: make Single controls direct/spammable while leaving Group sequencing/pacing unchanged.
- `25f3a915e17470346629bbdb7c3904f40114fef0` — 0.8.69-dev: recover from stale human Group locator targets by treating `Target is not a party bot` as a failed targeted attempt.
- `b02d67e7a35104a8fed4c5543ad4a26c0c1fe10a` — 0.8.68-dev: share one acknowledgement sequencer between Single and Group targeted controls; narrow exclusivity so global controls remain live.
- `8daa9aaca9567bc183c9e00ac4b88507e1cce33e` — 0.8.67-dev: remove speculative Group ack timeout/retarget retries; wrong acknowledgements immediately resend to the already-selected intended bot.
- `aa7f6f5aa3add58cc6b19461a9f69d7f23a92a9e` — 0.8.66-dev: Group fan-out advances from actor-identifying server acknowledgements and retries stale/missing recipients.
- `04807e4789646b6f3d87b228853ecd578c4107ad` — 0.8.65-dev: covered preset slots become Missing when their tracked human leaves and re-cover if that human returns before replacement.
- `160620b37b697963999fd61712dbde322df6e1a2` — 0.8.64-dev: preserve human-covered preset bot intent as dormant Active Roster slots.
- `541821f7e2cf6e27f7f51ce275f3b5befe038aad` — 0.8.63-dev: Group command startup refreshes the live roster once before resolving subgroup and recipients.
- `30e1f5d8f9b0e33a5bddaa8882e0d8d37468f6c9` — 0.8.62-dev: uniform 0.15s Group target settle/hold around every recipient.

## Completed / Verified
- Normal control commands use GUILD transport; spawn/add traffic remains SAY. User-verified on 0.8.54-dev.
- Macro-safe targeted `/scb stay` and `/scb move`, including no-target safety, are user-verified from 0.8.52-dev.
- Group targeting visibly cycles subgroup bots rather than only affecting the initially selected bot.
- Runtime testing showed target-propagation padding materially improves Group reliability: 0.8.60-dev reached roughly 95% success on the final recipient in the tested 5-player case.
- The preset execution tracker already stores every logical bot assignment plus exact tracked human `slotIndex`; the loss was in the tracker -> Active Roster handoff, not in preset storage.
- Active Roster slot consumers consistently gate bot expectations on `slot.expected`.
- 0.8.72-dev targeted-command smoke test is user-verified: bot-target Group controls, Ctrl-Come, busy-sequence messages, human/self blocking and no-target blocking all work as expected.
- 0.8.75-dev runtime gate is user-smoke-tested: rapid Single spam appears to work and Group still feels good, with no reported sequencing regression. This cleared the gate for the command-pipeline convergence.
- 0.8.78-dev command regression smoke is user-verified: combat-first Move/Stay macros work for All vs targeted-bot scope as intended; unavailable command buttons are truly inert with no gold highlight; valid buttons re-enable; Single spam and Group sequencing remain good.

## Implemented / Awaiting Test
- 0.8.81-dev corrects the 0.8.80 taxi transition failure:
  - `UnitOnTaxi("player")` remains the authoritative taxi signal;
  - the taxi watcher now polls every 0.10s for the full `PLAYER_CONTROL_LOST` interval instead of doing one delayed read;
  - after `PLAYER_CONTROL_GAINED`, it continues polling for a 2.0-second settle window and will keep polling longer if `UnitOnTaxi` still reports true;
  - opening the SCB main frame also starts the same short settle watcher;
  - no roster/session/Active Roster state is cleared or reclassified because bots temporarily despawn as world entities on taxi;
  - 0.8.79 manual Add identity/cooldown behavior is unchanged.
- 0.8.81 static inspection passed: two-file runtime diff, Lua block-balance clean, TOC/version consistency and non-force promotion after final branch-head recheck. Not user-tested yet.
- 0.8.80-dev adds the taxi-flight safety prerequisite on top of 0.8.79:
  - `UnitOnTaxi("player")` is the authoritative local taxi signal;
  - Commands, Assignments, and Summon sections are covered by high-level mouse blockers/dimmers while taxiing, so their nested operational controls cannot click through;
  - Preset editing remains usable; only Preset Summon is separately blocked/dimmed;
  - window close/toggle and non-bot editor/configuration interaction remain usable;
  - taxi state refreshes on main-frame show, world entry, and `PLAYER_CONTROL_LOST`/`PLAYER_CONTROL_GAINED`, with a short deferred refresh for transition timing;
  - entering taxi during an active physical bot spawn operation aborts that operation cleanly;
  - `SCB_SendSpawnCommand` has a hard taxi guard, so addon spawn traffic cannot escape through a stale UI or alternate addon path;
  - manual Add availability/request also hard-check taxi state;
  - the exact server line `Cannot add bots while flying.` is recognized as a fallback rejection, aborting owned spawn runtime and showing `Cannot summon bots while flying.`.
- 0.8.80 static inspection passed: scoped diff review, Lua block-balance checks on all modified Lua files, blocker/entry-point review, TOC/version consistency, and non-force promotion after final `dev` head recheck. Not user-tested yet.
- 0.8.79-dev implements architecture item 2.1, tracked addon manual Add:
  - one click validates/canonicalizes exactly one class/role/extra assignment and begins a `manual-add` `SCB.botOperation`;
  - one explicit assumed-spawn burst is registered before `SCB_SendSpawnCommand`, so join-message/roster-delta identity binding is shared with preset and maintenance spawning;
  - generated command extras are recorded from the actual validated payload, including defaulted Shaman totems/Paladin blessing behavior;
  - all addon manual Add role buttons are truly disabled while a bot operation owns the roster, and while the shared paced kick queue is active;
  - after send, Add remains locked until both the 1.0-second minimum floor has elapsed and the expected named bot is observed/bound; if no bot resolves, the existing 5-second pending-add timeout releases the operation;
  - successful fallback-polled arrivals are explicitly recorded in session state and synchronized into Active Roster, including the requested assumed role/extra, before the lock is released;
  - timeout/abort removes only that manual burst's still-unbound assumed identity so it cannot steal the next bot;
  - existing SAY spawn transport, immediate Add request feedback, auto-loot adoption and raw user-typed PartyBot behavior are preserved.
- 0.8.79 static inspection passed: base->candidate diff review, Lua block-balance checks on all modified Lua files, command/order audit proving assumed identity registration precedes send, direct-manual-send call-site audit, TOC/version consistency, and non-force promotion after a final `dev` head recheck.
- An earlier staged candidate `5c6a16570dc89b12c0acb82f2e9cd8fee9f2e61f` was rejected before promotion because it did not canonicalize generated extras and did not explicitly adopt a fallback-polled arrival; corrected candidate `46ac48b...` is the promoted runtime.
- 0.8.78-dev supersedes only the 0.8.77 Move/Stay macro policy:
  - `/scb move` and `/scb stay` are intentionally combat-first and always responsive;
  - friendly bot target -> request `target` scope and command that bot only;
  - any other target context, including no target, hostile target or player target -> request the explicit `all` scope (`moveall` / `stayall`);
  - both branches still go through `SCB_RequestCommand`; no ambiguous bare-command fallback is used;
  - the UI Single row remains target-only and unchanged.
- 0.8.78 static inspection passed: two-file diff only, Lua block-balance clean, TOC/version consistency, staged/non-force promotion. Not yet user-tested.
- 0.8.77-dev is a narrow regression fix on top of the 0.8.76 command front door:
  - its `/scb move` / `/scb stay` silent target-only macro behavior was superseded by the combat-first 0.8.78 policy before runtime test;
  - metadata-unavailable command buttons now call WoW `Button:Disable()` as well as greying to 0.5 alpha, preventing click execution and the button HIGHLIGHT/gold-border state while unavailable;
  - re-enabling is driven by the same unified availability refresh;
  - Single/Group/All/role semantics and Group timing are unchanged from 0.8.76.
- 0.8.77 static inspection passed: candidate diff review, Lua block-balance checks on modified owner files, TOC/version consistency and non-force staged promotion. No in-game result exists yet for 0.8.77.
- 0.8.76-dev introduces the first single-pipeline command convergence step:
  - every command-table entry declares a target semantic: target-agnostic, friendly-bot recipient, living-enemy context, or conditional friendly-target sensitivity;
  - `SCB_RequestCommand(commandKey, scope, modifiers)` is the command-matrix front door for UI buttons and supported command macros;
  - Single still sends immediately/fire-and-forget with no acknowledgement lock or Group 24/sec budget;
  - Group still owns actor-acknowledged sequencing, addon retargeting, 0.10-second settle after actual target changes, busy-message precedence, retries and the rolling 24/sec budget;
  - All Come/Play/Pause keep their existing friendly-player/bot target block, now from metadata rather than button-local conditionals;
  - role and paired-role commands remain target-agnostic;
  - AoE, Attack Start and Attack Stop now validate the already user-verified living-enemy requirement and grey/update from the same availability query;
  - roster changes and target-health changes refresh the unified command availability surface;
  - Spread toggle and `/scb stay`, `/scb move`, `/scb attackstart` now enter through the same request front door;
  - the blocked friendly-target wording is now `Only bots can be issued commands`.
- Static inspection for 0.8.76 passed: base->candidate diff review, Lua block-balance check on modified owner files, command call-site audit, stale-refresher audit, and non-force staged promotion. No in-game result exists yet for 0.8.76.
- 0.8.62-dev introduced uniform Group timing:
  `target -> 0.15s settle -> command(s) -> 0.15s hold -> next target`.
- 0.8.63-dev keeps Group-row UI refresh cached, but an actual Group command forces one fresh live-roster snapshot before subgroup/recipient resolution.
- 0.8.64-dev preserves a human-covered preset assignment as a dormant Active Roster slot with its underlying class/role/extra and logical slot intact.
- 0.8.65-dev adds the covered-slot lifecycle:
  - named human present -> `expected=false/state="covered"`;
  - named human absent -> same logical slot becomes `expected=true/state="missing"`;
  - named human returns before replacement -> slot becomes covered again;
  - once a replacement bot is bound, `coveredBy` is cleared and the slot becomes a normal expected bot slot.
- Replace Missing therefore reuses the existing Active Roster replacement record and spawn path; no separate party refill mechanism or spawn scheduler was added.
- Ctrl-click Group Come still sends Move + Come back-to-back in the same recipient send phase.
- 0.8.67-dev implements the agreed event-driven Group queue:
  - actual target change -> 0.10s settle -> send command(s) -> wait for acknowledgement(s);
  - all expected acknowledgements from the intended bot -> immediately target the next recipient;
  - wrong-bot acknowledgement -> keep the intended client target and immediately resend the same command(s), with no extra target swap or settle;
  - no acknowledgement timeout and no arbitrary retry limit were added;
  - Ctrl-Come remains one attempt containing back-to-back Move + Come; both response kinds are consumed before deciding success/failure, preventing a leftover response from the failed pair contaminating the retry;
  - the existing rolling 24 commands/sec budget remains the only pacing constraint beyond the 0.10s settle after actual target changes.
- 0.8.67-dev also narrows duplicate ChatFrame acknowledgement suppression to cross-frame copies, so a genuine repeated server reply during an immediate retry is still processed.
- 0.8.68-dev generalizes the Group acknowledgement engine into one targeted-command sequencer shared by Single and Group:
  - only one Single/Group targeted sequence can be active; a second targeted click is neither invoked nor queued;
  - Single captures the manually selected bot and sends immediately with no initial settle;
  - a wrong-actor Single acknowledgement retries once only while that same intended bot is still the player's current target;
  - a second wrong acknowledgement, or a player target change before retry, aborts without retargeting the player and emits the localized failure message plus `igQuestFailed` sound;
  - Ctrl-Come uses the same two-ack Move + Come attempt in both Single and Group modes;
  - Group preserves the 0.10s settle only after addon-driven target changes and its acknowledgement-driven immediate retry/advance behavior;
  - Single and Group share one rolling 24 commands/sec history.
- 0.8.68-dev removes the old broad `SCB_SendCommand` Group lock. All/role/standalone commands can send while a targeted sequence is active, and delayed `/scb attackstart` no longer waits for Group completion.
- Macro `/scb move` and `/scb stay` now enter the same Single-target acknowledgement sequencer instead of bypassing it.
- 0.8.69/0.8.70 human-target recovery was superseded after runtime testing proved bare `come`, `pause` and `unpause` can fall back to global behavior when the server target is a player or absent.
- 0.8.71-dev adopts the simpler safety rule: Group controls only operate when a friendly bot is currently targeted. A human/player target cannot be used as a Group locator and no Group sequence starts from it. Group command-row availability follows the same bot-target requirement. The normal bot-to-bot acknowledgement/retry sequencer remains unchanged.
- 0.8.72-dev adds localized centre-screen blocked-start feedback: active Group -> `Already commanding a group, please wait...`; active Single -> `Already commanding a bot, please wait...`; friendly human/self target -> `Humans cannot be commanded...`; no target/other invalid target -> `Command... what?`. Busy-state feedback takes precedence over target validation.
- 0.8.73-dev introduced friendly-player/bot gating for conditional All controls, but also changed the existing All Play/Pause server routes; that route change caused a regression and was not part of the requested UI gating.
- 0.8.74-dev restores the pre-existing All Play/Pause routes and keeps only the requested gating: All Come/Play/Pause are greyed and blocked when a friendly player or bot is targeted, and remain available for no target, hostile targets and friendly NPC targets.
- Static All-route audit confirms the addon uses distinct explicit commands (`cometome`, `unpause all`, `moveall`, `stayall`, `pause all`, plus standalone All routes). Current target-sensitivity rules are now represented by 0.8.76 command metadata and need the 0.8.76 runtime smoke.
- The acknowledgement tap runs before the existing ChatFrame display filter, so hidden bot messages remain available to Group verification without being shown.
- Existing bot-chat filter patterns provide actor-identifying response text for every Group-row target command:
  - Come: `Name* is coming to your position.`
  - Move: `Name* is now moving.` / `Name* is moving.`
  - Stay: `Name* is now staying.` / `Name* is staying.`
  - Pause: `Name* ... paused for 30 seconds.`
  - Play/unpause: `Name* ... unpaused.`
  Actor-specific movement failures also identify the selected name. These messages are filtered only at ChatFrame display, so they can be consumed internally as acknowledgements while remaining hidden.
- 0.8.68-dev targeted control behavior is user-tested as highly responsive/reliable overall; the human-locator stale-target hang was the one reproduced blocker. 0.8.69-dev contains the focused fix and is not yet user-verified.

## 2026-09-22 Full Addon Pipeline Audit / Agreed Direction

The current consolidation is substantially aligned with the intended architecture, but several live bypasses/compatibility paths remain. The target is **not** one giant state machine. Each domain gets one obvious request/ownership path, and a future read-only activity/status surface exposes state to presentation consumers such as the visualiser.

### Physical bot lifecycle
- `Spawn.lua` / `SCB.botOperation` remains the authoritative owner for physical bot-roster mutation and waits on the consequences of those mutations.
- Preset summon/rebuild and Replace Missing/Dead already use this coordinator and should remain the proven base.
- Addon manual Add buttons should become a lightweight one-assignment `manual-add` operation:
  - class/role/extra are prepared as one explicit spawn intent;
  - the joining bot is identity-bound through the same assumed-spawn/burst machinery;
  - manual Add is unavailable while a preset/rebuild/maintenance/manual-add physical operation owns the roster;
  - after a manual Add is sent, enforce at least a 1.0-second button cooldown **and** do not permit the next addon manual Add until the expected bot has been observed/bound or the existing short spawn timeout has expired. The cooldown is therefore a floor, not the only identity-safety barrier.
- A user manually typing a raw `.partybot add ...` command while SCB is in the middle of a physical operation is outside the supported coordinator contract; do not add fragile interception for arbitrary user chat commands.
- Remote/requested preset summon currently bypasses the top-level operation coordinator by calling `SCB_StartPresetSummonSnapshot()` directly. Fix this so accepting a remote summon enters the same preset-operation request path as the local Summon button.
- Preset communications carry **composition intent**, not execution identity. The requester does not need the generated bot names. The client that actually performs the summon owns bot-name -> logical-assignment binding as joins arrive.
- When a received preset is saved, preserve transmitted exact human `slotIndex` data as preset `playerSlots`; current save-received code keeps group/role but discards the exact slot.

### One logical-slot model at every preset size
- Five-player and raid presets should share the same editor semantics: a human identity owns an exact logical slot and suppresses the underlying bot intent while present.
- `size <= 5` is a **topology policy**, not a separate editor/identity model:
  - remain a party;
  - never convert to raid;
  - do not attempt subgroup manipulation;
  - preserve deterministic remaining-bot summon/order semantics;
  - retain the proven five-player bootstrap rule: one temporary occupant may reserve exactly one final required bot assignment when continuity requires it.
- `size > 5` uses raid topology. Bot subgroup/order placement remains intentionally controlled and deterministic. Human logical slots remain suppression/composition intent only.
- Do not infer a human logical slot from Blizzard party/raid row position. Conversely, do not use a human's logical slot as an instruction to force that human into a particular Blizzard row.
- The current `SCB_ArrangePresetPlayers()` / `PRESET_ARRANGE_PLAYERS` path still actively moves humans between raid subgroups from logical preset assignments. This conflicts with the newer model and should be removed/reworked during the unified logical-slot migration.
- Blizzard raid information remains authoritative for **actual current physical placement**. Bot identity/order is established from explicit summon/burst identity while ignoring human row order; Blizzard observation then tells SCB where every live member actually is.

### Preset live-layout mismatch presentation
Keep saved logical composition stable. Do **not** silently rewrite the preset to match Blizzard's transient layout.

Use the Preset UI as a temporary live-status projection when physical layout differs:
- If subgroup membership/composition is still correct but Blizzard has changed within-group row ordering, the whole affected preset group should **slowly pulse its background yellow**. Tooltip wording: **"Group composition correct; Blizzard client reordered members."**
- If a bot or player has been moved to a different raid subgroup outside SCB (for example through the Blizzard Raid tab), use the same slow yellow group-background pulse. Tooltip wording: **"Group rearranged in Blizzard Raid tab."**
- The pulse is informational, not an error and not an automatic correction request. It disappears when observed live layout again matches the logical/runtime expectation.
- Human row-order scrambling is expected and must not damage logical ownership. Bot logical order remains derived from the controlled summon identity/order, with actual subgroup location observed separately.
- Implementation should distinguish ordinary within-group Blizzard row reordering from actual subgroup-membership changes. Do not claim an exact saved physical row for a human.

### Reusable maintenance intent
- Roster/Active Roster should decide **which logical assignments** require action; Spawn should execute physical mutation.
- Refactor maintenance entry so selection produces a reusable maintenance intent rather than the Replace button owning a unique execution pipeline.
- Existing Replace Missing/Dead becomes one selector of logical assignments.
- Planned **Resummon Group N** becomes another selector: choose the active bot assignments belonging to that logical group, then feed them through the same paced removal -> observe absent -> capacity settle when required -> spawn burst -> identity bind -> subgroup placement -> Active Roster bind lifecycle.
- A future single-bot resummon can use the same mechanism. Do not add another scheduler.

### Declarative command pipeline
- Introduce one conceptual command request entry point. Buttons/macros should request `commandKey + scope + modifiers`; they should not independently implement target safety or sequencing rules.
- Separate **command target semantics** from **scope execution policy**.
- Command target semantics should be declarative metadata, with categories such as:
  - target-agnostic;
  - friendly-bot recipient;
  - living-enemy context;
  - conditional/target-sensitive server command;
  - other explicit context requirements only when server evidence justifies them.
- Scope/execution policy then decides mechanics:
  - Single: requires the appropriate friendly bot target, remains immediate/fire-and-forget/spammable, no Group acknowledgement lock and no Group 24/sec pacing;
  - Group: friendly bot is only the group locator, then the pipeline owns recipient targeting, 0.10-second settle after actual addon retargets, actor acknowledgement checks and the existing 24 commands/sec budget;
  - All/role/pair scopes: immediate when their command metadata says current target context is safe;
  - enemy-context actions such as Attack/AoE validate the hostile/living context but do not treat the enemy as a bot recipient.
- UI availability/greying should ask the command pipeline whether a command/scope combination is currently valid. The UI may display the result but must not own the underlying semantic rule.
- Preserve all runtime-proven command behaviour while moving ownership; do not make Single and Group identical merely to share an entry point.

### Dumb visualiser / shared activity surface
- The future gnomish LCD/pixel visualiser should contain no command, spawn, maintenance, roster or communications decision logic.
- Components should publish/update a small neutral read-only activity/status surface. The visualiser consumes that surface.
- Keep independent status channels where useful (for example Command, Bot Operation, Communication, Roster/Layout) so allowed concurrent activity remains representable instead of forcing unrelated domains into one giant state machine.
- Example Command state: action/scope/phase/current recipient/progress.
- Example Bot Operation state: operation kind/phase/progress/wait reason.
- The same surface can later feed developer diagnostics without coupling debug/UI code into the execution pipelines.
- Build the visualiser only after the pipeline/state surface is stable; it should be mostly presentation.

### Agreed implementation sequence after the 0.8.75 runtime gate
1. Define the declarative command target metadata and one command-request front door while preserving current Single/Group/All/role behaviour.
2. Close physical-lifecycle bypasses: tracked/cooldown-protected addon manual Add; remote accepted summons through the preset operation coordinator; preserve received human exact slots.
3. Perform the unified logical-slot migration for five-player + raid presets, remove logical-human -> physical-row/subgroup coupling, and add the yellow live-layout mismatch pulse/tooltips.
4. Separate maintenance assignment selection from execution and implement Resummon Group through the existing maintenance/bot-operation lifecycle.
5. Delete proven-dead legacy refill/compatibility runtime only after call-site audit and runtime gates show the authoritative paths cover the behaviour.
6. Add the neutral read-only activity/status surface.
7. Return to the visualiser as a dumb consumer of that surface.

## Current Issues
- The 5-player preset UI still derives human rows from current party order rather than exposing raid-style explicit logical slot assignment.
- Blizzard party/raid row placement must remain live observation only once explicit 5-player slot ownership is enabled.
- Post-replacement human return needs no addon arbitration: once Replace Missing has filled the group, the returning human cannot rejoin until the user manually frees a slot. SoloCraftBots must not auto-kick or otherwise make that choice.
- Pending regression items remain: dungeon -> 10-player preset retest for the 0.8.55 scope fix; monitor the intermittent 0.8.50 first-summon subgroup mismatch; Replace Dead still needs its separate runtime smoke.

## Testing

### Group Command Timing History
- No pause between retarget and command: did not work.
- 0.20s single pause: worked roughly 20% of the time.
- 0.10s before + 0.10s after each recipient: roughly 99% overall, except bot 4 remained unreliable.
- 0.10s before + 0.10s after, with bot 4 using 0.15s before + 0.15s after: roughly 99% for bots 1-3 and roughly 90% for bot 4.
- Uniform 0.15s before + 0.15s after every recipient: regressed to approximately the same behaviour as uniform 0.10s before + 0.10s after rather than improving monotonically.
- Current 0.8.65-dev feedback: when the fourth bot appears to miss a Group movement command, unfiltered bot movement output shows the third bot receives that movement command a second time. The chat/control command is therefore reaching the server, but server-side target state is still bot 3 when the fourth recipient's command is processed.

### Last Test
- Version/commit: `0.8.75-dev` / `2b19431de271906ae99d67b55e779488d8ca14d0`
- User smoke on 2026-09-22: rapid Single spam appears to work and Group still feels good. No sequencing regression was reported.
- Treat the 0.8.75 gate as passed for progression, but do not upgrade unreported subcases to separately user-tested; Single Ctrl-Come was not explicitly re-reported in this pass.
- Previously verified server command semantics remain the basis for 0.8.76 metadata:
  - `moveall` works globally with a player target or no target.
  - `stayall` works globally with a player target or no target.
  - `cometome` (and undocumented `come`) is conditional: valid bot target -> that one bot; no valid bot target -> all bots.
  - `pause all` is not a valid server command. The server command is bare `pause`, whose previously verified semantics are valid bot target -> one bot; no valid bot target -> all bots.
  - `unpause all` is not a valid server command. The server command is bare `unpause`, whose previously verified semantics are valid bot target -> one bot; no valid bot target -> all bots.
  - `aoe`, `attackstart` and `attackstop` require a living enemy target.
  - `usegobject` is global for bots in the group but requires both player and bots to be near the object; it cannot remotely operate an object.
  - All tested role commands are target-agnostic.
  - Server advertises `comehealer` and `spreadon`, but the existing aliases `comeheal` and `spread` are confirmed working.

### 0.8.76 Runtime Findings
- Partial user test on 2026-09-22 found two regressions:
  - `/scb move` and `/scb stay` now show the invalid-target error with no target. Pre-0.8.76 macro behavior was intentionally target-only and silent when no friendly bot was selected; do not make these macros fall through to broad server behavior.
  - command buttons that are visually grey/unavailable still execute their click/highlight path and show the gold border. Grey command buttons should be truly inert, including no click action and no pressed/highlight feedback.
- No other 0.8.76 behavior is promoted to user-tested from this partial report.

### Last Test
- Version/commit: `0.8.78-dev` / `0200cdb5ef59fc0cb4ef81016237d90ba16e22b9`
- User report on 2026-09-22: all requested 0.8.78 checks are working correctly.
- Verified in this pass:
  - no-target Move/Stay macros use All;
  - friendly-bot-target Move/Stay macros affect only that bot;
  - wrong/non-bot target uses the deliberate All route;
  - grey/unavailable command buttons are inert and do not show the gold highlight/border;
  - valid-context buttons re-enable;
  - Single spam remains good;
  - Group sequencing remains good.

### Next Test
- Runtime-test `0.8.81-dev` taxi detection:
  - board a taxi with SCB already open; within the transition, Commands/Assignments/Summon should become dim and inert and stay that way for the whole flight;
  - preset editor remains usable, but Preset Summon is inert;
  - land and confirm controls restore automatically;
  - if taxi begins while an addon spawn operation is active, it must abort cleanly without changing saved roster identity.
- If the UI still fails to enter taxi state, run `/run DEFAULT_CHAT_FRAME:AddMessage("taxi="..tostring(UnitOnTaxi("player")))` while mid-flight and report the exact value; this distinguishes client/API behavior from event timing.
- Then run the pending 0.8.79 manual Add lifecycle test.
- Covered-slot multiplayer testing remains pending until a second human is available.

## Planned / To-do
- Route accepted remote preset summons through the same preset-operation coordinator as local Summon, while keeping bot execution identity local to the summoning client.
- Preserve received preset exact human `slotIndex` data when saving communicated presets.
- Convert 5-player presets to the same exact logical human-slot editor/model as raid presets and remove human physical placement from logical identity.
- Remove/rework `PRESET_ARRANGE_PLAYERS` so logical human assignments no longer cause physical human subgroup arrangement.
- Add the slow yellow whole-group live-layout mismatch pulse and the two agreed tooltip states for Blizzard row reorder vs Raid-tab subgroup rearrangement.
- Preserve deterministic bot logical order while treating human physical placement as observational.
- Refactor maintenance selection into reusable logical-assignment intents, then implement Resummon Group through the existing bot-operation maintenance execution path.
- Audit every All-row command against actual server behaviour and encode target sensitivity in command metadata rather than button-local conditionals.
- Reuse existing tracker/preset slot data and proven refill semantics; avoid duplicating raid logic in a party-only path.
- Delete proven-dead legacy refill/compatibility runtime only after call-site audit and runtime proof.
- Add a neutral read-only activity/status surface only after command/bot-operation ownership is stable; the visualiser consumes it later.
- Post-replacement human-return policy is resolved: the user must manually free a group slot before the human can return; no automatic addon action is required.

## Ideas / Backlog
- Do a full pass over button artwork/colour states so available, disabled, active and selected states are visually consistent across the addon.
- Audit every centre-screen error/warning message for wording, severity, consistency and whether it belongs in centre-screen UI versus chat.
- Future visualiser concept: a gnomish LCD/pixel-display panel. Keep it deliberately dumb: Command, Bot Operation, Communications and Roster/Layout publish to a neutral activity/status surface; the visualiser only turns that state into text/icons/animation and never inspects scheduler internals directly.
- Consider whether Group row availability/UI refresh should also force a fresh snapshot, or whether fresh-on-command is sufficient after runtime testing.
- After the logical-slot work is stable, simplify or retire overlapping legacy refill paths only with migration/runtime proof.

## Deferred
- Do not add a delay between Ctrl-click Move and Come unless runtime evidence specifically shows the same-frame pair failing.
- Do not intercept or attempt to make arbitrary user-typed raw `.partybot add ...` commands safe during an SCB-owned physical operation; addon buttons are the supported tracked manual-add path.
- Do not collapse Command, Bot Operation, Communications and Roster into one giant state machine merely for the visualiser.
- Do not treat Blizzard row/order as logical preset identity or silently rewrite saved presets to match transient Blizzard layout.
- Do not auto-kick or auto-free a slot when a previously absent human returns after their logical slot has already been replaced.
- Dedicated 0.8.62-only timing validation is deferred; its behaviour will be covered with the current Group build.

## Exact Next Step
Fix the taxi watcher lifetime:
- runtime proof on 2026-09-23 shows `UnitOnTaxi("player")` returns `1` while visibly mid-flight;
- therefore do not change taxi APIs again;
- keep a low-cost taxi poll alive whenever the main SCB window is visible, so a flight begun after the prior 2-second settle window is still detected;
- retain transition polling while player control is lost/gained;
- add hard taxi guards to shared bot-affecting action entry points so stale UI cannot execute commands/removals/spawns;
- preset editing/configuration remains usable; Preset Summon remains blocked;
- do not change roster/session semantics because taxi despawn is temporary world disappearance, not group membership loss.

Then runtime-test taxi gating again before manual Add. Do not begin item 2.2 yet.
