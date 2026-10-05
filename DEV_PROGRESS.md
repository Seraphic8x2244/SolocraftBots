# Development Progress

> Sole live handoff for SoloCraftBots development. Git history carries history; keep this file focused on current constraints, proven behaviour, unresolved questions and the next coherent step.

## Current
- Branch: `dev`
- TOC version: `0.9.26-dev`
- Current implementation head: `de203c6aec51a4588c5264410d3f5b4dee9cd5d4`
- Accepted design handoff before the ZG/final-bot slice: `7b32dfa3cd2a2399106efa9bd567f2d96904cdf2`
- Request protocol 8 runtime validation is now completed on `0.8.111-dev` at handoff `dd1b21b9b23013a5f20bcc3f93d4c6b2bacb3b3b`: receiver-local capacity refusal PASS; leader-owned party→raid conversion PASS; receiving summoner requires neither leadership nor assistant PASS; Request-owned loot behavior absent PASS. A separate addon-level Auto Loot trigger gap was exposed: when a non-leader receiver performs the requested summon, the leader's SCB may never re-apply its own Auto Loot preference.
- Stable `main`: `0.9.16` at `03ea60a90b79a29d726c627f7b833ec673251cb6`. The released `0.9.16` baseline contains the accepted Appearance/Wisdom state. Current `dev` is `0.9.26-dev`: it inherits the still-pending `0.9.21-dev` T3 maintenance-bootstrap and `0.9.22-dev` Kick Dead runtime debt plus the unchanged `0.9.23-dev` raid-convert delegation slice. `0.9.24-dev` was a failed layout attempt; `0.9.25-dev` separated the colliding rows but was superseded before runtime retest; `0.9.26-dev` normalizes all five Misc checkboxes to the established 24px cadence at `de203c6aec51a4588c5264410d3f5b4dee9cd5d4`.
- Receiver-owned location-capacity guardrail remains explicitly accepted as correctness/state-integrity protection.
- Request protocol 8 carries no loot-setting behavior; Auto Loot remains addon-level state owned by the current group leader's SCB.
- `0.8.108-dev` side-drawer justification layout is runtime-confirmed working.
- `0.8.109-dev` readability/palette pass was visually received positively by the user.
- `0.8.110-dev` header homogeneity runtime: all four requested checks **PASS** — centered Preset/Options titles, both new X buttons, dynamic Options reflow, and hidden Preset self class/role widgets.
- New runtime issue found in `0.8.110-dev`: the Preset content chain shifted left by the same amount as the centered title. Root cause confirmed: `presetSelector` was anchored to `presetHeader:BOTTOMRIGHT`, so the centered title remained a layout owner.
- `0.8.111-dev` detaches Preset content geometry from the title. The selector is now right-aligned directly to the Preset panel and vertically positioned using the existing measured header height; Group selector and downstream controls remain chained from that panel-owned selector.
- `0.8.111-dev` Preset content anchor fix is **USER TESTED PASS**: user confirmed the layout is sorted.
- Immediate goal / exact next step: Options > Misc layout is **USER TESTED PASS** on `0.9.26-dev`. Continue the remaining `0.9.23` runtime matrix tests 2-9 with Revenga/Gaia, then the still-pending `0.9.22-dev` Kick Dead + ZG tests 2, 5 and corrected 6. Do not begin the visualiser until both are accepted.

## 0.9.26-dev Options > Misc normalized checkbox spacing retest
- User clarified that the spacing of the first three Misc checkboxes is already correct and should be used for all five rows.
- Implementation: `de203c6aec51a4588c5264410d3f5b4dee9cd5d4` / `0.9.26-dev`.
- The five checkbox anchors now follow one exact 24px cadence: `-30, -54, -78, -102, -126` for Auto-Swap Presets by Location, Auto-promote players in raid, Loot Safe, Auto-accept raid convert requests, and Confirm Bot Roles from Combat respectively.
- Misc expanded height is `188` with content height `162`, matching the normalized final row while preserving bottom clearance before Chat Filtering.
- Static implementation diff review: **PASS**. Product delta is limited to the two row anchors, matching section/content heights, and required TOC version bump. No settings behavior, communication, raid-convert logic, Kick Dead, ZG/bootstrap, or visualiser work changed.
- Canonical Lua 5.0.3 compiler check: **NOT RUN / unavailable** under the existing documented environment limitation; do not claim a compiler pass.
- Runtime state: **USER TESTED PASS**. User confirmed the normalized five-row Misc layout is correct on `0.9.26-dev`; all five checkboxes now read with the intended consistent spacing.
- Next step: continue `0.9.23` runtime matrix tests 2-9.

## 0.9.25-dev Options > Misc checkbox collision retest
- `0.9.24-dev` layout retest: **FAIL / worse**. User screenshot shows the previous diagnosis was incorrect: `Auto-accept raid convert requests` was not merely wrapping into `Loot Safe`; it was colliding with the pre-existing `Confirm Bot Roles from Combat` checkbox that is created later in `SCB_CreateOptionsUI()`.
- Root cause: Auto-accept was moved to `-108`, while Confirm Bot Roles still used `-112`, so the two independent checkbox rows were only 4px apart and their labels rendered on top of each other.
- Implementation: `3152df694ec258b261cfa53170cb8ca4e732ef8c` / `0.9.25-dev`.
- Fix is layout-only: Auto-accept remains at `-108`; Confirm Bot Roles moves from `-112` to `-138`; Misc expanded height increases from `168` to `194`, and content height from `142` to `168`, preserving bottom clearance before Chat Filtering.
- Static implementation diff review: **PASS**. Product delta is only the Confirm Bot Roles row position, matching Misc/content heights, and the required TOC version bump. No settings behavior, communication, raid-convert logic, Kick Dead, ZG/bootstrap, or visualiser work changed.
- Canonical Lua 5.0.3 compiler check: **NOT RUN / unavailable** under the existing documented environment limitation; do not claim a compiler pass.
- Runtime state: **IMPLEMENTED + STATIC-REVIEWED; NOT USER TESTED**. Superseded before runtime retest when the user clarified that the existing first-three-row spacing should be preserved exactly across all five rows.
- Superseded by the `0.9.26-dev` normalized 24px cadence above.

