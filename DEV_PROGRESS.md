# Development Progress

> Sole live handoff for SoloCraftBots development. Git history carries history; keep this file focused on current constraints, proven behaviour, unresolved questions and the next coherent step.

## Current
- Branch: `dev`
- TOC version: `0.9.4-dev`
- Current implementation head: `2cdf74df1988f1b7fb3c3ddee292924ce961dfe6`
- Current handoff/status head before this final handoff commit: `2cdf74df1988f1b7fb3c3ddee292924ce961dfe6`
- Request protocol 8 runtime validation is now completed on `0.8.111-dev` at handoff `dd1b21b9b23013a5f20bcc3f93d4c6b2bacb3b3b`: receiver-local capacity refusal PASS; leader-owned party→raid conversion PASS; receiving summoner requires neither leadership nor assistant PASS; Request-owned loot behavior absent PASS. A separate addon-level Auto Loot trigger gap was exposed: when a non-leader receiver performs the requested summon, the leader's SCB may never re-apply its own Auto Loot preference.
- Stable `main`: `0.9.0` at `4c1a75f052927be00aac91327a92dac902e2b301`; runtime source is the user-tested `0.8.117-dev` implementation `da22c1800797b628af8fb2442822ac96f0015833`, with `0.9.0-dev` RC `9161d333e3c42112d812abbc464e41d7b25e768c` changing only version metadata before promotion.
- Receiver-owned location-capacity guardrail remains explicitly accepted as correctness/state-integrity protection.
- Request protocol 8 carries no loot-setting behavior; Auto Loot remains addon-level state owned by the current group leader's SCB.
- `0.8.108-dev` side-drawer justification layout is runtime-confirmed working.
- `0.8.109-dev` readability/palette pass was visually received positively by the user.
- `0.8.110-dev` header homogeneity runtime: all four requested checks **PASS** — centered Preset/Options titles, both new X buttons, dynamic Options reflow, and hidden Preset self class/role widgets.
- New runtime issue found in `0.8.110-dev`: the Preset content chain shifted left by the same amount as the centered title. Root cause confirmed: `presetSelector` was anchored to `presetHeader:BOTTOMRIGHT`, so the centered title remained a layout owner.
- `0.8.111-dev` detaches Preset content geometry from the title. The selector is now right-aligned directly to the Preset panel and vertically positioned using the existing measured header height; Group selector and downstream controls remain chained from that panel-owned selector.
- `0.8.111-dev` Preset content anchor fix is **USER TESTED PASS**: user confirmed the layout is sorted.
- Immediate goal / exact next step: runtime-test the `0.9.4-dev` self-target bootstrap fix at `2cdf74df1988f1b7fb3c3ddee292924ce961dfe6`, then continue the remaining BWL batch validation. The neutral read-only activity/status surface and later visualiser remain explicitly deferred until this batch passes runtime validation.


## BWL 0.9.1-dev batch / 0.9.3-dev Pause Healers correction — runtime pending
Original BWL implementation head: `37097afe63259169ad0ece774cace26b27821ed7`. Current implementation head: `626b28c13baf013e834b383a9aecf4cda17786b3`. The established reverse-send/LIFO/full-rebuild ordinal finalizer remains the normal authoritative path; no activity/status surface or visualiser work has started.

### Pause Healers
- `0.9.1-dev` runtime result for the original Group-targeted implementation: **functional behavior PASS, UX rejected**. The command worked, but requiring a Group target and placing it in the Group row were rejected.
- `0.9.2-dev` moved the button to the **Healers** role row and removed the Group-target precondition, but its first separate role sequencer restored the player's target between healer sends. That interaction was rejected before runtime testing.
- `0.9.3-dev` introduced a fully separate Pause Healers sequencer and correctly preserved the tested Group sequencer. Runtime then exposed a remaining first-recipient edge case: when the player started with **self targeted**, the first bare `pause` could reach the server while self was still the authoritative selection and the server returned **"All party bots paused for 30 seconds."**. Other tested starting-target states worked.
- Correction to the earlier design description: Group sequencing was not a complete drop-in model for the first Pause Healers transition. Group starts from an already-selected bot; Pause Healers can start from an arbitrary target. The healer-to-healer sequencing is copied from Group, but the arbitrary-target -> first-healer bootstrap is a separate requirement.
- `0.9.4-dev` adds a self-target-only bootstrap settle before the first healer command. It uses at least 0.25 seconds and, when `GetNetStats()` reports higher latency, waits one reported round trip plus 0.10 seconds. This delay applies only until the first targeted `pause` is sent; subsequent healer-to-healer transitions remain the tested 0.10 seconds.
- The dedicated sequencer also treats **"All party bots paused for ..."** as an immediate failure condition and aborts/restores the original target instead of silently continuing the healer sequence. This is a safety fallback, not the primary fix.
- Pause Healers still builds recipients from all currently resolved healer bots in the live roster, excludes focused identity-recovery candidates, sends ordinary targeted `pause`, waits for the bot-specific pause acknowledgement, retries immediately on a recognised wrong-actor acknowledgement, and hard-aborts after 1.0 second with no timeout retry.
- Original target restoration still happens only after the whole sequence completes or aborts. If the sequence began with no target, completion/abort clears the temporary healer target.
- Group/Target commands remain blocked while Pause Healers owns the target; Pause Healers still refuses to start while the Group targeted sequencer is active.
- Static comparison confirms the proven Group recipient-selection, advancement, send, ACK-resolution, chat-handler and timeout-frame functions remain byte-identical to the `0.9.1-dev` implementation.

### Group targeted-command acknowledgement timeout
- Group `phase = "await"` now has a **1.0-second** acknowledgement deadline per recipient/attempt.
- Timeout prints the existing concise confirmation-failure wording, restores the original target through the normal sequencer cleanup, clears `SCB.targetedCommandState`, hides the sequencer frame and releases Group commands for immediate reuse.
- There is **no timeout retry**. The pre-existing wrong-actor acknowledgement correction path is unchanged; Single-target remains direct/spammable, Group target settle remains 0.10 seconds, and the 24 commands/second budget remains unchanged.

