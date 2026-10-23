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
            mechanics = {
                {
                    id = "egg", type = "assignable_bot_action", when = "present",
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
            mechanics = {},
            abilities = {
                {
                    id = "burningadrenaline", caster = "Vaelastrasz the Corrupt",
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
                    event = "CHAT_MSG_MONSTER_YELL", contains = "Too late, friends",
                    effects = { { type = "timer", id = "pull",
                        label = "Vael pull (estimate)", duration = 36,
                        provenance = "predicted" } },
                },
                {
                    event = "CHAT_MSG_MONSTER_YELL", contains = "I beg you, mortals",
                    effects = { { type = "timer", id = "pull",
                        label = "Vael pull (estimate)", duration = 26,
                        provenance = "predicted" } },
                },
                {
                    event = "CHAT_MSG_MONSTER_YELL",
                    contains = "FLAME! DEATH! DESTRUCTION!",
                    effects = { { type = "timer", id = "pull",
                        label = "Vael pull (estimate)", duration = 10,
                        provenance = "predicted" } },
                },
            },
        },
        broodlord = {
            detect = { zone = "Blackwing Lair", boss = "Broodlord Lashlayer" },
            mechanics = {}, triggers = {},
            abilities = {
                {
                    id = "blastwave", caster = "Broodlord Lashlayer",
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
            mechanics = {}, triggers = {},
            abilities = {
                {
                    id = "shadowflame", caster = "Firemaw",
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
                    id = "wingbuffet", caster = "Firemaw",
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
            mechanics = {}, triggers = {},
            abilities = {
                {
                    id = "shadowflame", caster = "Ebonroc",
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
                    id = "wingbuffet", caster = "Ebonroc",
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
            mechanics = {}, triggers = {},
            abilities = {
                {
                    id = "shadowflame", caster = "Flamegor",
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
                    id = "wingbuffet", caster = "Flamegor",
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
            mechanics = {}, triggers = {},
            abilityGroups = {
                {
                    id = "breaths", caster = "Chromaggus", label = "Breath",
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
            mechanics = {}, triggers = {},
            abilities = {
                {
                    id = "fear", caster = "Nefarian",
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
                    id = "shadowflame", caster = "Nefarian",
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
}
