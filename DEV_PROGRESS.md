# Development Progress

> Live project-development context for a fresh chat. Keep this current and concise. Remove or compress superseded detail once it no longer affects future work.

## Current
- Branch: `dev`
- Version: `0.8.88-dev`
- Current implementation commit: `252f6f3acb33f755b0c6d5c34dedc68e0538b15e` (`0.8.88-dev`)
- Current runtime-tested implementation: `ff9725d0336ded2f406661bf9863d88719322124` (`0.8.87-dev`, unified logical-slot gate passed)
- Stable baseline: `0.8.78` on `main`, promotion commit `87e61360ec36c2d9543b2e1bc8606b948b10d6bd`; tested runtime source `0200cdb5ef59fc0cb4ef81016237d90ba16e22b9`
- Goal: runtime-validate the `0.8.88-dev` yellow live-layout mismatch presentation on top of the runtime-cleared unified logical-slot model.
- Current scope boundary: 0.8.87 unified logical-slot behavior is user-tested and accepted. The 0.8.88 delta is presentation/observation only and is statically checked but not yet user-tested. Do not begin maintenance changes, visualiser work, or unrelated cleanup until this gate passes.

## Current Design / Development Contract

### Architecture / Ownership
- The established runtime architecture is six main Lua owners plus locale files:
  - `SoloCraftBots.lua` — addon bootstrap/core, shared primitives, common UI/frame/event plumbing and base state.
  - `Presets.lua` — desired/configured preset structure, preset groups/data/editor, location-to-preset-group/capacity policy, execution snapshots and preset validation.
  - `Roster.lua` — observed live party/raid membership and subgroup placement, human/bot/dead/missing observation, Active Roster, logical association, role/class evidence and logical maintenance selection.
  - `Spawn.lua` — authoritative physical bot lifecycle through `SCB.botOperation`: validated add sending, preset summon/rebuild, pending-add recovery, bootstrap/survivor handling, removal/capacity settle, maintenance mutation, burst scheduling and assumed-spawn identity.
  - `Communication.lua` — command-request semantics/execution, raw PartyBot transport, incoming server/chat feedback, and preset addon communications.
  - `Options.lua` — settings, tutorial/help and developer/debug tooling.
- `Presets.lua` owns desired logical composition; `Roster.lua` owns observed current reality. Do not conflate configured slot/group intent with Blizzard's current physical roster layout.
- `Spawn.lua` is the one owner for physical roster mutation. Roster/Active Roster chooses logical assignments requiring work; Spawn performs remove -> observe -> settle if capacity reuse requires it -> add -> identity bind -> subgroup placement -> Active Roster bind.
- Local Summon and accepted remote Summon Request both enter `SCB_StartPresetRebuild()` -> `SCB_RequestPresetOperation()` -> `SCB.botOperation`. New physical entry points must not bypass that coordinator.
- Commands enter through `SCB_RequestCommand(commandKey, scope, modifiers)`. Target semantics belong to command metadata/request logic; UI availability may reflect the result but must not own a separate semantic rule.
- Do not collapse Command, Bot Operation, Communications and Roster into one giant state machine. A future status/activity surface may expose them independently for presentation/debug consumers.