### Post-finalization class sanity and narrow identity recovery
- The settled bot-only ordinal mapping is still created exactly as before. A new post-finalization sanity pass only intervenes when a bound bot's actual live `UnitClass` / raid-tab class makes that binding impossible.
- Class comparison is subgroup-local. If actual class membership makes the correction unique, only `assignment.botName` mappings in that affected group are repaired; preset class/role/extra intent is never rewritten.
- If an implicated class has multiple candidate bots, SCB reuses the existing role-evidence machinery only for those candidate names. This focused mode works even when global combat confirmation is disabled, does not alter the saved option, and does not turn on whole-raid candidate scanning.
- Focused evidence is kept name-local until the complete candidate mapping is unambiguous, so it cannot write confirmation state into a known-wrong Active Roster slot. Once resolved, only the affected tracker-linked Active Roster group is rebound from the corrected name mapping.
- Live class is authoritative in both normal focused combat evidence and Druid power-bar sampling.
- Existing evidence already collected before finalization is consumed immediately. If a ready/restored tracker needs a unique correction, its existing Active Roster group is also rebound; if live class data is temporarily incomplete, the sanity pass remains pending rather than marking itself complete.
- Same-class role evidence is accepted only when it gives a one-to-one mapping. Unsupported/repeated-role ambiguity or irreconcilable class counts warn once and leave the ordinal mapping unchanged rather than guessing.
- Combat evidence never mutates the preset's intended class/role.

### Role-mismatch warning wording
- User-facing mismatch warnings now show the subgroup-local slot `((slotIndex - 1) % 5) + 1`, so global slot 11 is displayed as Group 3 / Slot 1.
- Internal/global slot IDs and warning dedupe identity remain unchanged.

### Validation state
- **Implemented:** yes, current version `0.9.4-dev`.
- **0.9.3 runtime:** ordinary Pause Healers sequencing worked, but **self-target start FAIL** because the server could interpret the first bare `pause` as the all-bots conditional.
- **0.9.4 static review:** PASS. Exact implementation delta `5ebee5d61ae6cc86cad5f6e31366fee3a57f052e` -> `2cdf74df1988f1b7fb3c3ddee292924ce961dfe6` changes only `Communication.lua` plus the TOC version bump.
- **Group pipeline preservation:** PASS. The six proven Group sequencing blocks remain byte-identical to `0.9.1-dev`.
- **Canonical Lua 5.0.3 compiler check:** **NOT RUN / unavailable in this execution environment**. Do not treat static review as a compiler pass.
- **Runtime:** the `0.9.4-dev` self-target bootstrap is **NOT YET RUNTIME TESTED**.

### Exact next runtime validation
1. Target yourself, then use Healers -> Pause Healers. Confirm the first command pauses only healer A, never produces **"All party bots paused for 30 seconds."**, and then progresses healer-by-healer on bot-specific ACKs.
2. Confirm the original self-target is restored only after the entire healer sequence completes.
3. Repeat from no target and from an enemy/non-healer target to confirm the previously working entry states remain unchanged.
4. Confirm healer-to-healer changes still use the normal 0.10-second settle after the first command.
5. If a recognised wrong-bot pause ACK occurs, confirm immediate resend to the intended healer. A missing ACK should still hard-abort after about 1.0 second with no timeout retry.
6. Exercise ordinary Group commands and confirm their tested sequencing remains unchanged.
7. Continue the remaining BWL identity-recovery and subgroup-local role-warning validation from the prior test plan.



## Architecture / ownership
- `SoloCraftBots.lua`: bootstrap/core/shared UI/primitives.
- `Presets.lua`: configured preset intent, editor, snapshots, validation and raid-role tracker creation/finalization.
- `Roster.lua`: observed party/raid reality, human/bot classification, Active Roster, provisional spawn assumptions, combat-role evidence and passive layout classification.
- `Spawn.lua`: sole owner of physical roster mutation through `SCB.botOperation`: summon/rebuild, add, subgroup moves, maintenance/refill, bootstrap/survivor handling.
- `Communication.lua`: PartyBot command transport, command semantics, incoming chat/system feedback and preset communications.
- `Options.lua`: settings/help/debug.
- Preserve one physical-operation coordinator. Presentation code must not mutate roster state.

## Authoritative logical / physical model
- A preset slot is intent. A human assigned to logical slot N suppresses exactly that slot's bot class/role intent.
- Party physical order is client-relative and cannot represent shared logical identity. Never warn because a party human is not in their logical absolute row.
- Raid subgroup membership is enforceable with `SetRaidSubgroup()`; exact row/order inside a subgroup is not.
- During raid rebuild, configured humans must be moved to their intended subgroup by name before bot bursts continue. Re-resolve raid indices immediately before each move.
- Human absolute row is irrelevant to bot identity.
- Full rebuilds intentionally burst one logical group at a time. Human-covered assignments are omitted, so a group with two humans and three bot intents summons exactly three bots.
- Preserve the established reverse-send/LIFO behaviour and the existing per-group settle boundary. Do not pack full-rebuild assignments across groups merely to save a burst.
- Final identity is the settled subgroup's **bot-only ordinal order** mapped to uncovered logical assignments in ascending slot order. This is the proven pre-0.8.87 principle from `6bcc9949222513d4f8e38a90d43071149f162f31`.
- Join-line name -> intent binding is provisional/operational identity. It remains important for mixed-group refill, but it must not overwrite settled full-rebuild ordinal identity.

## 0.8.97 implementation
### Full summon / rebuild identity — accepted baseline from 0.8.92
- `SCB_ArrangePresetHumanGroups()` preserves the proven subgroup-preparation rule: humans are resolved by name, moved only between subgroups, then subgroup membership is freshly verified. No row forcing exists.
- Full rebuild queues uncovered assignments group-by-group and uses `PRESET_WAIT_GROUP` between groups.
- `SCB_TryFinalizeRaidRoleTracking()` filters humans, obtains bots by Blizzard subgroup, requires exact per-group bot counts, then maps bot-only ordinal order to assignment order.
- `SCB_PostFinalizeRaidRoleTracking()` does not reconcile settled ordinal identity back through provisional join assumptions.
- `SCB_ReconcileTrackerFromAssumedRoles()` remains defined but has no call sites. Keep cleanup deferred until later.
- Active Roster settled identity outranks provisional `assumedRolesByName`; combat evidence never rewrites intended `slot.role`.