## 0.9.24-dev Options > Misc wrapped-label spacing retest
- `0.9.23-dev` runtime matrix Test 1: **FAIL**. In Options > Misc, `Loot Safe` and `Auto-accept raid convert requests` are too close because the final checkbox label wraps while the original rows remained on a fixed 24px cadence (`-78 / -102`).
- Implementation: `584198e28f76d40724ff3e2e523c5bc5e4b3e94b` / `0.9.24-dev`.
- Fix is layout-only: the final Auto-accept checkbox moves from `-102` to `-108`, giving 30px separation from `Loot Safe`. No option defaults, handlers, localization, communication, raid-convert behavior, Kick Dead behavior, ZG/bootstrap behavior, or visualiser work changed.
- Static implementation diff review: **PASS**. Product delta is only the one-line `Options.lua` row-position change plus the required TOC version bump.
- Canonical Lua 5.0.3 compiler check: **NOT RUN / unavailable** under the existing documented environment limitation; do not claim a compiler pass.
- Runtime state: **USER TESTED FAIL**. The screenshot confirms a worse overlap because `Confirm Bot Roles from Combat` remained at `-112` and collided with Auto-accept at `-108`; the earlier wrapped-label diagnosis was incorrect.
- Superseded by the `0.9.25-dev` collision fix above.

## 0.9.23-dev non-leader raid-convert delegation / Options cleanup
- User-reported defect: two humans form a party, zone into a dungeon, and a non-leader presses Summon for a preset larger than five. The preset scheduler reaches its party->raid conversion marker, native `ConvertToRaid()` silently cannot act for the non-leader, the queue changes to its raid-wait state, and the requester is left indefinitely showing Summoning with no recovery other than a leader-side forced action.
- Implementation: `c52e04a877e73d2e8df660b0c806de14f110b048` / `0.9.23-dev`.
- Local preset Summon now reuses the existing protocol-8 leader-control `L:...:CONVERT` transport instead of adding a second communication mechanism. All preset-owned conversion points that can encounter a human party use one `SCB_RequestRaidConvertForPresetOperation()` owner; the existing preset bot-operation lifecycle and summon scheduler remain authoritative.
- If the summoner is already party leader, the existing direct native `ConvertToRaid()` behavior is preserved. If the summoner is not leader, SCB identifies the current party leader, sends one targeted conversion request, leaves the original preset operation pending, and resumes through the existing raid-wait queue only after raid state is actually observed.
- Incoming conversion requests now have explicit leader-side policy:
  - new account-wide Options > Misc checkbox `Auto-accept raid convert requests`, default **OFF**;
  - OFF -> the current party leader receives an Accept / Decline prompt;
  - ON -> the current party leader immediately runs the same accepted conversion path without the prompt.
- Failure ownership is bounded by the existing 30-second communication timeout. Decline, explicit error/busy response, requester operation cancellation, sender departure, leadership loss/change, missing/non-responsive SCB leader, or conversion that never produces raid state all clear/abort the pending request instead of leaving Summon stuck indefinitely.
- The same shared `L CONVERT` receiver is still used by protocol-8 remote Preset Request conversion. That path therefore inherits the new leader prompt/auto-accept preference rather than maintaining a second conversion policy. Protocol remains 8; no snapshot/data-model fields changed.
- Options cleanup:
  - obsolete `Reset Tutorials` control, its reset-only handler/helper and reset-only locale strings were removed; the tutorial system itself was not otherwise changed;
  - Misc checkbox rows are now at `-30 / -54 / -78 / -102` beneath Loot Type Control, preserving the existing 24px cadence;
  - Misc subsection height remains 164; the new final 24px checkbox ends with approximately 12px of section clearance before Chat Filtering, replacing the old lower reset button that produced the screenshot overlap.
- Scope audit / static review **PASS** against the implementation diff:
  - product changes are limited to `Communication.lua`, `Spawn.lua`, `SoloCraftBots.lua`, `Options.lua`, `Presets.lua`, `Locale/enGB.lua`, and the required TOC bump;
  - `Spawn.lua` changes are limited to preset conversion routing plus stale-request cleanup on preset abort; maintenance conversion logic was not changed;
  - no new spawn scheduler, PartyBot transport, preset snapshot fields, SavedVariable migration, ZG/final-bot behavior, Kick Dead behavior, or visualiser work was added;
  - new communication helpers are SCB-owned functions rather than additional top-level locals, avoiding unnecessary Lua 5.0.3 chunk-local pressure.
- Canonical Lua 5.0.3 compiler check: **NOT RUN / unavailable in this executable environment**. GCC is present, but the private VanillaTemplate `tools/lua50/` checker/vendor files are accessible only through the GitHub connector and are not mounted in the executable container; no system Lua/luac is installed. Do not record a compiler pass.
- Runtime state: **IMPLEMENTED + STATIC-REVIEWED; NOT USER TESTED**.
- Required focused runtime matrix:
  1. **PASS on `0.9.26-dev`** — Options layout is accepted: all five Misc checkboxes use the same spacing and Chat Filtering is clear below them.
  2. Auto-accept **OFF**: two real humans in a normal party, non-leader presses Summon for a >5 preset -> leader receives Accept/Decline prompt; requester reports it is waiting; Accept converts to raid and the requester's original summon proceeds without a second Summon click.
  3. Decline with Auto-accept OFF -> requester aborts cleanly and does not remain in Summoning.
  4. Auto-accept **ON** -> no prompt; leader converts automatically and the requester's original summon proceeds.
  5. Non-responsive / no compatible SCB leader -> requester times out cleanly after the existing 30-second communication timeout; no stuck preset operation.
  6. Leadership changes while waiting -> requester fails cleanly; no stuck preset operation.
  7. Leader-initiated >5 preset summon -> existing direct conversion behavior remains unchanged.
  8. Existing remote Preset Request that needs party->raid conversion -> OFF prompts the actual leader; ON auto-accepts; accepted request still resumes only after raid state exists.
  9. <=5 preset summon -> no raid-convert request and existing five-player behavior remains unchanged.
- After this focused matrix, continue the previously pending `0.9.22-dev` Kick Dead UI + ZG tests 2, 5 and corrected Test 6. Visualiser remains deferred.

