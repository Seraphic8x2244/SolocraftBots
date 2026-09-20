# Development Progress

## Current
- Branch: `dev`
- Version: `0.8.62-dev`
- Current runtime commit: `30e1f5d8f9b0e33a5bddaa8882e0d8d37468f6c9`
- Current docs head before this workflow adoption: `37f34b11619eab990a19dccfa4c8e51d85935ab1`
- Goal: finish reliable Group-command targeting, then align 5-player roster/editor/maintenance behaviour with the same logical-slot model already used for raid presets.

## Recent Commits
- `30e1f5d8f9b0e33a5bddaa8882e0d8d37468f6c9` — 0.8.62-dev: uniform 0.15s Group target settle/hold around every recipient.
- `37f34b11619eab990a19dccfa4c8e51d85935ab1` — documented 0.8.62 Group target-buffer state.
- `74ca6c4040e47d290b775799c0e44404bebfb260` — 0.8.61-dev: final recipient padded to 0.15s on both sides.
- `483699234761f0e84871c4129b22523269ae8e38` — 0.8.60-dev: final post-send hold increased to 0.15s.

## Completed / Verified
- Normal control commands use GUILD transport; spawn/add traffic remains SAY. User-verified on 0.8.54-dev.
- Macro-safe targeted `/scb stay` and `/scb move`, including no-target safety, are user-verified from 0.8.52-dev.
- Group targeting now visibly cycles subgroup bots rather than only affecting the initially selected bot.
- Runtime testing showed target-propagation padding materially improves Group reliability: 0.8.60-dev reached roughly 95% success on the final recipient in the tested 5-player case.
- Existing raid preset logic already records exact logical human slot occupancy independently of Blizzard's physical row/order.
- Existing legacy preset refill logic can identify a tracked human's vacated logical slot; this behaviour is not yet carried through by Active Roster maintenance.

## Implemented / Awaiting Test
- 0.8.62-dev uses the same Group timing for every recipient:
  `target -> 0.15s settle -> command(s) -> 0.15s hold -> next target`.
- Ctrl-click Group Come still sends Move + Come back-to-back in the same recipient send phase; no runtime evidence currently justifies spacing those two commands.
- Group-only rolling 24 commands/second accounting and the Group control-command critical section remain active.
- User accepted progressing past a dedicated 0.8.62 timing gate because the change is small; 0.8.62 therefore remains implemented but not user-verified.

## Current Issues
- Group command selection currently begins from the cached live roster via `SCB_GetLiveRoster(false)`. Roster events normally refresh that cache, but Group should force a fresh live-roster snapshot before resolving target subgroup and recipients.
- Active Roster maintenance tracks expected bot slots, not the complete logical preset slot model. If a human leaves a full 5-player preset group, the newly exposed underlying bot slot is therefore not currently reported as Replace Missing.
- The 5-player preset UI does not yet expose the same front-facing logical-slot workflow as raid presets. Desired model: dragging a human onto a preset slot means that human suppresses the bot intent underneath that exact slot while present.
- Blizzard party/raid row placement must remain live observation only. Human logical slot assignment must not depend on party-frame or raid-frame row ordering.
- Pending regression items remain: dungeon -> 10-player preset retest for the 0.8.55 scope fix; monitor the intermittent 0.8.50 first-summon subgroup mismatch; Replace Dead still needs its separate runtime smoke.

## Testing

### Last Test
- Version/commit: `0.8.60-dev` / `483699234761f0e84871c4129b22523269ae8e38`
- Passed: Group retargeting generally worked and reliability was substantially improved.
- Failed: the final bot could still occasionally miss; observed success was roughly 95%.
- Not tested: 0.8.61-dev and 0.8.62-dev timing changes.

### Next Test
- After the fresh-roster snapshot change, exercise normal Group Come in both 4-bot and 5-bot subgroups.
- If normal Group Come is reliable, test Ctrl-click Group Come without adding a Move -> Come delay.
- In raid, confirm only the selected live subgroup responds and the original target is restored.
- Re-test the Group command immediately after a roster change so the fresh snapshot path is exercised.

## Planned / To-do
- Tighten Group command startup to force a fresh live-roster snapshot before choosing the target's subgroup and snapshotting bot recipients.
- Reuse the raid logical-slot model for 5-player presets rather than creating separate party semantics.
- Expose human-over-bot drag/drop for 5-player presets: exact human identity -> exact logical slot -> suppress underlying bot intent while that human is present.
- Carry human-occupied logical slots into the maintenance model so a tracked human leaving exposes the underlying bot assignment as Replace Missing.
- Replace Missing must respawn the exact bot class/role/extra belonging to the exposed logical slot, not infer a replacement from Blizzard row position.
- Preserve deterministic bot logical order while treating human physical placement as observational.
- Reuse the existing tracker/preset slot data and proven refill semantics where possible; avoid duplicating raid logic in a party-only path.

## Ideas / Backlog
- Define and test the policy for a saved human returning after Replace Missing has already filled that human's logical slot with its underlying bot.
- Consider whether Group row availability/UI refresh should also force a fresh snapshot, or whether fresh-on-command is sufficient after runtime testing.
- After the logical-slot work is stable, simplify or retire overlapping legacy refill paths only with migration/runtime proof.

## Deferred
- Do not add a delay between Ctrl-click Move and Come unless runtime evidence specifically shows the same-frame pair failing.
- Do not perform unrelated scheduler, identity or maintenance refactors while fixing Group snapshot freshness or logical human-slot maintenance.
- Do not treat Blizzard row/order as logical preset identity.
- Dedicated 0.8.62-only timing validation is deferred; its behaviour will be covered together with the next Group snapshot build.

## Exact Next Step
Implement the isolated fresh-live-roster snapshot at Group-command start, bump the addon to the next `0.8.x-dev` version, statically review the Group path for scope regressions, then update this file with the resulting commit and runtime test target before beginning the larger party/raid logical-slot maintenance/editor work.
