from __future__ import annotations

import unittest

from usage import SchemaError, local_from_iso, window_from_used_and_cap


class NormalizationTests(unittest.TestCase):
    def test_zero_cap_is_rejected(self):
        with self.assertRaises(SchemaError):
            window_from_used_and_cap("Weekly", 0, 0, 1_700_000_000_000)

    def test_invalid_iso_is_rejected(self):
        with self.assertRaises(SchemaError):
            local_from_iso("not-a-time")

    def test_unix_normalizer_accepts_provider_iso_timestamp(self):
        self.assertIsNotNone(window_from_used_and_cap("Monthly", 1, 10, "2026-09-19T20:15:29.000Z").reset_at)