## 0.9.18-dev ZG / final-bot removal safety
- User-accepted design handoff: `7b32dfa3cd2a2399106efa9bd567f2d96904cdf2`.
- Implementation commits: `350ebd8ca8fb1efacca2f64d5e10e2636dcec7d2` implemented the slice; `ebf547e4a39af361a5f7b6a6519b1e0ee288be50` tightened the boss-target predicate after static review so `UnitLevel() == -1` cannot admit a merely over-level hostile mob. Current TOC is `0.9.18-dev`.
- Original runtime issues in Zul'Gurub:
  1. Kick All retained one safety bot after the first boss because the removal path read cached saved-instance data instead of refreshing it for the action.
  2. After a wipe/re-entry with all bots dead, Replace Dead could remove the dead bots but rebuild only a party-sized group because maintenance did not recover raid topology after a full teardown.
- Fresh Raid-ID decisions are now action-driven. `SCB_RequestFinalBotRemovalDecision()` issues `RequestRaidInfo()` and waits for `UPDATE_INSTANCE_INFO`; a 2.5-second timeout, unavailable API, invalid/no matching ID, or zone mismatch fails conservatively. `SCB_MakeFinalRemovalDecision()` carries the refreshed decision into the removal action.
- `SCB_CanRemoveFinalBot()` is the shared final-bot-removal decision seam used by manual Kick All/Kick Dead and maintenance. Existing preset-rebuild bootstrap requirements still win before ordinary final removal.
- Instance-safety rule: with no other real human, an in-instance final bot is removable only after a fresh valid saved Raid ID. With another real human present, the pre-existing no-survivor behavior is retained.
- **Loot Safe** is account-wide option state under `SoloCraftBotsDB.options.lootSafe`, defaults **ON**, and appears in Misc options. It is independent of instance-retention safety:
  - disabled: no loot-specific protection; intentional loot loss is user responsibility;
  - enabled + another real human remains: does not block removal of every bot;
  - enabled + player is the only real human: final removal requires the fresh valid saved Raid ID, a currently targeted **dead `worldboss`**, and an open `LootFrame`;
  - there is no second-click override while enabled; disabling Loot Safe is the explicit override.
- The physical kick queue defers the Group-1 fallback bot to the final removal position and re-runs `SCB_CanRemoveFinalBot()` immediately before that final `UninviteByName()`. This re-evaluates live human count, location, boss-corpse target and loot-window state after the asynchronous Raid-ID refresh rather than trusting click-time state.
- Maintenance requests the same fresh decision before a true all-bot teardown. If the last-moment guard changes from allowed to blocked, `SCB_0826AdoptPreservedSurvivor()` adopts that retained bot into the existing survivor-replacement flow instead of losing its tracked assignment.
- Replace Dead / Resummon Group T3 topology recovery is maintenance-owned and does not alter the full Summon scheduler. If maintenance is non-raid in a T3 raid and remaining assignments require later raid groups:
  - party present -> request `ConvertToRaid()` with the existing bounded maintenance timeout;
  - fully solo -> send one real replacement assignment as the bootstrap, wait for it to join, convert the resulting party to raid, then continue normal subgroup placement and replacement bursts.
- Scope audit: no boss-death monitoring, NPC scanning, visualiser work, protocol change, SavedVariable migration, or unrelated refactor was added.
- Static source/diff review **PASS** for the intended scope. The implementation changes only `Communication.lua`, `Spawn.lua`, `SoloCraftBots.lua`, `Options.lua`, `Locale/enGB.lua`, and `SoloCraftBots.toc`; the correction commit then changes only `Communication.lua` and the TOC. No introduced `#` length syntax or `goto` tokens were found in the touched Lua files. The large maintenance prelude contains 25 local-function declarations / 96 textual `local` tokens after the two added helpers, so static inspection does not indicate local-scope pressure, but this is not a compiler result.
- Canonical Lua 5.0.3 compiler check: **NOT RUN / unavailable in this executable environment**. The canonical VanillaTemplate checker exists and GCC is available, but the checker/vendor files are not mounted here and direct shell access to GitHub fails DNS. GitHub has no workflow/check run configured for the implementation commits. Do not record a compiler pass.
- Runtime state: **IN PROGRESS** on `0.9.18-dev` / implementation `ebf547e4a39af361a5f7b6a6519b1e0ee288be50`.
  - Test 1 **USER TESTED PASS**: fresh Zul'Gurub with no saved Raid ID, solo human, Loot Safe OFF -> Kick All preserved one Group-1 safety bot, preventing the player from being stranded.
  - Test 3 **USER TESTED PASS**: after obtaining a valid ZG saved Raid ID, solo human, Loot Safe ON, no targeted dead boss and no open loot window -> Kick All triggered Loot Safe and preserved one bot.
  - Test 4 on `0.9.18-dev` **USER TESTED FAIL**: with the same valid ZG saved Raid ID, Loot Safe ON, dead boss targeted and loot window open, Kick All still triggered the Loot Safe warning and preserved the final bot instead of allowing removal.
  - Test 4 retest on `0.9.19-dev` **USER TESTED PASS**: with Loot Safe ON, valid ZG ID, dead boss targeted and loot window open, Kick All removed every bot and the loot window remained open/usable.
  - Runtime diagnosis from the live target/loot probe: `class=worldboss dead=1 loot=nil level=-1`. The dead-boss predicate is therefore correct for High Priest Venoxis; the failing condition is loot-window detection because the global Blizzard `LootFrame` is nil under the user's pfUI setup. The user's pfUI fork creates its replacement loot window as global `pfLootFrame`, so the current `SCB_IsLootWindowOpen()` implementation is UI-frame-specific and not robust.
  - Test 6 **USER TESTED FAIL after partial topology recovery**: after the user manually left the retained final-bot group and looted Venoxis, Replace Missing started from a full teardown. Six bots joined, which proves the one-bot bootstrap, party->raid conversion, and continuation beyond party size occurred. Maintenance then stopped with `Bot maintenance stopped because a replacement could not be moved to its raid group.` Runtime confirmation established the player Revenra is configured in preset Group 2. Root cause: maintenance rebuilt the raid but did not run the normal `SCB_ArrangePresetHumanGroups()` step before continuing mixed replacement bursts, leaving Revenra temporarily in G1; G1 then had no free slot for all five intended G1 bots, so one replacement spilled to G2 and could not be moved back.
  - `0.9.20-dev` Test 6 retest **USER TESTED PARTIAL / overall FAIL**: the prior subgroup-move timeout is fixed and Replace Missing completed the roster, but runtime inspection showed 18 T3 preset bots plus 1 non-T3 preset Paladin. The first real missing preset assignment had been sent while still a party and was incorrectly used to create raid topology; SoloCraft applies T3 only when a real preset bot is summoned into an already-existing raid in a valid raid zone. Therefore completion alone was not a valid PASS.
