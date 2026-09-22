# SoloCraftBots Development Handoff

Current branch: `dev`
Current addon line: `0.8.62-dev`
Current functional addon head: `30e1f5d8f9b0e33a5bddaa8882e0d8d37468f6c9`
Previous docs checkpoint: `00081235102ec6178f5b82deba6fff51253d101b`
Behavioural reference: `main` 0.7.14 (`6170b1535dba83882ee55eb38c35160c8fec9ca2`)


## 0.8.62-dev — uniform Group target padding

Runtime commit: `30e1f5d8f9b0e33a5bddaa8882e0d8d37468f6c9`

Completed:
- every Group recipient now uses target -> 0.15s settle -> command(s) -> 0.15s hold;
- removed the special final-recipient timing path;
- the working assumption is that the server resolves target-dependent PartyBot chat commands against the client's target with enough latency that a safety buffer is required around each recipient transition;
- Ctrl-click Group Come still sends Move and Come back-to-back in the same send phase because runtime testing has not shown a same-frame Move/Come problem;
- Group-only 24 commands/second accounting, Group critical section, subgroup filtering, GUILD transport and original-target restoration are unchanged.

Runtime status:
- untested as `0.8.62-dev`.

Exact next step:
- repeatedly test normal Group Come in both a 4-bot and 5-bot subgroup;
- if reliable, test Ctrl-click Group Come without adding any Move->Come delay;
- only introduce spacing between Move and Come if runtime evidence specifically shows that pair failing.


## Group timing decision — uniform 0.15s padding

Decision:
- replace the mixed 0.10s / final-recipient 0.15s timing with a uniform 0.15s pre-send settle and 0.15s post-send hold for every Group recipient;
- reason: runtime testing showed target-dependent command reliability improves as padding increases, and raid subgroups may contain five bots rather than the four-bot 5-player test case;
- this removes the special-case assumption that only the final recipient needs the larger margin.

Ctrl-click Group Come:
- Move and Come are currently emitted back-to-back during the same recipient send phase, with no delay between the two commands;
- preserve that behavior for this timing change unless runtime testing specifically shows that Move -> Come itself needs separation.

Preserve:
- Group-only rolling 24 commands/second budget;
- Group critical section preventing normal control-command interleaving;
- live subgroup recipient filtering;
- original-target restoration after the fan-out;
- GUILD transport and existing command syntax.

Exact next step:
- make Group use 0.15s before and after every recipient, bump the dev version, statically inspect, promote non-force, then retest normal Group Come before separately exercising Ctrl-click Group Come.


## 0.8.61-dev — final recipient padded on both sides

Runtime commit: `74ca6c4040e47d290b775799c0e44404bebfb260`

Completed:
- earlier Group recipients remain at 0.10s pre-send / 0.10s post-send;
- only the final recipient now uses 0.15s before its command and 0.15s after its command;
- the longer pre-send settle addresses the remaining ~5% final-recipient miss seen on 0.8.60;
- the longer post-send hold continues to protect against racing the original-target restore;
- Group-only 24 commands/second accounting, Group critical section, subgroup selection, GUILD transport, Ctrl-click Group Come and original-target restoration are otherwise unchanged.

Runtime status:
- untested as `0.8.61-dev`.

Exact next step:
- repeatedly test Group Come in a 5-player party and confirm whether the final bot reaches effectively 100% reliability;
- if reliable, repeat in a 10-player raid and then smoke Group Move/Stay/Pause/Unpause.


## 0.8.60 runtime result — final recipient ~95% reliable

Observed:
- extending only the final post-send hold from 0.10s to 0.15s improved the last bot to roughly 95% success;
- earlier subgroup recipients remain reliable;
- the remaining miss pattern is still isolated to the final recipient.

Decision:
- keep earlier recipients at 0.10s pre-send / 0.10s post-send;
- make only the final recipient use 0.15s pre-send and 0.15s post-send;
- preserve the Group-only 24 commands/second budget, Group critical section, subgroup resolution, GUILD transport and original-target restore behavior.

Exact next step:
- implement a final-recipient-specific 0.15s pre-send settle in addition to the existing 0.15s final post-send hold, bump the dev version, statically inspect, and retest repeated Group Come in a 5-player party.


## 0.8.60-dev — longer final target hold

Runtime commit: `483699234761f0e84871c4129b22523269ae8e38`

Completed:
- preserved the 0.10s pre-send settle and 0.10s normal post-send hold for every Group recipient;
- only the final recipient now receives a 0.15s post-send hold before SCB restores the user's original target;
- this specifically targets the 0.8.59 symptom where misses were concentrated on the last bot;
- Group-only 24 commands/second accounting, Group critical section, subgroup selection, target restoration, GUILD transport and Ctrl-click Group Come are unchanged.

Runtime status:
- untested as `0.8.60-dev`.

Exact next step:
- repeatedly test Group Come in a 5-player party and watch whether the final bot now responds consistently;
- if the final bot still misses while earlier bots remain reliable, increase only the final hold again rather than slowing the entire cycle.


## 0.8.59 runtime result — final recipient still occasionally misses

Observed:
- 0.10s pre-send settle + 0.10s post-send hold improved Group reliability to about 80%;
- misses now appear concentrated on the final bot in the subgroup.

Interpretation:
- because every bot receives the same pre-send settle, a last-recipient-specific miss points more strongly at the final original-target restore racing the last target-dependent command;
- avoid slowing every recipient unless runtime evidence requires it.

Decision:
- preserve 0.10s pre-send settle and 0.10s normal post-send hold;
- extend only the final recipient's post-send hold to 0.15s before restoring the user's original target;
- keep the Group-only 24 commands/second budget, critical section, subgroup selection, command transport and target restoration semantics otherwise unchanged.

Exact next step:
- implement the final-recipient 0.15s restore delay as the next dev build and retest Group Come repeatedly in a 5-player party.


## 0.8.59-dev — pre-send target propagation settle

Runtime commit: `943ae4407b8afaa6ee39f21f4ca002fdcaab8f2b`

Completed:
- Group now uses target -> 0.10s settle -> send command(s) -> 0.10s hold -> next target;
- the pre-send settle specifically addresses the observed server-side target propagation race;
- four bots take about 0.8s for one Group command and five recipients about 1.0s;
- the Group-only rolling 24 commands/second budget remains unchanged;
- the Group critical section remains unchanged, so other normal SCB control sends cannot interleave;
- original target restoration, live subgroup selection, recipient validation, GUILD transport and Ctrl-click Group Come semantics are unchanged.

Runtime status:
- untested as `0.8.59-dev`.

Exact next step:
- retest Group Come in a 5-player party first. Confirm all subgroup bots respond consistently rather than 20-50%;
- if reliable, repeat in a 10-player raid and smoke Move/Stay/Pause/Unpause;
- only tune the 0.10s settle/hold values if runtime evidence justifies it.


## 0.8.58 Group runtime result — target propagation still races

Observed:
- Group now visibly cycles targets and always works on the bot that was selected when the command started;
- remaining subgroup bots respond only about 20-50% of the time;
- therefore subgroup selection and client-side retargeting are functioning, but the target-dependent PartyBot command is often reaching the server before the new target has propagated server-side.

Relevant prior evidence:
- the existing delayed attack macro was added for the same class of issue: SCR/M target-next resolves more slowly than SCB can immediately issue the following attack command.

Decision:
- replace 0.8.58's immediate send + 0.02-second post-send hold with a symmetric target settle:
  target bot -> wait 0.10s -> send command(s) -> wait 0.10s -> next bot;
- preserve the Group-only 24 commands/second rolling budget and control-command critical section unchanged;
- do not alter subgroup membership logic, target restoration, GUILD transport, or command syntax.

Expected pacing:
- four bots in a normal 5-player party take about 0.8 seconds for one Group command;
- five recipients take about 1.0 second;
- this is slower than the preferred 0.1-second whole-group cycle, but runtime evidence now shows the faster timing is unreliable.

Exact next step:
- implement the two-phase 0.10s pre-send / 0.10s post-send Group state machine as the next dev build, then retest Group Come in 5-player and 10-player groups.