### Invariants
- Logical preset identity is independent of Blizzard row ordering. A human owns an exact logical slot and suppresses that underlying bot intent while present; Blizzard party/raid placement is live observation, not logical identity.
- `size <= 5` is a topology policy: remain a party, never convert to raid, do not manipulate subgroups, keep deterministic remaining-bot order, and reserve exactly one final required bot assignment when a continuity bootstrap occupies a slot.
- `size > 5` uses raid topology. Bot subgroup/order remains intentionally controlled; a human logical slot must not be treated as an instruction to force that human into a Blizzard row/subgroup.
- Active Roster covered-slot lifecycle is authoritative: human present -> `expected=false`, `state="covered"`; that human absent before replacement -> same logical slot becomes `expected=true`, `state="missing"`; human returns before replacement -> covered again; once a replacement bot binds, `coveredBy` is cleared and it becomes a normal expected bot slot.
- After Replace Missing fills a departed human's logical slot, SoloCraftBots must not auto-kick or auto-free a slot when that human returns. The user manually frees capacity if they want the human back.
- Canonical capacity-reuse rule: removal requested -> observe member absent from Blizzard roster -> wait 3.0 seconds -> permit an add that depends on the freed capacity. Harmless work that does not consume the freed slot may continue during the settle.
- Bootstrap means a temporary bot occupant used only to establish/preserve required party/raid/instance continuity. Reuse an existing bot when possible; do not retain/create one when humans already preserve topology; target topology remains authoritative.
- Maintenance is `botOperation(kind="maintenance")`. Player combat is an absolute block; stale remote member/pet combat may be overridden only after the existing 10-second allowance while the player is personally clear. Maintenance abort must not destroy persistent preset tracker state.
- Addon manual Add is `botOperation(kind="manual-add")`: register explicit assumed identity before send, lock addon Add while another physical operation owns the roster, enforce the 1.0-second minimum floor, and release only after the expected identity binds or the existing short pending-add timeout expires.
- Raw user-typed `.partybot add ...` during an SCB-owned physical operation is outside the supported coordinator contract. Do not add fragile chat interception to make arbitrary manual chat commands participate in SCB identity ownership.
- Taxi safety is action-time only: `SCB_CanOperateBots(showError)` owns the native `UnitOnTaxi("player")` query. Do not restore continuous taxi polling or taxi-specific greying. Taxi world despawn must not clear/reclassify logical roster/session identity.
- Do not use `UnitHealth()==0` as a dead-state fallback. Vanilla unknown/out-of-range health semantics can create unsafe false positives; if the historical omitted-dead-bot case recurs, investigate dead-state observation/classification instead.

### Protocol / Data Model
- `SCB.botOperation` is the authoritative physical-operation record with operation identity/kind/status/phase/revision, desired intent, timestamps and optional rebuild/safety/maintenance state. Only one active physical owner may control the roster at a time.
- Persistent Active Roster slots carry logical identity and expected state separately from observed member state. Consumers that expect a bot must gate on `slot.expected`.
- Preset addon protocol: prefix `SCBPRESET`, protocol `2`, 190-byte chunks, 30-second transaction timeout and 2-second handshake retry. Vanilla has no addon WHISPER destination here, so transport uses RAID with PARTY fallback and carries the intended target in the payload.
- Preset snapshots are composition intent, not execution identity. They serialize group id/name, size, preset name, role counts, each logical slot's class/role/extra, and each human's name/group/`slotIndex`/role/extra. Generated bot names and assumed-spawn identity are never transmitted.
- Incoming preset validation requires both sender and receiving client to be represented in the snapshot. The client that actually summons owns generated bot-name -> logical-assignment binding.
- Save Received now persists each transmitted human `slotIndex` into preset `playerSlots` using the same player key normalization as `playerGroups`/`playerRoles`. The protocol remains version 2 and the existing transmitted group/role/extra data is unchanged.
- PartyBot transport ownership: normal addon control commands use GUILD through `SCB_SendPartyBotCommand`; validated spawn/add commands use SAY through `SCB_SendSpawnCommand` and register spawn intent.
- Current command execution policy:
  - Single is friendly-bot-targeted, direct and spammable; it does not create acknowledgement state or use the Group 24/sec pacing budget.
  - Group uses the targeted bot only as a locator for the bot's current live Blizzard subgroup, then owns per-recipient retargeting, 0.10-second settle after actual addon target changes, actor acknowledgement handling and the rolling 24 commands/sec budget.
  - All/role/pair scopes send immediately when command metadata says the current target context is valid.
  - `/scb move` and `/scb stay` are combat-first: friendly bot target -> Single; otherwise explicit All (`moveall` / `stayall`).
  - `moveall` and `stayall` are global; bare `cometome`/`come`, `pause` and `unpause` are target-sensitive server commands; `aoe`, `attackstart` and `attackstop` require a living enemy target; tested role commands are target-agnostic.
- Ctrl-click Come sends Move + Come back-to-back in the same recipient send phase. Do not add an artificial delay unless runtime evidence specifically proves the same-frame pair fails.

