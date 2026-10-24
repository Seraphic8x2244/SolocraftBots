"""Approved AQ40 timers and C'Thun all-bot StartAttack contract."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
E = (ROOT / "encounters.lua").read_text()
M = (ROOT / "mechanics.lua").read_text()

def encounter(name, following):
    return E.split("        " + name + " = {", 1)[1].split(
        "        " + following + " = {", 1)[0]


class ApprovedAQ40(unittest.TestCase):
    def test_kri_and_yauj_timers(self):
        trio = encounter("bugtrio", "sartura")
        self.assertIn("Poison Volley", trio)
        self.assertIn("firstDelay = 8, repeatDelay = 8", trio)
        self.assertIn("firstDelay = 10, repeatDelay = 20", trio)
        self.assertIn('id = "greatheal"', trio)
        self.assertIn("castTime = 2", trio)
        for spell, delay in (("Kick", 5), ("Pummel", 4),
                             ("Shield Bash", 6), ("Counterspell", 10),
                             ("Earth Shock", 2), ("Spell Lock", 6)):
            self.assertIn(spell + " interrupts Princess Yauj's Great Heal", trio)
            self.assertIn("duration = " + str(delay), trio)
        self.assertIn("state.occurrence.observedStart", M)
        self.assertIn("no recent observed cast to interrupt", M)

    def test_sartura_only_whirlwind(self):
        sartura = encounter("sartura", "fankriss")
        self.assertEqual(sartura.count('id = "whirlwind"'), 1)
        self.assertIn("firstDelay = 8, repeatDelay = 5", sartura)
        self.assertIn('contains = "Battleguard Sartura gains Whirlwind."', sartura)
        self.assertIn('contains = "Whirlwind fades from Battleguard Sartura."', sartura)
        self.assertNotIn("Enrage", sartura)

    def test_ouro_explicit_ready_not_fake_submerge(self):
        ouro = encounter("ouro", "cthun")
        self.assertIn('id = "ourocycle"', ouro)
        self.assertIn("initialStages = {", ouro)
        self.assertIn('minDelay = 89, provenance = "predicted"', ouro)
        self.assertIn("firstDelay = 20.5, repeatDelay = 20.5", ouro)
        self.assertIn("firstDelay = 20, repeatDelay = 20", ouro)
        self.assertIn('contains = "Ground Rupture"', ouro)
        self.assertIn('castStages = {', ouro)
        self.assertIn('spellId = 26063', ouro)
        self.assertIn('sourceThreshold = "berserk"', ouro)
        self.assertIn('label = "Next Emerge (estimated)"', ouro)
        self.assertIn('function mechanics.ObserveDeclaredCastEvent(', M)
        self.assertIn('slot.progressState.instanceID == casterGuid', M)
        self.assertIn('castType ~= "CAST"', M)

    def test_cthun_attack_all_is_explicit_and_scoped(self):
        cthun = encounter("cthun", "sentinels")
        self.assertIn("clickTarget = true, attackAll = true", cthun)
        self.assertIn('function mechanics.AttackNPCAll(key)', M)
        self.assertIn('SCB_RequestCommand("attackstart", "all")', M)
        self.assertIn('mechanics.NPCInstanceID("target") ~= guid', M)
        self.assertIn('SCB_GetTargetPropagationSettle()', M)
        self.assertIn("frame.scbAttackAllButton", M)
        self.assertIn("slot.attackAll and not slot.dead", M)
        self.assertNotIn('SCB_SendCommand("attackstart")', M)


if __name__ == "__main__":
    unittest.main()