### Passive layout warning
- Party absolute-row mismatch logic remains removed.
- Raid mismatch classification is subgroup-only.
- 0.8.92 runtime: manually moving the user to the wrong raid subgroup correctly produced a warning and the next full Summon put them back into the configured subgroup.
- 0.8.92 presentation problem: the whole-group yellow pulse was so subtle that the user initially thought the build was stale.
- 0.8.93+ presentation change: mismatch classification also returns the exact logical slot(s) whose known member is in the wrong subgroup. Only those character rows receive a stronger gold pulse; the whole group background no longer pulses. The group tooltip remains available.
- This is presentation only; it does not change subgroup correction or physical roster ownership.

### Combat-role validation semantics
- Intended role and combat-confirmed role remain separate state. Evidence never mutates the requested role/preset.
- Validation-eligible classes remain Warrior, Paladin, Shaman, Druid and Priest.
- Rogue/Hunter/Warlock remain excluded. Runtime 0.8.92 confirmed Rogue correctly receives no second validation indicator.
- Mage remains excluded because Fire/Frost are preset specs but both map to `rangedps`; the current role validator cannot honestly distinguish the spec.
- First green tick = SCB bound the bot to that logical assignment.
- Second-indicator semantics remain the user's intended red/yellow/green progression:
  - no role evidence yet: red check = not validated yet;
  - one recognised independent observation: yellow check;
  - two observations agreeing with intended role: green check;
  - confirmed different role: persistent red `X` plus active warning.
- 0.8.94 temporarily removed the red stage-0 tick and broadened the spell catalogue; both were explicitly rejected by the user and reverted in 0.8.95.
- A confirmed mismatch opens a real `StaticPopup` (unless the user has explicitly hidden SCB screen warnings) and also writes the chat warning. The transient 2.4-second centre message is no longer the primary mismatch alert.
- Do not broaden the role-specific spell catalogue without explicit agreement. The original role-spell set is retained.
- Feral Druid validation uses the live power bar directly and does not inspect `Faerie Fire (Feral)` to distinguish bear/cat:
  - rage power type = bear/tank evidence;
  - energy power type = cat/melee evidence;
  - mana power type = no Feral-role evidence, then normal spell evidence may still apply.
- 0.8.96 still sampled the power bar only after combat text identified that Druid as the source. Runtime proved this was the wrong trigger: two bots visibly entered Bear Form while their validation checks remained red outside combat.
- 0.8.97 removes that combat gate. While role validation has pending tracked bots, the existing detection frame directly samples pending Druid unit power every 0.35 seconds. The interval is intentionally just beyond the existing 0.30-second duplicate-observation guard, preserving the established two-observation red -> yellow -> green threshold without introducing a second lifecycle.
- Power evidence remains `Rage power` or `Energy power`; no intended-role value is consulted.
- Full rebuild still starts a fresh role-validation epoch by clearing prior evidence/recent-observation/mismatch-warning state.

## Requested preset ownership — current protocol 8
- No Request path transfers party or raid leadership.
- No leadership/conversion side effect occurs before Accept.
- **Execution capacity is receiver-owned.** On Accept, the requestee compares `snapshot.size` against `SCB_GetLocationMaxCapacity(SCB_GetLocationContext())` using the requestee's current location. The same check runs again immediately before execution.
- Canonical capacity model remains: world 5; normal dungeon 10; Blackrock Spire/UBRS 15; ZG/AQ20 20; MC/Onyxia/BWL/AQ40/Naxx 40.
- If requested size exceeds the requestee's local maximum, refuse before conversion/destructive work.
- For an accepted >5-player snapshot that is locally valid while still in a party, the **actual current party leader** receives `CONVERT` and automatically calls `ConvertToRaid()`.
- The receiving summoner does not require Raid Assistant or raid-leader authority to summon bots.
- **Loot settings are not part of Request.** No snapshot field, Request state, leader-control action or Request completion condition may carry/apply the requestee's Auto Loot preference.
- Auto Loot remains ordinary addon-level behavior: every client may hold its own preference, but `SCB_ApplyAutoLootMethod()` only mutates loot when that client is the current party/raid leader. Therefore the current leader's SCB and setting are authoritative, independent of who requested or accepted the preset.
- Request communications are protocol 8. Protocol 7 is intentionally incompatible because it still contained Request-specific loot negotiation/delegation.


### Targeted Preset Manager UI slice
- `0.8.112-dev` implementation head: `267989036e23f3f4f4d10a3103bfd3d3f8d58c7a`.
- `0.8.112-dev` runtime: **PASS on all five requested checks** — hidden/no-gap state, visible red full-width Unassigned Players box, live grow/shrink/reflow on assignment changes, wider-preset multi-column wrapping, and Resummon vertical centring at default and adjusted Preset Groups icon sizes.
- Screenshot follow-up from the accepted runtime exposed two presentation-only refinements: Unassigned Players text padding was top-heavy, and Group headers still sat outside their bordered boxes.
- `0.8.113-dev` implementation head: `9125129649783b87cf928e653932870d1923f3fd`.
- `0.8.113-dev` runtime feedback: Unassigned padding PASS; five-row spacing PASS; overall size PASS. Remaining visual issues were Group-title padding not matching Unassigned, plus both divider rules appearing slightly overlong and visually heavier than the surrounding border.
- `0.8.114-dev` implementation head: `b000d6209131be326f4a21dbfc548355c1625f34`.
- Group-title anchor now exactly matches the accepted Unassigned Players title anchor: 6 units from the left and 5 units from the top.
- Both divider rules are inset 3 units from the box edges and use reduced alpha (0.55 instead of 0.9) while remaining one unit high, to better match the apparent weight of the existing tooltip border.
- No row geometry, header height, box height, assignment behavior, Resummon placement, Request, Auto Loot, roster, spawn, maintenance backend, or protocol behavior changed.
- `0.8.114-dev` runtime: **PASS** — Group title padding matches Unassigned Players; both divider lines now read correctly against the existing box borders; accepted row spacing and overall height remain good.
- Minor accepted follow-up: the Resummon glyph reads about 1 px high. Do not make a standalone build for this; queue a **1 px downward anchor nudge** into the next actual addon revision.