### Active Decisions
- 0.8.85 fixes Ctrl-Come modifier normalization at `SCB_RequestCommand`: Vanilla `IsControlKeyDown()` returns a truthy numeric value, so strict `== true` discarded the modifier after the 0.8.76 front-door convergence. The request front door now normalizes any truthy `forceMove` value to real boolean `true`; user confirmed the reported One Ctrl-Come path now works.
- 0.8.84 item 2.2 is implemented, statically checked and user-tested. Normal inbound requests, existing-bot teardown/rebuild, busy-operation exclusion, local Summon regression, and summoning-client ownership of generated bot identity all passed.
- 0.8.86 architecture item 2.3 is implemented and user-verified: Save Received retains transmitted exact human `slotIndex` in preset `playerSlots`, while preserving the existing `playerGroups` and `playerRoles` data and protocol-2 wire format.
- Party and raid presets now use one explicit logical-slot model. `SCB_ArrangePresetPlayers()` / `PRESET_ARRANGE_PLAYERS` are removed so logical human assignment no longer physically arranges humans. The focused 0.8.87 runtime gate is passed, including preset-switch persistence of moved human logical-slot assignment.
- Saved logical composition must not be silently rewritten to follow transient Blizzard layout. The 0.8.88 live mismatch presentation is implemented as a slow yellow whole-group background pulse:
  - same subgroup/composition but Blizzard row reorder: tooltip `Group composition correct; Blizzard client reordered members.`
  - actual subgroup rearrangement outside SCB: tooltip `Group rearranged in Blizzard Raid tab.`
- Layout mismatch classification belongs to Roster observation; Presets only renders the returned state. It is intentionally read-only and must never mutate saved logical slots, move humans, or create physical roster work.
- Maintenance selection should become reusable intent. Replace Missing/Dead and planned Resummon Group N should select logical assignments and feed the same Spawn-owned lifecycle; do not create another scheduler.
- Continue auditing All-row/server target sensitivity into declarative command metadata rather than button-local conditionals.
- Only after the logical-slot/maintenance cleanup and runtime gates should proven-dead legacy refill/compatibility runtime be deleted.
- The future gnomish LCD/pixel visualiser is deliberately dumb. First add a neutral read-only status/activity surface for Command, Bot Operation, Communication and Roster/Layout; the visualiser later consumes it without scheduler/business logic.

## Recent Relevant Commits
- `252f6f3acb33f755b0c6d5c34dedc68e0538b15e` — `0.8.88-dev`: add read-only live-layout mismatch classification plus slow yellow preset-group pulse/tooltips.
- `0a214582002239eb9b9df17d1b4e27241967b146` — accept the focused 0.8.87 unified logical-slot runtime gate and advance to mismatch presentation.
- `ff9725d0336ded2f406661bf9863d88719322124` — fix the unified logical-slot snapshot scope closure found during post-commit diff review.
- `aba30180ba1c40dd8544010291be55ee191589fb` — `0.8.87-dev`: unify party/raid human logical-slot editing and replace human arrangement with bot-only raid preparation.
- `6bcc9949222513d4f8e38a90d43071149f162f31` — record the verified 0.8.86 starting point before the logical-slot implementation.
- `c3f9d76bb240fef4d76331b27315f6460d097647` — `0.8.86-dev`: development version bump for architecture item 2.3.
- `c9a26ff8c0e58d08a6cb9992fa8af8065d9c482e` — preserve received preset human exact `slotIndex` as preset `playerSlots`.
- `a1e58a1981e4f556f2ddeed506e1813811fcef4f` — `0.8.85-dev`: normalize Ctrl-Come `forceMove` at the command request front door so Vanilla numeric modifier values are honored.
- `d877ebf8cb5f9ce23dd73a2971ed0221a61787e8` — document 0.8.84 remote summon coordination; pre-migration `dev` head.
- `e25d63f2a378ce1bcbf41682fc776794e91b0b03` — `0.8.84-dev`: accepted remote Summon Request enters the shared preset-operation coordinator.
- `9db2d7236f2a979e30a379a90edd2ebca5523eb6` — record manual Add cooldown runtime pass on 0.8.83-dev.
- `e27915c25eb11d9653e783061197715c3fd3bf39` — `0.8.83-dev`: final action-time taxi gate; supersedes all earlier taxi polling/UI-blocker attempts.
- `46ac48b01f9b701abe0b9151124a1e225a44a262` — `0.8.79-dev`: tracked addon manual Add with explicit identity and cooldown/lock ownership.
- `0200cdb5ef59fc0cb4ef81016237d90ba16e22b9` — `0.8.78-dev`: combat-first Move/Stay macro policy; user-tested runtime source for stable 0.8.78.
- `87e61360ec36c2d9543b2e1bc8606b948b10d6bd` (`main`) — promote tested 0.8.78 runtime to stable release.
- `04807e4789646b6f3d87b228853ecd578c4107ad` — `0.8.65-dev`: covered logical slots become Missing when their human leaves and re-cover if the human returns before replacement.
- `160620b37b697963999fd61712dbde322df6e1a2` — `0.8.64-dev`: preserve human-covered bot intent as dormant Active Roster slots.

