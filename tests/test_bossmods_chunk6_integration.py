"""Full six-chunk Boss Mods source integration contract.

These checks are source assertions. They do not simulate a game client or
replace the vendored Lua 5.0.3 compiler and in-game validation.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "SoloCraftBots.lua").read_text()
MECH = (ROOT / "mechanics.lua").read_text()
DATA = (ROOT / "encounters.lua").read_text()
TOC = (ROOT / "SoloCraftBots.toc").read_text()

class IntegratedBossModsContract(unittest.TestCase):
    def test_complete_zone_hierarchy(self):
        bwl = DATA.split("    bwl = {", 1)[1].split("    -- Chosen AQ40", 1)[0]
        aq = DATA.split("    aq40 = {", 1)[1]
        self.assertEqual(len(re.findall(r"^        [a-z]+ = \{", bwl, re.M)), 8)
        self.assertEqual(len(re.findall(r"^        [a-z]+ = \{", aq, re.M)), 11)
        for chunk in (bwl, aq):
            self.assertIn("moduleWaker =", chunk)
            self.assertIn("moduleSleeper =", chunk)
            self.assertIn("combatModules =", chunk)

    def test_single_owner_and_idle_scanner(self):
        self.assertNotIn("SCB_BossMods", MAIN)
        self.assertEqual(MECH.count('bossModsFrame:SetScript("OnUpdate"'), 1)
        self.assertIn("engine.TickRaidTargetScanner(elapsed)", MECH)
        self.assertIn("if not next(raidTargetScanner.requests) then", MECH)
        for obsolete in ("bossModsPollElapsed", "SCB_BossModsGroupCombat",
                         "SCB_BossModsObserveTargets"):
            self.assertNotIn(obsolete, MECH)
        self.assertIn('duration = "fixed", seconds = 5', MECH)

    def test_sentinel_complete_combat_lifecycle(self):
        d = DATA.split("        sentinels = {", 1)[1].split("        defender = {", 1)[0]
        self.assertIn('marker = true', d)
        self.assertIn('buffs = true', d)
        self.assertIn('dispatchDeclaredHP = false', d)
        self.assertIn('name = "Anubisath Sentinel", count = 4', d)
        for mark in ('function mechanics.BeginSentinelAttempt(',
                     'AcquirePresentation("hp", "sentinel:slot:" .. i)',
                     'GetRaidTargetIndex(unit) == slot.sentinelMark',
                     'function mechanics.ObserveSentinelSnapshot(',
                     'function mechanics.ObserveSentinelDeathMessage(',
                     'SentinelRecomputeInheritance(state)',
                     'entry.nearDeath = entry.lastPct <= 0.01',
                     'session.sentinelState = nil'):
            self.assertIn(mark, MECH)
        self.assertIn("math.max(corpses, state.messages)", MECH)

    def test_vael_postdeath_kick_survives(self):
        bwl = DATA.split("    bwl = {", 1)[1].split("    -- Chosen AQ40", 1)[0]
        self.assertIn('trackerEmpty = "BurningAdrenalineTracker"', bwl)
        self.assertIn('retainAfterBossDeath = true', bwl)
        self.assertIn('retained.action["kick:" .. slot.key] = true', MECH)
        self.assertIn("active.retainedActions[slot.key]", MECH)

    def test_compatibility_boundary(self):
        self.assertIn("## Interface: 11200", TOC)
        self.assertRegex(TOC, r"## Version: 0\.9\.\d+-dev")
        self.assertIn("local function SentinelState()", MECH)
        self.assertNotIn("function SCB_BossMods", MAIN)
        self.assertNotIn('SetScript("OnUpdate"', DATA)

if __name__ == "__main__":
    unittest.main()
