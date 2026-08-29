from __future__ import annotations

import unittest
from datetime import datetime

from config import Settings
from models import ProviderStatus, ProviderUsage, UsageWindow
from service import UsageService
from ui.tray import TrayApplication


class TrayTooltipTests(unittest.TestCase):
    def test_tooltip_includes_monthly_remaining_percentage(self):
        service = UsageService([])
        service.values["commandcode"] = ProviderUsage(
            provider="CommandCode",
            plan="GOAT",
            status=ProviderStatus.OK,
            five_hour=UsageWindow("5h", 0, 90, used=1, cap=10, remaining=9),
            weekly=UsageWindow("Week", 0, 75, used=5, cap=20, remaining=15),
            monthly=UsageWindow("Monthly", 0, 60, used=40, cap=100, remaining=60),
            fetched_at=datetime.now().astimezone(),
        )

        tooltip = TrayApplication(service, Settings())._tooltip()

        self.assertIn("Month 60%", tooltip)