## 0.8.58-dev — Group critical section + Group-only 24/s budget

Runtime commit: `5137eb4fab347535709135831b390be65a5ab36d`

Completed:
- the 24 commands/second rolling budget applies only to Group fan-out sends;
- normal One/All/role/other control commands are not counted against that Group budget;
- a Group press calculates the complete fan-out cost before starting and is rejected if that fan-out would exceed 24 Group sends in the current rolling 1.0-second window;
- normal 5-player Group commands with four bots therefore permit at most six complete one-command fan-outs per rolling second;
- Ctrl-click Group Come counts both Move and Come for every bot, so its budget cost is doubled;
- while `SCB.groupCommandState` is active, other normal SCB control sends cannot interleave with the target-sensitive fan-out;
- delayed control commands wait until the Group cycle finishes rather than firing inside it;
- Distance and Spread local state now changes only when their control command was actually sent, preventing UI/state drift if clicked during the Group critical section;
- preset/spawn transport is not rate-limited by this Group budget and retains its existing scheduling.

Preserved:
- 0.02-second per-recipient post-command target hold from 0.8.57;
- original target restoration only after the entire subgroup fan-out;
- live subgroup recipient selection and per-recipient validation;
- GUILD transport for control commands.

Runtime status:
- untested as `0.8.58-dev`.

Exact next step:
- test Group Come in a 5-player party, including rapid repeated clicks, and confirm all four bots respond while repeated presses stop before exceeding six complete fan-outs in a rolling second;
- then repeat in a 10-player raid, confirming only the selected subgroup responds and the original target is restored;
- also smoke a normal One/All control during/around Group usage to confirm it does not interleave with the active Group cycle and is otherwise unaffected.


## Group command exclusivity + spam-budget decision — 2026-09-20

Current decision:
- preserve the fast 0.02-second per-recipient Group target hold from 0.8.57;
- while a Group fan-out is active, normal user control commands must not interleave with it;
- Group command starts must respect a rolling budget of 24 Group fan-out commands per 1.0 second;
- for a normal 5-player party with four bots and one command per bot, that permits at most six complete Group presses inside any rolling second;
- Ctrl-click Group Come consumes two commands per recipient and therefore must consume twice the budget;
- do not apply a lossy transport-level drop to preset/spawn scheduling, because silently dropping a background add/removal command would corrupt those workflows.

Completed:
- 0.8.57 fast Group cycle is on dev at `c2c71ba70997e89a8c0f3953ccf76188add03dc4`;
- current docs head before this decision is `9aafc2fa8448ba87f33708896ba9a864e0ee23bd`.

Untested:
- 0.8.57 fast Group cycle itself still needs the 5-player and 10-player runtime smoke;
- the new exclusivity/rate-budget change described here is not implemented yet.

Deferred:
- do not globally rate-limit or drop Spawn/Preset `.partybot add` traffic in this change;
- do not change the 0.02-second target dwell unless the runtime test shows a target-evaluation race.

Exact next step:
- add a control-command gate so ordinary SCB control sends are rejected while `SCB.groupCommandState` is active unless they are the Group fan-out's own sends;
- add a rolling one-second history for Group fan-out sends and make Group reserve/check enough remaining budget for its complete fan-out before starting;
- keep background Spawn/Preset transport out of this gate;
- bump the addon line for the runtime change, statically inspect the candidate, then promote non-force to `dev`.


## 0.8.57-dev — fast Group target cycle

Runtime commit: `c2c71ba70997e89a8c0f3953ccf76188add03dc4`

Completed:
- changed Group pacing from 0.20-second pre-send + 0.20-second post-send dwell to a single 0.02-second post-command target hold per bot;
- each recipient is now targeted and commanded immediately in the same step, then that target is held for 0.02 seconds before advancing;
- five recipients should therefore cycle in roughly 0.10 seconds total;
- the user's original target is still restored only after the entire subgroup fan-out completes;
- recipient validation, subgroup selection, command routes, GUILD transport, and Ctrl-click Group Come semantics are unchanged.

Reason:
- 0.8.56's 0.20/0.20 pacing was intentionally conservative but too slow for normal use;
- the actual requirement is to avoid restoring the original target in the same frame as the target-dependent command, not to add a large visible dwell before every send.

Runtime status:
- untested as `0.8.57-dev`.

Exact next step:
- test Group Come in a 5-player party and then a 10-player raid. Confirm all bots in the selected live subgroup respond, other subgroups do not, and the original target returns after the very fast cycle. If target evaluation still races at 0.02 seconds, increase only the post-command hold rather than reintroducing a pre-send delay.


## 0.8.56-dev — paced Group target cycle

Runtime commit: `3d3f6c40011542c66a48917854669ddf1eab8be0`

Completed:
- replaced Group's same-frame retarget -> send -> restore sequence with a per-bot target state machine;
- the original friendly target is captured once at Group-command start;
- SCB selects each bot physically present in the selected live subgroup, then holds that target for 0.20 seconds before sending the target-only command;
- after sending, SCB holds the same target for another 0.20 seconds before selecting the next bot;
- the user's original target is restored only after the complete subgroup fan-out finishes;
- Ctrl-click Group Come still sends Move then Come to each recipient while that recipient remains targeted;
- recipients are still revalidated against the live roster immediately before send, and bots that vanish or change subgroup are skipped;
- Group selection semantics, GUILD command transport, normal One/All commands, preset timing and roster ownership are unchanged.

Reason for change:
- runtime testing of 0.8.55 confirmed Group failed in both 5-player and 10-player groups;
- only the already-targeted bot responded, and the target never visibly cycled;
- the old implementation restored the original target in the same update step as the command send, making server-side target evaluation race the immediate restore.

Runtime status:
- untested as `0.8.56-dev`;
- no Lua/luac interpreter is available in the development environment, so static inspection cannot replace the in-game smoke.

Still untested / unresolved:
- 0.8.55 dungeon -> 10-player preset regression test remains pending;
- 0.8.50 first-summon subgroup mismatch remains monitor-in-normal-play;
- Replace Dead remains separately untested.

Deferred:
- do not tune the 0.20-second dwell unless runtime evidence shows it is too short or unnecessarily slow;
- do not change Group recipient selection or command syntax unless the paced target cycle still fails.

Exact next step:
- in a 5-player party, target any valid friendly member and click Group Come. Confirm the visible target cycles through each bot in Group 1, each bot comes, and the original target returns at the end. Then repeat in a 10-player raid and confirm only bots in the selected subgroup respond. If that passes, smoke Group Move/Stay/Pause/Unpause and Ctrl-click Group Come once.


## Group scope confirmed broken — 2026-09-20

Runtime result on `0.8.55-dev`:
- Group commands fail in both a 5-player party and a 10-player raid;
- only the bot that was already targeted when the Group command was clicked responds;
- the visible target does not appear to cycle through subgroup bots.

Interpretation:
- this confirms the 0.8.53 Group implementation is defective rather than a 5-player-only ambiguity;
- current code retargets a recipient, sends the target-dependent command, and restores the original target inside the same update step;
- that same-frame retarget/send/restore is now the leading cause: the server can evaluate the PartyBot target command after the original target has already been restored.

Completed / still valid:
- 0.8.54 GUILD command transport remains runtime-passed;
- 0.8.52 macro-safe `/scb stay` and `/scb move`, including no-target safety, remain runtime-passed;
- no further Group-scope code has been changed yet.

Untested / unresolved:
- 0.8.55 dungeon -> 10-player preset retest remains pending;
- 0.8.50 first-summon subgroup mismatch remains monitor-in-normal-play;
- Replace Dead remains separately untested.

Deferred:
- do not change subgroup selection semantics, command routes, GUILD transport, roster ownership, or preset timing as part of this fix.

Exact next step:
- replace Group's same-frame per-action retarget/send/restore with a paced per-bot target cycle: capture the user's original target once, select each subgroup bot, hold that target briefly before sending its command(s), advance to the next bot after a deliberate dwell, and restore the original target only after the full subgroup fan-out completes. Preserve validation and skip bots that vanish or change subgroup during the cycle.





## Testing hold before next chat — 2026-09-20

