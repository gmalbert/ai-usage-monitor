"""Provider-neutral models used by every presentation surface."""
from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime
from enum import Enum
from typing import Any


class ProviderStatus(str, Enum):
    OK = "ok"
    STALE = "stale"
    AUTH_ERROR = "auth_error"
    NETWORK_ERROR = "network_error"
    SCHEMA_ERROR = "schema_error"
    API_ERROR = "api_error"
    CODEX_NOT_INSTALLED = "codex_not_installed"
    NOT_LOGGED_IN = "not_logged_in"
    APP_SERVER_START_FAILED = "app_server_start_failed"
    APP_SERVER_PROTOCOL_ERROR = "app_server_protocol_error"
    RATE_LIMIT_DATA_UNAVAILABLE = "rate_limit_data_unavailable"
    STALE_LOG_FALLBACK = "stale_log_fallback"


@dataclass
class UsageWindow:
    name: str
    used_percent: float
    remaining_percent: float
    reset_at: datetime | None = None
    used: float | None = None
    cap: float | None = None
    remaining: float | None = None
    source_type: str = "usage_window"


@dataclass
class ProviderUsage:
    provider: str
    plan: str | None
    status: ProviderStatus
    five_hour: UsageWindow | None
    weekly: UsageWindow | None
    monthly: UsageWindow | None
    fetched_at: datetime
    stale: bool = False
    error: str | None = None
    credit_balance: float | None = None
    reset_credits_available: int | None = None

    def windows(self) -> list[UsageWindow]:
        return [window for window in (self.five_hour, self.weekly, self.monthly) if window]


def _serialize(value: Any) -> Any:
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, list):
        return [_serialize(item) for item in value]
    if isinstance(value, dict):
        return {key: _serialize(item) for key, item in value.items()}
    return value


def usage_to_dict(usage: ProviderUsage) -> dict[str, Any]:
    return _serialize(asdict(usage))
