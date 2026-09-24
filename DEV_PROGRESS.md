# Development Progress

> Live project-development context for a fresh chat. Keep this current and concise. Remove or compress superseded detail once it no longer affects future work.

## Current
- Branch: `dev`
- Version: `0.8.84-dev`
- Development head before this documentation-only workflow migration: `d877ebf8cb5f9ce23dd73a2971ed0221a61787e8`
- Current runtime commit: `e25d63f2a378ce1bcbf41682fc776794e91b0b03` (`0.8.84-dev`)
- Stable baseline: `0.8.78` on `main`, promotion commit `87e61360ec36c2d9543b2e1bc8606b948b10d6bd`; tested runtime source `0200cdb5ef59fc0cb4ef81016237d90ba16e22b9`
- Goal: runtime-clear architecture item 2.2, the remote Summon Request convergence onto the shared preset-operation coordinator.
- Current scope boundary: do not start item 2.3 received-slot persistence, the unified logical-slot migration, or visualiser work until the 0.8.84 remote-summon runtime gate is reported back.

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
- Known item 2.3 gap: the wire format already carries exact human `slotIndex`, but Save Received currently persists only `playerGroups` and `playerRoles`; it must later preserve those exact slots as preset `playerSlots`.
- PartyBot transport ownership: normal addon control commands use GUILD through `SCB_SendPartyBotCommand`; validated spawn/add commands use SAY through `SCB_SendSpawnCommand` and register spawn intent.
- Current command execution policy:
  - Single is friendly-bot-targeted, direct and spammable; it does not create acknowledgement state or use the Group 24/sec pacing budget.
  - Group uses the targeted bot only as a locator for the bot's current live Blizzard subgroup, then owns per-recipient retargeting, 0.10-second settle after actual addon target changes, actor acknowledgement handling and the rolling 24 commands/sec budget.
  - All/role/pair scopes send immediately when command metadata says the current target context is valid.
  - `/scb move` and `/scb stay` are combat-first: friendly bot target -> Single; otherwise explicit All (`moveall` / `stayall`).
  - `moveall` and `stayall` are global; bare `cometome`/`come`, `pause` and `unpause` are target-sensitive server commands; `aoe`, `attackstart` and `attackstop` require a living enemy target; tested role commands are target-agnostic.
- Ctrl-click Come sends Move + Come back-to-back in the same recipient send phase. Do not add an artificial delay unless runtime evidence specifically proves the same-frame pair fails.

### Active Decisions
- 0.8.84 item 2.2 is implemented but not user-tested: accepted remote Summon Request now enters the same non-forced preset-operation front door as local Summon; requester remains composition-only and summoning-client identity ownership is unchanged.
- After item 2.2 runtime clearance, item 2.3 is next: preserve received exact human `slotIndex` when saving a communicated preset.
- Then migrate party and raid presets to one explicit logical-slot model. Remove/rework `SCB_ArrangePresetPlayers()` / `PRESET_ARRANGE_PLAYERS` so logical human assignment no longer physically arranges humans.
- Saved logical composition must not be silently rewritten to follow transient Blizzard layout. Planned live mismatch presentation is a slow yellow whole-group background pulse:
  - same subgroup/composition but Blizzard row reorder: tooltip `Group composition correct; Blizzard client reordered members.`
  - actual subgroup rearrangement outside SCB: tooltip `Group rearranged in Blizzard Raid tab.`
- Maintenance selection should become reusable intent. Replace Missing/Dead and planned Resummon Group N should select logical assignments and feed the same Spawn-owned lifecycle; do not create another scheduler.
- Continue auditing All-row/server target sensitivity into declarative command metadata rather than button-local conditionals.
- Only after the logical-slot/maintenance cleanup and runtime gates should proven-dead legacy refill/compatibility runtime be deleted.
- The future gnomish LCD/pixel visualiser is deliberately dumb. First add a neutral read-only status/activity surface for Command, Bot Operation, Communication and Roster/Layout; the visualiser later consumes it without scheduler/business logic.

## Recent Relevant Commits
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
- Stable/released baseline is `0.8.78` on `main` at `87e61360ec36c2d9543b2e1bc8606b948b10d6bd`.

## Implemented / Awaiting Runtime Test
- `0.8.84-dev` / `e25d63f2a378ce1bcbf41682fc776794e91b0b03`: architecture item 2.2 only. Remote Summon Request acceptance now calls `SCB_StartPresetRebuild(incoming.snapshot, false)` instead of the lower-level snapshot summoner.
- This gives remote acceptance the same active-operation exclusion, pending-add handling, existing-bot teardown/rebuild coordination, Active Roster transition setup, taxi gate and coordinator phase ownership as local Summon.
- Wire data remains composition-only; no requester-side generated bot identity was added.
- Item 2.3 Save Received exact-slot persistence is intentionally unchanged.