Current decision:
- make no further Group-scope code changes until the user retests it in both a 5-player party and a 10-player raid;
- the earlier 5-player result is treated as a suspected failure, not yet a confirmed implementation defect;
- Group scope is intended to work in a 5-player party when a valid friendly target selects the live subgroup;
- preserve the current 0.8.53 Group implementation unchanged until the two controlled retests provide evidence.

Confirmed passed:
- 0.8.54 GUILD command transport;
- 0.8.52 macro-safe `/scb stay` and `/scb move`, including no-target safety.

Still untested / unresolved:
- 0.8.55 preset subgroup barrier scope fix needs the dungeon -> 10-player preset path retested to confirm the former `Spawn.lua:1185` error is gone;
- 0.8.53 Group scope needs explicit targeted tests in both a 5-player party and a 10-player raid;
- 0.8.50 first-summon subgroup mismatch remains monitor-in-normal-play;
- Replace Dead remains separately untested.

Exact next step:
- user tests Group scope with a valid friendly target in a 5-player party, then in a 10-player raid, before any further Group code changes. When practical, also retry the dungeon -> 10-player preset summon to clear 0.8.55. Start the next development chat from this handoff with those results.

## 0.8.55-dev — preset subgroup barrier scope fix

Runtime commit: `66ba0d1ca4e810a1cfdcfda6f84bd2a55ff27ddf`

Completed:
- fixed the deterministic Lua error at `Spawn.lua:1185` by making `SCB_PresetSubgroupMoveBarrierPassed` visible outside the scoped legacy burst prelude where the preset scheduler calls it;
- helper logic, roster revision semantics, 1.0-second inter-group wait, spawn pacing, survivor handling, and combat retry behavior are unchanged.

Runtime status:
- untested as `0.8.55-dev`;
- 0.8.54 GUILD transport is user-confirmed working;
- 0.8.52 macro-safe Stay/Move is user-confirmed working including no-target safety;
- 0.8.53 Group scope still fails in a 5-player party and remains unresolved;
- 0.8.50 first-summon subgroup mismatch remains monitor-in-normal-play;
- Replace Dead remains separately untested.

Exact next step:
- retry the dungeon -> 10-player preset summon that previously faulted at `Spawn.lua:1185`; confirm the Lua error is gone and the preset proceeds. Then isolate the 5-player Group-scope failure separately.

## Runtime results / active bug — 2026-09-20

User-confirmed:
- 0.8.54 GUILD transport works for tested control commands;
- 0.8.52 macro-safe `/scb stay` and `/scb move` work, including the no-target safety case;
- 0.8.53 Group scope did not work in a 5-player group; do not mark Group scope passed yet.

New failure:
- while in a dungeon and attempting to summon a 10-player preset, Lua error at `Spawn.lua:1185`: nil value;
- current source shows line 1185 calling `SCB_PresetSubgroupMoveBarrierPassed()`;
- that helper is currently declared `local` inside the scoped legacy burst prelude near the top of `Spawn.lua`, while line 1185 is outside that scope, so the call resolves as an unavailable global at runtime;
- this is a code-scope defect, not a server timing result.

Exact next step:
- export/fix the subgroup-barrier helper visibility without changing its behavior, bump the dev version, then retest the 10-player preset-from-dungeon path. After the crash is fixed, separately diagnose why Group scope is unavailable/nonfunctional in a 5-player party rather than assuming that behavior is intentional.

## 0.8.54-dev — guild-chat control command transport

Runtime commit: `0a2688b5567c6a35365d3d2d2a534e02facfb762`

Completed:
- changed the shared PartyBot sender's default channel from PARTY to GUILD;
- changed `SCB_SendCommand` so normal control commands explicitly use GUILD;
- changed the developer batch sender so non-`add` commands use GUILD as well;
- spawn/add traffic remains explicitly routed through SAY by `SCB_SendSpawnCommand`, including manual summons, presets, and maintenance replacements;
- no spawn dead-state guard, command pacing, Group fan-out timing, target restoration, roster logic, or preset timing changed.

Runtime status:
- untested as `0.8.54-dev`;
- `0.8.52-dev` macro-safe Stay/Move and `0.8.53-dev` Group scope still need their command smoke, now through the GUILD transport;
- `0.8.50-dev` first-summon subgroup mismatch remains monitor-in-normal-play rather than runtime-passed;
- Replace Dead remains separately untested.

Deferred:
- do not move spawn/add traffic to GUILD in this build; SAY remains the intentional spawn transport and naturally prevents dead players from issuing SAY;
- no central rate throttle or explicit dead-state spawn throttle was added.

Exact next step:
- in-game, verify ordinary control commands are accepted when sent through GUILD, including one direct Come/Move/Stay/Pause command, `/scb stay` and `/scb move`, and one Group-scope command. Confirm spawning still uses SAY and behaves unchanged. If clean, continue the existing 0.8.52/0.8.53 command-scope smoke and record the result.

## 0.8.53-dev — live subgroup command scope

Runtime commit: `499ec3f038f860d26156e3afc3644fd9ae859e3f`

Completed:
- added a **Group** command row between All and One with Come, Unpause, Move, Stay and Pause;
- Group scope is resolved from the current target's observed Blizzard party/raid subgroup in Live Roster, never from logical preset placement;
- a friendly human, bot or the player can act as the subgroup selector as long as the target exists in Live Roster;
- the selected command fans out through the existing target-only PartyBot commands, so no unverified native subgroup command syntax was introduced;
- bot recipients are snapshotted by name from the selected live subgroup, then re-resolved immediately before each action; bots that vanished or moved subgroup are skipped;
- fan-out is serialized at one target command per 0.15 seconds, with the first action immediate, to avoid burst chat/server spam;
- SCB temporarily targets each recipient bot only when necessary, verifies the retarget succeeded, sends the command, and restores/clears the user's prior target only when SCB actually changed it;
- Ctrl-click Group Come preserves the existing Move-then-Come semantics per bot;
- the Group row availability updates from target changes and visible roster changes;
- Group currently reuses the existing All recipient artwork because no dedicated Group icon exists; tooltips explicitly state that Group means the current target's live party/raid group;
- the first staged candidate was rejected before promotion after review found a target-restoration edge case; the promoted candidate includes the verified-retarget guard.

Runtime status:
- untested as `0.8.53-dev`;
- `0.8.52-dev` macro-safe `/scb stay` and `/scb move` are also awaiting the same short command smoke;
- `0.8.50-dev` first-summon subgroup mismatch remains monitor-in-normal-play rather than runtime-passed;
- Replace Dead remains separately untested from the recent smoke sequence.

Deferred:
- optional startup/lazy-UI and deeper developer-debug-buffer optimisation remain low-value/medium-risk and are not being mixed into the command feature gate;
- a dedicated Group recipient icon is cosmetic follow-up only if desired;
- the established preset spawn/inter-group timing remains unchanged.

Exact next step:
- smoke the command features in a party/raid: verify `/scb stay` and `/scb move` affect only one valid targeted bot and are silent with no/non-bot target; then target a member of a subgroup containing multiple bots and verify Group Come/Move/Stay/Pause/Unpause affect only bots physically in that subgroup, other subgroups remain unchanged, and the original target is restored after the paced fan-out. Also test Ctrl-click Group Come once. If clean, treat the command-scope work as runtime-cleared and decide whether 0.8 is ready for a broader regression/main-promotion review.

## 0.8.52-dev — macro-safe single-target Stay / Move

Runtime commit: `98caa2711b98d7035ce57e9d5906205ced71ae30`

Completed:
- added `/scb stay` and `/scb move` as macro-friendly entry points for the existing One/target command semantics;
- both commands require the current target to pass the same friendly PartyBot validation used by the One UI row;
- with no valid bot target they return silently, preventing SoloCraft's target command fallback from affecting the whole bot group;
- no command matrix/UI, spawn, roster, maintenance, or pacing behavior changed.

Runtime status:
- untested as `0.8.52-dev`;
- expected smoke is simple: target one friendly bot and confirm each slash command affects only it; then repeat with no target / a non-bot target and confirm nothing is sent.

