# SoloCraft Bots

A bot control panel for **SoloCraft**. It is designed as a full replacement for PCP and FRB, with a different design philosophy.

## Addon Focus

- Intuitive, graphical control of bot summoning, commands and assignments.
- A powerful, visual preset manager for building parties and raids.
- Configure presets with specific group compositions, including other human players.

## Features

- **Summon bots:** choose faction-appropriate classes and roles/specs, paladin blessings and shaman totems, with near/far spawning.
- **Party and raid presets:** save 5, 10, 15, 20 or 40-player setups with role totals and room for human players. Drag players between raid groups, adjust whole groups with Shift-click, and organise, rename or reorder presets.
- **Location-based selection:** organise presets by dungeon, raid or custom group, with optional automatic Preset Group switching when you change location.
- **Share with friends:** send presets to other SoloCraft Bots users or ask them to summon a setup, with their confirmation.
- **Maintain your group:** replace dead or missing bots from the tracked active roster, preserving known class, role and group assignments. Kick Dead and Kick All include a safety survivor when needed to avoid instance removal.
- **Command bots:** control all bots, a target or role groups. Manage movement, attacking, pausing, tank pulls, spreading, AoE and object interaction.
- **Focus and crowd control:** assign bots to raid markers for focus targets or CC.
- **Optional automation:** set the loot method and auto-promote other human players to raid assistant when you're raid leader.
- **Make it comfortable:** movable, collapsible panels, adjustable spacing and preset sizing, bot chat filters, tutorial hints and saved settings.
- **Addon support:** apply tracked tank roles to pfUI and provide FillRaidBots compatibility. Neither addon is required.

## Getting started

1. Place the `SoloCraftBots` folder in `Interface/AddOns/` so it contains `SoloCraftBots.toc`.
2. Open with `/scb` or `/solocraftbots`, or assign a key in WoW's Key Bindings menu.
3. Summon individual bots, or open **Presets** to build and save a group.

Hover over controls for their shortcuts. **Ctrl-click Come** also releases Stay; **Ctrl-click Summon** cancels an active summon operation and retries. Options include automatic promotion and location switching, both off by default.

Requires SoloCraft's `.partybot` commands; no DLLs or other addons are required. Available group sizes and bot commands depend on the server and location.

**Branches:** `main` is the stable build; `dev` contains ongoing development. This README describes the features on its branch.