- Required focused runtime matrix:
  1. **PASS** — In ZG before a saved ID exists, Loot Safe **OFF**, solo-human, Kick All preserved one Group-1 safety bot.
  2. After obtaining a valid ZG saved ID, keep Loot Safe **OFF**, press Kick All while solo-human, and confirm all bots are removed after the action-driven refresh.
  3. **PASS** — With Loot Safe enabled, solo-human and valid ZG ID, Kick All without both a targeted dead boss and open loot window triggered Loot Safe and preserved one bot.
  4. **PASS on `0.9.19-dev`** — With Loot Safe enabled + valid ZG ID, dead boss targeted and loot window open, Kick All removed every bot and the loot window remained open. (`0.9.18-dev` failed this because pfUI did not expose Blizzard `LootFrame`.)
  5. With Loot Safe enabled and 2+ real humans present, press Kick All and confirm all bots can be removed without requiring the boss-corpse/loot-window gate.
  6. **FAIL on `0.9.20-dev`; `0.9.21-dev` RETEST REQUIRED** — Full teardown Replace Missing completes without the old subgroup timeout, but `0.9.20-dev` produces 18 T3 preset bots + 1 non-T3 first preset bot because that real assignment is summoned before raid conversion. `0.9.21-dev` must prove a temporary bootstrap creates/parks the raid first, then all 19 real preset replacements are T3 and complete in intended groups.
- Visualiser remains deferred until this runtime matrix is accepted.
- `0.9.19-dev` correction is USER TESTED PASS: Loot Safe tracks native `LOOT_OPENED` / `LOOT_CLOSED` events instead of the Blizzard `LootFrame` global, and the option label is `Auto-Swap Presets by Location`.
- `0.9.20-dev` / `0485419d0e6fab4c88202704132319753208ffb6` correctly restored configured human subgroups after maintenance rebuilt raid topology, eliminating the earlier G1-capacity/subgroup timeout. Runtime then exposed a separate T3 correctness defect: it used the first real replacement as the bootstrap, so that bot was created pre-raid and remained non-T3. Treat `0.9.20-dev` Test 6 as partial only, not PASS.
- Why this escaped earlier runtime use: normal Replace Missing is usually exercised either while already in a raid (hole-patching) or while duo with Gaia, where an existing party can be converted before replacements. The newly exposed failure is specifically the full-maintenance-rebuild edge: valid T3 raid zone + tracked raid preset + non-raid + effectively solo + missing preset bots. In that state, real preset replacements must not start until temporary bootstrap -> raid conversion -> G8 parking -> human subgroup restoration has completed.
- `0.9.21-dev` / `c079bd500124cce5d84612059d337161b7b31909` implements that correction inside the existing maintenance coordinator only. Raid-topology need is now based on a tracked raid preset in a valid T3 raid zone before any real replacement is sent, not merely on whether a remaining assignment targets G2+. If an existing party member is present, maintenance converts that party first. If effectively solo, maintenance sends a dedicated temporary Warrior bootstrap through the shared `SCB_BeginAssumedSpawnBurst()` + `SCB_SendSpawnCommand()` path, converts to raid, parks the bootstrap in G8 through the established subgroup helper, restores configured human groups, and only then begins ordinary maintenance bursts. After the first real T3 replacement burst completes, the temporary bootstrap is removed through shared `SCB_KickBots()` and the existing removal-settle delay before later bursts continue, so it is gone well before a 20-player instance-cap boundary. No second scheduler, replacement owner, identity tracker, or direct PartyBot command path was added.
- Exact next runtime step: load `0.9.22-dev` and test the Kick Dead UI plus the pending ZG matrix in one runtime session. Confirm the new button appears between Replace Missing/Dead and Kick All and removes only dead bots through the established safety path. Then, because `/reload` clears maintenance history, Summon the same full raid preset before the solo full-teardown test and reproduce Kick All -> one Loot Safe survivor -> manual leave-group -> Replace Missing without another reload. Confirm temporary bootstrap -> raid conversion -> G8 parking -> Revenra G2 -> all real replacements T3 -> temporary bootstrap removed -> final intended roster with no subgroup/instance-full failure. Also complete saved-ID + Loot Safe OFF full Kick All and Loot Safe ON + 2 real humans full Kick All. Visualiser remains deferred.
- Static scope review for `0.9.21-dev`: compared with handoff `17363bc352fdcc81f6728baad993aec64e3ac251`, product changes are limited to `Spawn.lua` plus the required TOC bump. Canonical Lua 5.0.3 compiler check is **not run** in the current execution environment; do not claim a compiler pass.
- `0.9.22-dev` Kick Dead UI is IMPLEMENTED / runtime untested. Commit `68f641ca519e4b46c762f5810cbf3354638298b9` adds only the main-window button/layout: Replace remains 96px wide, Kick Dead and Kick All are 70px, centred on the existing 256px frame. The new button calls the pre-existing `SCB_KickDeadOnClick()` -> `SCB_KickBots("dead")` owner and reuses existing `KICK_DEAD` / `TIP_KICK_DEAD` locale strings; no kick/safety logic changed. Commit `d886fa150358f7ce2c6d1370639abf79a1b6a3ab` bumps the TOC to `0.9.22-dev`. Static diff from handoff `7077632decf1cd5e1d4c01c4c64753e8a74ce82d` is limited to `SoloCraftBots.lua` and `SoloCraftBots.toc`. Canonical Lua 5.0.3 compiler check remains NOT RUN / unavailable.