Exact next step:
- implement the separately-scoped Group command row between All and One. Resolve the target's current Blizzard subgroup from Live Roster, fan the selected target-only command out to bots physically in that same subgroup, throttle the fan-out, and restore the user's original target after each temporary bot target. Do not use logical preset group membership for this feature.

## 0.8.51-dev — maintenance queue head-index pass

Runtime commit: `29003117948aacfcca4b0618d459a85e412b38a5`

Completed:
- converted maintenance replacement's potentially large `state.remaining` FIFO from repeated `table.remove(..., 1)` shifts to a logical `remainingHead`;
- maintenance burst selection now reads the next up-to-five assignments from the logical head;
- completed bursts advance the head by the number of resolved assignments instead of shifting the retained array;
- survivor replacement resets the maintenance queue/head to its one retained survivor assignment exactly as before;
- removal pacing, 3.0-second capacity settle, mixed-group burst size/order, combat gates, identity binding and survivor semantics are unchanged;
- remaining front-shift audit now contains only two small `pendingAssumedSpawns` pops, two one-shot Group 1 construction edits, and the bounded developer debug log.

Decision:
- the remaining `pendingAssumedSpawns` queue is intentionally burst-sized and also supports class-aware arbitrary-position consumption, so head-index conversion would add complexity for negligible gain;
- the Group 1 removals are construction-time one-shot edits;
- the debug buffer is developer-only and its dominant cost is full log refresh/concat, not the occasional trim shift;
- therefore the FIFO/head-index optimization pass is complete here.

Runtime status:
- `0.8.51-dev` is untested;
- `0.8.50-dev` first-summon subgroup issue remains monitor-in-normal-play rather than runtime-passed;
- Replace Dead remains separately untested from the recent smoke sequence.

Exact next step:
- move out of queue archaeology. Review the deferred performance/startup items and choose only changes with a clear practical benefit; otherwise begin the deferred user-facing command-scope work (Group command scope and macro-safe Stay/Move) without mixing both categories in one build.

## 0.8.50 runtime disposition — monitor in normal play

User decision:
- the original first-summon Group 1/2 crossing is too intermittent to reproduce efficiently on demand;
- do not block development on a forced reproduction attempt;
- keep the 0.8.50 subgroup-revision barrier in place and watch for recurrence during normal raid play;
- this is not a runtime-pass claim for the original symptom.

Development consequence:
- proceed to the deferred queue/micro-optimisation work;
- preserve the current 1.0-second inter-group wait unless future evidence points specifically at inter-group stabilization;
- if the first-summon mismatch recurs, capture the exact starting topology/survivor state and revisit the barrier with that evidence.

Exact next step:
- audit the remaining small front-removal FIFOs left after 0.8.49 and convert only queues where repeated index-1 removal is meaningful enough to justify another behavior-preserving change. Leave bounded/one-shot arrays alone.

## 0.8.50-dev — initial raid subgroup revision barrier

Runtime commit: `c7b55b13aa2d0819b45686c7b62d26dac2509070`

Completed:
- survivor/bootstrap Group-8 parking now records the current roster-event revision immediately before `SetRaidSubgroup`;
- human preset arrangement records the same barrier before each requested subgroup move;
- `PRESET_ARRANGE_PLAYERS` no longer releases the first real preset burst merely because `GetRaidRosterInfo` already reflects the target layout; at least one later roster event must advance `SCB.rosterEventRevision`;
- coordinator-side survivor parking is carried on the active preset `botOperation`, so the barrier survives the handoff into the preset queue;
- direct/shared preset queue entry without a `botOperation` uses a queue-local fallback barrier that is cleared with spawn runtime reset;
- the established 1.0-second inter-group wait, burst construction, survivor removal timing, combat gates, and FIFO/head-index scheduler semantics are unchanged;
- candidate diff was staged off-branch, inspected as one commit ahead of `f9d8211`, then promoted to `dev` by non-force ref update.

Runtime status:
- untested as `0.8.50-dev`;
- the intermittent first-summon Group 1/2 crossing remains the active runtime gate until this build is exercised;
- `0.8.49-dev` FIFO/head-index behaviour is therefore not yet marked runtime-passed independently;
- Replace Dead remains separately untested from the recent smoke sequence.

Deferred:
- do not change the established 1.0-second inter-group wait unless the initial subgroup barrier fails to resolve the first-summon issue;
- remaining small FIFO conversions, optional lazy UI/startup work, deeper debug-buffer optimisation, Group command scope, and macro-safe Stay/Move remain deferred.

Exact next step:
- smoke the same first-summon raid scenario that previously showed Group 1/2 crossing, ideally with a retained survivor so Group-8 parking is exercised. Verify the first attempt has the expected human subgroup placement, tank/role markings, and Group 1/2 composition without needing a second summon. If that passes, run one normal summon-over and the server-combat retry path if practical; keep the 1.0-second inter-group wait unchanged unless a separate failure demonstrates it is needed.

## 0.8.49 runtime investigation — first-summon role/icon mismatch

Observed:
- on one first summon, the live raid/pfUI tank markings did not match the preset's expected tank slots;
- a second summon immediately afterward produced the expected result;
- user notes an older implementation intentionally spawned Group 1 one bot short while a survivor occupied capacity; current design instead parks the survivor in Group 8 before arrangement.

Audit result:
- the raid survivor/bootstrap construction, Group-8 parking helper, assumed-role binding, roster-delta binding, burst-intent construction, and system-message identity binding are byte-for-byte unchanged between 0.8.47 and 0.8.48; wrapper flattening did not resurrect the old raid Group-1-minus-one behaviour;
- the remaining `heldAssignment` Group-1-minus-one path is confined to size <= 5, where Group 8 does not exist;
- raid-size survivor handling keeps the full Group 1 assignment set, parks the survivor in Group 8, then removes it after a real Group 1 bot is observed;
- the separate raid-from-empty `firstAssignment` path intentionally sends one real Group 1 assignment before conversion and removes that already-sent assignment from the later Group 1 burst; it is not survivor capacity subtraction;
- the screenshot shows Groups 1 and 2 containing the correct combined class pool but with members crossing the subgroup boundary, while a second summon corrected it. This points to first-summon subgroup/capacity stabilization timing rather than composition generation or wrapper flattening;
- `SCB_ArrangePresetPlayers` does verify target human subgroups after issuing `SetRaidSubgroup`, but it can proceed as soon as `GetRaidRosterInfo` reflects the move; there is no explicit server-roster-event stabilization barrier before the first bot burst;
- inter-group progression also uses a fixed 1.0-second wait rather than a roster-confirmed burst-completion barrier.

Status:
- 0.8.49 remains not runtime-passed;
- no runtime code changed during this investigation;
- Replace Dead remains separately untested.

Exact next step:
- harden the initial raid subgroup handoff first: require subgroup moves (including survivor parking and human arrangement) to be confirmed by a subsequent roster revision before releasing the first preset bot burst, rather than relying only on immediate `GetRaidRosterInfo` reflection. Then smoke the same first-summon scenario before considering any change to the established 1.0-second inter-group wait.

## 0.8.49-dev — preset spawn FIFO head-index pass

Runtime commit: `3e71700c06041c9a59339bfb377cdb5b3fd5e467`

Completed:
- converted the hot preset-spawn scheduler from repeated `table.remove(queue, 1)` shifts to a logical queue head;
- converted preset burst-plan consumption to a logical head as well;
- combat retry now rewinds into the already-consumed queue prefix instead of repeatedly inserting at physical index 1;
- queue count/peek/pop/replace/prepend/reset operations are centralized in `SoloCraftBots.lua`;
- all queue observers in SoloCraftBots/Presets/Spawn now use logical-head semantics;
- operation completion and abort paths explicitly reset retained queue storage;
- static block-balance validation passes for all six Lua owner files;
- targeted audit confirms no remaining front-removal/index-1 access on the preset spawn queue or burst-plan queue.

Runtime status:
- untested as `0.8.49-dev`.

Still deliberately unchanged / deferred:
- `pendingAssumedSpawns` still has two small front-removal call sites;
- maintenance `state.remaining`, temporary group-construction arrays, and the bounded debug line buffer still use front removal where applicable;
- Replace Dead remains untested from the 0.8.48 smoke sequence;
- optional lazy UI/startup and deeper debug-buffer optimisation remain deferred;
- Group command scope and macro-safe Stay/Move feature work remain deferred.

