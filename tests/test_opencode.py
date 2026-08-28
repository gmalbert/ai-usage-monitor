from __future__ import annotations

import unittest
from unittest.mock import patch

from providers.opencode import OpenCodeGoProvider
from usage import SchemaError


class OpenCodeTests(unittest.TestCase):
    @patch("providers.opencode.get_json")
    def test_normalizes_all_windows(self, get_json):
        get_json.return_value = {"usage": {key: {"percent": percent, "resetsAt": "2026-09-01T12:00:00Z"} for key, percent in (("rolling", 0), ("weekly", 1), ("monthly", 14))}}
        usage = OpenCodeGoProvider("test-key").fetch()
        self.assertEqual(usage.monthly.remaining_percent, 86)

    @patch("providers.opencode.get_json")
    def test_missing_monthly_is_rejected(self, get_json):
        get_json.return_value = {"usage": {"rolling": {"percent": 0, "resetsAt": "2026-09-01T12:00:00Z"}, "weekly": {"percent": 1, "resetsAt": "2026-09-01T12:00:00Z"}}}
        with self.assertRaises(SchemaError): OpenCodeGoProvider("test-key").fetch()