## 0.9.16-dev SoloCraft Wisdom capability correction
- User runtime evidence indicates PartyBot Paladins do not actually cast Blessing of Wisdom below level 30, despite normal Vanilla spell availability being lower.
- Narrow correction at implementation head `1183385fcdc17b2a2156f36849c8399e13054790`: `SCB.PALADIN_BLESSING_MIN_LEVEL.BoW` changed from 14 to 30. No other blessing threshold changed.
- This intentionally models observed SoloCraft PartyBot capability rather than generic Vanilla spell-learning level.
- Expected effect: Auto Blessing allocation, manual preset blessing availability, main Paladin blessing selection, Request capability validation and execution all inherit the corrected level-30 gate through the existing shared availability functions.
- Runtime state: **USER ACCEPTED without direct sub-30 addon retest**. The server behavior motivating the change was observed by the user, and the implementation delta is only `BoW = 14` -> `BoW = 30`. A sub-30 character is not currently available, so this must not be recorded as USER TESTED PASS.

## 0.9.15-dev Preset Manager Appearance
- Scope explicitly switched by the user after the `0.9.11-dev` activity/status surface was runtime-accepted. Appearance is implemented; the visualiser has not started.
- Implementation sequence: `d095622de6930ec8e391460e75af34244ae45650` introduced Appearance; `22d2162af6e5fe4fbcfbdd0b92ce2b6eed1cbb27` corrected right-click selector input and sex previews; `f32e643630db0520ee8ba0114c4b48ea13390757` preserved Preset Manager title alignment while expanded; `6223992ca83f06a351ea308c4271d073263adc2a` scoped common-class rules and race choices by faction.
- Account-wide `SoloCraftBotsDB.appearanceRules` stores optional Race/Sex preferences per **faction + class + broad role**. Preset slots and communication payloads are unchanged. Alliance/Horde preferences therefore coexist without a Warrior/Rogue/etc. rule crossing factions.
- Preset Manager now has a top-left Appearance button. Opening it expands the drawer left by one compact column while existing preset selectors, group boxes and the Preset Manager title retain their established screen position. Rows are `[Class Icon] [Role Icon] [Race] [Sex]`.
- Visible rows follow the current faction's available classes. Duplicate broad-role specs collapse to one rule (for example Mage Fire/Frost share `mage:rangedps`), matching the agreed class+role model rather than per-spec or per-slot configuration.
- Race and Sex each default to `?`, meaning omitted/random server default. Left/right click cycles forward/back. Race choices are restricted to Vanilla-valid races for that class and current faction. Sex is `?`, Male or Female.
- Race visuals use Blizzard's character-create race atlas; Sex previews use the selected race, or the first legal class/faction race while Race itself remains random.
- `SCB_BuildSpawnCommand()` remains the construction front door. Existing class/role/extra handling runs first, then configured race and/or sex tokens are appended. This applies consistently to preset summons, rebuild/refill paths, manual Add and bootstrap calls that already use the builder.
- Spawn validation now removes recognised appearance tokens before sending the remaining payload through the established class/role/extra validator. This preserves Mage Fire, Paladin blessing and Shaman four-totem validation while accepting race/sex in the generated command.
- Server syntax assumption is based on SoloCraft's documented optional tokens: `human/dwarf/nightelf/gnome/orc/undead/tauren/troll` plus `male/female`; either dimension may be omitted and remains random.
- Static/diff review **PASS**: `fd9b974983a5d6d073330d28ddef31a688211af4` -> `6223992ca83f06a351ea308c4271d073263adc2a` changes only `Locale/enGB.lua`, `Presets.lua`, `SoloCraftBots.lua`, `SoloCraftBots.toc`, and `Spawn.lua`; no protocol file or visualiser work changed. TOC is `0.9.15-dev`; stable `main` remains `0.9.9`.
- Static compatibility inspection found no introduced `#` length syntax or `goto`. The canonical Lua 5.0.3 compiler check is **NOT RUN / unavailable in the current executable environment**; do not treat static inspection as a compiler pass.
- Runtime state: **USER TESTED PASS on `0.9.15-dev` appearance implementation `6223992ca83f06a351ea308c4271d073263adc2a`**. The user confirmed the Appearance feature works in game, including applying configured race/sex to spawned bots. The later `0.9.16-dev` product delta changes only the Blessing of Wisdom minimum-level value plus TOC metadata; Appearance behavior itself is unchanged and accepted.

## 0.9.11-dev neutral activity/status surface
- Implementation commits: `cb10d9dd71a826c393d0414d2d4d86a61360d7e9` introduced the surface and four domain publishers; `c18c8384023c6db12d8cfd2b25be4429da06d87e` completed progress publication and static-review corrections.
- New `Activity.lua` owns a session-only neutral status store. It exposes `SCB_GetActivityStatus([channel])` and `SCB_GetActivityStatusRevision()`; getters return defensive deep copies so presentation consumers cannot mutate the backing state.
- Canonical channels are independent rather than mutually exclusive: `command`, `botOperation`, `communication`, and `rosterLayout`.
- **Command:** Group and Pause Healers sequencers publish action/scope/phase/current recipient/progress while retaining their existing owners and timing. Direct one-shot commands publish only a completed latest status and do not displace an active sequencer.
- **Bot Operation:** the existing `SCB.botOperation` coordinator remains authoritative. The surface derives operation kind/action/phase/wait reason/progress; roster events refresh preset progress without adding another scheduler.
- **Communication:** the existing protocol-8 state remains authoritative. One channel carries an `activities` array so concurrent Send, Request and incoming transfer activity can coexist; chunk progress and completion/timeout state are observational only.
- **Roster/Layout:** live roster counts/revision and tracked raid-layout mismatch counts are published from existing roster/layout observation. Layout status is marked `suppressed` while a bot operation intentionally suppresses mismatch presentation.
- `Activity.lua` contains no frames, command sending, spawn/maintenance logic, communications transport or roster decisions. No visualiser/presentation was added.
- Compatibility scope is unchanged: no SavedVariable schema change, no protocol bump, and no command/spawn ownership change. `Presets.lua` and the planned Appearance feature were untouched.
- Source/diff audit PASS: handoff `fb0a9e9414393cf9f387477112b869e615a92d6b` -> implementation head changes only `Activity.lua`, `Communication.lua`, `Roster.lua`, `Spawn.lua`, and `SoloCraftBots.toc`; TOC is `0.9.11-dev` and loads `Activity.lua` before runtime owners. Stable `main` remains `0.9.9`.
- Canonical Lua 5.0.3 compiler check: **NOT RUN / unavailable in this execution environment**. Direct container network access also cannot fetch the repository; do not treat source review as a compiler pass.
- Runtime state: **USER TESTED PASS on `0.9.11-dev` / handoff `764cc99ed4024e75e970be414b02c3c798a97e2c`**. Clean `/reload` passed with no addon load error. Command surface passed with direct `Stay -> All` reporting `stay | all | sent | false`, and an ordinary Group command completed normally with Group state visible. Bot Operation passed during a preset summon with `true | preset | summon` and passed the final inactive-state check after completion. Roster/Layout counts/state worked normally. Communication Send/Request activity worked normally. An earlier long diagnostic `/script` for Bot Operation produced a Lua error, but the simplified getter inspection did not reproduce it and the summon itself completed normally; no addon defect was established from that diagnostic command.
- The surface is runtime-accepted. The visualiser may now be built as a presentation-only consumer of these getters.

