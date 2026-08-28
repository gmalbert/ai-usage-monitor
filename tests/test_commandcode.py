from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from providers.commandcode import CommandCodeProvider
from usage import SchemaError


class CommandCodeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.auth = Path(self.temp.name) / "auth.json"
        self.auth.write_text(json.dumps({"apiKey": "test-key"}), encoding="utf-8")

    def tearDown(self): self.temp.cleanup()

    def responses(self, plan="individual-goat", org=True):
        return iter([
            {"org": {"id": "org-1"} if org else None},
            {"windowLimits": {"fiveHour": {"used": 1, "cap": 10, "resetAt": 1_700_000_000_000}, "weekly": {"used": 2, "cap": 20, "resetAt": 1_700_000_000_000}}},
            {"data": {"planId": plan, "status": "active", "currentPeriodStart": "2026-08-01", "currentPeriodEnd": 1_700_000_000_000}},
            {"totalMonthlyCredits": 7, "periodBasis": "billing-period"},
        ])

    @patch("providers.commandcode.get_json")
    def test_normalizes_credits_and_plan(self, get_json):
        get_json.side_effect = self.responses()
        usage = CommandCodeProvider(self.auth).fetch()
        self.assertEqual(usage.plan, "GOAT")
        self.assertEqual(usage.monthly.remaining, 63)
        self.assertEqual(usage.five_hour.remaining_percent, 90)

    @patch("providers.commandcode.get_json")
    def test_omits_missing_org_id(self, get_json):
        get_json.side_effect = self.responses(org=False)
        CommandCodeProvider(self.auth).fetch()
        self.assertNotIn("orgId", get_json.call_args_list[-1].args[2])

    @patch("providers.commandcode.get_json")
    def test_unknown_plan_is_rejected(self, get_json):
        get_json.side_effect = self.responses(plan="new-plan")
        with self.assertRaises(SchemaError): CommandCodeProvider(self.auth).fetch()
