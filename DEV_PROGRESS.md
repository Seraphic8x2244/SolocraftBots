# Development Progress

## Current
- Branch: `dev`
- Version: `0.8.72-dev`
- Current runtime commit: `15586faeade26e4c0ec16698c25cb80239c45208`
- Latest status commit before this update: `301f604f8b9b66f9fc800e01d74f49539188d5b8`
- Goal: finish reliable Group-command targeting, then align 5-player roster/editor/maintenance behaviour with the same logical-slot model already used for raid presets.

## Recent Commits
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

## Implemented / Awaiting Test
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
- Static All-route audit confirms the addon uses distinct explicit commands (`cometome`, `unpause all`, `moveall`, `stayall`, `pause all`, plus standalone All routes). This does not prove server behavior while a target is selected; runtime verification is still required before any All-row greying is added.
- The acknowledgement tap runs before the existing ChatFrame display filter, so hidden bot messages remain available to Group verification without being shown.
- Existing bot-chat filter patterns provide actor-identifying response text for every Group-row target command:
  - Come: `Name* is coming to your position.`
  - Move: `Name* is now moving.` / `Name* is moving.`
  - Stay: `Name* is now staying.` / `Name* is staying.`
  - Pause: `Name* ... paused for 30 seconds.`
  - Play/unpause: `Name* ... unpaused.`
  Actor-specific movement failures also identify the selected name. These messages are filtered only at ChatFrame display, so they can be consumed internally as acknowledgements while remaining hidden.
- 0.8.68-dev targeted control behavior is user-tested as highly responsive/reliable overall; the human-locator stale-target hang was the one reproduced blocker. 0.8.69-dev contains the focused fix and is not yet user-verified.

## Current Issues
- Play All and Pause All currently route to invalid server commands (`unpause all` / `pause all`).
- Come All currently routes to conditional `cometome`; with a valid bot selected the server narrows it to that bot, so the addon does not currently guarantee All semantics for Come.
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
- Version/commit: `0.8.72-dev` / `15586faeade26e4c0ec16698c25cb80239c45208`
- Targeted-command behavior remains thoroughly user-verified and working as expected.
- Server command semantics were directly verified from server chat responses:
  - `moveall` works globally with a player target or no target.
  - `stayall` works globally with a player target or no target.
  - `cometome` (and undocumented `come`) is conditional: valid bot target -> that one bot; no valid bot target -> all bots.
  - `pause all` is not a valid server command. The server command is bare `pause`, whose previously verified semantics are valid bot target -> one bot; no valid bot target -> all bots.
  - `unpause all` is not a valid server command. The server command is bare `unpause`, whose previously verified semantics are valid bot target -> one bot; no valid bot target -> all bots.
  - `aoe` requires a living enemy target.
  - `usegobject` is global for bots in the group but requires both player and bots to be near the object; it cannot remotely operate an object.
  - `attackstart` requires a living enemy target.
  - `attackstop` requires a living enemy target.
  - All tested role commands are target-agnostic.
  - Server advertises `comehealer` and `spreadon`, but the existing aliases `comeheal` and `spread` are confirmed working.

### Next Test
- No further server-command audit is required for the currently exposed command matrix.
- Resolve the addon-side All-route mismatches exposed by the audit before promotion:
  - Play All currently sends invalid `unpause all`.
  - Pause All currently sends invalid `pause all`.
  - Come All currently sends conditional `cometome`, so with a valid bot selected it affects only that bot rather than all bots.
- Preserve proven routes:
  - Move All -> `moveall`
  - Stay All -> `stayall`
  - role routes remain target-agnostic
  - AoE/Attack Start/Attack Stop remain enemy-target-dependent
  - Object remains global-with-proximity semantics.
- Covered-slot multiplayer testing remains pending until a second human is available.

## Planned / To-do
- Audit every All-row command against actual server behaviour. The addon currently routes All through explicit all-style PartyBot commands, but verify that having a selected target cannot make any of them target-scoped. If any All command becomes target-sensitive while a target exists, disable/grey that All control while a target is selected rather than allowing ambiguous behaviour.
- Expose human-over-bot drag/drop for 5-player presets: exact human identity -> exact logical slot -> suppress underlying bot intent while that human is present.
- Stop deriving 5-player logical human ownership from Blizzard party-row order once explicit assignment exists.
- Preserve deterministic bot logical order while treating human physical placement as observational.
- Reuse existing tracker/preset slot data and proven refill semantics; avoid duplicating raid logic in a party-only path.
- Post-replacement human-return policy is resolved: the user must manually free a group slot before the human can return; no automatic addon action is required.

## Ideas / Backlog
- Do a full pass over button artwork/colour states so available, disabled, active and selected states are visually consistent across the addon.
- Audit every centre-screen error/warning message for wording, severity, consistency and whether it belongs in centre-screen UI versus chat.
- Future visualiser concept: a gnomish LCD/pixel-display panel showing what the command machine is doing. The shared Single/Group pipeline should make queued state/status/icon output possible later; keep the visualiser as a consumer of pipeline state/events rather than coupling UI logic into the sequencer.
- Consider whether Group row availability/UI refresh should also force a fresh snapshot, or whether fresh-on-command is sufficient after runtime testing.
- After the logical-slot work is stable, simplify or retire overlapping legacy refill paths only with migration/runtime proof.

## Deferred
- Do not add a delay between Ctrl-click Move and Come unless runtime evidence specifically shows the same-frame pair failing.
- Do not perform unrelated scheduler, identity or maintenance refactors while working on logical human-slot maintenance.
- Do not treat Blizzard row/order as logical preset identity.
- Dedicated 0.8.62-only timing validation is deferred; its behaviour will be covered with the current Group build.

## Exact Next Step
Design the safest addon-side implementation for All Come, All Pause and All Play using the verified server semantics. Do not rely on invented `pause all` / `unpause all` commands. Do not assume clearing the client target immediately guarantees a no-target server state; previous stale-target testing proved client/server target propagation can lag.
