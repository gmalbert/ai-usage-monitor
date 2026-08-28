from __future__ import annotations

import json
import os
from datetime import datetime
from pathlib import Path

from models import ProviderStatus, ProviderUsage
from providers.base import UsageProvider
from providers.http import get_json
from usage import SchemaError, window_from_used_and_cap

COMMANDCODE_BASE_URL = "https://api.commandcode.ai"
COMMANDCODE_PLAN_CREDITS = {"individual-go": 10, "individual-provider": 15, "individual-pro": 30, "teams-pro": 40, "individual-goat": 70, "individual-pro-v1": 80, "individual-max": 150, "individual-ultra": 300}


class CommandCodeProvider(UsageProvider):
    key = "commandcode"

    def __init__(self, auth_path: Path | None = None) -> None:
        self.auth_path = auth_path or Path(os.environ.get("USERPROFILE", str(Path.home()))) / ".commandcode" / "auth.json"

    def _token(self) -> str:
        try:
            token = json.loads(self.auth_path.read_text(encoding="utf-8")).get("apiKey")
        except (OSError, ValueError) as exc:
            raise ValueError("CommandCode authentication file is missing or invalid") from exc
        if not isinstance(token, str) or not token.strip():
            raise ValueError("CommandCode authentication file has no apiKey")
        return token

    def fetch(self) -> ProviderUsage:
        token = self._token()
        whoami = get_json(f"{COMMANDCODE_BASE_URL}/alpha/whoami", token)
        credits = get_json(f"{COMMANDCODE_BASE_URL}/alpha/billing/credits", token)
        subscription = get_json(f"{COMMANDCODE_BASE_URL}/alpha/billing/subscriptions", token)
        data = subscription.get("data")
        if not isinstance(data, dict):
            raise SchemaError("CommandCode subscription is missing")
        period_start, period_end, plan_id = data.get("currentPeriodStart"), data.get("currentPeriodEnd"), data.get("planId")
        if not isinstance(plan_id, str) or plan_id not in COMMANDCODE_PLAN_CREDITS:
            raise SchemaError("Unknown CommandCode plan ID")
        org = whoami.get("org") if isinstance(whoami.get("org"), dict) else None
        params = {"since": period_start}
        if org and org.get("id"):
            params["orgId"] = org["id"]
        summary = get_json(f"{COMMANDCODE_BASE_URL}/alpha/usage/summary", token, params)
        windows = credits.get("windowLimits")
        if not isinstance(windows, dict):
            raise SchemaError("CommandCode API format changed: windowLimits is missing")
        five, weekly = windows.get("fiveHour"), windows.get("weekly")
        if not isinstance(five, dict) or not isinstance(weekly, dict):
            raise SchemaError("CommandCode API format changed: rolling windows are missing")
        monthly_used, cap = summary.get("totalMonthlyCredits"), COMMANDCODE_PLAN_CREDITS[plan_id]
        monthly = window_from_used_and_cap("Monthly", monthly_used, cap, period_end)
        return ProviderUsage("CommandCode", plan_id.removeprefix("individual-").upper(), ProviderStatus.OK,
            window_from_used_and_cap("5-hour", five.get("used"), five.get("cap"), five.get("resetAt")),
            window_from_used_and_cap("Weekly", weekly.get("used"), weekly.get("cap"), weekly.get("resetAt")), monthly, datetime.now().astimezone())