## Static / Automated Checks
- 0.8.84 runtime diff was exactly `Communication.lua` plus TOC version bump to `0.8.84-dev`.
- Remote and local Summon both enter `SCB_StartPresetRebuild`; no `SCB_StartPresetSummonSnapshot` call remains in `Communication.lua`, and low-level snapshot summoning is confined to `Spawn.lua`.
- Preset wire-format audit confirms no generated bot identity fields; TOC loads `Spawn.lua` before `Communication.lua`.
- The repository currently has no GitHub Actions workflow directory and the 0.8.84 runtime commit has no CI status checks.
- This workflow migration is documentation-only by scope; runtime files/TOC must remain byte-identical to pre-migration `dev`.

## Current Issues
- 0.8.84 remote Summon Request coordinator convergence is statically checked but not user-tested.
- Save Received discards transmitted exact human `slotIndex` instead of populating preset `playerSlots` (item 2.3).
- Five-player preset UI still derives human rows from current party order instead of exposing the raid-style explicit logical-slot model.
- `SCB_ArrangePresetPlayers()` / `PRESET_ARRANGE_PLAYERS` still couples logical human assignment to physical raid subgroup movement and conflicts with the agreed model.
- Pending regression debt: retest dungeon -> 10-player preset for the historical 0.8.55 scope fix; monitor the intermittent first-summon subgroup mismatch first observed around 0.8.50; Replace Dead still needs a separate focused runtime smoke.
- Historical Naxx observation: one genuinely dead bot was once omitted from Replace Missing/Dead. If it recurs, investigate Vanilla dead-state observation/classification rather than adding an unsafe health fallback.

## Testing

### Last Runtime Test
- Version/commit: `0.8.83-dev` / `e27915c25eb11d9653e783061197715c3fd3bf39`
- Passed: final action-time taxi safety and addon manual Add cooldown/normal summon behavior.
- Failed: none reported on that tested delta.
- Not tested: 0.8.84 remote Summon Request coordinator convergence.

### Next Runtime Test
- Use two SCB clients on `0.8.84-dev`.
- Empty/no-active-operation case: requester sends Summon Request; summoning client accepts; summon completes normally.
- Existing bots, out of combat: remote acceptance performs the same coordinated teardown/rebuild as local Summon.
- Busy ownership: while the summoning client already owns a physical bot operation, accept another remote request and verify no nested/second summon starts.
- Smoke local Summon afterward for regression.
- Confirm requester does not need generated bot-name state; logical/generated identity remains local to the summoning client.

## Planned / Next Work
1. Runtime-clear 0.8.84 item 2.2.
2. Implement item 2.3: preserve received exact human `slotIndex` as preset `playerSlots` when saving communicated presets.
3. Unify party/raid explicit logical-slot editing, remove logical-human -> physical-placement coupling, and add the agreed yellow live-layout mismatch pulse/tooltips.
4. Separate maintenance selection from execution and implement Resummon Group through the existing maintenance/bot-operation lifecycle.
5. Audit remaining All-row/server target sensitivity and keep semantics declarative.
6. Delete only proven-dead legacy refill/compatibility runtime after call-site audit and runtime proof.
7. Add the neutral read-only activity/status surface.
8. Return to the visualiser as a presentation-only consumer.

## Deferred / Out of Scope
- Do not start item 2.3, logical-slot migration or visualiser work until the 0.8.84 remote-summon runtime gate is reported back.
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
- Do not promote the current 0.8.84 dev line before its new runtime delta is user-tested and the broader intended consolidation/regression gate is accepted.
- Known validation debt accepted for current release: none newly accepted here; 0.8.84 remains development-only and explicitly untested.
- External/runtime prerequisites: WoW 1.12.1 / Interface 11200 and a SoloCraft/PartyBot-capable server. Preset communications require a compatible SoloCraftBots protocol-2 peer. pfUI role-state integration is supported observationally but is not the physical-operation owner.

## Exact Next Step
User-test `0.8.84-dev` architecture item 2.2: remote Summon Request acceptance must behave like local Summon through the shared preset-operation coordinator, including existing-bot teardown/rebuild and busy-operation exclusion.

Do not start item 2.3 or visualiser work until this runtime gate is reported back.
