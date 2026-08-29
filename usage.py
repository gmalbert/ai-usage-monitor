"""Normalization helpers shared by provider adapters and UIs."""
from __future__ import annotations

from datetime import datetime, timezone

from models import UsageWindow


class SchemaError(ValueError):
    """A provider response did not satisfy its versioned contract."""


def number(value: object, field: str) -> float:
    if isinstance(value, bool):
        raise SchemaError(f"{field} must be a number")
    try:
        return float(value)
    except (TypeError, ValueError) as exc:
        raise SchemaError(f"{field} must be a number") from exc


def percent(value: object, field: str) -> float:
    result = number(value, field)
    if not 0 <= result <= 100:
        raise SchemaError(f"{field} must be between 0 and 100")
    return result


def local_from_unix(value: object, field: str = "timestamp") -> datetime:
    if isinstance(value, str) and not value.replace(".", "", 1).isdigit():
        return local_from_iso(value, field)
    seconds = number(value, field)
    # CommandCode uses milliseconds; Codex uses seconds.
    if seconds > 10_000_000_000:
        seconds /= 1000
    try:
        return datetime.fromtimestamp(seconds, tz=timezone.utc).astimezone()
    except (OverflowError, OSError, ValueError) as exc:
        raise SchemaError(f"{field} is not a valid timestamp") from exc


def local_from_iso(value: object, field: str = "timestamp") -> datetime:
    if not isinstance(value, str):
        raise SchemaError(f"{field} must be an ISO-8601 timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise SchemaError(f"{field} is not a valid ISO-8601 timestamp") from exc
    if parsed.tzinfo is None:
        raise SchemaError(f"{field} must include a timezone")
    return parsed.astimezone()


def window_from_used_and_cap(name: str, used: object, cap: object, reset_at: object) -> UsageWindow:
    used_value, cap_value = number(used, f"{name}.used"), number(cap, f"{name}.cap")
    if cap_value <= 0:
        raise SchemaError(f"{name}.cap must be greater than zero")
    used_percent = max(0.0, min(100.0, used_value / cap_value * 100))
    return UsageWindow(name, used_percent, 100 - used_percent, local_from_unix(reset_at), used_value, cap_value, cap_value - used_value)


def window_from_percent(name: str, used_percent: object, reset_at: datetime | None) -> UsageWindow:
    used = percent(used_percent, f"{name}.percent")
    return UsageWindow(name, used, 100 - used, reset_at)


def format_local_time(value: datetime | None, verb: str = "Resets") -> str:
    if value is None:
        return ""
    rendered = value.strftime("%b %d, %I:%M %p").replace(" 0", " ")
    delta = value - datetime.now().astimezone()
    total_minutes = max(0, int(delta.total_seconds() // 60))
    days, remainder = divmod(total_minutes, 24 * 60)
    hours, minutes = divmod(remainder, 60)
    if days:
        if hours:
            relative = f"in {days}d {hours}h"
        else:
            relative = f"in {days}d"
    else:
        relative = f"in {hours}h {minutes}m" if hours else f"in {minutes}m"
    return f"{verb}: {rendered} · {relative}"
