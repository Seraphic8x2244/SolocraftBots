-- SoloCraftBots: declarative Boss Mods encounter data (WoW Lua 5.0.3).
-- No boss functions, command paths, private polling, saved runtime state or UI
-- owners belong here. mechanics.lua owns validation, cast/recipient lifecycles,
-- independent clocks and the existing SCB UI/action pipeline.
--
-- abilities = { { id, caster, label, mode="fixed"|"priority"|"opportunistic",
--   firstDelay=seconds from observed engage (optional), castTime=estimate,
--   repeatDelay=seconds, resetOn="start"|"finish",
--   startOffset=estimated cast length when resetting from observed start,
--   startRule={event|events, contains|pattern},
--   finishRule={event|events, contains|pattern}, interruptRule=...,
--   auras={{id,label,target="player"|"capture",gain=...,fade=...,
--           duration=seconds,action="kick"?}, ...} } }
-- abilityGroups = { {id,caster,label,names={observed possibilities},
--   maxVisible=2,firstSlots={30,60},startRule={event,pattern=...},
--   castTime,repeatDelay,resetOn,startOffset,...} }
-- firstSlots are UNNAMED speculative first-readiness hints. They hide on
-- reaching readiness; they do NOT decide which spell will be observed.
-- Expected cast length only limits flashing; it is NOT a confirmed finish.
-- All BigWigs-sourced timings below are hypotheses pending Solocraft tests.
--
-- Razorgore egg sequence continues to use the SCB target, command, and
-- removal owners (default Boss Mods-only 0.10-second settle).