## BWL 0.9.1-dev batch / 0.9.4 release state
Original BWL implementation head: `37097afe63259169ad0ece774cace26b27821ed7`. BWL-era implementation head: `626b28c13baf013e834b383a9aecf4cda17786b3`. The established reverse-send/LIFO/full-rebuild ordinal finalizer remains the normal authoritative path. The activity/status surface was not part of that BWL batch and is now implemented separately as documented above; visualiser work has still not started.

### Pause Healers
- `0.9.1-dev` runtime result for the original Group-targeted implementation: **functional behavior PASS, UX rejected**. The command worked, but requiring a Group target and placing it in the Group row were rejected.
- `0.9.2-dev` moved the button to the **Healers** role row and removed the Group-target precondition, but its first separate role sequencer restored the player's target between healer sends. That interaction was rejected before runtime testing.
- `0.9.3-dev` introduced a fully separate Pause Healers sequencer and correctly preserved the tested Group sequencer. Runtime then exposed a remaining first-recipient edge case: when the player started with **self targeted**, the first bare `pause` could reach the server while self was still the authoritative selection and the server returned **"All party bots paused for 30 seconds."**. Other tested starting-target states worked.
- Correction to the earlier design description: Group sequencing was not a complete drop-in model for the first Pause Healers transition. Group starts from an already-selected bot; Pause Healers can start from an arbitrary target. The healer-to-healer sequencing is copied from Group, but the arbitrary-target -> first-healer bootstrap is a separate requirement.
- `0.9.4-dev` adds a self-target-only bootstrap settle before the first healer command. It uses at least 0.25 seconds and, when `GetNetStats()` reports higher latency, waits one reported round trip plus 0.10 seconds. This delay applies only until the first targeted `pause` is sent; subsequent healer-to-healer transitions remain the tested 0.10 seconds. **Runtime PASS:** user confirmed Pause Healers works after this fix.
- The dedicated sequencer also treats **"All party bots paused for ..."** as an immediate failure condition and aborts/restores the original target instead of silently continuing the healer sequence. This is a safety fallback, not the primary fix.
- Pause Healers still builds recipients from all currently resolved healer bots in the live roster, excludes focused identity-recovery candidates, sends ordinary targeted `pause`, waits for the bot-specific pause acknowledgement, retries immediately on a recognised wrong-actor acknowledgement, and hard-aborts after 1.0 second with no timeout retry.
- Original target restoration still happens only after the whole sequence completes or aborts. If the sequence began with no target, completion/abort clears the temporary healer target.
- Group/Target commands remain blocked while Pause Healers owns the target; Pause Healers still refuses to start while the Group targeted sequencer is active.
- At the `0.9.4` BWL validation point, the proven Group recipient-selection, advancement, send, ACK-resolution, chat-handler and timeout-frame functions were byte-identical to the `0.9.1-dev` implementation. Current `0.9.11-dev` adds read-only activity publication/metadata around that sequencer, so the byte-identical statement no longer applies to the current tree; routing, target-settle timing, ACK decisions, retry policy and timeout behavior were not intentionally changed.

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
- **Pause Healers:** runtime **PASS**, including the self-target bootstrap fix.
- **Ordinary Group sequencing:** runtime **PASS**. User confirmed normal Group commands sequence correctly.
- **Group timeout:** implementation/static review PASS; runtime remains **opportunistic**. The user cannot safely manufacture a missing acknowledgement, so if a naturally non-responsive Group command occurs they will watch for the ~1.0-second failure message and verify a new Group command works immediately afterward.
- **Wrong-actor Group acknowledgement correction:** static review PASS; runtime **not deliberately reproducible**. The path is designed to self-correct by resending to the intended bot, and the user has not observed a clear failure case.
- **Full-rebuild identity baseline:** the established reverse-send/LIFO/bot-only ordinal finalizer was **not changed** by this batch. The only identity addition is a narrow post-finalization class sanity/recovery layer that runs after the proven finalizer. Do not treat routine ordinal rebuild behavior as a newly introduced mechanism requiring artificial fault injection.
- **Mismatch visibility:** a confirmed role mismatch is intentionally obvious: persistent red X, chat warning, and a real `StaticPopup` unless SCB screen warnings are explicitly hidden.
- **Rare identity-recovery and subgroup-local warning wording:** keep as **opportunistic runtime validation** if a genuine mismatch occurs. Do not manufacture these states merely to satisfy the checklist.
- **Group pipeline preservation:** the `0.9.4` runtime behavior remains the baseline. `0.9.11-dev` now inserts observational status-publisher calls/metadata into the proven Group sequencer, so current source is no longer byte-identical to `0.9.1-dev`; no command routing, target-settle timing, ACK/retry or timeout decisions were intentionally changed. Include an ordinary Group-command smoke in the activity-surface runtime validation.
- **Canonical Lua 5.0.3 compiler check:** **NOT RUN / unavailable in this execution environment**. Do not treat static review as a compiler pass.

### Opportunistic checks while playing
1. If a Group command ever stalls naturally, verify SCB reports failure at about 1.0 second, restores the original target, releases the pipeline and performs no timeout retry.
2. If a wrong-actor acknowledgement is ever visible, verify SCB resends to the intended bot and then continues normally.
3. If a genuine class/role identity mismatch occurs, verify the popup/chat/red-X warning is clear and that any repair stays scoped to the implicated group/candidates without changing preset intent.
4. If a mismatch warning occurs in a later subgroup, verify its displayed slot is subgroup-local 1–5 rather than the global raid slot.





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