Exact next step:
- smoke `0.8.49-dev` with a normal preset summon and summon-over, plus the server-combat retry path if practical; verify queue ordering, group pacing, final roster tracking, and Kick All/maintenance coexistence. If clean, decide whether the remaining small FIFOs merit conversion or whether to move on.

## 0.8.48 runtime result — 2026-09-20

User-confirmed on `0.8.48-dev`:
- clean load passed;
- Options/combat-role confirmation toggle and role-indicator behaviour passed;
- preset save/load with placed-human behaviour passed;
- summon/summon-over passed;
- Replace Missing passed;
- paced Kick All passed;
- summon in combat continued to refuse destructive teardown as intended.

Still untested:
- Replace Dead specifically; no bot was killed during this smoke pass.

Interpretation:
- the proven-dead deletion plus captured-wrapper flattening cleanup is runtime-cleared for the exercised paths;
- structural duplicate/wrapper cleanup is complete.

Exact next step:
- begin the FIFO/head-index queue micro-optimisation pass as the next dev version, preserving command order, batch sizes, pacing intervals, combat gates, and survivor/bootstrap semantics exactly.

## 0.8.48-dev — captured-wrapper flattening pass

Runtime commit: `490b93c7574e3f6518732c6fd84b95b3ff372be6`

Completed:
- flattened all 16 remaining captured duplicate-global families into one authoritative implementation each;
- duplicate `SCB_*` global audit is now zero across the six owner files;
- removed the superseded pre-Spawn maintenance update chain entirely; the 3.0-second removal/capacity settle constant now lives with the Spawn owner;
- folded exact logical-player slot persistence and snapshot validation into Presets while retaining Roster's live logical-layout/snapshot construction responsibilities;
- folded role-indicator refresh hooks into the Presets UI owners;
- folded combat-role lifecycle gating into the final Roster implementations at the lexical point where their local lifecycle helpers are in scope;
- folded safety-message presentation into Communication and combat-role option UI behaviour into Options;
- static block-balance validation passes for all six Lua owners;
- raw ownership audit remains clean: one `.partybot` `SendChatMessage` owner and one actual `UninviteByName` call in the paced Communication removal queue.

Runtime status:
- untested as `0.8.48-dev`;
- `0.8.47-dev` role-indicator behaviour is runtime-passed;
- prior smoke coverage remains: summon-over passed, Replace Missing passed, and normal preset summon in combat correctly refused destructive teardown;
- Replace Dead specifically has not yet been exercised in the short post-cleanup smoke sequence.

Deferred after this gate:
- FIFO head-index conversion / queue micro-optimisations;
- optional lazy UI/startup and deeper debug-buffer optimisation;
- Group command scope and macro-safe Stay/Move feature work.

Exact next step:
- smoke `0.8.48-dev`: clean load; open Options and toggle combat-role confirmation; verify assumed/confirmation ticks; save/load a raid preset with an explicitly placed human if practical; summon or summon-over once; Replace Missing/Dead if available; and run paced Kick All. If clean, the structural duplicate/wrapper cleanup is complete and work can move to the deferred FIFO/micro-optimisation pass.

## 0.8.47 runtime result — 2026-09-20

User-confirmed:
- with combat-role confirmation disabled, the summon/assumed role ticks remain visible;
- the combat-confirmation ticks stay hidden as intended.

Interpretation:
- the 0.8.47 role-indicator gating correction is runtime-passed;
- the 0.8.46 proven-dead deletion pass remains healthy under the smoke coverage already recorded.

Still untested from this short smoke sequence:
- Replace Dead specifically; Replace Missing already passed.

Exact next step:
- begin the captured-wrapper flattening pass as `0.8.48-dev`; preserve current behaviour, flatten one authoritative implementation per remaining duplicate family, re-run the duplicate-global audit, and keep queue/timing/combat/survivor semantics untouched.

## 0.8.47-dev — role-indicator gating correction

Runtime commit: `a305bcb9e27a3360e63415bb8436b49670dddce0`

Changes:
- the assumed/summon role tick is no longer gated by the combat-role confirmation option;
- the combat-confirmation tick remains hidden when combat-role confirmation is disabled;
- no summon, teardown, removal, maintenance, pacing, or combat-safety logic changed.

Runtime context from 0.8.46 smoke:
- summon-over passed;
- Replace Missing passed;
- normal preset summon in combat correctly refused destructive teardown;
- Replace Dead remains untested in this smoke sequence.

Untested:
- `0.8.47-dev` role-indicator behaviour in game.

Exact next step:
- verify in a 5-player group with combat-role confirmation disabled that summon/assumed ticks remain visible while combat-confirmation ticks stay hidden; if correct, resume the 16-family wrapper-flattening cleanup pass.

## 0.8.46 runtime smoke update — 2026-09-19

User-confirmed on `0.8.46-dev`:
- summon-over / preset replacement works;
- Replace Missing works;
- starting a normal preset summon in combat refuses destructive teardown as intended;
- Replace Dead has not yet been exercised in this smoke pass.

UI finding:
- with combat-role confirmation disabled, both preset role indicators disappear in a 5-player group;
- expected behaviour is to keep the summon/assumed-role tick visible and hide only the combat-confirmation tick;
- root cause is in `SCB_RefreshPresetRoleIndicators()`: the `detectionEnabled` condition currently gates the whole indicator branch, including `scbAssumedTick:Show()`.

Exact next step:
- make a narrow `0.8.47-dev` UI correction so the assumed/summon tick is independent of combat-role detection while the confirmation tick remains feature-gated; do not mix wrapper cleanup into this fix. After runtime confirmation, resume the 16-family wrapper-flattening pass.

## 0.8.46-dev — proven-dead implementation deletion pass

Runtime commit: `83b1c22af87e3a228db6ef38d08c5996031e8dd5`

Completed:
- removed 23 superseded global function definitions across 20 duplicate families;
- deletions were limited to implementations overwritten later in TOC order and not captured by wrapper aliases;
- removed 679 lines from `Presets.lua`, 85 from `Roster.lua`, 82 from `Spawn.lua`, and 19 from `SoloCraftBots.lua`;
- no Lua lines were added or rewritten; the only non-deletion runtime diff is the TOC bump to `0.8.46-dev`;
- current duplicate-global audit is down to 16 families, and every remaining family is an intentional base/wrapper capture chain reserved for the wrapper-flattening pass;
- the single raw `.partybot` transport owner remains `SCB_SendPartyBotCommand`; the live paced removal owner remains unchanged.

Untested:
- `0.8.46-dev` runtime itself;
- the explicit Presets role-indicator spot check with combat-role confirmation disabled remains outstanding.

Deferred:
- wrapper flattening for the 16 captured duplicate families;
- FIFO head-index conversion and other queue/micro-optimisations;
- optional lazy UI/startup and deeper debug-buffer work;
- Group command scope and macro-safe Stay/Move feature work.

Exact next step:
- smoke `0.8.46-dev` in game: confirm clean addon load, one normal preset summon/rebuild, one Replace Dead/Missing cycle if available, paced Kick All, and the disabled combat-role indicator state; if clean, begin the wrapper-flattening cleanup from the 16 remaining captured families.

## 0.8.46 cleanup start checkpoint — 2026-09-19

Current state before runtime edits:
- branch: `dev`;
- addon: `0.8.45-dev`;
- dev head / latest docs commit: `863a5fca4d97c82dd3ba0295f1136e57e6b5bdb3`;
- latest functional runtime commit: `379859be7196872328a106085cec37c161ef23eb`;
- completed: 0.8.45 passed the 40-player BWL natural-play gate, including repeated preset rebuilds, dead/missing maintenance, removals while dead, and paced Kick All;
- untested: the explicit Presets role-indicator spot check with combat-role confirmation disabled;
- deferred: wrapper flattening, FIFO head-index conversion, other micro-optimisations, lazy UI/startup work, and later command-scope features.

