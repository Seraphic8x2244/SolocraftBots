# Development Progress

## Current
- Branch: `dev`
- Version: `0.8.67-dev`
- Current runtime commit: `8daa9aaca9567bc183c9e00ac4b88507e1cce33e`
- Latest status commit before this update: `608380d47b32095e23268c397bd2454060b3954a`
- Goal: finish reliable Group-command targeting, then align 5-player roster/editor/maintenance behaviour with the same logical-slot model already used for raid presets.

## Recent Commits
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
- The acknowledgement tap runs before the existing ChatFrame display filter, so hidden bot messages remain available to Group verification without being shown.
- Existing bot-chat filter patterns provide actor-identifying response text for every Group-row target command:
  - Come: `Name* is coming to your position.`
  - Move: `Name* is now moving.` / `Name* is moving.`
  - Stay: `Name* is now staying.` / `Name* is staying.`
  - Pause: `Name* ... paused for 30 seconds.`
  - Play/unpause: `Name* ... unpaused.`
  Actor-specific movement failures also identify the selected name. These messages are filtered only at ChatFrame display, so they can be consumed internally as acknowledgements while remaining hidden.
- 0.8.61-0.8.67 changes remain implemented but not yet user-verified.

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
- Version/commit: `0.8.60-dev` / `483699234761f0e84871c4129b22523269ae8e38`
- Group retargeting was substantially improved, but the fourth/final recipient remained the distinctive failure point.

### Next Test
- On 0.8.67-dev, repeatedly exercise Group Come with four bots and normal message filtering enabled. Confirm each correct acknowledgement advances immediately with no visible fixed post-command pause.
- Temporarily unfilter movement messages for a stale-target diagnostic pass. Expected failure/recovery shape: intended C is client-targeted, command produces a B movement line, SoloCraftBots immediately resends without another target swap/settle, then C's movement line confirms and the queue targets D.
- Smoke Group Move, Stay, Pause and Play/unpause so each acknowledgement pattern is confirmed in-game.
- Test Ctrl-click Group Come: Move + Come stay back-to-back; both replies for one attempt must be consumed before the pair advances or retries.
- Re-test immediately after a roster change and confirm the original selected target is restored at completion.
- Covered-slot multiplayer testing remains pending until a second human is available: leave -> Replace Missing, rejoin-before-replace -> re-cover, then actual replacement -> exact underlying class/role/extra.

## Planned / To-do
- Expose human-over-bot drag/drop for 5-player presets: exact human identity -> exact logical slot -> suppress underlying bot intent while that human is present.
- Stop deriving 5-player logical human ownership from Blizzard party-row order once explicit assignment exists.
- Preserve deterministic bot logical order while treating human physical placement as observational.
- Reuse existing tracker/preset slot data and proven refill semantics; avoid duplicating raid logic in a party-only path.
- Post-replacement human-return policy is resolved: the user must manually free a group slot before the human can return; no automatic addon action is required.

## Ideas / Backlog
- Consider whether Group row availability/UI refresh should also force a fresh snapshot, or whether fresh-on-command is sufficient after runtime testing.
- After the logical-slot work is stable, simplify or retire overlapping legacy refill paths only with migration/runtime proof.

## Deferred
- Do not add a delay between Ctrl-click Move and Come unless runtime evidence specifically shows the same-frame pair failing.
- Do not perform unrelated scheduler, identity or maintenance refactors while working on logical human-slot maintenance.
- Do not treat Blizzard row/order as logical preset identity.
- Dedicated 0.8.62-only timing validation is deferred; its behaviour will be covered with the current Group build.

## Exact Next Step
Runtime-test 0.8.67-dev against the exact acknowledgement flow: target change -> 0.10s settle -> send -> wait; correct actor -> immediate next target; wrong actor -> immediate resend to the unchanged intended target. Confirm this first with four-bot Group Come and one unfiltered stale-target diagnostic pass, then smoke the remaining Group commands and Ctrl-Come.
