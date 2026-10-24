"""Static regression contract for the generic Action Widget extension.

Run with: python -m unittest discover -s tests -p 'test_*_contract.py'
These checks do not substitute for WoW 1.12.1 runtime testing.
"""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "mechanics.lua").read_text()


class ActionWidgetContract(unittest.TestCase):
    def test_command_ownership(self):
        self.assertIn("SCB_RequestCommand(commandStep.command, commandStep.scope)", SOURCE)
        self.assertIn("SCB_GetTargetPropagationSettle()", SOURCE)
        self.assertIn("mechanics.ScheduleTimer(timerName, settle", SOURCE)
        self.assertIn("bindings[bindingKey] ~= originalBinding", SOURCE)

    def test_conditions_fail_closed(self):
        self.assertIn("local function BoundActionAvailable(slot)", SOURCE)
        self.assertIn('condition.recipient == "bot" and not bot', SOURCE)
        self.assertIn('condition.recipient == "human" and bot', SOURCE)
        self.assertIn('condition.target == "bound"', SOURCE)
        self.assertIn('return false, "action condition not met"', SOURCE)

    def test_role_resolution_and_validation(self):
        self.assertIn("local function ActionForMember(config, member)", SOURCE)
        self.assertIn("member.confirmedRole or member.assumedRole or member.role", SOURCE)
        self.assertIn('config.action.type == "by_role"', SOURCE)
        self.assertIn('return false, "invalid role action"', SOURCE)
        self.assertIn('return false, "no action for recipient role"', SOURCE)

    def test_disabled_and_hidden_ui(self):
        self.assertIn("config.hideWhenUnavailable and not available", SOURCE)
        self.assertIn("slot.frame:SetAlpha(available and 1 or 0.4)", SOURCE)
        self.assertIn('not available and "Unavailable"', SOURCE)

    def test_retention_and_repeat_clicks(self):
        self.assertIn("function mechanics.RetainBoundActionAfterAura(key, seconds)", SOURCE)
        self.assertIn("Now() + seconds", SOURCE)
        self.assertIn("sequenceSerial = sequenceSerial + 1", SOURCE)
        self.assertIn("slot.expiresAt and now >= slot.expiresAt", SOURCE)

    def test_existing_bwl_paths_remain(self):
        self.assertIn('if config.action and config.action.type == "kick"', SOURCE)
        self.assertIn('SCB_KickBots("all", { name = name })', SOURCE)
        self.assertIn('mechanics.BindSelectedBot(cfg.binding, active.generation)', SOURCE)


if __name__ == "__main__":
    unittest.main()