Exact next step:
- build `0.8.46-dev` as the first proven-dead implementation deletion pass only: remove superseded global definitions that are overwritten later in TOC order and are not captured by wrapper aliases; preserve the 0.8.45 BWL-proven runtime semantics and do not alter pacing, settle timing, combat gates, survivor/bootstrap rules, or mixed-group identity behaviour.

## Refactor polish checkpoint — 2026-09-19

Current runtime state:
- branch: `dev`;
- addon: `0.8.45-dev`;
- functional runtime head: `379859be7196872328a106085cec37c161ef23eb`;
- latest docs head before this checkpoint: `fe30a12e3d07a9f06cb67953f26daa858650a26c`;
- 0.8.45 completed a successful 40-player Blackwing Lair natural-play gate with repeated preset summons/rebuilds, dead/missing maintenance, removals while the player was dead, and repeated paced Kick All;
- only explicit UI spot check still unreported: role ticks hidden when combat-role confirmation is disabled.

Duplicate-global audit:
- 36 `SCB_*` globals currently have multiple definitions across the six-owner files;
- about 20 are superseded implementations where a later owner replaces the earlier implementation without preserving it;
- about 16 are deliberate base/wrapper chains where the later definition captures the earlier function and therefore must be flattened before the base can be deleted.

First safe cleanup batch (no intended behaviour change):
- remove superseded preset/runtime implementations now owned later in TOC order, including old maintenance, old preset rebuild/scheduler/click paths, old spawn sender/click paths, and duplicated roster helpers that are replaced outright;
- retain all functions that are captured by a `local ... = SCB_Foo` wrapper alias until that wrapper is flattened;
- preserve current owner boundaries: Roster = observation/identity, Spawn = physical lifecycle/add timing, Communication = final click/comms/removal UI owner, Options = option/UI owner;
- do not touch combat predicates, 5-per-0.10s removal pacing, 3-second removal settle, 1-second maintenance stabilization, survivor/bootstrap semantics, or mixed-group burst identity.

Wrapper-flattening batch after safe deletions:
- fold each intentional wrapper/base pair into one authoritative implementation in its final owner;
- priority families include preset logical-slot UI/save/load wrappers, snapshot validation/build wrappers, combat-role lifecycle wrappers, Options UI/check wrappers, and safety-message presentation wrapper;
- re-run duplicate-global audit after each batch until every remaining duplicate is intentional and justified, then remove the remaining wrapper aliases.

Deferred after structural cleanup:
- FIFO head-index conversion / lower-value queue micro-optimisations;
- optional lazy UI/startup and deeper debug-buffer optimisation;
- Group command scope and macro-safe Stay/Move remain feature work after refactor completion.

Exact next step:
- create `0.8.46-dev` as a behaviour-preserving proven-dead implementation deletion pass, beginning with the superseded definitions that are not captured by wrapper aliases; statically compare the candidate against 0.8.45 and keep the BWL-proven runtime behaviour as the reference.

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

## 0.8.42-dev — mixed-group maintenance bursts

Runtime commit: `856a38c16e59a99d35462bd61a3f8e201f7fbcbf`

Changes:
- maintenance now takes the next up to five sorted replacement intents across raid groups instead of completing one destination group at a time;
- one mixed burst retains the established reverse command-send / SoloCraft join-message identity ordering;
- each joined bot is resolved through its burst ID + logical slot/group assumption rather than inferred from physical roster order;
- each replacement is verified against its own intended subgroup;
- subgroup correction performs one move or swap per fresh roster observation so raid indices are never reused after a mutation;
- `SwapRaidSubgroup` is used when two misplaced burst bots occupy one another's needed full groups; ordinary `SetRaidSubgroup` remains the fallback;
- all bots in the burst share one 1.0-second post-arrival stabilization, then the next up-to-five begins;
- 3.0-second removal/capacity settle, maintenance combat rules, survivor handling, spawn identity rules and server authority are unchanged.

Current runtime-test status:
- `0.8.39-dev`: practical 10-man Stockades gate passed;
- `0.8.40-dev`: combat-safe preset teardown entry runtime-tested successfully in normal play;
- `0.8.41-dev`: FAILED runtime test in a 40-player raid — same-frame Kick All disconnected the player/client;
- `0.8.42-dev`: mixed-group maintenance burst is statically reviewed but not runtime-tested.

Natural-play ZF test target (no dedicated test matrix required):
- normal preset replacement while already in combat must not kick the group;
- Kick All should still retain the required survivor and settle normally;
- if two or more bots become missing/dead across different groups, one Replace action should restore up to five together to their exact roles/groups;
- ordinary summon/rebuild and pfUI tank marking should remain healthy.

Remaining deferred performance/cleanup work:
- broader proven-dead implementation and remaining low-value wrapper cleanup;
- FIFO head-index conversion and other low-priority micro-optimisations;
- startup/lazy-UI and deeper debug-buffer optimisations remain optional later work.

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


## Combat-safe preset teardown runtime result — 2026-09-19

- Normal preset summon while the group is already in combat correctly blocks before destructive teardown.
- The 0.8.40 combat-entry change is therefore runtime-passed.
- Remaining runtime gate for the stacked 0.8.41-0.8.42 work: 40-player raid test of same-frame Kick All and mixed-group maintenance replacement.


## 40-player Kick All A/B result — FAILED

- 0.8.41 same-frame Kick All caused a disconnect during the 40-player raid test.
- Treat same-frame mass `UninviteByName` as rejected for this client/server environment.
- Do not continue testing the same-frame variant.
- Mixed-group maintenance in 0.8.42 has not yet been invalidated by this result and remains pending runtime coverage.
- Exact next step: restore the previously proven 5 removals per 0.10 seconds Kick All pacing as an isolated runtime change, retain the 0.8.42 maintenance burst implementation, then continue the raid using that build.


## Shared bot-removal mechanic rule — 2026-09-19

Replace Dead/Missing must not use a separate immediate-uninvite path from Kick All. All multi-bot physical removals should feed one shared paced removal mechanism so the proven 5-removals-per-0.10-second server/client safety limit is applied consistently.

Immediate next step:
- expose the existing paced Kick All queue as a shared bot-removal API;
- route maintenance dead-bot removals through that same queue;
- keep maintenance's existing "wait until every requested name is absent -> 3.0-second capacity settle -> spawn" state machine unchanged;
- do not alter survivor removal semantics or add-time combat safety in this change.

## 0.8.43-dev — paced Kick All restored

Runtime commit: `3751b829dec1b80e29aa6daa11c7e4048354405a`

- Restored the proven Kick All queue at 5 removals per 0.10 seconds after the 40-player same-frame A/B caused a disconnect.
- Survivor selection/anchor behaviour is unchanged.
- 0.8.42 mixed-group maintenance remains present and pending runtime test.
- Exact next step: continue the 40-player raid on 0.8.43; verify paced Kick All no longer disconnects, then exercise mixed-group Replace Missing/Dead if practical.


## 0.8.44-dev — unified bot removal

Runtime commit: `8b26872df77c09e0a6e8b28b7211e46994ab70ab`

Authoritative removal contract:
- `SCB_KickBots("all", options)` and `SCB_KickBots("dead", options)` are the single public physical bot-removal entry point;
- every queued removal uses the proven 5-removals-per-0.10-second pacing;
- Kick All calls `"all"`;
- Kick Dead calls `"dead"`;
- preset teardown callers now use explicit `"all"` rather than the old boolean contract;
- Replace Dead/Missing always enters through `"dead"` with an exact tracked-name filter; a missing-only operation therefore performs a successful no-op removal phase before its existing settle/spawn flow;
- the retained maintenance safety survivor is removed through the same queue with a one-name `"all"` filter when it is finally safe to replace;
- maintenance still waits until all requested names are absent, then applies the existing 3.0-second capacity settle before adding replacements;
- mixed-group maintenance bursts from 0.8.42 remain unchanged after the removal phase.

Runtime status:
- untested as 0.8.44;
- 40-player same-frame Kick All remains permanently rejected from the 0.8.41 disconnect result.

Exact next test:
- continue the 40-player raid using 0.8.44; paced Kick All and Replace Dead/Missing should now exercise the same removal queue, while mixed-group replacement remains the main outstanding runtime gate.