## Completed / User-Verified
- `0.8.83-dev` / `e27915c25eb11d9653e783061197715c3fd3bf39`: action-time taxi blocking works as intended. Bot-affecting actions remain visually normal but do nothing mid-flight, emit the red taxi error + failure sound, preset editing stays usable, and normal operation resumes after landing.
- `0.8.83-dev` / `e27915c25eb11d9653e783061197715c3fd3bf39`: tracked manual Add cooldown/lock behavior inherited from 0.8.79 was user-tested; normal manual summon and intended cooldown behavior work.
- `0.8.78-dev` / `0200cdb5ef59fc0cb4ef81016237d90ba16e22b9`: command regression smoke passed — Move/Stay macros select Single vs All correctly, unavailable command buttons are inert with no gold highlight, valid buttons re-enable, Single spam remains good and Group sequencing remains good.
- `0.8.45-dev` / `379859be7196872328a106085cec37c161ef23eb`: natural-play 40-player BWL pass covered repeated preset summons/rebuilds, dead/missing maintenance refills and unified paced removal without observed hangs/disconnects/wrong replacement flow.
- `0.8.85-dev` / `a1e58a1981e4f556f2ddeed506e1813811fcef4f`: user confirmed Ctrl-click One Come works after modifier normalization; the reported regression is runtime-cleared.
- `0.8.84-dev` / `e25d63f2a378ce1bcbf41682fc776794e91b0b03`: architecture item 2.2 is fully user-verified. Remote requests land normally; accepting with existing bots performs coordinated teardown/rebuild; busy-operation attempts are rejected with the expected busy warnings and do not start nested physical operations; local Summon still works; requester-side generated bot-name state is not required.
- `0.8.86-dev` / runtime `c3f9d76bb240fef4d76331b27315f6460d097647`: architecture item 2.3 is user-verified. A received preset was saved and reloaded with the transmitted human exact logical `slotIndex` preserved, while group and role/extra data remained intact.
- `0.8.87-dev` / implementation `ff9725d0336ded2f406661bf9863d88719322124`: unified party/raid logical-slot migration is user-verified. Self can be moved to a different logical slot in a 5-man preset; summoning suppresses/replaces the correct underlying bot slot; raid summon still works correctly; and moved player location persists when swapping presets.
- Stable/released baseline is `0.8.78` on `main` at `87e61360ec36c2d9543b2e1bc8606b948b10d6bd`.

## Implemented / Awaiting Runtime Test
- `0.8.88-dev` / implementation `252f6f3acb33f755b0c6d5c34dedc68e0538b15e`: `SCB_GetPresetLiveLayoutMismatches()` now classifies stable tracked raid groups without changing preset or roster state.
- Classification is deliberately narrow: it applies only to the currently selected tracked raid preset, requires the observed raid count to match the tracked preset size, and stays quiet while an SCB physical bot operation is active.
- For each logical group, every expected logical slot must still resolve to a live tracked occupant before layout presentation is considered. This prevents missing-member/maintenance states from being mislabeled as Blizzard reordering.
- If the live member set differs from the logical group set, the group is `regrouped`; if the member set is identical but one or more Blizzard rows differ from logical rows, it is `reordered`.
- Preset group frames render either mismatch as the agreed slow yellow background pulse. The exact tooltip text is localized and distinguishes client row reorder from actual Raid-tab subgroup rearrangement.
- Presentation refreshes from the existing tracker live-layout observation path and when the Presets drawer/preset selection is opened or changed. No human placement, saved preset data, Spawn operation, maintenance scheduler, protocol data, or bot ordering path was changed.
- The 0.8.87 logical-slot migration remains the exact runtime-cleared baseline beneath this untested presentation delta.

