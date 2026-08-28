from __future__ import annotations

import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from providers.http import ProviderHTTPError, get_json


class HttpTests(unittest.TestCase):
    @patch("providers.http.urlopen")
    def test_401_is_sanitized(self, urlopen):
        urlopen.side_effect = HTTPError("https://example.test", 401, "Unauthorized", {}, None)
        with self.assertRaisesRegex(ProviderHTTPError, "HTTP 401"):
            get_json("https://example.test", "never-print-me")

    @patch("providers.http.urlopen")
    def test_429_is_sanitized(self, urlopen):
        urlopen.side_effect = HTTPError("https://example.test", 429, "Rate limited", {}, None)
        with self.assertRaisesRegex(ProviderHTTPError, "HTTP 429"):
            get_json("https://example.test", "never-print-me")

    @patch("providers.http.urlopen")
    def test_identifies_local_monitor(self, urlopen):
        urlopen.return_value.__enter__.return_value.read.return_value = b"{}"
        get_json("https://example.test", "never-print-me")
        request = urlopen.call_args.args[0]
        self.assertEqual(request.get_header("User-agent"), "AIUsageMonitor/1.0")
