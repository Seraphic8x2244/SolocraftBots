# SoloCraftBots 0.7.14 Behaviour Baseline

Purpose: preserve known-good behaviour while 0.8.x consolidates architecture.

This is not a complete user manual. It is a regression baseline for systems most likely to be affected by consolidation.

## Presets

- Supported preset sizes: 5 / 10 / 15 / 20 / 40.
- Presets store bot class/role/extra intent and human raid-group assignments.
- Save button shows Saved when editor intent matches stored preset; meaningful edits show Unsaved Changes.
- Human raid subgroup is semantic preset intent.
- Blizzard moving a human to a different row within the same subgroup is presentation-only and must not dirty the preset.
- When same-group live row differs from preset row, the live character slot is shown in Blizzard's position with a pulsing green background and tooltip: `Not in preset location due to Blizzard raid handling`.
- Moving a human to a different raid subgroup is a meaningful preset change and may make the preset Unsaved.
- Reselecting/reloading a preset restores saved preset intent.

## Preset group/location rules

- World: 5-man.
- Dungeons may be run as 10-man raids after entering an instance.
- Blackrock Spire supports 15.
- ZG / AQ20: 20.
- MC / Onyxia / BWL / AQ40 / Naxx: 40.
- AQ40 client zone string is `Ahn'Qiraj` even though the user-facing preset group label remains Temple of Ahn'Qiraj.
- Automatic location-based preset-group switching must not overwrite a dirty preset silently.

## Summoning

- Summoning uses `/say` commands.
- SoloCraft same-burst command processing is reverse/LIFO; the addon sends a logical burst in reverse command order so join order matches desired logical order.
- Normal preset burst is one logical subgroup, maximum 5 bot summons.
- There is an exact 1.0 second boundary between logical five-slot groups in the current scheduler.
- Server combat can delay/retry spawning according to the existing retry ladder.
- Exact SoloCraft error `Cannot add bots right now.` hard-aborts the active spawn operation.

## Party-to-raid conversion

- For presets larger than 5 inside supported instance contexts, conversion to raid occurs safely before later raid groups are filled.
- Ordinary solo >5 flow can summon the first real G1 bot to establish a party, convert to raid, arrange humans, then continue remaining bursts.
- T3 raid-zone solo starts may use a temporary bootstrap/safety bot because a party must exist before `ConvertToRaid()`.
- Bootstrap/survivor handling converges on the same practical goal: keep a temporary safe member while raid conversion/group arrangement occurs, then remove it after real G1 is established.

## Rebuild over an existing summon

- Existing unwanted bots are removed before the replacement preset proceeds.
- If a survivor is retained to preserve group/raid state, conversion/progression waits until the unwanted bots are actually gone and the survivor state is valid.
- 0.7.14 still contains different settle timing between Replace Dead and preset-over-preset rebuild; this is a known consolidation target, not baseline behavior to accidentally reinterpret.

## Replace Dead / Missing

- Maintenance is based on the active tracked logical slot, not an arbitrary current visual row.
- Replacement should preserve the intended class/role/extra for that slot.
- Replace Dead currently waits for the removed bot name to disappear, then uses a 3-second server removal settle before summoning its replacement.
- Combat remains a hard gate where the existing maintenance flow requires it.

## Bot identity

- Name-bound identity is authoritative after binding.
- Same-burst identity order is based on explicit burst plans, not timestamp equality.
- Timestamps are diagnostics/timeouts only, not the source of ordering truth.
- Exact `slotIndex` is preferred when reconciling assumptions to tracker slots; command/group matching is legacy fallback behaviour.
- Known 0.7.14 architectural risk: the pending assumed-spawn queue is global and can theoretically leak stale intents into later bursts. This is a known defect candidate, not desired behavior.
- Known 0.7.14 architectural risk: roster-delta fallback may overlap with membership-message binding. Audit before changing it.

## Roles

- `assumedRole` represents requested/intended role.
- `confirmedRole` is optional combat-derived validation.
- Resolved live role currently prefers `confirmedRole` over `assumedRole`.
- Combat confirmation is OFF by default in 0.7.14.
- When confirmation is OFF, high-volume combat-text listeners should not remain registered during normal gameplay.
- When confirmation is ON, already-confirmed bots should stop being scanned.
- When every relevant live bot is confirmed, combat scanning should unregister/go dormant.
- New/replacement/unconfirmed bots should wake the scanner when confirmation is enabled.

## Combat evidence

- Confirmation threshold is currently 2 recognized observations.
- Duplicate same-name/same-spell evidence within the short suppression window is ignored; repeated later observations may count.
- Strongest role score wins; assumed role acts as a tie-break where applicable.
- Paladin tank evidence in the current baseline is deliberately restricted to strong indicators such as Righteous Fury and Holy Shield; weak/shared spells such as Consecration, Seal of Righteousness and Blessing of Sanctuary must not be reintroduced casually.

## pfUI tank roles

- SCB resolves a bot's live role as confirmed role first, otherwise assumed role.
- SCB writes tank names to pfUI's raid tank-role map only for SCB-managed names.
- Manual pfUI tank assignments not written by SCB should be left untouched.
- Bootstrap/safety bots should not be treated as genuine tracked tank assignments.

## Human player editor behaviour

- 5-man placement follows actual party layout.
- Raid presets assign human players to raid groups.
- Dragging a player between groups is an explicit preset edit.
- Player role/spec controls are class-aware and separate from the bot assignment underneath a human-covered slot.
- A live human covering a row makes the underlying bot assignment inactive for automatic extras such as blessing allocation, but does not delete that stored bot assignment.

## UX / safety principles

- Preserve player agency.
- Block impossible/unsupported actions, not merely unusual choices.
- Do not silently correct user data.
- Visual warnings are acceptable.
- Do not use hidden TargetByName probing for maintenance.
- Manual command controls may use party chat while dead; summoning remains `/say`.

## Regression scenarios for 0.8 consolidation

At minimum retest these after each relevant consolidation phase:

1. 5-man preset from solo.
2. 10-man dungeon preset from solo.
3. 10-man preset over an existing 5-man summon with one survivor retained.
4. 20/40-man raid-zone start from solo requiring bootstrap/conversion.
5. Consecutive raid-group bursts preserve intended name/slot/role mapping.
6. Replace Dead preserves intended slot role and waits for server removal settle.
7. Combat confirmation OFF produces no persistent combat scanner load.
8. Combat confirmation ON sleeps once all bots are confirmed.
9. pfUI tank icons match intended/confirmed tank roles immediately after spawn.
10. Blizzard within-group human row reorder changes display only, leaves preset Saved, shows green live-location pulse.
11. Human subgroup change is treated as a real preset difference.
12. Location auto-swap does not silently discard dirty preset edits.

Any intentional change to these behaviours during 0.8.x must be recorded in `DECISIONS.md`.