## Static / Automated Checks
- Focused 0.8.88 diff from accepted-gate checkpoint `0a214582002239eb9b9df17d1b4e27241967b146` to implementation `252f6f3acb33f755b0c6d5c34dedc68e0538b15e` changes only `Locale/enGB.lua` (+2), `Presets.lua` (+75), `Roster.lua` (+119/-1), and the TOC version bump.
- Post-commit diff review confirms the new Roster path only observes tracker/live roster identity and returns `reordered`/`regrouped`; the Presets path only changes group-frame backdrop/tooltip state.
- Focused classification harness passed: exact layout -> no mismatch; same-group row reorder -> `reordered`; cross-group swap -> both affected groups `regrouped`; missing-member count -> suppressed; different selected preset -> suppressed.
- The newly added Lua blocks parse successfully with the available LuaTeX Lua parser. No standalone Lua 5.0 compiler executable is available in this runtime, so this is a syntax/static-flow check rather than a target-client compiler result.
- The focused 0.8.87 implementation diff from the documented starting-point commit `6bcc9949222513d4f8e38a90d43071149f162f31` through `ff9725d0336ded2f406661bf9863d88719322124` changes only `Presets.lua` (+29/-103), `Roster.lua` (+16/-39), `Spawn.lua` (+12/-23), and the TOC version bump (+1/-1).
- Repository scan confirms zero remaining references to `SCB_AutoPartyPlayerSlots`, `SCB_ArrangePresetPlayers`, `PRESET_ARRANGE_PLAYERS`, `presetHumanGroups`, or `parkBeforeArrange`.
- Remaining `SetRaidSubgroup` calls were inspected: they operate on bot burst/refill placement, bot maintenance placement, or temporary bot bootstrap/survivor parking. No remaining human logical-slot path calls `SetRaidSubgroup`.
- `PRESET_PREPARE_RAID_BOTS` has one definition, one enqueue site and one queue handler; the handler only preserves the existing bot bootstrap/survivor parking barrier before deterministic raid bot bursts.
- Party snapshot validation already requires unique numeric `slotIndex` values; `SCB_GetSnapshotOccupiedSlots()` suppresses those exact party logical slots, so the unified editor feeds the existing exact-slot execution path without a new party compatibility layer.
- No standalone Lua 5.0-compatible compiler executable is available in the current chat runtime, so 0.8.87 has static diff/flow validation but no local compiler result.
- Item 2.3 protocol behavior remains unchanged: `SCBPRESET` protocol 2 serialization/deserialization was not edited by this slice.

## Current Issues
- The 0.8.88 mismatch presentation has not yet been exercised in WoW 1.12.1; runtime behavior/visual strength/tooltip accessibility are the current focused gate.
- No known runtime issue remains in the 0.8.87 unified logical-slot core after the focused gate passed.
- No remaining known issue from the 0.8.85 Ctrl-Come regression; user confirmed the reported One path works.
- Item 2.2 has no remaining known runtime issue after the 0.8.84 pass.
- Item 2.3 has no remaining known runtime issue after the 0.8.86 pass.
- Pending regression debt: retest dungeon -> 10-player preset for the historical 0.8.55 scope fix; monitor the intermittent first-summon subgroup mismatch first observed around 0.8.50; Replace Dead still needs a separate focused runtime smoke.
- Historical Naxx observation: one genuinely dead bot was once omitted from Replace Missing/Dead. If it recurs, investigate Vanilla dead-state observation/classification rather than adding an unsafe health fallback.

## Testing

### Last Runtime Test
- Version/implementation: `0.8.87-dev` / `ff9725d0336ded2f406661bf9863d88719322124` plus documentation-only branch updates.
- Passed: self can be moved to a different logical slot in a 5-man preset; summoning suppresses/replaces the correct underlying bot slot; raid summon still works correctly; moved player location persists when swapping presets.
- Result: the focused 0.8.87 unified logical-slot gate is accepted as passed.

