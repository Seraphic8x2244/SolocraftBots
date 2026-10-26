"""Regression assertions for the complete Boss Mods ownership extraction.

Static source checks, not Lua compilation or in-game validation.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "SoloCraftBots.lua").read_text(encoding="utf-8")
MECH = (ROOT / "mechanics.lua").read_text(encoding="utf-8")
TOC = (ROOT / "SoloCraftBots.toc").read_text(encoding="utf-8")

class BossModsOwnerExtraction(unittest.TestCase):
    def test_main_is_general_purpose_only(self):
        for marker in ("SCB_BossMods", "bossModsZone", "bossModsEvents",
                       "bossModDefinitions", "options.bossMods"):
            self.assertNotIn(marker, MAIN)
        self.assertIn('eventFrame:SetScript("OnEvent"', MAIN)
        self.assertIn('SCB_RefreshTargetCommandRow()', MAIN)
        self.assertIn('SCB_HandleRosterChange()', MAIN)

    def test_single_module_frame_and_load_order(self):
        self.assertEqual(MECH.count('SoloCraftBotsBossModsEventFrame'), 1)
        self.assertEqual(MECH.count('bossModsFrame:SetScript("OnEvent"'), 1)
        self.assertEqual(MECH.count('bossModsFrame:SetScript("OnUpdate"'), 1)
        self.assertIn('bossModsFrame:RegisterEvent("PLAYER_LOGIN")', MECH)
        self.assertIn('SCB_BossModsInitialize()\n        SCB_BossModsRefreshZone()', MECH)
        self.assertLess(TOC.index("mechanics.lua"), TOC.index("encounters.lua"))
        self.assertRegex(TOC, r"## Version: 0\.9\.\d+-dev")

    def test_retired_scan_group_combat_and_render_cadences(self):
        for marker in ('SCB_BossModsCompleteSweep()',
                       'bossModsElapsed >= 0.10',
                       'bossModsVisualElapsed >= (1 / 30)',
                       'mechanics.ObserveDeclaredUnits({ unit }, active.generation)',
                       'SCB_BossModsTrackCombatState(true)',
                       'raidTargetScanner.calm >= 2',
                       'mechanics.DisengageEncounter("raid disengaged", state.generation)',
                       'engine.ObserveBossDeathMessage(',
                       'engine.ObserveDeclaredCastEvent(',
                       'engine.UpdateTimers(now)',
                       'engine.UpdatePresentationState(now)',
                       'engine.UpdatePresentation(GetTime and GetTime() or 0)'):
            self.assertIn(marker, MECH)

    def test_zone_and_optional_cast_event_ownership(self):
        for marker in ('pcall(bossModsFrame.RegisterEvent, bossModsFrame, eventName)',
                       'pcall(bossModsFrame.UnregisterEvent, bossModsFrame, eventName)',
                       'engine.Reset("zone exit")',
                       'bossModsFrame:RegisterEvent("ZONE_CHANGED")',
                       'bossModsFrame:RegisterEvent("ZONE_CHANGED_INDOORS")',
                       'bossModsFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")',
                       'bossModsFrame:RegisterEvent("PLAYER_ENTERING_WORLD")'):
            self.assertIn(marker, MECH)

    def test_options_defaults_migrated(self):
        for key in ("bossModsShowPlayerName", "bossModsShowAuraName",
                    "bossModsTimersExpandUp", "bossModsTrackerExpandUp"):
            self.assertIn("options." + key, MECH)
            self.assertNotIn("options." + key, MAIN)

if __name__ == "__main__":
    unittest.main()
