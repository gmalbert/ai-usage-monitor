"""Codex adapter using the local app-server; it never reads OAuth credentials."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import threading
from datetime import datetime
from pathlib import Path
from queue import Empty, Queue

from models import ProviderStatus, ProviderUsage
from providers.base import UsageProvider
from usage import SchemaError, local_from_unix, number, window_from_percent


class CodexProvider(UsageProvider):
    key = "codex"

    def __init__(self, executable: str | None = None) -> None:
        self.executable = executable or self._find_executable()

    @staticmethod
    def _find_executable() -> str | None:
        """Find Codex on PATH or in the Codex desktop app's versioned Windows bundle."""
        if located := shutil.which("codex"):
            return located
        local_app_data = os.environ.get("LOCALAPPDATA")
        if not local_app_data:
            return None
        bundled_root = Path(local_app_data) / "OpenAI" / "Codex" / "bin"
        try:
            candidates = sorted(bundled_root.glob("*/codex.exe"), key=lambda path: path.stat().st_mtime, reverse=True)
        except OSError:
            return None
        return str(candidates[0]) if candidates else None

    def _read_response(self, process: subprocess.Popen[str], request_id: int) -> dict:
        assert process.stdout is not None
        queue: Queue[str] = Queue()
        reader = threading.Thread(target=lambda: [queue.put(line) for line in process.stdout], daemon=True)
        reader.start()
        try:
            while True:
                line = queue.get(timeout=12)
                value = json.loads(line)
                if value.get("id") == request_id:
                    if "error" in value:
                        raise SchemaError("Codex app-server returned an error")
                    return value.get("result", {})
        except Empty as exc:
            raise TimeoutError("Codex app-server timed out") from exc

    def _request(self, process: subprocess.Popen[str], request_id: int, method: str, params: dict | None = None) -> dict:
        assert process.stdin is not None
        message = {"jsonrpc": "2.0", "id": request_id, "method": method}
        if params is not None:
            message["params"] = params
        process.stdin.write(json.dumps(message) + "\n")
        process.stdin.flush()
        return self._read_response(process, request_id)

    @staticmethod
    def _field(value: dict, camel: str, snake: str):
        return value.get(camel, value.get(snake))

    def _normalize_limits(self, limits: dict, reset_credits: dict | None = None, stale: bool = False) -> ProviderUsage:
        """Normalize either the live app-server payload or Codex's local rollout record."""
        mapped: dict[str, object] = {}
        for item in (limits.get("primary"), limits.get("secondary")):
            if not isinstance(item, dict):
                continue
            minutes = self._field(item, "windowDurationMins", "window_minutes")
            if minutes is None:
                continue
            duration = number(minutes, "windowDurationMins")
            used = self._field(item, "usedPercent", "used_percent")
            reset_at = self._field(item, "resetsAt", "resets_at")
            if 270 <= duration <= 330:
                mapped["five_hour"] = window_from_percent("5-hour", used, local_from_unix(reset_at))
            elif 9000 <= duration <= 11000:
                mapped["weekly"] = window_from_percent("Weekly", used, local_from_unix(reset_at))
        if not mapped:
            raise SchemaError("Codex rate-limit data contains no recognized windows")
        individual = limits.get("individualLimit", limits.get("individual_limit"))
        monthly = None
        if isinstance(individual, dict):
            remaining_percent = number(self._field(individual, "remainingPercent", "remaining_percent"), "individualLimit.remainingPercent")
            used, cap = number(individual.get("used"), "individualLimit.used"), number(individual.get("limit"), "individualLimit.limit")
            monthly = window_from_percent("Monthly", 100 - remaining_percent, local_from_unix(self._field(individual, "resetsAt", "resets_at")))
            monthly.used, monthly.cap, monthly.remaining = used, cap, cap - used
        credits = limits.get("credits") if isinstance(limits.get("credits"), dict) else {}
        balance = credits.get("balance")
        reset_credits = reset_credits or {}
        return ProviderUsage("Codex", str(limits.get("planType", limits.get("plan_type", "Codex"))).title(),
            ProviderStatus.STALE if stale else ProviderStatus.OK, mapped.get("five_hour"), mapped.get("weekly"), monthly,
            datetime.now().astimezone(), stale=stale, error="Latest local Codex session record; live refresh unavailable." if stale else None,
            credit_balance=float(balance) if balance not in (None, "") else None,
            reset_credits_available=reset_credits.get("availableCount", reset_credits.get("available_count")))

    def _fetch_app_server(self) -> ProviderUsage:
        if not self.executable:
            raise FileNotFoundError("Codex is not installed or not on PATH")
        # The desktop app establishes HOME itself, but a PyInstaller process may not.
        # Codex uses HOME to find its login and app-server configuration on Windows.
        environment = os.environ.copy()
        user_home = environment.get("USERPROFILE") or str(Path.home())
        if os.name == "nt":
            environment["HOME"] = user_home
            environment.setdefault("USERPROFILE", user_home)
        popen_options: dict = {}
        if os.name == "nt":
            # A windowed PyInstaller app would otherwise flash a blank console every refresh.
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startup.wShowWindow = subprocess.SW_HIDE
            popen_options = {"creationflags": subprocess.CREATE_NO_WINDOW, "startupinfo": startup}
        process = subprocess.Popen([self.executable, "app-server", "--stdio"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, bufsize=1, env=environment, **popen_options)
        try:
            self._request(process, 1, "initialize", {"clientInfo": {"name": "AIUsageMonitor", "version": "1.0.0"}, "capabilities": {}})
            result = self._request(process, 2, "account/rateLimits/read")
        finally:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
        limits = result.get("rateLimits")
        if not isinstance(limits, dict):
            raise SchemaError("Codex rate-limit data is unavailable")
        reset = result.get("rateLimitResetCredits") if isinstance(result.get("rateLimitResetCredits"), dict) else {}
        return self._normalize_limits(limits, reset)

    @staticmethod
    def _rate_limits_from(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key == "rate_limits" and isinstance(item, dict):
                    yield item
                yield from CodexProvider._rate_limits_from(item)
        elif isinstance(value, list):
            for item in value:
                yield from CodexProvider._rate_limits_from(item)

    def _rollout_fallback(self) -> ProviderUsage | None:
        home = Path(os.environ.get("USERPROFILE", str(Path.home())))
        sessions = home / ".codex" / "sessions"
        try:
            files = sorted(sessions.rglob("*.jsonl"), key=lambda path: path.stat().st_mtime, reverse=True)[:20]
        except OSError:
            return None
        for path in files:
            try:
                for line in reversed(path.read_text(encoding="utf-8").splitlines()):
                    for limits in self._rate_limits_from(json.loads(line)):
                        return self._normalize_limits(limits, stale=True)
            except (OSError, ValueError, SchemaError):
                continue
        return None

    def fetch(self) -> ProviderUsage:
        try:
            return self._fetch_app_server()
        except (FileNotFoundError, OSError, TimeoutError, SchemaError):
            fallback = self._rollout_fallback()
            if fallback:
                return fallback
            raise
