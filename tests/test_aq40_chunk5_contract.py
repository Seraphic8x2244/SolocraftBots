"""AQ40 Chunk 5 static source-contract tests.

Execute from a checkout with: python3 -m unittest discover -s tests
These assertions are NOT WoW 1.12.1 runtime, Lua compiler or source-event
confirmation. Unknown signals deliberately remain undocumented as facts.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MECH = (ROOT / "mechanics.lua").read_text()
ENCOUNTERS = (ROOT / "encounters.lua").read_text()
OWNER = (ROOT / "SoloCraftBots.lua").read_text()
TOC = (ROOT / "SoloCraftBots.toc").read_text()
AQ = ENCOUNTERS.split("    aq40 = {", 1)[1]


class AQ40Chunk5Contract(unittest.TestCase):
    def test_bwl_and_zone_owner_survive(self):
        self.assertIn('bwl = {', ENCOUNTERS)
        self.assertIn('zone = "Blackwing Lair"', ENCOUNTERS)
        self.assertIn('moduleLifecycle.raids[zone]', MECH)
        self.assertIn('zone = "Ahn\'Qiraj"', ENCOUNTERS)
        self.assertIn('engine.ObserveDeclaredUnits(tokens, state.generation)', MECH)
        self.assertIn('bossModsEvents[bossModsZone][event]', MECH)
        self.assertIn('SetScript("OnUpdate"', MECH)
        self.assertNotIn('SCB_BossMods', OWNER)

    def test_declaration_and_alias_guards(self):
        self.assertIn('local function CheckObservedUnits(d)', MECH)
        self.assertIn('or not CheckObservedUnits(d)', MECH)
        self.assertIn('function mechanics.CanonicalBoss(zone, boss)', MECH)
        self.assertIn('aliases = { "Princess Yauj", "Vem" }', AQ)
        self.assertIn('aliases = { "Emperor Vek\'nilash" }', AQ)
        self.assertIn('aliases = { "Eye of C\'Thun" },', AQ)
        cthun = AQ.split('        cthun = {', 1)[1].split('        sentinels = {', 1)[0]
        self.assertIn('endOnBossDeath = false', cthun)
        self.assertIn('aliases = { "Eye of C\'Thun" },', cthun)

    def test_yauj_ready_requires_observed_interrupt(self):
        trio = AQ.split('        bugtrio = {', 1)[1].split('        sartura = {', 1)[0]
        self.assertIn('readyLabel = "Heal Ready"', trio)
        self.assertIn('type = "ability_lockout"', trio)
        self.assertIn('ability = "greatheal"', trio)
        self.assertIn('firstDelay = 10, repeatDelay = 20', trio)
        self.assertIn('castTime = 2', trio)
        self.assertNotIn('id = "greatheal", caster = "Princess Yauj",\n                    label = "Great Heal", mode = "opportunistic",\n                    castTime = 2, repeatDelay', trio)

    def test_individual_hp_death_and_target_guards(self):
        for creature in ("Anubisath Sentinel", "Sartura's Royal Guard",
                         "Princess Yauj", "Flesh Tentacle"):
            self.assertIn(creature, AQ)
        self.assertIn("mechanics.NPCInstanceID(unit)", MECH)
        self.assertIn("slot.instanceID", MECH)
        self.assertIn("clickTarget = true", AQ)
        self.assertIn("hideOnDeath = true", AQ)
        self.assertIn("endOnBossDeath = false", AQ)

    def test_thresholds_have_no_fabricated_etas(self):
        self.assertIn("threshold = 0.30", AQ)
        self.assertIn("threshold = 0.20", AQ)
        self.assertIn('frame.detail:SetText("?")', MECH)
        self.assertIn("mechanics.ObserveHPThreshold(", MECH)

    def test_partial_hits_do_not_assert_complete_counts(self):
        self.assertIn("maximum = 200, maximumKind = \"reference\"", AQ)
        self.assertIn("maximum = 110, maximumKind = \"reference\"", AQ)
        self.assertIn('type = "counter_hit"', AQ)
        self.assertIn('observedOnly = true', AQ)
        self.assertIn('frame.detail:SetText("Observed")', MECH)
        self.assertIn('cooldown not established', MECH)
        self.assertNotIn('repeatDelay = 600', AQ)

    def test_defender_dev_only_recorder_is_opt_in(self):
        self.assertIn('function mechanics.RecordDefenderHit(', MECH)
        self.assertIn('active.id ~= "aq40.defender"', MECH)
        self.assertIn('db.bossModDefenderRecord ~= true', MECH)
        self.assertIn('string.find(version, "%-dev$")', MECH)
        self.assertIn('if id and id ~= slot.instanceID then', MECH)
        self.assertIn('SLASH_SCBDEFENDER1 = "/scbdefender"', MECH)
        self.assertIn('table.getn(samples) > 200', MECH)
        self.assertEqual(AQ.count('type = "dev_interval"'), 4)

    def test_defender_sampling_rejects_unseen_second_live_instance(self):
        section = MECH.split('function mechanics.RecordDefenderHit(', 1)[1].split('-- Only dev builds expose', 1)[0]
        self.assertIn('and not slot.dead then', section)
        self.assertIn('if id and id ~= slot.instanceID then', section)
        self.assertIn('candidate = slot', section)
        self.assertIn('mechanics.NPCInstanceID(candidate.unit) ~= id', section)
        self.assertNotIn('and mechanics.NPCInstanceID(slot.unit) == slot.instanceID then', section)

    def test_no_hidden_generated_command_path(self):
        self.assertIn('SCB_RequestCommand(commandStep.command, commandStep.scope)', MECH)
        self.assertNotIn('SCB_RequestCommand(', AQ)
        self.assertNotIn('SetRaidTarget(', AQ)
        self.assertNotIn('SetScript("OnUpdate"', AQ)

    def test_recipient_action_requires_exact_live_observed_aura(self):
        section = MECH.split('local function BoundActionAvailable(slot)', 1)[1]
        section = section.split('local function ActionForMember', 1)[0]
        self.assertIn('if condition.observedAura then', section)
        self.assertIn('auraSlot.key == condition.observedAura', section)
        self.assertIn('auraSlot.generation == active.generation', section)
        self.assertIn('auraSlot.memberBinding == config.binding', section)
        self.assertIn('auraSlot.target == name', section)
        self.assertIn('Now() < auraSlot.expiresAt', section)
        self.assertIn('if not observed then return false end', section)
        validation = MECH.split('function mechanics.ShowBoundBotAction', 1)[1]
        self.assertIn('type(c.observedAura) ~= "string"', validation)
        click = MECH.split('function mechanics.HandleActionClick', 1)[1]
        self.assertIn('if not BoundActionAvailable(slot) then', click)

    def test_observed_finish_deduplicates_only_exact_positive_event_identity(self):
        section = MECH.split('function mechanics.ObserveAbilityFinish(', 1)[1].split('function mechanics.ObserveAbilityInterrupt(', 1)[0]
        self.assertIn('state.lastFinishObservationId == observationId', section)
        self.assertIn('return true, "duplicate observation"', section)
        self.assertIn('state.lastFinishObservationId = observationId', section)
        self.assertIn('return false, "invalid observation identity"', section)
        self.assertNotIn('observationId or', section)
        dispatch = MECH.split('local function Deliver(spec, isGroup)', 1)[1].split('-- Per-recipient auras', 1)[0]
        self.assertIn('details and details.observationId', dispatch)
        self.assertIn('mechanics.ObserveAbilityFinish(spec.id,', dispatch)

    def test_version_is_dev(self):
        self.assertRegex(TOC, r'## Version: 0\.9\.\d+-dev')


if __name__ == "__main__":
    unittest.main()