## Paladin Auto Blessing — `0.9.9-dev` role-indicator retest
- Implementation head: `80464531d7065762d78c7b474f3ab1942297503b`.
- Stored preset intent and effective blessing are separate. New Paladin assignments store `Auto`; existing explicit assignments remain explicit and are never silently migrated.
- Capability policy is centralized: `BoM` level 4+, `BoW` 14+, `BoS` 26+, `BoL` 40+, `BoK` 60+ only. No additional role-specific exclusions are currently proven.
- New exact-server runtime evidence supports the `BoK` 60+ gate: at player level 59, manual `.pa add paladin healer bok` was accepted syntactically but the summoned Paladin cast Blessing of Might rather than Kings. Treat successful command acceptance as insufficient evidence of blessing availability; the observed applied blessing is authoritative for this capability check.
- Auto allocates after explicit/manual assignments, filters by current summoner level, avoids duplicates while unused blessings remain, then duplicates only when necessary. The existing blessing list order is the current priority/tie-break order: `BoK -> BoM -> BoS -> BoW -> BoL`; level filtering removes unavailable entries.
- Manual blessing cycling is `Auto` plus only currently available explicit blessings. A saved explicit blessing that is unavailable on this character stays explicit, is shown unavailable, and cannot execute until changed to Auto/an available blessing.
- Execution snapshots preserve stored intent. Protocol 8 still serializes the existing `class/role/extra` fields; `extra=Auto` survives local rebuild, Send, save-received-preset and Request. The client that actually starts the PartyBot summon resolves a copied slot set against its own level, so the saved/sent snapshot is not mutated.
- Request acceptance checks local blessing capability before leader conversion. The execution boundary resolves again immediately before tracker/command creation.
- Auto buttons display the resolved blessing icon with the actual Vanilla 1.12 pet-autocast enabled model `Interface\\Buttons\\UI-AutoCastButton.mdx`; manual selection hides it. The Auto tooltip states the current resolved blessing.
- Preset Manager now includes an **Active Blessings** row containing the unique currently effective bot blessings.
- `0.9.7-dev` runtime result: the user reports the interface and Auto-resolution logic working correctly; on a level-33 Warrior, the active Auto Paladin resolved to `BoM`. Summon execution then failed before spawning with `A Paladin has a manual blessing unavailable at your current level...` even though the active Paladin was Auto.
- Root cause confirmed by source audit: manual blessing capability validation ran for every stored Paladin slot, including bot slots hidden/inactive because a human occupied them. A human-covered legacy/manual `BoK`/`BoL` slot could therefore veto the whole summon even though that bot would not execute.
- `0.9.8-dev` fix: a human-covered Paladin slot preserves its explicit blessing intent in the copied execution snapshot but no longer contributes an unavailable-capability error. Active manual Paladin slots remain capability-gated exactly as before. **Runtime PASS confirmed** on the original level-33 Warrior failure case.
- New runtime regression found immediately after that PASS: the summoned Auto Paladin no longer showed the preset role-confirmation ticks. Root cause: tracker assignments store the concrete executed blessing (`BoM`) while the preset row stores portable intent (`Auto`); the role-indicator row matcher compared `extra` values directly and rejected `Auto ~= BoM`, suppressing both assumed and confirmed ticks even though role detection itself remained intact.
- `0.9.9-dev` fix: tracker assignments now persist `intentExtra` alongside the concrete execution `extra`; role-indicator matching compares the current preset against stored intent while summon/refill execution continues using the concrete blessing. A narrow compatibility path lets pre-`0.9.9` Auto-Paladin trackers with concrete blessing extras continue to match after reload.
- The `0.9.9` Auto Blessing source audit PASS remains valid: blanket level-60 gate removed; Auto is structurally valid but never sent to PartyBot; snapshot construction preserves Auto; execution resolves Auto; Send copies preserved intent; Request validates receiver-local capability; inactive human-covered manual Paladin slots no longer veto execution. The activity/status surface was not part of that Auto Blessing change and was added later in `0.9.10-dev` / `0.9.11-dev`.
- Canonical Lua 5.0.3 compiler check remains **not run/unavailable** in this execution environment. No GitHub Actions workflow runs are configured for the implementation head.
- **`0.9.8-dev` occupied-slot retest: USER TESTED PASS.** On the same level-33 Warrior/preset that failed on `0.9.7-dev`, the visible Paladin remained Auto resolved to `BoM`; Summon proceeded without the manual-blessing-unavailable error and the Paladin applied `BoM` in game.
- **`0.9.9-dev` role-indicator retest: USER TESTED PASS.** Auto Paladins show both the assignment/assumed-role tick and the combat-role confirmation tick correctly.
- **Runtime validation summary**:
  1. Multiple active Auto Paladins allocate the available blessings without premature duplication: **USER TESTED PASS**.
  2. Normal preset-save persistence of stored `Auto`: **USER TESTED PASS**. Stable `0.9.9` Send/receive also preserves Auto Blessing intent: **USER TESTED PASS**.
  3. **Active Blessings** display behavior: **USER TESTED PASS**.
  4. Auto/manual blessing presentation and resolved blessing display: **USER ACCEPTED / PASS**.
  5. Level-boundary behavior: no further artificial runtime test required by the user. Capability checks are flat numeric gates (`BoM` 4, `BoW` 14, `BoS` 26, `BoL` 40, `BoK` 60); exact-server level-59 `bok` evidence confirms Kings is unavailable below 60 and the server falls back to Might.
- The earlier level-33 runtime evidence also confirms `BoM`, `BoW`, and `BoS` work while `BoK` and `BoL` do not at that level.
- Runtime evidence motivating the policy remains the level-33 test where manual PartyBot Paladin healer summons accepted `BoM`, `BoW`, and `BoS`, while `BoK` and `BoL` did not work.

