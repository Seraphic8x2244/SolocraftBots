"""Chunk 4 BWL declarations/lifecycle/scan integration contracts.

These assertions inspect source wiring; they are not Lua compilation or in-game tests.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
DATA = (ROOT / "encounters.lua").read_text(encoding="utf-8")
MECH = (ROOT / "mechanics.lua").read_text(encoding="utf-8")
TOC = (ROOT / "SoloCraftBots.toc").read_text(encoding="utf-8")
BWL = DATA.split("    bwl = {", 1)[1].split("    -- Chosen AQ40", 1)[0]

BOSSES = {
    "razorgore": ("Razorgore the Untamed", "combat"),
    "vaelastrasz": ("Vaelastrasz the Corrupt", "burningadrenaline"),
    "broodlord": ("Broodlord Lashlayer", "blastwave"),
    "firemaw": ("Firemaw", "casts"),
    "ebonroc": ("Ebonroc", "casts"),
    "flamegor": ("Flamegor", "casts"),
    "chromaggus": ("Chromaggus", "breaths"),
    "nefarian": ("Nefarian", "casts"),
}


def section(key):
    return BWL.split("        " + key + " = {", 1)[1].split("\n        },", 1)[0]


class BWLModuleMigration(unittest.TestCase):
    def test_all_eight_encounters_have_active_lifecycle_and_scan(self):
        self.assertEqual(len(re.findall(r"^        [a-z]+ = \\{", BWL, re.M)), 8)
        for key, (boss, submodule) in BOSSES.items():
            with self.subTest(boss=key):
                entry = section(key)
                self.assertIn('requiredZone = "Blackwing Lair"', entry)
                self.assertIn('moduleWaker = "' + boss + '"', entry)
                self.assertIn("passiveModules =", entry)
                self.assertIn("combatModules =", entry)
                self.assertIn('scan = { observations = { identity = true } }', entry)
                self.assertIn('id = "' + submodule + '"', entry)
                self.assertIn('name = "' + boss + '", count = 1', entry)

    def test_razorgore_still_requires_positive_presence(self):
        egg = section("razorgore")
        self.assertIn('id = "eggbreaker"', egg)
        self.assertIn('submodule = "eggbreaker"', egg)
        self.assertIn('when = "present"', egg)
        self.assertNotIn("prepareInZone = true", egg)
        self.assertIn('{ command = "come", scope = "target" }', egg)
        self.assertIn('{ command = "object", scope = "all" }', egg)

    def test_vael_pre_pull_and_postdeath_retention(self):
        vael = section("vaelastrasz")
        self.assertIn('id = "engagetimer"', vael)
        self.assertEqual(vael.count('submodule = "engagetimer"'), 3)
        self.assertIn('duration = 36', vael)
        self.assertIn('duration = 26', vael)
        self.assertIn('duration = 10', vael)
        self.assertIn('submodule = "burningadrenaline"', vael)
        self.assertIn('retainUntilResolved = true', vael)
        self.assertIn('trackerEmpty = "BurningAdrenalineTracker"', vael)
        self.assertEqual(vael.count('retainAfterBossDeath = true'), 2)
        self.assertEqual(vael.count('action = "kick"'), 2)
        self.assertIn('retained.action["kick:" .. slot.key] = true', MECH)
        self.assertIn('session.retainedActions[actionKey]', MECH)

    def test_timers_remain_scoped_to_combat_modules(self):
        for key in ("broodlord", "firemaw", "ebonroc", "flamegor",
                    "chromaggus", "nefarian"):
            entry = section(key)
            sub = BOSSES[key][1]
            ids = re.findall(r'id = "([a-z]+)", submodule = "' + sub + r'"', entry)
            self.assertEqual(len(ids), 1 if key in ("broodlord", "chromaggus") else 2)

    def test_shared_request_lifetime_and_old_scanner(self):
        for snippet in (
            "BeginEncounterScanRequests(active)",
            "CancelEncounterScanRequests(old.generation)",
            "CancelEncounterScanRequests(session.generation)",
            'duration = "combat", encounter = session.id',
            "submodule = sub.id",
            "dispatchDeclaredHP = scan.dispatchDeclaredHP",
            'mechanics.ObserveBoss(zone, observation.name, "dead", "unit")',
            "if raid and raid.wakers[name] and not dead then",
            "bossModsPollElapsed >= 0.4",
            "SCB_BossModsObserveTargets()",
        ):
            self.assertIn(snippet, MECH)
        self.assertIn("## Version: 0.9.93-dev", TOC)


if __name__ == "__main__":
    unittest.main()