### Next Runtime Test
- Test exact runtime code `0.8.88-dev` at `252f6f3acb33f755b0c6d5c34dedc68e0538b15e` plus documentation-only handoff commits.
- First confirm a raid group whose live Blizzard rows exactly match its logical rows has no yellow pulse.
- Same-subgroup reorder case: use a preset where the same five intended members remain in the same subgroup but Blizzard presents at least one on a different row (a human deliberately saved to a non-Blizzard row is a strong case). The whole affected preset group should pulse slowly yellow and hovering the group background should show `Group composition correct; Blizzard client reordered members.`
- Actual subgroup case: rearrange members in the Blizzard Raid tab without using SCB so a tracked member crosses subgroup boundaries. Every affected logical group whose composition changed should pulse yellow and show `Group rearranged in Blizzard Raid tab.`
- Restore the Blizzard layout and confirm the pulse clears. Confirm switching to a different preset suppresses the active-layout warning for that other preset.
- Confirm SCB does not move any human or alter the saved logical slot assignment as a result of these warnings.
- Do not begin maintenance changes, visualiser work, or unrelated cleanup unless the 0.8.88 presentation gate is accepted.

## Planned / Next Work
1. Runtime-clear the 0.8.88 yellow live-layout mismatch presentation.
2. Separate maintenance selection from execution and implement Resummon Group through the existing maintenance/bot-operation lifecycle.
3. Audit remaining All-row/server target sensitivity and keep semantics declarative.
4. Delete only proven-dead legacy refill/compatibility runtime after call-site audit and runtime proof.
5. Add the neutral read-only activity/status surface.
6. Return to the visualiser as a presentation-only consumer.

## Deferred / Out of Scope
- The broader logical-slot migration is no longer blocked; item 2.3 passed its focused runtime gate. Visualiser work remains deferred until the logical-slot/maintenance cleanup and runtime gates are complete.
- Do not intercept arbitrary user-typed raw `.partybot add ...` commands into the SCB coordinator.
- Do not add a delay between Ctrl-click Move and Come without focused runtime evidence.
- Do not rewrite saved presets to follow Blizzard's transient row/order changes.
- Do not auto-kick or auto-free capacity for a returning human after their missing slot has already been replaced.
- Do not build a second physical scheduler or collapse independent domains into one giant state machine for the visualiser.
- Cosmetic button/artwork state cleanup, centre-screen message wording review and optional startup/lazy-UI/debug-buffer micro-optimisation remain lower-priority backlog unless promoted explicitly.

## Release / Promotion Notes
- Current stable `main`: `0.8.78` / `87e61360ec36c2d9543b2e1bc8606b948b10d6bd`; verified against the actual remote during this workflow migration.
- Stable 0.8.78 was promoted from tested runtime `0200cdb5ef59fc0cb4ef81016237d90ba16e22b9`; the promotion preserved the previous main history rather than force-pushing.
- Stable 0.8.78 release tree used the tested dev runtime/assets unchanged. Release-only differences were stable TOC title/version and exclusion of development status files; no `Debug.lua` existed in that release tree.
- No current main-only runtime/assets are known to require special preservation, but future promotion must still compare `main` and `dev` rather than assuming replacement because main has diverged historically.
- Do not promote the current dev line yet. Item 2.3 and the 0.8.87 unified logical-slot core are runtime-cleared, but the implemented 0.8.88 mismatch presentation is still awaiting runtime validation and later architecture work remains before the intended release gate.
- Current `main` and `dev` have diverged historically, so release preparation must compare and reconcile them rather than overwrite `main`.
- Known validation debt accepted for current release: none newly accepted here; 0.8.88 remains development-only and untested in runtime.
- External/runtime prerequisites: WoW 1.12.1 / Interface 11200 and a SoloCraft/PartyBot-capable server. Preset communications require a compatible SoloCraftBots protocol-2 peer. pfUI role-state integration is supported observationally but is not the physical-operation owner.

## Exact Next Step
Runtime-test the focused `0.8.88-dev` presentation at implementation `252f6f3acb33f755b0c6d5c34dedc68e0538b15e`: verify no pulse for an exact layout, the yellow reorder tooltip for same-group Blizzard row differences, the yellow regroup tooltip for an actual Raid-tab subgroup change, and clearing after the layout is restored.

Do not begin maintenance changes, visualiser work, or unrelated cleanup until this runtime gate is explicitly accepted.
