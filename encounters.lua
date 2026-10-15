-- SoloCraftBots Boss Mods — EDITABLE, DECLARATIVE ENCOUNTER DATA (Lua 5.0.3).
-- Dormant: NOT listed in SoloCraftBots.toc; contains NO custom Lua handlers.
-- Add encounters here using the same detect/mechanics/triggers/effects grammar.
-- Timings below are REFERENCES from pinned ElesionWoW BigWigs source, NOT
-- confirmed on the SoloCraft server. A predicted timer displays with "~".
-- Source: ElesionWoW/BigWigs @ 47b538024cf127346d624ba7b21a8aff56cb4587
-- Activation is separately approved in Chunk 6 after server event validation.
--
-- Detection: SCB owner must supply zone-gated alive/absent/dead observations.
-- The presence widget requires actually OBSERVED living Razorgore even pre-pull.
-- Aura patterns capture an exact raid member name, including human recipients;
-- only a freshly validated bot is allowed to expose an actionable kick.
-- Server target-update acknowledgement for eggbreaker sequence is NOT YET
-- available: the engine refuses to execute it instead of risking Object All.

SoloCraftBots = SoloCraftBots or {}
SoloCraftBots.bossModDefinitions = {
    bwl = {
        razorgore = {
            detect = {
                zone = "Blackwing Lair",
                boss = "Razorgore the Untamed",
            },
            mechanics = {
                {
                    id = "egg",
                    type = "assignable_bot_action",
                    when = "present",
                    binding = "razoreggboi",
                    label = "Assign Eggbreaker",
                    assignedLabel = "name",
                    assignable = true,
                    icon = {
                        texture = "Interface\\Icons\\INV_Egg_03",
                        size = 30,
                        point = "CENTER",
                        relativePoint = "LEFT",
                        x = 0,
                        y = 3,
                    },
                    action = {
                        type = "sequence",
                        steps = {
                            {
                                command = "come",
                                scope = "target",
                            },
                            {
                                command = "object",
                                scope = "all",
                            },
                        },
                    },
                },
            },
            triggers = {},
        },
        vaelastrasz = {
            detect = {
                zone = "Blackwing Lair",
                boss = "Vaelastrasz the Corrupt",
            },
            mechanics = {},
            triggers = {
                {
                    event = "CHAT_MSG_MONSTER_YELL",
                    contains = "Too late, friends",
                    effects = {
                        {
                            type = "timer",
                            id = "pull",
                            label = "Vael pull (estimate)",
                            duration = 36,
                            provenance = "predicted",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_MONSTER_YELL",
                    contains = "I beg you, mortals",
                    effects = {
                        {
                            type = "timer",
                            id = "pull",
                            label = "Vael pull (estimate)",
                            duration = 26,
                            provenance = "predicted",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_MONSTER_YELL",
                    contains = "FLAME! DEATH! DESTRUCTION!",
                    effects = {
                        {
                            type = "timer",
                            id = "pull",
                            label = "Vael pull (estimate)",
                            duration = 10,
                            provenance = "predicted",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
                    contains = "You are afflicted by Burning Adrenaline.",
                    effects = {
                        {
                            type = "aura_apply",
                            id = "burning",
                            target = "player",
                            label = "Burning Adrenaline",
                            duration = 20,
                            action = "kick",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE",
                    pattern = "^(.+) is afflicted by Burning Adrenaline%.$",
                    effects = {
                        {
                            type = "aura_apply",
                            id = "burning",
                            target = "capture",
                            label = "Burning Adrenaline",
                            duration = 20,
                            action = "kick",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE",
                    pattern = "^(.+) is afflicted by Burning Adrenaline%.$",
                    effects = {
                        {
                            type = "aura_apply",
                            id = "burning",
                            target = "capture",
                            label = "Burning Adrenaline",
                            duration = 20,
                            action = "kick",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_AURA_GONE_SELF",
                    pattern = "^Burning Adrenaline fades from (.+)%.$",
                    effects = {
                        {
                            type = "aura_remove",
                            id = "burning",
                            target = "capture",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_AURA_GONE_PARTY",
                    pattern = "^Burning Adrenaline fades from (.+)%.$",
                    effects = {
                        {
                            type = "aura_remove",
                            id = "burning",
                            target = "capture",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_AURA_GONE_OTHER",
                    pattern = "^Burning Adrenaline fades from (.+)%.$",
                    effects = {
                        {
                            type = "aura_remove",
                            id = "burning",
                            target = "capture",
                        },
                    },
                },
            },
        },
        broodlord = {
            detect = {
                zone = "Blackwing Lair",
                boss = "Broodlord Lashlayer",
            },
            mechanics = {},
            triggers = {
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                    contains = "Broodlord Lashlayer's Blast Wave",
                    effects = {
                        {
                            type = "notice",
                            id = "blast_warn",
                            label = "Blast Wave!",
                            lifespan = 3,
                        },
                        {
                            type = "timer",
                            id = "blast_cooldown",
                            label = "Blast Wave earliest (estimate)",
                            duration = 20,
                            provenance = "predicted",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
                    contains = "Broodlord Lashlayer's Blast Wave",
                    effects = {
                        {
                            type = "notice",
                            id = "blast_warn",
                            label = "Blast Wave!",
                            lifespan = 3,
                        },
                        {
                            type = "timer",
                            id = "blast_cooldown",
                            label = "Blast Wave earliest (estimate)",
                            duration = 20,
                            provenance = "predicted",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                    contains = "Broodlord Lashlayer's Blast Wave",
                    effects = {
                        {
                            type = "notice",
                            id = "blast_warn",
                            label = "Blast Wave!",
                            lifespan = 3,
                        },
                        {
                            type = "timer",
                            id = "blast_cooldown",
                            label = "Blast Wave earliest (estimate)",
                            duration = 20,
                            provenance = "predicted",
                        },
                    },
                },
            },
        },
        firemaw = {
            detect = {
                zone = "Blackwing Lair",
                boss = "Firemaw",
            },
            mechanics = {},
            triggers = {
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                    contains = "Firemaw begins to cast Shadow Flame.",
                    effects = {
                        {
                            type = "notice",
                            id = "shadowflame_cast",
                            label = "Shadow Flame casting!",
                            lifespan = 3,
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                    contains = "Firemaw's Shadow Flame hits",
                    effects = {
                        {
                            type = "timer",
                            id = "shadowflame_cooldown",
                            label = "Shadow Flame next (estimate)",
                            duration = 14,
                            provenance = "predicted",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
                    contains = "Firemaw's Shadow Flame hits",
                    effects = {
                        {
                            type = "timer",
                            id = "shadowflame_cooldown",
                            label = "Shadow Flame next (estimate)",
                            duration = 14,
                            provenance = "predicted",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                    contains = "Firemaw's Shadow Flame hits",
                    effects = {
                        {
                            type = "timer",
                            id = "shadowflame_cooldown",
                            label = "Shadow Flame next (estimate)",
                            duration = 14,
                            provenance = "predicted",
                        },
                    },
                },
            },
        },
        ebonroc = {
            detect = {
                zone = "Blackwing Lair",
                boss = "Ebonroc",
            },
            mechanics = {},
            triggers = {
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                    contains = "Ebonroc begins to cast Shadow Flame.",
                    effects = {
                        {
                            type = "notice",
                            id = "shadowflame_cast",
                            label = "Shadow Flame casting!",
                            lifespan = 3,
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                    contains = "Ebonroc's Shadow Flame hits",
                    effects = {
                        {
                            type = "timer",
                            id = "shadowflame_cooldown",
                            label = "Shadow Flame next (estimate)",
                            duration = 14,
                            provenance = "predicted",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
                    contains = "Ebonroc's Shadow Flame hits",
                    effects = {
                        {
                            type = "timer",
                            id = "shadowflame_cooldown",
                            label = "Shadow Flame next (estimate)",
                            duration = 14,
                            provenance = "predicted",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                    contains = "Ebonroc's Shadow Flame hits",
                    effects = {
                        {
                            type = "timer",
                            id = "shadowflame_cooldown",
                            label = "Shadow Flame next (estimate)",
                            duration = 14,
                            provenance = "predicted",
                        },
                    },
                },
            },
        },
        flamegor = {
            detect = {
                zone = "Blackwing Lair",
                boss = "Flamegor",
            },
            mechanics = {},
            triggers = {
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                    contains = "Flamegor begins to cast Shadow Flame.",
                    effects = {
                        {
                            type = "notice",
                            id = "shadowflame_cast",
                            label = "Shadow Flame casting!",
                            lifespan = 3,
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                    contains = "Flamegor's Shadow Flame hits",
                    effects = {
                        {
                            type = "timer",
                            id = "shadowflame_cooldown",
                            label = "Shadow Flame next (estimate)",
                            duration = 14,
                            provenance = "predicted",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
                    contains = "Flamegor's Shadow Flame hits",
                    effects = {
                        {
                            type = "timer",
                            id = "shadowflame_cooldown",
                            label = "Shadow Flame next (estimate)",
                            duration = 14,
                            provenance = "predicted",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                    contains = "Flamegor's Shadow Flame hits",
                    effects = {
                        {
                            type = "timer",
                            id = "shadowflame_cooldown",
                            label = "Shadow Flame next (estimate)",
                            duration = 14,
                            provenance = "predicted",
                        },
                    },
                },
            },
        },
        nefarian = {
            detect = {
                zone = "Blackwing Lair",
                boss = "Nefarian",
            },
            mechanics = {},
            triggers = {
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                    contains = "Nefarian begins to cast Bellowing Roar.",
                    effects = {
                        {
                            type = "notice",
                            id = "fear_warn",
                            label = "Bellowing Roar — fear!",
                            lifespan = 3,
                        },
                        {
                            type = "timer",
                            id = "fear_cooldown",
                            label = "Fear next (estimate)",
                            duration = 23.5,
                            provenance = "predicted",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                    contains = "Nefarian begins to cast Shadow Flame.",
                    effects = {
                        {
                            type = "notice",
                            id = "shadowflame_cast",
                            label = "Shadow Flame casting!",
                            lifespan = 3,
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
                    contains = "Nefarian's Shadow Flame hits",
                    effects = {
                        {
                            type = "timer",
                            id = "shadowflame_cooldown",
                            label = "Shadow Flame earliest (estimate)",
                            duration = 16.5,
                            provenance = "predicted",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
                    contains = "Nefarian's Shadow Flame hits",
                    effects = {
                        {
                            type = "timer",
                            id = "shadowflame_cooldown",
                            label = "Shadow Flame earliest (estimate)",
                            duration = 16.5,
                            provenance = "predicted",
                        },
                    },
                },
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                    contains = "Nefarian's Shadow Flame hits",
                    effects = {
                        {
                            type = "timer",
                            id = "shadowflame_cooldown",
                            label = "Shadow Flame earliest (estimate)",
                            duration = 16.5,
                            provenance = "predicted",
                        },
                    },
                },
            },
        },
    },
}
