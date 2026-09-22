# Icon Artwork / Image Generation Guide

This document records the current SoloCraftBots icon-art direction so future image-generation work can resume without reconstructing the brief from chat history.

## Goal

Preserve the existing SoloCraftBots icon style. Do not redesign the whole set.

The existing icon sheet is the primary visual reference for:
- embossed relief style;
- lighting and material treatment;
- background colour language;
- symbol scale and visual weight;
- overall Warcraft-compatible UI feel.

New work should only revise or add the specific icons listed below.

## Asset Format

Target addon assets:
- square icons;
- nominal design size: 64x64;
- final WoW 1.12.1 texture files may use power-of-two source dimensions as needed;
- no custom outer button border baked into the artwork;
- no metallic frame/chrome around the tile;
- no text or labels inside the icon;
- artwork should be suitable for use underneath Blizzard-style button border art.

The icon itself may retain the same subtle textured square background used by the existing set. "No border" means no additional decorative frame around that square.

## Style Rules

Use the existing SoloCraftBots icons as the style reference, not as a prompt to redesign them.

Keep:
- simple, readable relief symbols;
- pale ivory/metal relief treatment;
- restrained surface wear/texture;
- strong silhouette at small sizes;
- existing category/background colours;
- similar lighting direction and relief depth.

Avoid:
- modern sci-fi UI styling;
- glossy app-icon framing;
- new gold/silver rims;
- thin sketch-like line art;
- over-detailed character illustration;
- changing unrelated colours or symbols;
- adding decorative elements just to fill space.

When using image generation, prompts should say explicitly that the job is to create *new/revised symbols in the established style*, not to create a new icon family.

## Revised / New Icon Set

### Scope icons

The old human-silhouette scope icons are being replaced with a simple gnomish robot-head relief.

Robot design:
- head only;
- simplified mechanical/gnomish face;
- rounded head/helmet;
- circular lens-like eyes;
- small side caps/ear-bolts;
- simple central face/nose plate;
- readable as a relief emblem at small size;
- not a full robot character;
- not a direct copy of any supplied robot reference.

Icons:
- **Single / One** — one large robot head.
- **Group** — exactly five robot heads. They should read as a group of five, not a leader plus four followers; keep head sizes reasonably uniform.
- **All** — many robot heads in a dense formation. It must look unmistakably larger in scope than Group. Prefer several staggered rows / a compact crowd rather than merely six or seven heads.

### Lock / Unlock

Revise both together as a matched pair.

Requirements:
- identical lock body;
- identical proportions;
- identical keyhole;
- identical relief depth and visual weight;
- only the shackle state changes.

**Lock**
- closed shackle.

**Unlock**
- same lock;
- shackle opens sideways / reversed;
- do not make the shackle simply pop upward.

These are intended to look like two states of one asset, not two independently designed padlocks.

### Tank Pull

Replace the current shield + bow/arrow concept.

New symbol:
- tank shield as the primary shape;
- a **real arrow** with shaft and arrowhead;
- arrow should communicate pull/engage direction;
- do not use a mouse-pointer/chevron style arrow;
- do not use a bow;
- keep the shield visually dominant.

### Maintenance icons

These depend on the robot-head language being approved first.

**Replace Dead**
- dead/inactive version of the approved robot head;
- likely X/dead eyes or another simple, immediately readable dead-state treatment.

**Replace Missing**
- question mark;
- keep it simple and consistent with the relief family.

**Kick Bot / Kick All**
- boot striking/overlapping an active robot symbol;
- if the UI action represents all bots, use a crowd/multiple-bot cue rather than relying on one robot alone.

**Kick Dead**
- boot striking/overlapping the dead robot symbol.

The boot should remain a simple emblem, not a detailed character foot/leg illustration.

## Recommended Generation Workflow

Do not regenerate the entire existing icon set unless explicitly requested.

Use the current icon sheet as the primary style reference and generate only the revised/new assets.

Work in small batches to reduce drift.

### Batch A
1. Single / One
2. Group
3. All
4. Tank Pull
5. Lock
6. Unlock

### Batch B
1. Replace Dead
2. Replace Missing
3. Kick Bot / Kick All
4. Kick Dead
5. optional utility icon
6. optional utility icon

Batch B should not be attempted until the robot-head design from Batch A is accepted.

## Prompting Guidance

Image generation has previously drifted when asked to make a complete "new icon set". Avoid that wording.

Prefer wording like:

> Use the supplied SoloCraftBots icon sheet as the primary style reference. Preserve its embossed relief style, lighting, material treatment, symbol weight, and existing background-colour language. Create only the following new/revised icons. Do not redesign unrelated icons. Each result is a square borderless button-fill asset with no outer frame, trim, chrome, or text.

Then define each requested symbol concretely.

For All / Group / Single, explicitly state the count/scope distinction. "Many" should be visually much denser than five.

For Tank Pull, explicitly say **real arrow with shaft and arrowhead, not a UI pointer**.

For Lock / Unlock, explicitly say they are a matched state pair and should differ only in shackle position.

## Review Criteria

Before accepting an icon, check:
- Does the symbol read correctly at small size?
- Does it look like it belongs beside the existing icons?
- Did the generator add a border/frame that was not requested?
- Did the background colour drift?
- Is the relief depth/material consistent?
- Is Single vs Group vs All obvious without studying the image?
- Do Lock and Unlock look like the same physical lock?
- Does Tank Pull show a real arrow and keep the shield primary?
- Did the generator introduce unnecessary complexity?

If any of those fail, revise only that icon/batch rather than regenerating the whole set.

## Current Direction

The existing artwork style is liked and should be preserved.

This is a semantic/consistency revision pass, not a wholesale art redesign. The intent is to improve a small number of weaker concepts and add missing maintenance-button artwork while keeping the established SoloCraftBots visual identity intact.
