"""Non-secret application configuration and Windows paths."""
from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass
from pathlib import Path


APP_NAME = "AIUsageMonitor"
HTTP_TIMEOUT_SECONDS = 10
DEFAULT_REFRESH_SECONDS = 300


def app_data_dir() -> Path:
    root = os.environ.get("LOCALAPPDATA") or os.environ.get("XDG_CACHE_HOME")
    return Path(root) / APP_NAME if root else Path.home() / ".cache" / APP_NAME


@dataclass
class Settings:
    refresh_seconds: int = DEFAULT_REFRESH_SECONDS
    warning_threshold: float = 50
    critical_threshold: float = 20
    start_with_windows: bool = False
    show_notifications: bool = True


def config_path() -> Path:
    return app_data_dir() / "config.json"


def load_settings() -> Settings:
    try:
        raw = json.loads(config_path().read_text(encoding="utf-8"))
        allowed = {key: raw[key] for key in Settings.__annotations__ if key in raw}
        return Settings(**allowed)
    except (OSError, ValueError, TypeError):
        return Settings()


def save_settings(settings: Settings) -> None:
    path = config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(asdict(settings), indent=2), encoding="utf-8")