## Current next step — role UI + command ownership audit

User report:
- combat-role confirmation is disabled in Options, but a role tick remains visible on Presets;
- physical/server command families should have one authoritative owner with option/mode arguments rather than parallel implementations.

Verified before runtime patch:
- the combat-role option is functioning: disabling it unregisters combat-role events and stops confirmation scanning;
- Presets UI is inconsistent: it always shows the green assumed-role tick and only hides the confirmation tick when combat-role confirmation is disabled;
- `.partybot` transport still has multiple direct `SendChatMessage` paths (normal control, spawn, Debug, Clear Marks);
- live single-bot survivor/bootstrap and refill-anchor removals still contain raw `UninviteByName` calls outside the shared removal owner;
- older superseded Presets maintenance/scheduler definitions also contain direct removal calls and are candidates for the deferred proven-dead cleanup rather than new runtime ownership.

Exact next step:
1. make Presets role indicators obey the combat-role feature toggle as one unit;
2. add one `SCB_SendPartyBotCommand(command, options)` transport owner and route normal, spawn, Clear Marks and Debug transport through it while preserving spawn validation;
3. route live survivor/bootstrap/refill-anchor removals through `SCB_KickBots(...)` so the queue implementation remains the only live physical `UninviteByName` owner;
4. leave native raid-layout APIs separate for now; audit them during the deferred layout/dead-code cleanup.


## 0.8.45-dev — role-toggle fix + command transport ownership

Runtime commit: `379859be7196872328a106085cec37c161ef23eb`

Role UI finding/fix:
- the Options checkbox was functioning and correctly disabled combat-role event scanning;
- the Presets tick gate was broken because `SCB_RefreshPresetRoleIndicators` referenced a later local helper outside its lexical scope, so the intended disabled-option hide path never executed;
- a public `SCB_IsRoleDetectionEnabled()` now owns the setting read;
- when combat-role confirmation is disabled, both assumed/confirmation role ticks are hidden on Presets.

Command ownership changes:
- added `SCB_SendPartyBotCommand(command, options)` as the single raw `.partybot` chat transport;
- normal controls use PARTY through `SCB_SendCommand`;
- validated spawn commands use SAY through `SCB_SendSpawnCommand` with spawn-intent registration;
- Clear Marks and Debug now route through the same transport owner;
- live preset survivor, bootstrap survivor and refill-anchor removals now route through `SCB_KickBots` rather than raw `UninviteByName`.

Audit result:
- only one live raw `SendChatMessage(".partybot ...")` remains: inside `SCB_SendPartyBotCommand`;
- only one live raw `UninviteByName` remains: inside the paced kick queue implementation;
- three raw `UninviteByName` calls remain in superseded Presets maintenance/scheduler definitions and should be deleted with the deferred proven-dead-code cleanup, not maintained as alternate runtime paths;
- native raid-layout operations (`SetRaidSubgroup`, `SwapRaidSubgroup`, promotion) remain separate and should be assessed as a layout-owner cleanup rather than folded into a generic PartyBot dispatcher.

Runtime status: untested as 0.8.45.


## 0.8.45 runtime result — 40-player BWL pass

Natural-play 40-player Blackwing Lair session completed successfully on `0.8.45-dev`.

Observed working during the run:
- repeated Summon Preset operations;
- summon-over / preset replacement operations;
- partial maintenance refills for both dead and missing bots;
- maintenance removals while the player was dead;
- no hangs, disconnects, wrong obvious replacement flow, or other observed failures during the session.

Interpretation:
- the unified `SCB_KickBots("all"|"dead", options)` removal owner and paced queue behaved correctly through real raid maintenance churn;
- the mixed-group maintenance burst work has now received meaningful 40-player natural-play coverage;
- preset teardown / rebuild changes continue to behave correctly under repeated use.

Still not explicitly confirmed from this report:
- Presets role-indicator visibility with combat-role confirmation disabled.

Next development step:
- move into proven-dead historical implementation / low-value wrapper cleanup, then lower-priority queue and micro-optimisation work, while keeping the current runtime behaviour as the reference.


## 2026-09-22 single-pipeline architecture handoff

Current repository state at this decision point:
- branch: `dev`;
- TOC version: `0.8.75-dev`;
- current runtime commit: `2b19431de271906ae99d67b55e779488d8ca14d0`;
- branch head before this docs-only handoff: `2684875d60915472474911b5ef53bf9d228044bb` (icon artwork generation guide);
- immediate runtime gate remains the 0.8.75 Single-control spam test plus Group sequencing reconfirmation.

### Architectural objective

Continue the 0.8 convergence toward **one obvious pipeline/owner per behaviour**, specifically to make future features cheap to add and to make the eventual gnomish LCD visualiser a trivial presentation consumer.

Do **not** interpret "single pipeline" as one giant mutually-exclusive state machine. Command sequencing, physical bot lifecycle, addon communications and roster observation are distinct domains and some are intentionally concurrent. The design target is:
- one request/front door per domain;
- shared authoritative low-level owners for transport/removal/spawn identity;
- no feature-specific duplicate schedulers;
- one small neutral read-only activity/status surface that presentation code can consume.

### Manual Add buttons

Addon manual Add should be tracked rather than remaining an unowned spawn side effect.

Target behaviour:
1. Button selects one validated class/role/extra assignment.
2. Start a lightweight one-assignment `manual-add` physical operation / explicit spawn intent.
3. Register explicit identity before sending the validated `add`.
4. Bind the arriving bot name through the same assumed-spawn/burst identity machinery used by presets and maintenance.
5. Disable addon manual Add while any other physical bot operation (preset/rebuild, maintenance, another manual-add) owns the roster.
6. After send, impose a minimum **1.0-second cooldown**, but do not consider cooldown expiry alone sufficient. The next addon manual Add is allowed only after the expected join has been observed/bound or the existing short spawn timeout expires. This prevents laggy joins from crossing identities.
7. A user who manually types a raw `.partybot add ...` command during an SCB-owned summon/rebuild does so outside the supported coordinator contract. Do not add fragile chat interception to compensate.

### Remote/requested preset summon

Current issue found in the full-addon audit:
- local Summon uses `SCB_StartPresetRebuild()` -> `SCB_RequestPresetOperation()` -> `SCB.botOperation`;
- accepting a remote Summon Request currently calls `SCB_StartPresetSummonSnapshot()` directly and therefore enters underneath the coordinator.

Required fix:
- accepting a remote/requested summon must enter the same preset-operation request front door as local Summon;
- requester transmits **composition intent**, not live bot identity;
- only the client that actually summons bots binds generated bot names to logical assignments;
- requester does not need the summoned bot names;
- communications serialization already carries each human's exact `slotIndex`, but Save Received Preset currently discards it. Preserve those exact slots as preset `playerSlots`.

### Unified logical-slot model: party and raid

A preset has N underlying logical bot/composition intents. Human assignment means:
> human identity -> exact logical slot -> suppress exactly that underlying bot intent while that human is present.

This semantic is the same at every preset size.

#### Five-player topology policy

`size <= 5` inherits special **execution/topology** rules, not a separate logical-editor model:
- stay party;
- never convert to raid;
- no subgroup manipulation;
- exact human logical slots suppress underlying bot intents;
- remaining bots keep deterministic controlled summon/order;
- bootstrap continuity may temporarily occupy one slot and therefore reserves exactly one final required bot assignment when necessary;
- use the existing tracker/Active Roster/refill semantics rather than inventing a party-only maintenance system.

#### Raid topology policy

`size > 5`:
- raid conversion/topology rules apply as needed;
- bot subgroup placement/order is controlled and meaningful;
- human logical slot remains only suppression/composition intent;
- do not treat a human's logical slot as a command to force their physical Blizzard row or subgroup;
- bot identity/order comes from explicit spawn burst identity and controlled bot summon order while human row position is ignored;
- Blizzard roster observation tells SCB the actual current subgroup/location after the fact.

The current `SCB_ArrangePresetPlayers()` / `PRESET_ARRANGE_PLAYERS` stage still moves humans between raid subgroups based on logical preset assignment. That conflicts with the newer model and should be removed/reworked as part of this migration.