### Auto Loot authority/state trigger — `0.8.115-dev` implemented; runtime PASS
- Implementation head: `b0ed87093d79cddeab6c38fd8853d71f7fdebc90`.
- Ownership is unchanged: Request protocol 8 carries no loot setting/state and only `SCB_ApplyAutoLootMethod()` may call `SetLootMethod()`; that function still refuses mutation unless the local client is the actual party/raid leader.
- Existing option-change and locally-recognised bot-add/adoption triggers remain intact.
- `SCB_HandleRosterChange()` now treats an observed non-raid -> raid transition as an Auto Loot authority/state trigger and immediately applies + queues the existing retry path.
- Raid leadership transitions are detected narrowly from the local player's rank crossing raid-leader rank 2; ordinary assistant-rank changes do not count.
- `PARTY_LEADER_CHANGED` now also applies + queues through the existing leader-gated Auto Loot path, covering party leadership changes and providing an additional event-level authority trigger.
- No new scheduler/timing exists; the existing 0.25-second / four-attempt `SCB_QueueAutoLootApply()` retry behavior is reused unchanged.
- Request/Communication code is unchanged and contains no loot-setting references.
- Runtime result: **PASS**. Gaia leader / Round Robin immediately applied on invite; Revenga / Free For All requested the >5 preset and Round Robin remained authoritative through Request/conversion; transferring leadership to Revenga automatically changed loot to Free For All; transferring leadership back to Gaia automatically restored Round Robin. This confirms the non-leader never overrides the current leader's preference.
- The bundled 1 px Resummon Group downward nudge is also **USER TESTED PASS** with no other header/layout regression reported.

## Refill / maintenance contract
- Refill intentionally differs from full rebuild: up to five missing/dead assignments may be mixed across destination groups in one burst.
- Keep exact burst intent records, reverse send, join-assumption identity, subgroup movement and Active Roster replacement binding.
- Do not redesign refill into group-by-group bursts; mixed-group refill saves meaningful time.
- Combat-role validation is an independent watchdog for mistaken mixed-burst identity assumptions, not a reason to remove that optimisation.
- 0.8.99 added **Resummon Group** as another `kind="maintenance"` action rather than a new physical-operation path; 0.8.101 keeps that physical backend and removes the rejected target-selection presentation layer.
- **Implemented authoritative Resummon Group UX:** each visible preset group owns a mini `RotateCcw` button inside the `Group N` title/header, justified right. Clicking it passes that logical group directly into the maintenance action. No target selection or target-dependent enablement remains.
- The provisional full-width Command Bots Resummon Group button, target-as-group-selector helpers and target-driven refresh path are removed.
- The action should rebuild every expected tracked bot assignment in the chosen logical group, including already-missing tracked assignments. Humans and unbound/manual bots remain untouched.
- If any tracked assignment in the selected group cannot produce a valid replacement record, the action aborts before kicking anything; no partial destructive resummon.
- Destination capacity remains preflighted before any kick. Humans, manual/unbound bots and other non-removed occupants count against the five-player destination capacity; if the complete tracked group cannot fit, the action refuses unchanged rather than failing mid-rebuild.
- Live tracked bots in the selected group remain routed through the shared paced kick queue, existing 3-second capacity settle, combat wait, assumed-spawn burst identity, subgroup placement and Active Roster binding paths.
- If the selected group contains every live bot and survivor safety is required, preserve the existing retained-survivor lifecycle. A lone required survivor must be left in place rather than risking instance removal.
- Runtime 0.8.101 exposed a post-bind refresh gap where a group containing humans could return without combat-role validation ticks. 0.8.102 fixed this by clearing recycled per-name role evidence/live confirmation on replacement binding and re-queuing the existing preset-indicator + role-detection lifecycle. **Runtime smoke test now PASS on the current 0.8.111-dev line:** after Resummon Group, eligible replacement bots regained the normal binding/role-validation indicator lifecycle and the human remained untouched.

## Mini-button visual system — finalized design; 0.8.102 exact artwork implemented
Lucide is used only for the **small utility/chrome controls**. This is not a global artwork redesign. Use the exact official/free Lucide glyph geometry, rasterized directly to Vanilla-compatible TGA; do not redraw, stylize or AI-reinterpret it. The source TGAs remain 32x32, but Lucide textures now render centred at a **14px default** inside the existing control hitboxes.

Agreed Lucide mapping:
- Main Close: `X`.
- Options / Config: `Cog`.
- Section expand/collapse: `ChevronDown` / `ChevronUp` (**plain Candidate 1**, separate icon assets).
- Presets drawer open/close: `ChevronLeft` / `ChevronRight` (separate icon assets).
- Dropdown indicator: `ChevronDown`.
- Preset Delete: `Trash`.
- Preset Rename: `Pencil`.
- Preset Move Up: `ArrowUp`.
- Preset Move Down: `ArrowDown`.
- Resummon Group: `RotateCcw`.
- Spawn Near/Far: `Telescope`; retain state treatment rather than using different semantic glyphs.
- Clear Focus/CC assignments: `Eraser`.
- Assignment mode Focus: `Crosshair`.
- Assignment mode CC: `WandSparkles` (chosen specifically for WoW sheep/polymorph/magic-CC semantics).
- Layout Increase: `Plus`.
- Layout Decrease: `Minus`.
- Checkbox Off/On: `Square` / `SquareCheckBig`.
- Debug Close: reuse `X`.

Explicitly **unchanged**:
- all Command Bots button artwork;
- preset and Summon Bots class/role icons;
- player role icons;
- blessing/totem icons;
- raid-mark icons;
- other gameplay/identity artwork.

