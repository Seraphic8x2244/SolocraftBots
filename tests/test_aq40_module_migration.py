"""Chunk 5 AQ40 migration and former broad-scan retirement checks (static only)."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
DATA = (ROOT / "encounters.lua").read_text(encoding="utf-8")
MECH = (ROOT / "mechanics.lua").read_text(encoding="utf-8")
BWL = DATA.split("    bwl = {", 1)[1].split("    -- Chosen AQ40", 1)[0]
AQ = DATA.split("    aq40 = {", 1)[1]
NAMES = ("skeram", "bugtrio", "sartura", "fankriss", "viscidus",
         "huhuran", "twins", "ouro", "cthun", "sentinels", "defender")

def section(name):
    return AQ.split("        " + name + " = {", 1)[1].split("\n        },", 1)[0]

class AQ40MigrationContract(unittest.TestCase):
    def test_all_eleven_registered_in_hierarchy_with_scanner(self):
        self.assertEqual(len(re.findall(r"^        [a-z]+ = \{", AQ, re.M)), 11)
        for key in NAMES:
            with self.subTest(encounter=key):
                part = section(key)
                for mark in ("requiredZone = \"Ahn'Qiraj\"", "moduleWaker =",
                             "passiveModules = {}", "combatModules =",
                             'id = "combat"', "scan = { observations = {",
                             "dispatchDeclaredHP = true"):
                    self.assertIn(mark, part)

    def test_group_sleepers_and_sentinel_deferred_scope(self):
        for key in ("bugtrio", "twins"):
            part = section(key)
            self.assertIn("moduleSleeper = { npcdead =", part)
            self.assertGreaterEqual(part.count("count = 1"), 2)
        self.assertIn('name = "Anubisath Sentinel", count = 4', section("sentinels"))
        self.assertIn("endOnBossDeath = false", section("skeram"))
        self.assertIn("endOnBossDeath = false", section("sentinels"))
        self.assertIn('name = "C\'Thun", count = 1', section("cthun"))

    def test_retired_scan_and_replacement_coverage(self):
        for mark in ('SCB_BossModsCompleteSweep()', 'SCB_BossModsTrackCombatState(true)',
                     'SCB_BossModsVisitScanToken(base .. "target")',
                     'mechanics.DisengageEncounter("raid disengaged", state.generation)',
                     'mechanics.ObserveModuleNPCDeath(bossModsZone, name, "unit")',
                     'engine.DispatchEvent(eventName, message, nil, state.generation)',
                     'bossModsFrame:RegisterEvent("UNIT_TARGET")',
                     'bossModsFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")',
                     'AQ40SkeramMark(observation)',
                     'AQ40OuroSubmerge(Now(), observed["Ouro"]'):
            self.assertIn(mark, MECH)
        for retired in ("bossModsPollElapsed", "SCB_BossModsObserveTargets",
                        "SCB_BossModsGroupCombat", "AQ40VisibleBoss"):
            self.assertNotIn(retired, MECH)
        self.assertEqual(MECH.count('bossModsFrame:SetScript("OnUpdate"'), 1)

    def test_bwl_retention_still_owned_by_same_engine(self):
        self.assertEqual(len(re.findall(r"^        [a-z]+ = \{", BWL, re.M)), 8)
        self.assertIn('trackerEmpty = "BurningAdrenalineTracker"', BWL)
        self.assertIn('retainAfterBossDeath = true', BWL)
        self.assertIn('retained.action["kick:" .. slot.key] = true', MECH)
        self.assertIn('active.retainedActions[slot.key]', MECH)

if __name__ == "__main__":
    unittest.main()