SoloCraftBots = SoloCraftBots or {}
SoloCraftBots.bossModDefinitions = {
    bwl = {
        razorgore = {
            -- Presence actions require the SCB owner's positive alive scan.
            detect = { zone = "Blackwing Lair", boss = "Razorgore the Untamed" },
            requiredZone = "Blackwing Lair",
            moduleWaker = "Razorgore the Untamed",
            passiveModules = { { id = "eggbreaker" } },
            combatModules = { { id = "combat",
                scan = { observations = { identity = true } } } },
            moduleSleeper = { npcdead = { name = "Razorgore the Untamed", count = 1 } },
            mechanics = {
                {
                    id = "egg", submodule = "eggbreaker",
                    type = "assignable_bot_action", when = "present",
                    binding = "razoreggboi", label = "Assign Eggbreaker",
                    assignedLabel = "name", assignable = true,
                    icon = {
                        texture = "Interface\\Icons\\INV_Egg_03",
                    },
                    action = { type = "sequence", steps = {
                        { command = "come", scope = "target" },
                        { command = "object", scope = "all" },
                    } },
                },
            },
            abilities = {}, abilityGroups = {}, triggers = {},
        },
        vaelastrasz = {
            detect = { zone = "Blackwing Lair", boss = "Vaelastrasz the Corrupt" },
            requiredZone = "Blackwing Lair",
            moduleWaker = "Vaelastrasz the Corrupt",
            passiveModules = { { id = "engagetimer" } },
            combatModules = { {
                id = "burningadrenaline", retainUntilResolved = true,
                scan = { observations = { identity = true } },
                tracker = { id = "BurningAdrenalineTracker", kind = "aura",
                    keyPrefix = "decl:burningadrenaline_burning:",
                    actionKeyPrefix = "kick:decl:burningadrenaline_burning:" },
            } },
            moduleSleeper = {
                npcdead = { name = "Vaelastrasz the Corrupt", count = 1 },
                trackerEmpty = "BurningAdrenalineTracker",
            },
            mechanics = {},
            abilities = {
                {
                    id = "burningadrenaline", submodule = "burningadrenaline",
                    caster = "Vaelastrasz the Corrupt",
                    label = "Burning Adrenaline", mode = "opportunistic",
                    -- Auras arrive independently from any observed spell cast.
                    auras = {
                        {
                            id = "burning", label = "Burning Adrenaline",
                            icon = "Interface\\Icons\\INV_Gauntlets_03",
                            target = "player", duration = 20,
                            action = "kick", kickLabel = "Kick",
                            retainAfterBossDeath = true,
                            gain = {
                                event = "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
                                contains = "You are afflicted by Burning Adrenaline.",
                            },
                        },
                        {
                            id = "burning", label = "Burning Adrenaline",
                            icon = "Interface\\Icons\\INV_Gauntlets_03",
                            target = "capture", duration = 20,
                            action = "kick", kickLabel = "Kick",
                            retainAfterBossDeath = true,
                            gain = {
                                events = {
                                    "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE",
                                    "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE",
                                },
                                pattern = "^(.+) is afflicted by Burning Adrenaline%.$",
                            },
                            fade = {
                                events = {
                                    "CHAT_MSG_SPELL_AURA_GONE_SELF",
                                    "CHAT_MSG_SPELL_AURA_GONE_PARTY",
                                    "CHAT_MSG_SPELL_AURA_GONE_OTHER",
                                },
                                pattern = "^Burning Adrenaline fades from (.+)%.$",
                            },
                        },
                    },
                },
            },
            triggers = {
                {
                    submodule = "engagetimer", event = "CHAT_MSG_MONSTER_YELL", contains = "Too late, friends",
                    effects = { { type = "timer", id = "pull",
                        label = "Vael pull (estimate)", duration = 36,
                        provenance = "predicted" } },
                },
                {
                    submodule = "engagetimer", event = "CHAT_MSG_MONSTER_YELL", contains = "I beg you, mortals",
                    effects = { { type = "timer", id = "pull",
                        label = "Vael pull (estimate)", duration = 26,
                        provenance = "predicted" } },
                },
                {
                    submodule = "engagetimer", event = "CHAT_MSG_MONSTER_YELL",
                    contains = "FLAME! DEATH! DESTRUCTION!",
                    effects = { { type = "timer", id = "pull",
                        label = "Vael pull (estimate)", duration = 10,
                        provenance = "predicted" } },
                },
            },
        },
        broodlord = {
            detect = { zone = "Blackwing Lair", boss = "Broodlord Lashlayer" },
            requiredZone = "Blackwing Lair",
            moduleWaker = "Broodlord Lashlayer",
            passiveModules = {},
            combatModules = { { id = "blastwave",
                scan = { observations = { identity = true } } } },
            moduleSleeper = { npcdead = { name = "Broodlord Lashlayer", count = 1 } },
            mechanics = {}, triggers = {},
            abilities = {
                {
                    id = "blastwave", submodule = "blastwave", caster = "Broodlord Lashlayer",
                    label = "Blast Wave", mode = "opportunistic",
                    icon = "Interface\\Icons\\Spell_Holy_Excorcism_02",
                    repeatDelay = 20, resetOn = "finish",
                    finishRule = {
                        events = {
                            "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        },
                        contains = "Broodlord Lashlayer's Blast Wave",
                    },
                },
            },
        },
        firemaw = {
            detect = { zone = "Blackwing Lair", boss = "Firemaw" },
            requiredZone = "Blackwing Lair",
            moduleWaker = "Firemaw",
            passiveModules = {},
            combatModules = { { id = "casts",
                scan = { observations = { identity = true } } } },
            moduleSleeper = { npcdead = { name = "Firemaw", count = 1 } },
            mechanics = {}, triggers = {},
            abilities = {
                {
                    id = "shadowflame", submodule = "casts", caster = "Firemaw",
                    label = "Shadow Flame", mode = "opportunistic",
                    icon = "Interface\\Icons\\Spell_Fire_Incinerate",
                    firstDelay = 14, castTime = 2, repeatDelay = 14,
                    resetOn = "finish",
                    startRule = {
                        event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        contains = "Firemaw begins to cast Shadow Flame.",
                    },
                    finishRule = {
                        events = {
                            "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        },
                        contains = "Firemaw's Shadow Flame hits",
                    },
                },
                {
                    id = "wingbuffet", submodule = "casts", caster = "Firemaw",
                    label = "Wing Buffet", mode = "opportunistic",
                    icon = "Interface\\Icons\\INV_Misc_MonsterScales_14",
                    firstDelay = 30, castTime = 1,
                    -- Only start is observed; this forecasts 29s after the
                    -- expected 1s cast, never asserts completion occurred.
                    repeatDelay = 29, resetOn = "start", startOffset = 1,
                    startRule = {
                        event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        contains = "Firemaw begins to cast Wing Buffet.",
                    },
                },
            },
        },
        ebonroc = {
            detect = { zone = "Blackwing Lair", boss = "Ebonroc" },
            requiredZone = "Blackwing Lair",
            moduleWaker = "Ebonroc",
            passiveModules = {},
            combatModules = { { id = "casts",
                scan = { observations = { identity = true } } } },
            moduleSleeper = { npcdead = { name = "Ebonroc", count = 1 } },
            mechanics = {}, triggers = {},
            abilities = {
                {
                    id = "shadowflame", submodule = "casts", caster = "Ebonroc",
                    label = "Shadow Flame", mode = "opportunistic",
                    icon = "Interface\\Icons\\Spell_Fire_Incinerate",
                    firstDelay = 14, castTime = 2, repeatDelay = 14,
                    resetOn = "finish",
                    startRule = {
                        event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        contains = "Ebonroc begins to cast Shadow Flame.",
                    },
                    finishRule = {
                        events = {
                            "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        },
                        contains = "Ebonroc's Shadow Flame hits",
                    },
                },
                {
                    id = "wingbuffet", submodule = "casts", caster = "Ebonroc",
                    label = "Wing Buffet", mode = "opportunistic",
                    icon = "Interface\\Icons\\INV_Misc_MonsterScales_14",
                    firstDelay = 30, castTime = 1, repeatDelay = 29,
                    resetOn = "start", startOffset = 1,
                    startRule = {
                        event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        contains = "Ebonroc begins to cast Wing Buffet.",
                    },
                },
            },
        },
        flamegor = {
            detect = { zone = "Blackwing Lair", boss = "Flamegor" },
            requiredZone = "Blackwing Lair",
            moduleWaker = "Flamegor",
            passiveModules = {},
            combatModules = { { id = "casts",
                scan = { observations = { identity = true } } } },
            moduleSleeper = { npcdead = { name = "Flamegor", count = 1 } },
            mechanics = {}, triggers = {},
            abilities = {
                {
                    id = "shadowflame", submodule = "casts", caster = "Flamegor",
                    label = "Shadow Flame", mode = "opportunistic",
                    icon = "Interface\\Icons\\Spell_Fire_Incinerate",
                    firstDelay = 14, castTime = 2, repeatDelay = 14,
                    resetOn = "finish",
                    startRule = {
                        event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        contains = "Flamegor begins to cast Shadow Flame.",
                    },
                    finishRule = {
                        events = {
                            "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        },
                        contains = "Flamegor's Shadow Flame hits",
                    },
                },
                {
                    id = "wingbuffet", submodule = "casts", caster = "Flamegor",
                    label = "Wing Buffet", mode = "opportunistic",
                    icon = "Interface\\Icons\\INV_Misc_MonsterScales_14",
                    firstDelay = 30, castTime = 1, repeatDelay = 29,
                    resetOn = "start", startOffset = 1,
                    startRule = {
                        event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        contains = "Flamegor begins to cast Wing Buffet.",
                    },
                },
            },
        },
        chromaggus = {
            detect = { zone = "Blackwing Lair", boss = "Chromaggus" },
            requiredZone = "Blackwing Lair",
            moduleWaker = "Chromaggus",
            passiveModules = {},
            combatModules = { { id = "breaths",
                scan = { observations = { identity = true } } } },
            moduleSleeper = { npcdead = { name = "Chromaggus", count = 1 } },
            mechanics = {}, triggers = {},
            abilityGroups = {
                {
                    id = "breaths", submodule = "breaths", caster = "Chromaggus", label = "Breath",
                    mode = "opportunistic", maxVisible = 2,
                    firstSlots = { 30, 60 },
                    names = { "Corrosive Acid", "Frost Burn", "Ignite Flesh",
                        "Incinerate", "Time Lapse" },
                    -- 1.12-era BigWigs icon identities for the five breaths.
                    -- First-slot hints remain '?' until an actual breath is seen.
                    icons = {
                        ["Corrosive Acid"] = "Interface\\Icons\\Spell_Nature_Acid_01",
                        ["Frost Burn"] = "Interface\\Icons\\Spell_Frost_ChillingBlast",
                        ["Ignite Flesh"] = "Interface\\Icons\\Spell_Fire_Fire",
                        ["Incinerate"] = "Interface\\Icons\\Spell_Shadow_ChillTouch",
                        ["Time Lapse"] = "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar",
                    },
                    castTime = 2,
                    -- Independent observed breath: ~60s from its projected
                    -- end, anchored ONLY to that breath's real cast start.
                    resetOn = "start", startOffset = 2, repeatDelay = 60,
                    startRule = {
                        event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        pattern = "^Chromaggus begins to cast (.+)%.$",
                    },
                },
            },
        },
        nefarian = {
            detect = { zone = "Blackwing Lair", boss = "Nefarian" },
            requiredZone = "Blackwing Lair",
            moduleWaker = "Nefarian",
            passiveModules = {},
            combatModules = { { id = "casts",
                scan = { observations = { identity = true } } } },
            moduleSleeper = { npcdead = { name = "Nefarian", count = 1 } },
            mechanics = {}, triggers = {},
            abilities = {
                {
                    id = "fear", submodule = "casts", caster = "Nefarian",
                    label = "Bellowing Roar", mode = "opportunistic",
                    icon = "Interface\\Icons\\Spell_Shadow_Charm",
                    firstDelay = 25, castTime = 1.5,
                    repeatDelay = 23.5, resetOn = "start", startOffset = 1.5,
                    startRule = {
                        event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        contains = "Nefarian begins to cast Bellowing Roar.",
                    },
                },
                {
                    id = "shadowflame", submodule = "casts", caster = "Nefarian",
                    label = "Shadow Flame", mode = "opportunistic",
                    icon = "Interface\\Icons\\Spell_Fire_Incinerate",
                    firstDelay = 19.7, castTime = 2,
                    repeatDelay = 16.5, resetOn = "finish",
                    startRule = {
                        event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        contains = "Nefarian begins to cast Shadow Flame.",
                    },
                    finishRule = {
                        events = {
                            "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        },
                        contains = "Nefarian's Shadow Flame hits",
                    },
                },
            },
        },
    },

    -- Chosen AQ40 mechanics only. Missing reliable native evidence remains
    -- undeclared: an absent effect is NOT inferred from an unobserved event.
    aq40 = {
        skeram = {
            detect = { zone = "Ahn'Qiraj", boss = "The Prophet Skeram",
                endOnBossDeath = false },
            mechanics = {}, abilities = {}, triggers = {},
            -- Real-boss raid marker 6 uses native maximum-health comparison\n            -- in the encounter owner; no clone or MC mechanics requested.
        },
        bugtrio = {
            detect = { zone = "Ahn'Qiraj", boss = "Lord Kri",
                aliases = { "Princess Yauj", "Vem" },
                endOnBossDeath = false },
            mechanics = {},
            hpUnits = {
                { id = "kri", name = "Lord Kri", label = "Lord Kri" },
                { id = "yauj", name = "Princess Yauj", label = "Princess Yauj" },
                { id = "vem", name = "Vem", label = "Vem" },
            },
            abilities = {
                {
                    id = "poison", caster = "Lord Kri", label = "Poison Volley",
                    mode = "opportunistic",
                    -- Pinned BigWigs: first 8-10s, subsequent 8-14s.
                    -- Earliest readiness is estimated, not a confirmed cast.
                    firstDelay = 8, repeatDelay = 8, resetOn = "finish",
                    icon = "Interface\\Icons\\Spell_Nature_CorrosiveBreath",
                    finishRule = {
                        events = { "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE" },
                        contains = "Lord Kri's Poison Volley",
                    },
                },
                {
                    id = "greatheal", caster = "Princess Yauj",
                    label = "Great Heal", readyLabel = "Heal Ready",
                    mode = "opportunistic", castTime = 2,
                    icon = "Interface\\Icons\\Spell_Holy_GreaterHeal",
                    startRule = {
                        events = { "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF",
                            "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE" },
                        contains = "Princess Yauj begins to cast Great Heal.",
                    },
                },
                {
                    id = "fear", caster = "Princess Yauj", label = "Fear",
                    mode = "opportunistic",
                    -- Pinned BugFamily: initial 10-20s, later 20s.
                    firstDelay = 10, repeatDelay = 20, resetOn = "start",
                    castTime = 1,
                    icon = "Interface\\Icons\\Spell_Shadow_Possession",
                    startRule = {
                        event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        contains = "Princess Yauj begins to cast Fear.",
                    },
                },
            },
            -- School lockout is counted only when the native log explicitly
            -- names the interrupt spell AND its Great Heal target. Durations
            -- are per interrupt type; absent evidence remains unresolved.
            triggers = {
                {
                    events = { "CHAT_MSG_SPELL_SELF_DAMAGE",
                        "CHAT_MSG_SPELL_PARTY_DAMAGE",
                        "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE" },
                    contains = "Kick interrupts Princess Yauj's Great Heal",
                    effects = { { type = "ability_lockout",
                        id = "lockout_kick",
                        ability = "greatheal", duration = 5 } },
                },
                {
                    events = { "CHAT_MSG_SPELL_SELF_DAMAGE",
                        "CHAT_MSG_SPELL_PARTY_DAMAGE",
                        "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE" },
                    contains = "Pummel interrupts Princess Yauj's Great Heal",
                    effects = { { type = "ability_lockout",
                        id = "lockout_pummel",
                        ability = "greatheal", duration = 4 } },
                },
                {
                    events = { "CHAT_MSG_SPELL_SELF_DAMAGE",
                        "CHAT_MSG_SPELL_PARTY_DAMAGE",
                        "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE" },
                    contains = "Shield Bash interrupts Princess Yauj's Great Heal",
                    effects = { { type = "ability_lockout",
                        id = "lockout_shieldbash",
                        ability = "greatheal", duration = 6 } },
                },
                {
                    events = { "CHAT_MSG_SPELL_SELF_DAMAGE",
                        "CHAT_MSG_SPELL_PARTY_DAMAGE",
                        "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE" },
                    contains = "Counterspell interrupts Princess Yauj's Great Heal",
                    effects = { { type = "ability_lockout",
                        id = "lockout_counterspell",
                        ability = "greatheal", duration = 10 } },
                },
                {
                    events = { "CHAT_MSG_SPELL_SELF_DAMAGE",
                        "CHAT_MSG_SPELL_PARTY_DAMAGE",
                        "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE" },
                    contains = "Earth Shock interrupts Princess Yauj's Great Heal",
                    effects = { { type = "ability_lockout",
                        id = "lockout_earthshock",
                        ability = "greatheal", duration = 2 } },
                },
                {
                    events = { "CHAT_MSG_SPELL_SELF_DAMAGE",
                        "CHAT_MSG_SPELL_PARTY_DAMAGE",
                        "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE" },
                    contains = "Spell Lock interrupts Princess Yauj's Great Heal",
                    effects = { { type = "ability_lockout",
                        id = "lockout_spelllock",
                        ability = "greatheal", duration = 6 } },
                },
            },
        },
        sartura = {
            detect = { zone = "Ahn'Qiraj", boss = "Battleguard Sartura" },
            mechanics = {},
            hpUnits = {
                { id = "boss", name = "Battleguard Sartura",
                    label = "Battleguard Sartura" },
                { id = "guard", name = "Sartura's Royal Guard",
                    label = "Royal Guard" },
            },
            abilities = {
                {
                    id = "whirlwind", caster = "Battleguard Sartura",
                    label = "Whirlwind",
                    mode = "opportunistic",
                    -- Sartura only. Positive aura gain is active start,
                    -- positive fade is end. Earliest cooldown 5s after fade.
                    firstDelay = 8, repeatDelay = 5,
                    resetOn = "finish", castTime = 15,
                    icon = "Interface\\Icons\\Ability_Whirlwind",
                    -- Aura gain is observed activation, not a cast start or
                    -- proof of when the next Whirlwind will become available.
                    startRule = {
                        event = "CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS",
                        contains = "Battleguard Sartura gains Whirlwind.",
                    },
                    finishRule = {
                        event = "CHAT_MSG_SPELL_AURA_GONE_OTHER",
                        contains = "Whirlwind fades from Battleguard Sartura.",
                    },
                },
            },
            triggers = {},
        },
        fankriss = {
            detect = { zone = "Ahn'Qiraj", boss = "Fankriss the Unyielding" },
            mechanics = {},
            hpUnits = {
                { id = "boss", name = "Fankriss the Unyielding",
                    label = "Fankriss" },
                { id = "worm", name = "Spawn of Fankriss",
                    label = "Enraging Worm", hideOnDeath = true },
            },
            abilities = {
                {
                    id = "entangle", caster = "Fankriss the Unyielding",
                    label = "Entangle", mode = "opportunistic",
                    observedOnly = true,
                    auras = {
                        { id = "self", label = "Entangle",
                            target = "player",
                            icon = "Interface\\Icons\\Spell_Nature_Web",
                            gain = { event = "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
                                contains = "You are afflicted by Entangle." },
                            fade = { event = "CHAT_MSG_SPELL_AURA_GONE_SELF",
                                contains = "Entangle fades from you." } },
                        { id = "other", label = "Entangle",
                            target = "capture",
                            icon = "Interface\\Icons\\Spell_Nature_Web",
                            gain = { events = {
                                "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE",
                                "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE" },
                                pattern = "^(.+) is afflicted by Entangle%.$" },
                            fade = { events = {
                                "CHAT_MSG_SPELL_AURA_GONE_PARTY",
                                "CHAT_MSG_SPELL_AURA_GONE_OTHER" },
                                pattern = "^Entangle fades from (.+)%.$" } },
                    },
                },
            }, triggers = {},
            -- No Come command until target-bound post-fade safety is proven.
        },
        viscidus = {
            detect = { zone = "Ahn'Qiraj", boss = "Viscidus" },
            mechanics = {},
            abilities = {
                {
                    id = "toxin", caster = "Viscidus", label = "Toxin",
                    observedOnly = true, mode = "opportunistic",
                    auras = {
                        { id = "self", label = "Toxin", target = "player",
                            icon = "Interface\\Icons\\Spell_Nature_AbolishMagic",
                            gain = { event = "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
                                contains = "You are afflicted by Toxin." },
                            fade = { event = "CHAT_MSG_SPELL_AURA_GONE_SELF",
                                contains = "Toxin fades from you." } },
                    },
                },
            },
            counters = {
                { id = "frosthits", label = "Observed Frost Hits",
                    maximum = 200, maximumKind = "reference",
                    icon = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
                { id = "meleehits", label = "Observed Melee Hits",
                    maximum = 110, maximumKind = "reference",
                    icon = "Interface\\Icons\\INV_Sword_04" },
            },
            triggers = {
                -- Native other-recipient Toxin applications expose a roster name.
                -- Only the first positively matched live bot is retained.
                { events = { "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE",
                        "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE" },
                    pattern = "^(.+) is afflicted by Toxin%.$",
                    effects = { { type = "viscidus_toxin", id = "toxin_other" } } },
                { event = "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
                    contains = "You are afflicted by Toxin.",
                    effects = { { type = "viscidus_toxin", id = "toxin_self", target = "player" } } },
                -- BigWigs' native emote boundaries: frost hits count until
                -- frozen, then melee hits count. A later slow emote resets
                -- the next frost cycle without inventing a glob duration.
                { event = "CHAT_MSG_RAID_BOSS_EMOTE",
                    contains = " is frozen solid!",
                    effects = { { type = "viscidus_phase", id = "frozen", phase = "melee" } } },
                { event = "CHAT_MSG_RAID_BOSS_EMOTE",
                    contains = " begins to slow!",
                    effects = { { type = "viscidus_phase", id = "slow", phase = "frost" } } },
                -- Confirmed creature buff applications; these are only a
                -- subset of frost damage hits, not a complete frost count.
                {
                    event = "CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS",
                    pattern = "^Viscidus gains (Chilled)%.$",
                    effects = { { type = "counter_hit", id = "frosthits" } },
                },
                {
                    event = "CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS",
                    contains = "Viscidus gains Winter's Chill.",
                    effects = { { type = "counter_hit", id = "frosthits" } },
                },
                -- Native physical hit/crit text differs for self and others.
                -- Do not count spell damage as a physical hit.
                { event = "CHAT_MSG_COMBAT_SELF_HITS",
                    pattern = "^You [hc][ir][ti].* Viscidus for ",
                    effects = { { type = "counter_hit", id = "meleehits" } } },
                { events = { "CHAT_MSG_COMBAT_PARTY_HITS",
                        "CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS" },
                    pattern = " [hc][ir][ti].* Viscidus for ",
                    effects = { { type = "counter_hit", id = "meleehits" } } },
                -- Elesion counts native spell combat messages containing Frost
                -- damage; restrict to messages explicitly naming Viscidus.
                { events = { "CHAT_MSG_SPELL_SELF_DAMAGE",
                        "CHAT_MSG_SPELL_PARTY_DAMAGE",
                        "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE" },
                    pattern = "Viscidus.*Frost damage",
                    effects = { { type = "counter_hit", id = "frosthits" } } },
            },
            -- No guessed phase transitions from incomplete hit totals.
        },
        huhuran = {
            detect = { zone = "Ahn'Qiraj", boss = "Princess Huhuran" },
            mechanics = {}, abilities = {}, triggers = {},
            thresholds = {
                { id = "berserk", name = "Princess Huhuran",
                    label = "Berserk (30% HP)", threshold = 0.30,
                    icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy" },
            },
        },
        twins = {
            detect = { zone = "Ahn'Qiraj", boss = "Emperor Vek'lor",
                aliases = { "Emperor Vek'nilash" },
                endOnBossDeath = false },
            mechanics = {}, abilities = {}, triggers = {},
            -- Vek'lor target-of-target requires positive target-chain
            -- identity; no name-only fallback.
        },
        ouro = {
            detect = { zone = "Ahn'Qiraj", boss = "Ouro" },
            mechanics = {},
            -- First readiness is estimated from observed engagement.
            -- Only a positive Ground Rupture refreshes this single row.
            initialStages = {
                { id = "ourocycle", label = "Next Submerge (estimated)",
                    minDelay = 89, provenance = "predicted",
                    icon = "Interface\\Icons\\INV_Misc_Shovel_01" },
            },
            -- Optional SuperWoW UNIT_CASTEVENT. The spell must be a real
            -- successful cast by the same Ouro GUID already observed in the
            -- HP threshold tracker. Vanilla has no equivalent positive event.
            castStages = {
                { id = "ourocycle", spellId = 26063,
                    sourceThreshold = "berserk",
                    label = "Next Emerge (estimated)", minDelay = 27,
                    provenance = "predicted",
                    icon = "Interface\\Icons\\INV_Misc_Shovel_01" },
            },
            thresholds = {
                { id = "berserk", name = "Ouro",
                    label = "Berserk (20% HP)", threshold = 0.20,
                    icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy" },
            },
            abilities = {
                {
                    id = "sweep", caster = "Ouro", label = "Sweep",
                    mode = "opportunistic",
                    firstDelay = 20.5, repeatDelay = 20.5,
                    resetOn = "start", castTime = 1.5,
                    icon = "Interface\\Icons\\Spell_Nature_Thorns",
                    startRule = {
                        event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        contains = "Ouro begins to cast Sweep.",
                    },
                },
                {
                    id = "sandblast", caster = "Ouro", label = "Sand Blast",
                    mode = "opportunistic",
                    firstDelay = 20, repeatDelay = 20,
                    resetOn = "start", castTime = 2,
                    icon = "Interface\\Icons\\Spell_Nature_Cyclone",
                    startRule = {
                        event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        contains = "Ouro begins to perform Sand Blast.",
                    },
                },
            },
            triggers = {
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                    contains = "Ground Rupture",
                    effects = { { type = "timer_stage", id = "ourocycle",
                        label = "Next Submerge (estimated)",
                        minDelay = 89, provenance = "predicted",
                        icon = "Interface\\Icons\\INV_Misc_Shovel_01" } },
                },
            },
            -- Submerge lacks a confirmed native signal: do not infer it from
            -- losing the target or invent a stage/interval countdown.
        },
        cthun = {
            detect = { zone = "Ahn'Qiraj", boss = "C'Thun",
                aliases = { "Eye of C'Thun" },
                endOnBossDeath = false },
            mechanics = {}, triggers = {},
            hpUnits = {
                { id = "flesh", name = "Flesh Tentacle",
                    label = "Flesh Tentacle", hideOnDeath = true,
                    clickTarget = true, attackAll = true },
                -- Shared template, separate positive per-spawn GUID rows.
                { id = "giant", name = "Giant Claw Tentacle",
                    aliases = { "Giant Eye Tentacle" },
                    label = "Giant Tentacle", hideOnDeath = true,
                    clickTarget = true },
            },
            abilities = {
                {
                    id = "darkglare", caster = "Eye of C'Thun",
                    label = "Dark Glare", mode = "opportunistic",
                    -- Elesion 47b5380 reference estimates, not runtime-verified.
                    -- Readiness never fabricates a cast; native cast text
                    -- confirms each actual start and refreshes the cycle.
                    firstDelay = 45, repeatDelay = 87,
                    resetOn = "start", castTime = 3,
                    icon = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
                    startRule = {
                        event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                        contains = "Eye of C'Thun begins to cast Dark Glare.",
                    },
                },
            },
            triggers = {
                { event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                    contains = "Eye of C'Thun begins to cast Dark Glare.",
                    effects = { { type = "cthun_glare", id = "glare_active" } } },
                { event = "CHAT_MSG_COMBAT_HOSTILE_DEATH",
                    contains = "Eye of C'Thun dies.",
                    effects = { { type = "cthun_phase2", id = "phase2" } } },
                -- These Birth messages identify a *spawn already occurring*.
                -- A reference next-spawn window is not a claimed unique unit.
                { event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF",
                    contains = "Giant Claw Tentacle begins to cast Birth.",
                    effects = { { type = "timer_stage", id = "giant_eye_next",
                        label = "Next Giant Eye (reference)",
                        minDelay = 30, provenance = "predicted" } } },
                { event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF",
                    contains = "Giant Eye Tentacle begins to cast Birth.",
                    effects = { { type = "timer_stage", id = "giant_claw_next",
                        label = "Next Giant Claw (reference)",
                        minDelay = 30, provenance = "predicted" } } },
                -- 8s post-Weakened reference begins after its 45s duration,
                -- not at the initial weakened emote.
                { event = "CHAT_MSG_MONSTER_EMOTE",
                    contains = "is weakened!",
                    effects = { { type = "cthun_weakened", id = "weaken_recovery" } } },
                -- Native emote positively establishes the start of Weakened.
                -- This 45s bar is an Elesion reference, not a phase detector.
                { event = "CHAT_MSG_MONSTER_EMOTE",
                    contains = "is weakened!",
                    effects = { { id = "weakened", type = "timer",
                        label = "Weakened (reference 45s)",
                        duration = 45, provenance = "predicted" } } },
            },
            -- Native BigWigs 47b5380 phase transition: Eye death is definitive.
            -- The first giant claw is due 12s after phase two; subsequent
            -- births alternate, while post-Weakened scheduling begins when
            -- the 45s window ENDS rather than when it starts.
            -- Giant Tentacle shared HP row remains separate from spawn
            -- estimates; do not derive identity from birth messages.
        },
        sentinels = {
            detect = { zone = "Ahn'Qiraj", boss = "Anubisath Sentinel",
                endOnBossDeath = false },
            mechanics = {}, abilities = {}, triggers = {},
            hpUnits = {
                { id = "sentinel", name = "Anubisath Sentinel",
                    label = "Anubisath Sentinel", clickTarget = true,
                    hideOnDeath = true },
            },
            -- Priority is keyed to a positively observed ORIGINAL ability,
            -- never the union of abilities gained after another Sentinel dies.
            -- This is declaration data only: no combat-log text is assumed
            -- to establish the original/inherited provenance of an ability.
            initialAbilityPriority = {
                { rank = 1, names = { "Mortal Strike" } },
                { rank = 2, names = { "Mending" } },
                { rank = 3, names = { "Fire Reflect", "Arcane Reflect" } },
                { rank = 4, names = { "Frost Reflect", "Shadow Reflect" } },
                { rank = 5, names = { "Shadowbolt Volley", "Shadow Storm" } },
                { rank = 6, names = { "Knockback" } },
                { rank = 7, names = { "Mana Burn" } },
                { rank = 8, names = { "Thorns" } },
                { rank = 9, names = { "Thunderclap" } },
            },
            -- Per-GUID initial distinguishing ability and inheritance
            -- attribution still require a positive GUID-bound observation.
        },
        defender = {
            detect = { zone = "Ahn'Qiraj", boss = "Anubisath Defender" },
            mechanics = {},
            hpUnits = {
                { id = "defender", name = "Anubisath Defender",
                    label = "Anubisath Defender", hideOnDeath = true },
            },
            abilities = {
                {
                    id = "meteor", caster = "Anubisath Defender",
                    label = "Meteor observed", observedOnly = true,
                    mode = "opportunistic",
                    icon = "Interface\\Icons\\Spell_Fire_Fireball02",
                    finishRule = {
                        events = { "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE" },
                        contains = "Anubisath Defender's Meteor hits",
                    },
                },
                {
                    id = "plague", caster = "Anubisath Defender",
                    label = "Plague", observedOnly = true,
                    mode = "opportunistic",
                    -- Same bot-bound Kick aura path as Vael Burning Adrenaline.
                    -- Pinned Elesion BigWigs: Plague duration 40 seconds.
                    auras = {
                        { id = "plague", label = "Plague",
                            icon = "Interface\\Icons\\Spell_Shadow_CurseOfTounges",
                            target = "player", duration = 40,
                            action = "kick", kickLabel = "Kick",
                            gain = {
                                event = "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
                                contains = "You are afflicted by Plague.",
                            },
                        },
                        { id = "plague", label = "Plague",
                            icon = "Interface\\Icons\\Spell_Shadow_CurseOfTounges",
                            target = "capture", duration = 40,
                            action = "kick", kickLabel = "Kick",
                            gain = {
                                events = {
                                    "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE",
                                    "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE",
                                },
                                pattern = "^(.+) is afflicted by Plague%.$",
                            },
                            fade = {
                                events = {
                                    "CHAT_MSG_SPELL_AURA_GONE_SELF",
                                    "CHAT_MSG_SPELL_AURA_GONE_PARTY",
                                    "CHAT_MSG_SPELL_AURA_GONE_OTHER",
                                },
                                pattern = "^Plague fades from (.+)%.$",
                            },
                        },
                    },
                },
                {
                    id = "shadowstorm", caster = "Anubisath Defender",
                    label = "Shadow Storm observed", observedOnly = true,
                    mode = "opportunistic",
                    icon = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
                    finishRule = {
                        events = { "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE" },
                        contains = "Anubisath Defender's Shadow Storm hits",
                    },
                },
                {
                    id = "thunderclap", caster = "Anubisath Defender",
                    label = "Thunderclap observed", observedOnly = true,
                    mode = "opportunistic",
                    icon = "Interface\\Icons\\Ability_ThunderClap",
                    finishRule = {
                        events = { "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
                            "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE" },
                        contains = "Anubisath Defender's Thunderclap hits",
                    },
                },
            },
            -- Dev-branch local-self hit/application sampling only.
            -- Party and raid AoE lines may repeat for a single occurrence;
            -- they are intentionally excluded from timing measurements.
            triggers = {
                -- Reflect spell evidence follows pinned Elesion's native
                -- combat strings. Record the identified pair as a passive
                -- status, never a fabricated 600s cooldown.
                { events = { "CHAT_MSG_SPELL_SELF_DAMAGE",
                        "CHAT_MSG_SPELL_PARTY_DAMAGE",
                        "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE" },
                    contains = "Moonfire is reflected back by Anubisath Defender.",
                    effects = { { type = "ability_observed", id = "def_fire_arcane",
                        label = "Reflect", ability = "Fire / Arcane",
                        icon = "Interface\\Icons\\Spell_Arcane_PortalDarnassus" } } },
                { events = { "CHAT_MSG_SPELL_SELF_DAMAGE",
                        "CHAT_MSG_SPELL_PARTY_DAMAGE",
                        "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE" },
                    contains = "Fireball is reflected back by Anubisath Defender.",
                    effects = { { type = "ability_observed", id = "def_fire_arcane",
                        label = "Reflect", ability = "Fire / Arcane",
                        icon = "Interface\\Icons\\Spell_Arcane_PortalDarnassus" } } },
                { events = { "CHAT_MSG_SPELL_SELF_DAMAGE",
                        "CHAT_MSG_SPELL_PARTY_DAMAGE",
                        "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE" },
                    contains = "Frostbolt is reflected back by Anubisath Defender.",
                    effects = { { type = "ability_observed", id = "def_frost_shadow",
                        label = "Reflect", ability = "Frost / Shadow",
                        icon = "Interface\\Icons\\Spell_Frost_FrostBolt02" } } },
                { events = { "CHAT_MSG_SPELL_SELF_DAMAGE",
                        "CHAT_MSG_SPELL_PARTY_DAMAGE",
                        "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE" },
                    contains = "Corruption is reflected back by Anubisath Defender.",
                    effects = { { type = "ability_observed", id = "def_frost_shadow",
                        label = "Reflect", ability = "Frost / Shadow",
                        icon = "Interface\\Icons\\Spell_Frost_FrostBolt02" } } },
                { event = "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                    contains = "Anubisath Defender's Meteor hits you",
                    effects = { { type = "dev_interval", id = "met_sample",
                        ability = "meteor" } } },
                { event = "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
                    contains = "You are afflicted by Plague.",
                    effects = { { type = "dev_interval", id = "pla_sample",
                        ability = "plague" } } },
                { event = "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                    contains = "Anubisath Defender's Shadow Storm hits you",
                    effects = { { type = "dev_interval", id = "sha_sample",
                        ability = "shadowstorm" } } },
                { event = "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                    contains = "Anubisath Defender's Thunderclap hits you",
                    effects = { { type = "dev_interval", id = "thu_sample",
                        ability = "thunderclap" } } },
            },
            -- Native reflection strings identify the school pair, not a
            -- 600-second cooldown. Persist a passive identified marker only.
            -- Individual casts need no GUID while a single Defender is active.
            -- No mutually exclusive pair inferred from unverified damage.
            -- Reflect evidence uses Elesion's exact spell examples.
            -- (Ability 3 is identification only; 4/5 deliberately ignored.)
            -- Additional cooldowns require recorded intervals.
        },
    },
}