Implementation intent:
- use the Lucide pass to unify only the mini-control layer;
- preserve current tooltips, state semantics and click behaviour unless separately specified;
- do not substitute Lucide icons into the Command Bots matrix or role/class systems.
- 0.8.102 uses direct rasterizations of the official Lucide SVG geometry for all 20 existing `artwork/lucide_*.tga` files. Telescope retains separate silver/off and gold/on state treatment.
- 0.8.103 separated Lucide texture size from button-frame size while preserving existing hitboxes.
- 0.8.104 shipped defaults are **12px for Command Buttons** and **10px for Preset Groups**. Existing profiles migrate untouched 14px baselines to those defaults; explicit user adjustments are preserved.
- Command Buttons -> `Icon Size` live-controls Focus/CC/Clear plus the Command/Assignments section chevrons and the Command Buttons options-subsection chevron.
- Preset Groups -> `Icon Size` live-controls Resummon Group, the Presets drawer and selector chevrons, the Preset Groups options-subsection chevron, and preset dropdown Delete/Rename/Move icons.
- Lucide chrome outside those two scoped areas remains fixed at the global 14px default. Non-Lucide Command Bots/gameplay/class/role artwork is unchanged.
- `artwork/LUCIDE_LICENSE.txt` carries the upstream Lucide/Feather license notice for the distributed artwork.

## Side-drawer justification
- Account-wide option: `SoloCraftBotsDB.options.drawerJustification` = `"left"` or `"right"`; invalid/missing values default to `"right"`.
- Main-window top-left chevron displays the **current** justification: `<` for Left, `>` for Right.
- Preset Manager is always the inner side drawer next to Main when open.
- Options is always the outer drawer when Preset Manager is open; otherwise Options sits directly beside Main.
- Opening/closing Preset Manager or Options, or toggling justification, re-anchors visible drawers immediately.
- `0.8.108-dev` layout behavior is user-confirmed working.
- `0.8.109-dev` sizes the justification chevron from the live Command icon-size value so it matches the main vertical Command/Assignments section chevrons.

## UI text palette
- `Locale/Chat.lua` is the single editable source for the shared SCB/UI palette:
  - `COLOR_SCB = 88CCFF` — existing light-blue chat color and primary UI headers.
  - `COLOR_UI_GOLD = FFD100` — section/subsection headers.
  - `COLOR_UI_SILVER = C0C0C0` — ordinary descriptive/value text.
  - `COLOR_UI_WHITE = FFFFFF` — button and dropdown content.
- Main headers `SoloCraft Bots`, `Preset Manager`, and `Options` use SCB blue.
- Main sections and Options subsections (Presets, Command Bots, Assignments, Summon Bots, Misc, Chat Filtering, Layout, Command Buttons, Preset Groups, etc.) use gold.
- Ordinary text in the three primary windows uses silver.
- Text-button/dropdown content uses white.
- Semantic color remains allowed where it communicates state or identity, notably class-colored player names and red/green preset save/risk feedback.

## Other preserved invariants
- Active Roster keeps logical identity/expected state separate from observation. Human-covered bot slots remain dormant intents; if the human leaves before replacement they become missing; if the human returns before replacement they become covered again.
- After a missing human slot has been replaced by a bot, do not auto-kick/free capacity when the human returns.
- Capacity reuse remains: removal observed absent -> 3.0s settle -> dependent add.
- Bootstrap is continuity-only; reuse an existing bot when possible.
- Maintenance remains `botOperation(kind="maintenance")`; player combat is an absolute block and the existing stale-remote-combat allowance remains.
- Manual Add remains coordinated through `botOperation(kind="manual-add")`.
- Raw user-typed `.partybot add ...` remains outside SCB coordinator ownership.
- Taxi safety remains action-time only through `SCB_CanOperateBots(showError)`.
- Never use `UnitHealth()==0` as a dead-state fallback.
- Preset protocol is now `SCBPRESET` protocol 8. Snapshot payload contents are unchanged and still carry logical composition/human slot intent, never generated bot names; protocol 8 keeps leadership fixed, enforces receiver-local execution capacity, uses leader-directed party->raid conversion where required, never gates summoning on assistant rank, and carries **no loot-setting behavior**.
- Command semantics and tested Ctrl-Come/Move/Stay behaviour are unchanged.

## Request protocol 8 runtime result — 0.8.111-dev / dd1b21b9b23013a5f20bcc3f93d4c6b2bacb3b3b
1. **Receiver-owned location capacity: PASS.**
   - Receiver produced the correct capacity error.
   - No bot summon and no party→raid conversion occurred.
2. **Automatic leader-owned party→raid conversion: PASS.**
3. **No leadership / assistant requirement for the receiving summoner: PASS.**
4. **No Request-owned loot behavior: PASS, with separate Auto Loot trigger issue discovered.**
   - Request did not change loot method itself.
   - Test settings: user's Auto Loot = Free For All; Gaia's Auto Loot = Round Robin; actual party/raid loot method remained Group Loot.
   - Current implementation only changes loot when the local client is the actual group/raid leader, which is correct ownership.
   - However, automatic apply is only triggered by that client's own Auto Loot option change, locally-recognised SCB bot-add events, and specific local add/adoption paths. A leader observing bots summoned by another SCB client can therefore receive roster changes without running its own Auto Loot apply path.
   - `PARTY_LEADER_CHANGED`, generic raid conversion/roster change, and Request completion do not currently guarantee that the leader re-applies its configured Auto Loot method.
   - Fix must remain addon-level/leader-owned; do not put loot state back into Request protocol data or Request completion semantics.

## Resummon Group role-validation runtime result — 0.8.111-dev
- **Resummon Group role-validation smoke: PASS.**
- The historical 0.8.101 missing-indicator regression is no longer active in current runtime.
- Replacement bots in a mixed human/bot preset group regained the expected role-validation indicator lifecycle after Resummon Group; the human remained untouched.
- This closes the outstanding runtime-validation debt for the 0.8.102 post-bind refresh fix.

## Runtime results
Exact `0.8.92-dev` baseline:
1. **5-player logical-slot regression: PASS.**
   - User confirmed non-first logical player placement suppresses/replaces the correct underlying bot intent.
   - No invalid party row warning reported.
2. **10-player subgroup + deterministic summon: PASS.**
   - User tested two separate 10-player presets with the player in Group 1 in one preset and Group 2 in the other.
   - No stuck `Preset Summon is already in progress` state.
   - User explicitly does not want this re-tested.
3. **Passive subgroup detection/correction: PASS through 0.8.96.**
   - Manual wrong-subgroup move was detected.
   - Full Summon restored the configured subgroup.
   - 0.8.92 whole-group pulse was too subtle.
   - User runtime-tested the targeted character-box pulse in 0.8.96 and confirmed it is working.