### Blizzard reorder / user rearrangement presentation

Known Vanilla behaviour: humans may appear at stable positions initially, but adding another player/bot can scramble their displayed within-group order. Bots remain usable for SCB identity/order because SCB controls their summon order and ignores human rows when binding bot identities.

Do not mutate the saved preset to follow these transient physical changes.

Instead, show the discrepancy directly on the Preset UI:

**Blizzard within-group reorder**
- If group membership/composition remains correct but Blizzard changes the displayed within-group row order, slowly pulse the **entire affected group background yellow**.
- Tooltip: **"Group composition correct; Blizzard client reordered members."**
- This is informational, not an error.
- Logical human assignments and bot intents remain unchanged.

**Raid-tab subgroup rearrangement**
- If a bot or player is observed in a different raid subgroup from the runtime/logical expectation because the group was rearranged outside SCB (for example via Blizzard Raid tab), use the same slow yellow whole-group background pulse.
- Tooltip: **"Group rearranged in Blizzard Raid tab."**
- Do not silently rewrite the preset and do not automatically undo the user's arrangement merely because the display differs.
- The pulse clears when observed layout again matches the expected layout.

Implementation distinction:
- ordinary row-order permutation inside the same subgroup -> Blizzard reorder state;
- actual subgroup-membership difference -> rearranged state.
- Never claim an exact physical row is owned by a human logical slot.

### Reusable maintenance intent / Group Resummon

Current maintenance already has the difficult physical machinery: paced shared removal, absent observation, 3-second capacity settle where needed, explicit spawn bursts, identity binding, subgroup placement and Active Roster rebinding.

Refactor the front of that system so **selection** is separate from **execution**:
- Roster/Active Roster selects logical assignments and produces a maintenance intent.
- Spawn/botOperation executes the physical lifecycle.

Selectors:
- Replace Missing/Dead -> missing/dead logical assignments;
- Resummon Group N -> currently active bot assignments for logical group N;
- future Resummon One -> one logical assignment.

Do not add a new Group Resummon scheduler.

### Declarative command semantics and one command-request front door

The existing command table is the right base, but target rules and execution mechanics are still partly distributed across click handlers and targeted helpers.

Add declarative metadata describing **what target context the server command requires/observes**, independent of recipient scope. Candidate semantic classes:
- target-agnostic;
- friendly-bot recipient;
- living-enemy context;
- conditional/target-sensitive server command;
- add another explicit class only when server evidence requires it.

Then use scope/execution policy:
- **Single**: friendly bot required where appropriate; direct/fire-and-forget; deliberately spammable; no Group acknowledgement lock; no Group 24 commands/sec budget.
- **Group**: friendly bot is the group locator; addon retargets each group bot; actual target changes get the proven 0.10-second settle; actor replies advance/retry; existing rolling 24 commands/sec budget remains.
- **All / roles / paired roles**: immediate when command metadata says the current target context is safe.
- **Enemy-context commands** such as Attack/AoE: validate the living hostile target but do not treat that enemy as a bot recipient.
- Conditional target-sensitive server commands are gated/blocked when the current target would change their intended meaning.

Buttons/macros should become callers:
> request commandKey + scope + modifiers

They may ask the pipeline for availability so they can grey themselves out, but button code must not own the semantic rule.

Do not homogenize Single and Group timing merely to share an API. The point is one request model with explicit execution policies.

### Dumb visualiser

The future gnomish LCD/pixel display should not inspect `targetedCommandState`, spawn queues, kick queues, pending assumed spawns, comm transaction internals, etc.

Expose a small neutral read-only activity/status surface. Independent components publish/update their own status:
- Command: action, scope, phase, current recipient, progress;
- Bot Operation: operation kind, phase, progress, wait reason;
- Communication: action/peer/phase;
- Roster/Layout: useful transient layout status such as reorder/rearranged state.

The visualiser only translates this status into text/icons/animation. No command/spawn/maintenance decisions live inside it. Debug tooling may later consume the same surface.

### Agreed implementation order

After the 0.8.75 runtime gate:
1. introduce declarative command target semantics and one command-request front door, preserving all current runtime-proven policies;
2. close physical-lifecycle bypasses: tracked 1.0-second-floor manual Add + operation lock, remote accepted summon through the preset coordinator, received exact human slots preserved;
3. perform the unified five-player/raid logical-slot migration, remove human logical-slot -> physical arrangement coupling, and add yellow layout mismatch pulse/tooltips;
4. refactor maintenance selection into reusable intents and add Resummon Group through the existing maintenance/bot-operation lifecycle;
5. delete proven-dead refill/compatibility runtime only after call-site audit and runtime proof;
6. add the neutral activity/status surface;
7. return to the visualiser as a dumb consumer.

### Testing / status discipline

Nothing in this 2026-09-22 architecture section is an in-game test result. It records agreed design and static audit findings only.

Keep states distinct:
- implemented;
- checked/static-inspected;
- user tested;
- stable;
- released.

Current exact next step remains the 0.8.75 runtime test. If it passes, begin implementation-order item 1 above. Do not start the visualiser first.


## 0.8.76-dev command request convergence — 2026-09-22

Runtime commit: `96781f32a40b5956051274affdc939913d76c54a`

### Runtime gate entering this build
- 0.8.75-dev / `2b19431de271906ae99d67b55e779488d8ca14d0` received a user smoke pass: rapid Single spam appears to work and Group still feels good.
- This is sufficient to clear the documented 0.8.75 progression gate, but only the reported smoke is user-tested; do not silently mark unreported subcases as separately verified.

### Implemented in 0.8.76
- Added declarative command target semantics to the command table:
  - target-agnostic;
  - friendly-bot recipient;
  - living-enemy context;
  - conditional friendly-player/bot target sensitivity.
- Added `SCB_RequestCommand(commandKey, scope, modifiers)` as the single command-matrix request front door.
- Command UI buttons and supported macros now call the request front door rather than owning their own target/scope rules.
- Single policy is intentionally unchanged: friendly bot required, immediate/fire-and-forget, spammable, no Group acknowledgement lock and no Group 24/sec pacing.
- Group policy is intentionally unchanged: friendly bot locator, fresh live-roster resolution at start, addon recipient targeting, 0.10-second settle after real target changes, actor acknowledgement/retry, original-target restoration and rolling 24 commands/sec budget.
- Group busy feedback still takes precedence over current-target validation.
- Existing All Come/Play/Pause friendly-player/bot blocking moved from button-local logic into metadata-driven request validation.
- Role and paired-role command routes remain target-agnostic.
- The already verified living-enemy requirement for AoE, Attack Start and Attack Stop is now enforced and exposed through the same availability query. Target-health changes refresh these button states.
- Spread toggle and `/scb stay`, `/scb move`, delayed `/scb attackstart` use the request front door.
- Friendly human/self blocked-command wording changed from `Humans cannot be commanded...` to `Only bots can be issued commands`.
- Visualiser work remains deferred.

### Checked / not user-tested
- Candidate was staged off-branch, reviewed against `7e935e440b4651ae93899c95f3b1c4f902845ac4`, and promoted to `dev` non-force only after the head was rechecked.
- Static checks passed for the modified runtime owners: Lua block balance, stale removed-helper references, command call-site ownership, route-preservation diff review and TOC/version consistency.
- One pre-promotion candidate was rejected because review found two regressions: roster updates still referenced the removed Group-only refresher, and the new front door initially evaluated target validity before Group busy-state precedence. Neither rejected form was promoted.
- 0.8.76 has **not** been tested in game yet.

### Exact next step
Runtime-test `0.8.76-dev`:
- clean load/no Lua errors;
- Single direct/spam behaviour;
- Group sequencing plus busy-message precedence;
- conditional All gating;
- role/paired-role behaviour unchanged;
- living-enemy AoE/Attack availability including target death;
- `/scb stay`, `/scb move`, delayed `/scb attackstart`, Ctrl-Come and Spread toggle;
- new `Only bots can be issued commands` wording.

If that passes, continue with implementation-order item 2 from the single-pipeline architecture handoff. Do not start the visualiser.
