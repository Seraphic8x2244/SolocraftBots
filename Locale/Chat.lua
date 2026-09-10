-- SoloCraft Bots - master chat presentation values.
-- Keep these near the top of the locale load so chat colours are easy to tune.
SoloCraftBotsLocale = SoloCraftBotsLocale or {}
local T = SoloCraftBotsLocale

-- Master chat colours (RRGGBB)
T["COLOR_SCB"] = "88CCFF"

-- Vanilla class colours
T["COLOR_CLASS_WARRIOR"] = "C79C6E"
T["COLOR_CLASS_PALADIN"] = "F58CBA"
T["COLOR_CLASS_HUNTER"] = "ABD473"
T["COLOR_CLASS_ROGUE"] = "FFF569"
T["COLOR_CLASS_PRIEST"] = "FFFFFF"
T["COLOR_CLASS_SHAMAN"] = "2459FF"
T["COLOR_CLASS_MAGE"] = "69CCF0"
T["COLOR_CLASS_WARLOCK"] = "9482C9"
T["COLOR_CLASS_DRUID"] = "FF7D0A"

-- SCB role colours
T["COLOR_ROLE_TANK"] = "3399FF"
T["COLOR_ROLE_HEALER"] = "33CC66"
T["COLOR_ROLE_MELEE"] = "FF5555"
T["COLOR_ROLE_RANGED"] = "FF5555"

-- Spawn-extra colours
T["COLOR_EXTRA_BLESSING"] = "FFD100"
T["COLOR_EXTRA_FIRE"] = "FF7A1A"
T["COLOR_EXTRA_FROST"] = "66CCFF"

-- Chat wording. Prefix styling is applied by code from COLOR_SCB.
T["CHAT_PREFIX"] = "[SCB]"
T["CHAT_ADDED"] = "Added"
T["CHAT_LOADED_PRESET"] = "Loaded %s preset with %s %s"
T["CHAT_BOT_ONE"] = "bot"
T["CHAT_BOT_MANY"] = "bots"

-- Centre-screen summon failure wording.
T["SUMMON_BLOCKED_STEALTH"] = "Cannot summon bots while stealthed."
T["SUMMON_BLOCKED_PROWL"] = "Cannot summon bots while prowling."
T["SUMMON_BLOCKED_SHADOWMELD"] = "Cannot summon bots while Shadowmelded."
T["SUMMON_BLOCKED_INVISIBILITY"] = "Cannot summon bots while invisible."
T["SUMMON_BLOCKED_NOW"] = "Cannot summon bots right now."