4. **Combat validation: PARTIAL; 0.8.97 Feral power path PASS.**
   - Rogue exclusion passed.
   - Two feral Druids and one DPS Warrior did not accumulate evidence at a reasonable rate while clearing roughly 25% of Stockades at level 60; one feral reached yellow, the others remained stage 0.
   - User observed repeated Feral Faerie Fire, which 0.8.92 ignored because the spell is shared by bear/cat.
   - User also clarified that a genuine mismatch must produce an obvious popup rather than relying on a passive icon/transient centre message.
   - 0.8.96 direct power inference was runtime-tested with two bear Druids: both visibly entered Bear Form but remained red because the read was still combat-text-triggered.
   - 0.8.97 direct-power rebuild is runtime-confirmed: a preset-bound Druid validated as soon as Bear Form/rage appeared, without requiring combat.
   - User also manually joined an unbound Cat Druid after kicking a Rogue. Preset Manager correctly did not show that Druid, a role-validation tick, or a subgroup-warning highlight because it had no preset/logical-slot binding. This is expected behaviour, not a regression.

## Static validation for 0.8.97
- Verified `dev` was still exactly at the 0.8.96 handoff before the write; the implementation update was fast-forward only.
- Reviewed the 0.8.97 diff.
- Confirmed the combat handler no longer performs the Feral power inference.
- Confirmed a single direct scanner now reads pending Druid live unit power through the existing role-detection lifecycle.
- Confirmed the scanner retains the existing two-observation threshold and uses a 0.35-second sample interval, just beyond the existing 0.30-second duplicate guard.
- Confirmed there are zero `Faerie Fire (Feral)` references in `Roster.lua`.
- Confirmed the red stage-0 validation tick remains restored and the unrequested extra Warrior/Druid spells remain absent.
- Canonical Lua 5.0.2 compiler pass is **not claimed** in this environment.

## Static validation for 0.8.99
- Verified `dev` still matched the documented 0.8.97 handoff before writing; implementation commit was a fast-forward.
- Reviewed the Resummon Group implementation diff `0785bca9cade18ca7aca798f41791b1b666e5ad8` plus the destination-capacity guard `20ee998a730cd9afd9b6524713a4d57066fabc11`.
- Confirmed Resummon Group starts `SCB_BeginBotOperation("maintenance", ...)` and stores its state in `operation.maintenance`.
- Confirmed removals route through `SCB_KickBots("all", { names=..., manageSafety=false, silent=true })`; no new uninvite scheduler exists.
- Confirmed replacement bursts still use `SCB_0826BeginMaintenanceBurst()`, the existing assumed-spawn burst identity path and `SCB_BindReplacementToActiveSlot()`.
- Confirmed humans/unbound bots are not added to the removal-name set.
- Confirmed invalid/unbuildable selected-group records abort before any kick.
- Confirmed destination occupancy is checked before removal so an unbound/manual bot cannot make the rebuilt tracked group overfill a party/raid subgroup after destructive work has started.
- Historical note only: 0.8.99 statically confirmed target-driven button refresh, but that UX is now rejected and must be removed during the Resummon Group redesign.
- Canonical Lua 5.0.2 compiler pass is **not claimed** in this environment.

## Static validation for 0.8.100
- Verified `dev` matched the documented 0.8.99 handoff before the implementation write; update was fast-forward only.
- Reviewed implementation diff `bc77a914da0c11e15939216abcb0bf51925d5d94`.
- Confirmed the old sender-side “create a raid before requesting” and Raid Assistant preconditions are gone.
- Confirmed leadership transfer is receiver-initiated only after Accept, not when the prompt is merely received.
- Confirmed the receiver waits for local leader authority before conversion/rebuild and waits for raid formation before continuing a >5 request.
- Confirmed receiver-side Auto Loot is applied immediately before the accepted rebuild and queued for retry using the existing auto-loot path.
- Confirmed raid loot authority now checks local raid rank 2 instead of depending only on `IsPartyLeader()`.
- Confirmed communication protocol is 3 on both serialized snapshots and offer handshakes.
- Canonical Lua 5.0.2 compiler pass is **not claimed** in this environment.

## Static validation for 0.8.101
- Verified `dev` was exactly at handoff `8f344391dfcb68cf2e5ba13549de82ff49e4e3fa` before the implementation write; the update was fast-forward only.
- Reviewed implementation diff `56b7a19a7d9a0df59d23e717112d2e918c233900`.
- Confirmed the provisional full-width Command Bots Resummon button and all target-as-group-selector helpers/refresh identifiers are absent.
- Confirmed each visible preset group creates a right-justified `RotateCcw` mini button carrying `scbGroupIndex`, and the maintenance backend now accepts the logical group directly.
- Confirmed the existing maintenance preflight/capacity/survivor/removal/spawn plumbing remains the physical execution path.
- Confirmed all 20 Lucide TGA assets are present as 32x32 32-bit assets; the Telescope keeps separate near/far state treatment while using the same semantic glyph.
- Confirmed stock `UICheckButtonTemplate` usage is removed from the mini-control layer and Command Bots/class/role/gameplay artwork was not replaced.
- Canonical Lua 5.0.2 compiler pass is **not claimed** in this environment; no Lua executable/project compiler is available in the current tool environment.

## 0.8.111 implementation / static validation / next runtime test
1. **0.8.110 header homogeneity: USER TESTED PASS.**
   - Preset Manager title centered: PASS.
   - Options title centered: PASS.
   - Preset and Options X buttons close correctly: PASS.
   - Options reflows inward after Preset closes: PASS.
   - Preset self class/role widgets are no longer visible: PASS.

2. **Preset content shift regression: USER TESTED PASS.**
   - Runtime had shown the entire Preset content block floating left because `presetSelector` was still anchored to `presetHeader:BOTTOMRIGHT`.
   - `0.8.111-dev` re-anchors `presetSelector` to `presetPanel:TOPRIGHT`, retains measured header-height spacing, and leaves the downstream chain unchanged.
   - User confirmed the corrected layout is sorted.

