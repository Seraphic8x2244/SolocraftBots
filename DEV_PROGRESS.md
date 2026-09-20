# Development Progress

## Current
- Branch: `dev`
- Version: `0.8.65-dev`
- Current runtime commit: `04807e4789646b6f3d87b228853ecd578c4107ad`
- Latest status commit before this update: `c87421fde49bb5171344e3822c9e823d5d4c3018`
- Goal: finish reliable Group-command targeting, then align 5-player roster/editor/maintenance behaviour with the same logical-slot model already used for raid presets.

## Recent Commits
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
- 0.8.61-0.8.65 changes remain implemented but not yet user-verified.

## Current Issues
- The 5-player preset UI still derives human rows from current party order rather than exposing raid-style explicit logical slot assignment.
- Blizzard party/raid row placement must remain live observation only once explicit 5-player slot ownership is enabled.
- Post-replacement human return needs no addon arbitration: once Replace Missing has filled the group, the returning human cannot rejoin until the user manually frees a slot. SoloCraftBots must not auto-kick or otherwise make that choice.
- Pending regression items remain: dungeon -> 10-player preset retest for the 0.8.55 scope fix; monitor the intermittent 0.8.50 first-summon subgroup mismatch; Replace Dead still needs its separate runtime smoke.

## Testing

### Last Test
- Version/commit: `0.8.60-dev` / `483699234761f0e84871c4129b22523269ae8e38`
- Passed: Group retargeting generally worked and reliability was substantially improved.
- Failed: the final bot could still occasionally miss; observed success was roughly 95%.
- 0.8.65-dev runtime feedback: Group controls subjectively feel less responsive on the fourth member again. It is not yet established whether this means visible latency or an occasional missed command.

### Next Test
- Exercise normal Group Come in both 4-bot and 5-bot subgroups; re-test immediately after a roster change.
- If normal Group Come is reliable, test Ctrl-click Group Come without adding a Move -> Come delay.
- Summon a full 5-player preset containing another human, have that human leave, and confirm Replace Missing appears for the underlying exact bot assignment.
- Before clicking Replace Missing, have that human rejoin and confirm the slot becomes covered again and Replace Missing clears.
- Repeat the leave case, run Replace Missing, and confirm the exact underlying class/role/extra is restored through the existing maintenance flow.

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
Clarify the 0.8.65 Group fourth-member regression by testing whether the fourth bot is merely delayed or actually misses commands. If it is only latency, tune the intermediate Group timing without weakening final-recipient reliability. Covered-slot testing remains pending until a second human is available; do not block 5-player editor work on that unavailable test.
