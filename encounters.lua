-- SoloCraftBots: EDIT-ONLY ENCOUNTER DEFINITIONS (Lua 5.0.3).
-- NO boss functions, custom parsers or runtime hooks belong in this file.
-- Dormant until the separately approved Chunk 6 TOC/lifecycle integration.
-- Timings are ElesionWoW BigWigs REFERENCE estimates, not proven on SoloCraft:
-- https://github.com/ElesionWoW/BigWigs/tree/47b538024cf127346d624ba7b21a8aff56cb4587/Raids/BWL
-- An estimated countdown displays with "~". The notice lifespan is only UI.
--
-- Grammar:
--   bwl.<boss>.detect  = { zone="Blackwing Lair", boss="Exact NPC name" }
--   bwl.<boss>.mechanics = { { id, type="assignable_bot_action",
--       when="present", binding, label, assignable=true, icon={...}, action={...} } }
--   bwl.<boss>.triggers = { { event="..." OR events={"...","..."},
--       contains="literal" OR pattern="Lua (capture) pattern", effects={...} } }
--   effects: timer {id,label,duration,provenance="predicted"/"fixed"/"observed"},
--            notice {id,label,lifespan},
--            aura_apply {id,target="player"/"capture",label,duration?,action="kick"?},
--            aura_remove {id,target="player"/"capture"},
--            ability_observed {id,label,target="capture",allowed={spell names},
--                noticeLifespan=seconds?}; records real casts, no future-cast guess.
--   Shared aura id + captured name distinguishes multiple simultaneous victims.
--   Any kick is allowed only for a fresh, positively identified live bot.
--   Razorgore presence means the boss has been actually observed ALIVE in BWL.
--   Absent/hidden => no egg icon; binding persists until confirmed death/reset.
--   Egg action sequence is structurally declared but FAILS CLOSED until the SCB
--   target owner implements genuine server target-update confirmation (Chunk 6).

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
                            { command = "come", scope = "target" },
                            { command = "object", scope = "all" },
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
                            kickLabel = "Kick",
                        },
                    },
                },
                {
                    events = { "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE" },
                    pattern = "^(.+) is afflicted by Burning Adrenaline%.$",
                    effects = {
                        {
                            type = "aura_apply",
                            id = "burning",
                            target = "capture",
                            label = "Burning Adrenaline",
                            duration = 20,
                            action = "kick",
                            kickLabel = "Kick",
                        },
                    },
                },
                {
                    events = { "CHAT_MSG_SPELL_AURA_GONE_SELF", "CHAT_MSG_SPELL_AURA_GONE_PARTY", "CHAT_MSG_SPELL_AURA_GONE_OTHER" },
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
                    events = { "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE" },
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
                    events = { "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE" },
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
                    events = { "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE" },
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
                    events = { "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE" },
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
        -- SoloCraft can expose 0, 1 or 2 breath types in a given week.
        -- This one generic observed-ability row learns ONLY an actual cast.
        -- Five entries are POTENTIAL source spell names, NOT expected slots.
        -- No forced first cast, breath rotation, cooldown or assumed second.
        chromaggus = {
            detect = {
                zone = "Blackwing Lair",
                boss = "Chromaggus",
            },
            mechanics = {},
            triggers = {
                {
                    event = "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
                    pattern = "^Chromaggus begins to cast (.+)%.$",
                    effects = {
                        {
                            type = "ability_observed",
                            id = "breaths",
                            label = "Breath observed",
                            target = "capture",
                            allowed = {
                                "Corrosive Acid",
                                "Frost Burn",
                                "Ignite Flesh",
                                "Incinerate",
                                "Time Lapse",
                            },
                            noticeLifespan = 3,
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
                            label = "Bellowing Roar - fear!",
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
                    events = { "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE" },
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