3. **Checks performed.**
   - Verified starting handoff exactly matched `4b0b17bc711063a22ae2a74936df35710f3b5734` / `0.8.110-dev`.
   - Current implementation head before this handoff update is `ef47c5d0fac9dafd722e33b27c407ce78d43d8a4`; TOC is `0.8.111-dev`.
   - Static inspection confirms no remaining selector anchor to `presetHeader`.
   - Static inspection confirms initial selector placement and dynamic layout both anchor to the Preset panel's right edge, with the group selector chained from it.
   - Canonical Lua 5.0.3 compiler check is not run/unavailable in the current executable environment; do not claim a compiler pass.

4. **Runtime status.**
   - No further local UI test is required for the 0.8.108-0.8.111 drawer/header/readability slice.
   - Request protocol 8 runtime validation is complete at `0.8.111-dev` / `dd1b21b9b23013a5f20bcc3f93d4c6b2bacb3b3b`; see the dedicated result section above.
   - The next runtime test is now the targeted `0.8.112-dev` Preset Manager UI slice; Auto Loot validation remains queued behind that PASS.

## 0.8.112-0.8.114 Preset Manager UI validation
1. **`0.8.112-dev` runtime result: PASS.**
   - User confirmed all five requested checks passed.
   - This validates the dynamic Unassigned Players box, preserved draggable/class-coloured player controls, live reflow, wide-layout wrapping, and Resummon centring behavior at the exact `0.8.112-dev` implementation head `267989036e23f3f4f4d10a3103bfd3d3f8d58c7a`.

2. **`0.8.113-dev` implementation.**
   - Verified starting `dev` exactly matched handoff `317468e3be77aee4d669228d9b9634229930f06d` / `0.8.112-dev`.
   - Implementation commit is `9125129649783b87cf928e653932870d1923f3fd`; TOC is `0.8.113-dev`.
   - Group title and Resummon controls are now actual children of the Group frame, with an 18-unit internal header band and a one-pixel divider anchored border-to-border.
   - Assignment rows keep their prior relative geometry by adding the same 18-unit header offset to their top anchor.
   - Unassigned Players receives matching divider treatment and more balanced 6-left/5-top title padding.
   - Vertical grid gap drops from 20 to 6 now that it no longer has to contain the next row's external Group header, limiting total panel growth to about 4 units per rendered Group row.

3. **Checks performed.**
   - Reviewed the complete `0.8.113-dev` implementation diff: only `Presets.lua` and `SoloCraftBots.toc` changed.
   - Confirmed no assignment-map, Request, Auto Loot, roster, spawn, maintenance backend, or protocol logic changed.
   - Confirmed Group frame content height remains user-layout-derived; the fixed 18-unit header is additive rather than rewriting saved layout values.
   - Canonical Lua 5.0.3 compiler check is **not run** in the current executable environment; do not claim a compiler pass.

4. **`0.8.113-dev` runtime result: PARTIAL.**
   - Unassigned Players padding: PASS.
   - Five assignment rows / interaction layout: PASS.
   - Overall panel/group height: PASS.
   - Group-title padding: needs refinement to match Unassigned Players.
   - Unassigned and Group dividers: structurally correct but slightly overlong and visually thicker than the surrounding border.

5. **`0.8.114-dev` implementation / runtime result: PASS.**
   - Verified starting `dev` exactly matched handoff `4a1bd21dd70473cd14e21fbbfd532069b4e469fd` / `0.8.113-dev`.
   - Implementation commit is `b000d6209131be326f4a21dbfc548355c1625f34`; TOC is `0.8.114-dev`.
   - Group title now uses the exact same 6-left/5-top padding as the accepted Unassigned title.
   - Both divider rules are inset 3 units on each side and reduced to 0.55 alpha; height remains one unit.
   - User confirmed the resulting padding/divider treatment looks good.
   - Accepted follow-up: Resummon appears about 1 px high; queue a 1 px downward anchor nudge into the next actual addon build rather than creating a UI-only revision.
   - Canonical Lua 5.0.3 compiler check is **not run** in the current executable environment; do not claim a compiler pass.

6. **`0.8.115-dev` queued visual follow-up implemented.**
   - Resummon Group keeps the same frame size, horizontal position, header height and row geometry.
   - Its existing centre anchor is moved down by exactly 1 px.
   - Runtime confirmation is bundled with the Auto Loot test rather than requiring another UI-only revision.


## 0.8.115 implementation / static validation / next runtime test
1. **Implementation.**
   - Verified starting `dev` exactly matched handoff `bf7a3455348d01755c705271e2028049e24c9b70` / `0.8.114-dev`.
   - Implementation commit is `b0ed87093d79cddeab6c38fd8853d71f7fdebc90`; TOC is `0.8.115-dev`.
   - Changed runtime files are `Roster.lua`, `SoloCraftBots.lua`, `Presets.lua`, plus the required TOC version bump.

2. **Static validation.**
   - Full diff reviewed; no Communication/Request code changed.
   - Repository scan confirms the only `SetLootMethod()` calls remain inside `SCB_ApplyAutoLootMethod()`.
   - Party->raid detection is observation-based, so it covers conversion initiated by another SCB client rather than depending on the local summoner path.
   - Raid leadership detection only fires when the local player's rank changes to/from leader rank 2.
   - Non-leader calls remain harmless because `SCB_ApplyAutoLootMethod()` still checks `SCB_IsLocalGroupLeader()` before any `SetLootMethod()`.
   - Existing Auto Loot retry cadence is reused; no timing values changed.
   - Canonical Lua 5.0.3 compiler check is **not run** in the current executable environment; do not claim a compiler pass.

3. **Runtime test — `0.8.115-dev` / `b0ed87093d79cddeab6c38fd8853d71f7fdebc90`: PASS.**
   - Gaia leader / Auto Loot Round Robin -> Gaia invited Revenga: actual loot method switched to Round Robin immediately. PASS.
   - Revenga Auto Loot Free For All -> Revenga requested the preset while Gaia remained leader: actual loot method stayed Round Robin through the Request/conversion path. PASS; non-leader preference did not override leader authority.
   - Leadership transferred to Revenga: actual loot method automatically became Free For All. PASS.
   - Leadership transferred back to Gaia: actual loot method automatically returned to Round Robin. PASS.
   - Resummon Group 1 px downward nudge: PASS; user confirmed it looks correct.
   - No further Auto Loot or Preset Manager UI runtime work is required for this build.


