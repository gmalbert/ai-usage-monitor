from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

from config import app_data_dir
from models import ProviderStatus, ProviderUsage, UsageWindow, usage_to_dict


def _window(value: dict | None) -> UsageWindow | None:
    if not value:
        return None
    value = dict(value)
    if value.get("reset_at"):
        value["reset_at"] = datetime.fromisoformat(value["reset_at"])
    return UsageWindow(**value)


def _usage(value: dict) -> ProviderUsage:
    value = dict(value)
    value["fetched_at"] = datetime.fromisoformat(value["fetched_at"])
    value["status"] = ProviderStatus(value["status"])
    for key in ("five_hour", "weekly", "monthly"):
        value[key] = _window(value.get(key))
    return ProviderUsage(**value)


class UsageCache:
    def __init__(self, path: Path | None = None) -> None:
        self.path = path or app_data_dir() / "cache.json"

    def load(self) -> dict[str, ProviderUsage]:
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
            return {key: _usage(value) for key, value in raw.get("providers", {}).items()}
        except (OSError, ValueError, TypeError):
            return {}

    def save(self, values: dict[str, ProviderUsage]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps({"saved_at": datetime.now().astimezone().isoformat(), "providers": {key: usage_to_dict(value) for key, value in values.items()}}, indent=2), encoding="utf-8")