## Planned / later
- Main-window 30-second role countdown indicators (deferred; do not mix into the current ZG/bootstrap runtime slice):
  - **Tank Pull / DPS:** when the server chat reports the Tank Pull DPS-delay message (user-observed wording: `Tanks are not pulling *mobname*, DPS will join in 30 seconds!`), show one shared 30-second countdown adjacent to the main-window Melee DPS and Ranged DPS controls, preferably immediately to their left. The server message should be the timing authority rather than button-click time.
  - **Pause Healers:** show the equivalent 30-second countdown adjacent to the Healer control. The existing targeted pause pipeline already confirms each healer with `<name> paused for 30 seconds.`; start the displayed countdown from the **first successfully confirmed healer pause**, not the final healer, because that first healer is the earliest one that can resume.
  - These counters are presentation/status consumers of existing command/server-message events only. Do not create a parallel command scheduler or gameplay-timing owner.

- Neutral read-only activity/status surface: **IMPLEMENTED and USER TESTED PASS on `dev` at `0.9.11-dev`; accepted before visualiser work.**
- Preset Manager Appearance: **USER TESTED PASS / accepted**. Implementation was tested at `0.9.15-dev` / `6223992ca83f06a351ea308c4271d073263adc2a`; the `0.9.16-dev` delta does not alter Appearance behavior.
- Visualiser may now proceed as the next slice and must remain a presentation-only consumer of the accepted activity/status surface.
- Remove only proven-dead legacy refill/compatibility code after runtime proof.
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

## 0.9.4 release
- User approved the current BWL command state for promotion to `main`.
- User-tested runtime source: `0.9.4-dev` implementation `2cdf74df1988f1b7fb3c3ddee292924ce961dfe6`; Pause Healers and ordinary Group sequencing are runtime PASS.
- Rare Group timeout, wrong-actor ACK, and mismatch-warning paths remain documented as opportunistic validation because they are not safely reproducible on demand.
- Stable promotion commit: `a03b060dada7f03d860ef124bc54fa48fab745d4`; stable TOC is `SoloCraft Bots` / `0.9.4`.
- Promotion used the established snapshot method with prior stable `main` as parent; branch histories were not merged.
- Post-promotion tree audit PASS at release time: compared with the dev release state, only `SoloCraftBots.toc`, `DEV_PROGRESS.md`, and `dev_rulebook.md` differed. Current dev has since advanced with Auto Blessing runtime changes.
- Exact stable metadata/tree was not separately runtime-tested; runtime behavior inherits the tested `0.9.4-dev` product tree.
- Canonical Lua 5.0.3 compiler check remains **not run/unavailable** in the current executable environment.
- Current addon work has since advanced to `0.9.15-dev` on `dev` for Preset Manager Appearance; stable `0.9.9` remains released on `main`. Auto Blessing Send/receive persistence and Request execution are USER TESTED PASS; Auto Blessing validation is closed.

## 0.9.16 release
- User explicitly authorized promotion of the current accepted dev state to stable using the established release rules.
- Release source product: `0.9.16-dev` implementation `1183385fcdc17b2a2156f36849c8399e13054790`; later dev commits through `2dde4a7759e5b6b7d4076cfc449fcaea2995d5ff` are documentation/status only.
- Preset Manager Appearance is USER TESTED PASS / accepted. The SoloCraft Blessing of Wisdom minimum-level correction (`BoW = 30`) is USER ACCEPTED based on observed server behavior but was not directly re-tested on a sub-30 character before release.
- Stable promotion commit: `03ea60a90b79a29d726c627f7b833ec673251cb6`; stable TOC is `SoloCraft Bots` / `0.9.16`.
- Promotion used the established snapshot method with prior stable `main` `b374655e145bc0626e5fe112ec9098b96cae0617` as parent; diverged branch histories were not merged.
- Stable tree audit PASS: compared with current dev, the only root differences are stable `SoloCraftBots.toc` metadata plus omission of `DEV_PROGRESS.md` and `dev_rulebook.md`. All product Lua, locale, artwork and supporting files match the dev snapshot.
- `Activity.lua` is included in stable and loaded before the runtime owners exactly as on dev.
- Exact stable metadata/tree was not separately runtime-tested after promotion; runtime behavior inherits the accepted dev source. The documented Wisdom sub-30 validation debt remains unchanged.
- Canonical Lua 5.0.3 compiler check remains not run/unavailable for this slice; do not infer a compiler pass from the release audit.

## 0.9.9 release
- User explicitly accepted the current Auto Blessing state as stable and authorized promotion so Send/receive can be tested on stable clients.
- Tested/accepted runtime implementation: `0.9.9-dev` at `80464531d7065762d78c7b474f3ab1942297503b`. Later dev commits through `48b604ad808fed523fe7d07da3ebbdb45b8e5e1b` changed only `DEV_PROGRESS.md`.
- Stable promotion commit: `b374655e145bc0626e5fe112ec9098b96cae0617`; stable TOC is `SoloCraft Bots` / `0.9.9`.
- Promotion used the established snapshot method with prior stable `main` `a03b060dada7f03d860ef124bc54fa48fab745d4` as parent; diverged branch histories were not merged.
- Post-promotion tree audit PASS at the time of the `0.9.9` release: stable then differed from the accepted dev release state only by `SoloCraftBots.toc`, omission of `DEV_PROGRESS.md`, and omission of `dev_rulebook.md`. Current `dev` has since advanced with the neutral activity/status surface.
- Post-release validation: Auto Blessing persistence through protocol **Send/receive is USER TESTED PASS** on stable `0.9.9`. Normal preset-save persistence is also USER TESTED PASS. A preset **Request** containing Auto Blessing was sent and executed successfully: **USER TESTED PASS**. Auto Blessing protocol validation is closed.
- Exact stable metadata/tree was not separately runtime-tested; runtime behavior inherits the accepted `0.9.9-dev` product code.
- Canonical Lua 5.0.3 compiler check remains **not run/unavailable** in the current executable environment; no GitHub Actions workflow is configured for this release.

## Release note
`0.9.16` is the current stable release on `main` at `03ea60a90b79a29d726c627f7b833ec673251cb6`. The neutral read-only activity/status surface and Preset Manager Appearance are USER TESTED PASS / accepted. The SoloCraft Wisdom minimum-level correction is released as USER ACCEPTED without a sub-30 addon retest. `dev` remains `0.9.16-dev`; the visualiser has not started and is the next available slice.