## All-row/server target-sensitivity audit — 0.8.115-dev
- Audit completed against the current Command Bots route matrix, Group/Target sequencing, modifier handling, slash/special paths, historical SoloCraft runtime evidence, and current upstream vMaNGOS PartyBot command source. No addon behavior changed during the audit.
- Group and Target intentionally use targeted command forms/sequencing. Paired role routes and special construction do not accidentally leak into recipient `all`.
- `moveall` and `stayall` remain historically runtime-proven global on SoloCraft.
- All Come uses `cometome`, which is server target-sensitive. SCB already treats this as conditional; Ctrl-Come All is `moveall` followed by the same `cometome` behavior.
- All Play/Pause remain `unpause all` / `pause all`. Current upstream vMaNGOS parses `all` explicitly, while older SoloCraft runtime evidence was contradictory. Preserve the existing conservative handling unless new exact-server runtime evidence justifies changing it.
- AoE, Attack Start, and Attack Stop intentionally use the selected living enemy as command context while addressing the bot group; this is expected target context, not accidental All-recipient narrowing.
- **Object is the concrete mismatch found by the audit.** Current upstream `usegobject` has a selected-player branch and a group branch, and the user confirms SoloCraft can target one bot to use the gameobject. The agreed UI should expose that native behavior directly rather than forcing All semantics:
  - friendly bot targeted -> tooltip `Object`; button remains clickable and sends the existing command;
  - human player targeted -> button greyed/disabled and unclickable;
  - anything else -> tooltip `Object All`; button remains clickable and sends the existing command.
- Do **not** add a timeout, delayed send, forced detarget, target restoration, or propagation state. The user explicitly considers normal manual target/click timing sufficient; keep the correction purely in availability/tooltip presentation around the existing server command.
- The narrow correction is now implemented in `0.8.116-dev`; see the validation block below.

## Object target-state correction — 0.8.116-dev / 0.8.117-dev
- `0.8.116-dev` implementation head: `157574ebe9e061b0054328e5147f46783736847e`.
- `0.8.116-dev` runtime result: **target-state logic PASS, with two uncovered server preconditions**.
  - Friendly bot target -> Object enabled with tooltip `Object`: PASS.
  - Human-player target -> Object greyed/disabled and unclickable: PASS.
  - Other/no target -> Object enabled with tooltip `Object All`: PASS.
  - Exception discovered: with no bots present, clicking Object produced the server message `You are not in a group.`
  - Exception discovered: with a group present outside an instance map, clicking Object produced the server message `You have to be in an instance map.`
- `0.8.117-dev` implementation head: `da22c1800797b628af8fb2442822ac96f0015833`.
- Runtime route remains unchanged: Object still sends only the existing `usegobject` command through its existing `all` route.
- Object availability now additionally requires the established live roster to contain at least one bot and the established location context to report `inInstance == true`.
- Existing roster events already refresh command availability when membership changes. The existing delayed location-refresh owner now also refreshes command availability after its location probe settles, preventing a stale Object state when entering/leaving an instance.
- No new scheduler, delay value, target clearing/restoration, timeout or propagation state was added.
- Static diff review: runtime changes are limited to `Communication.lua`, the location-owner refresh hook in `Presets.lua`, and the required `SoloCraftBots.toc` bump to `0.8.117-dev`; no Request, spawn, preset composition, maintenance, command transport or `usegobject` routing changed.
- Canonical Lua 5.0.3 compiler check is **not run**: the checker files are not present in the executable container and that container cannot resolve GitHub to fetch them. Do not claim a compiler pass.
- Runtime result for `0.8.117-dev` / `da22c1800797b628af8fb2442822ac96f0015833`: **PASS**.
  1. In an instance with at least one bot present, Object remains available and the target-sensitive `Object` / `Object All` behavior works as intended.
  2. With zero live bots, Object is greyed/disabled; the invalid server-side `You are not in a group.` path is no longer reachable through the button.
  3. With a bot/group present outside an instance map, Object is greyed/disabled; the invalid server-side `You have to be in an instance map.` path is no longer reachable through the button.
- Object target-state and availability work is now closed with no remaining runtime validation debt.


## Deferred / later
- Remove only proven-dead legacy refill/compatibility code after runtime proof.
- Add neutral read-only activity/status surface, then visualiser as a presentation-only consumer.
- Historical regression debt: dungeon -> 10-player scope retest; Replace Dead focused smoke; investigate dead-state observation only if the old omitted-dead-bot case recurs.

## 0.9.0 release
- User explicitly approved the 0.9.0 milestone and promotion to `main`.
- Tested runtime source: `0.8.117-dev` implementation `da22c1800797b628af8fb2442822ac96f0015833`; Object and preceding active slices are closed with the documented runtime PASS results.
- Release-candidate source: `0.9.0-dev` implementation `9161d333e3c42112d812abbc464e41d7b25e768c`; delta from the tested source is TOC version metadata only.
- Stable `main`: `0.9.0` at `4c1a75f052927be00aac91327a92dac902e2b301`.
- Promotion used a snapshot tree derived from the release candidate with old `main` as the commit parent; diverged branch histories were not merged over the tested runtime.
- Stable TOC is `SoloCraft Bots` / `0.9.0`. `DEV_PROGRESS.md` and `dev_rulebook.md` are absent from the stable tree; no dev-only loader/debug entries exist.
- Post-promotion tree audit: compared with the dev release state, only `SoloCraftBots.toc`, `DEV_PROGRESS.md`, and `dev_rulebook.md` differ. Compared with the tested `0.8.117-dev` source, those same three paths are the only differences; all runtime code and artwork blobs are identical.
- Exact stable metadata/tree was not separately runtime-tested after promotion; runtime behavior inherits the user-tested source unchanged. This distinction is intentional and recorded rather than treating release as a runtime test.
- Canonical Lua 5.0.3 compiler check remains **not run/unavailable** in the executable environment: the checker is not mounted locally and direct container network access cannot fetch it. Do not claim a compiler pass.

## Release note
`0.9.0` is the current stable release on `main`. Future addon work remains on `dev`; the next addon-affecting revision should advance the development patch version from `0.9.0-dev`.
