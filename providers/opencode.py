from __future__ import annotations

import os
import json
from datetime import datetime
from pathlib import Path

from credential_store import load_opencode_key
from models import ProviderStatus, ProviderUsage
from providers.base import UsageProvider
from providers.http import get_json
from usage import SchemaError, local_from_iso, window_from_percent

OPENCODE_USAGE_URL = "https://opencode.ai/zen/go/v1/usage"


class OpenCodeGoProvider(UsageProvider):
    key = "opencode"

    def __init__(self, api_key: str | None = None) -> None:
        self.api_key = api_key

    @staticmethod
    def _stored_api_key() -> str | None:
        """Use a pre-existing OpenCode credential store when its common JSON layout is present."""
        candidates = (Path.home() / ".config" / "opencode" / "auth.json", Path.home() / ".local" / "share" / "opencode" / "auth.json")
        for path in candidates:
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                continue
            for key in ("apiKey", "api_key", "token"):
                value = data.get(key) if isinstance(data, dict) else None
                if isinstance(value, str) and value:
                    return value
        return None

    def fetch(self) -> ProviderUsage:
        api_key = self.api_key or os.environ.get("OPENCODE_GO_API_KEY") or load_opencode_key() or self._stored_api_key()
        if not api_key:
            raise ValueError("OpenCode Go API key is missing. Use the tray menu to add it or set OPENCODE_GO_API_KEY.")
        payload = get_json(OPENCODE_USAGE_URL, api_key)
        usage = payload.get("usage")
        if not isinstance(usage, dict):
            raise SchemaError("OpenCode Go usage API format changed. Provider adapter needs updating.")
        def make(key: str, name: str):
            value = usage.get(key)
            if not isinstance(value, dict) or "percent" not in value or "resetsAt" not in value:
                raise SchemaError("OpenCode Go usage API format changed. Provider adapter needs updating.")
            return window_from_percent(name, value["percent"], local_from_iso(value["resetsAt"], f"usage.{key}.resetsAt"))
        return ProviderUsage("OpenCode Go", "Go", ProviderStatus.OK, make("rolling", "5-hour"), make("weekly", "Weekly"), make("monthly", "Monthly"), datetime.now().astimezone())
