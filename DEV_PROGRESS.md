# Development Progress

## Current
- Branch: `dev`
- Version: `0.8.64-dev`
- Current runtime commit: `160620b37b697963999fd61712dbde322df6e1a2`
- Latest status commit before this update: `2e236612cdbb4f30abb062d1843e62d92b1b8285`
- Goal: finish reliable Group-command targeting, then align 5-player roster/editor/maintenance behaviour with the same logical-slot model already used for raid presets.

## Recent Commits
- `160620b37b697963999fd61712dbde322df6e1a2` — 0.8.64-dev: preserve human-covered preset bot intent as dormant Active Roster slots.
- `541821f7e2cf6e27f7f51ce275f3b5befe038aad` — 0.8.63-dev: Group command startup refreshes the live roster once before resolving subgroup and recipients.
- `30e1f5d8f9b0e33a5bddaa8882e0d8d37468f6c9` — 0.8.62-dev: uniform 0.15s Group target settle/hold around every recipient.
- `74ca6c4040e47d290b775799c0e44404bebfb260` — 0.8.61-dev: final recipient padded to 0.15s on both sides.

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
- 0.8.64-dev now keeps a dormant Active Roster entry for a preset assignment covered by a tracked human:
  `expected=false`, `state="covered"`, with the underlying class/role/extra, logical slot, intended group and covering human name preserved.
- Existing Active Roster counts, missing/dead detection, reconciliation and maintenance continue to ignore covered slots because they require `slot.expected`.
- Ctrl-click Group Come still sends Move + Come back-to-back in the same recipient send phase.
- 0.8.61-0.8.64 changes remain implemented but not yet user-verified.

## Current Issues
- Covered Active Roster slots are preserved but not yet promoted to Replace Missing when their tracked human leaves.
- The 5-player preset UI still derives human rows from current party order rather than exposing raid-style explicit logical slot assignment.
- Blizzard party/raid row placement must remain live observation only once explicit 5-player slot ownership is enabled.
- Pending regression items remain: dungeon -> 10-player preset retest for the 0.8.55 scope fix; monitor the intermittent 0.8.50 first-summon subgroup mismatch; Replace Dead still needs its separate runtime smoke.

## Testing

### Last Test
- Version/commit: `0.8.60-dev` / `483699234761f0e84871c4129b22523269ae8e38`
- Passed: Group retargeting generally worked and reliability was substantially improved.
- Failed: the final bot could still occasionally miss; observed success was roughly 95%.
- Not tested: 0.8.61-dev through 0.8.64-dev.

### Next Test
- Exercise normal Group Come in both 4-bot and 5-bot subgroups; re-test immediately after a roster change.
- If normal Group Come is reliable, test Ctrl-click Group Come without adding a Move -> Come delay.
- After covered-slot activation is implemented, summon a full 5-player preset containing another human, have that human leave, and confirm Replace Missing exposes the underlying exact bot assignment.
- If the human rejoins before replacement, confirm the slot becomes covered again and is no longer reported missing.

## Planned / To-do
- Teach Active Roster sync to keep a covered slot dormant while its named human is present, promote it to `expected=true/state="missing"` when that human leaves, and re-cover it if the human returns before replacement.
- Clear the covering-human marker when a replacement bot is actually bound to the slot.
- Expose human-over-bot drag/drop for 5-player presets: exact human identity -> exact logical slot -> suppress underlying bot intent while that human is present.
- Replace Missing must respawn the exact bot class/role/extra belonging to the exposed logical slot, not infer a replacement from Blizzard row position.
- Preserve deterministic bot logical order while treating human physical placement as observational.
- Reuse existing tracker/preset slot data and proven refill semantics; avoid duplicating raid logic in a party-only path.

## Ideas / Backlog
- Define the policy for a saved human returning after Replace Missing has already filled that human's logical slot with its underlying bot; do not auto-kick a live replacement without an explicit policy.
- Consider whether Group row availability/UI refresh should also force a fresh snapshot, or whether fresh-on-command is sufficient after runtime testing.
- After the logical-slot work is stable, simplify or retire overlapping legacy refill paths only with migration/runtime proof.

## Deferred
- Do not add a delay between Ctrl-click Move and Come unless runtime evidence specifically shows the same-frame pair failing.
- Do not perform unrelated scheduler, identity or maintenance refactors while working on logical human-slot maintenance.
- Do not treat Blizzard row/order as logical preset identity.
- Dedicated 0.8.62-only timing validation is deferred; its behaviour will be covered with the current Group build.

## Exact Next Step
Implement covered-slot lifecycle in Active Roster sync: while `coveredBy` is present as a human, keep the slot dormant; when that human leaves, convert the same logical slot to `expected=true/state="missing"`; if the human returns before replacement, restore `expected=false/state="covered"`. Clear `coveredBy` only when a replacement bot is bound. Do not change editor UI or spawn scheduling in this step.
