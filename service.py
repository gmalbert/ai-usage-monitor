"""Concurrent refresh, cache fallback, and notification threshold state."""
from __future__ import annotations

import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

from cache import UsageCache
from models import ProviderStatus, ProviderUsage
from providers.base import UsageProvider
from providers.http import ProviderHTTPError
from usage import SchemaError


class UsageService:
    def __init__(self, providers: list[UsageProvider], cache: UsageCache | None = None, logger: logging.Logger | None = None) -> None:
        self.providers, self.cache, self.logger = providers, cache or UsageCache(), logger or logging.getLogger("ai_usage_monitor")
        self.values = self.cache.load()
        self.thresholds: dict[str, str] = {}

    @staticmethod
    def _failure(provider: UsageProvider, exc: Exception, old: ProviderUsage | None) -> ProviderUsage:
        if isinstance(exc, (FileNotFoundError,)):
            status = ProviderStatus.CODEX_NOT_INSTALLED
        elif isinstance(exc, ProviderHTTPError) and exc.status_code in (401, 403):
            status = ProviderStatus.AUTH_ERROR
        elif isinstance(exc, (ConnectionError, TimeoutError)):
            status = ProviderStatus.NETWORK_ERROR
        elif isinstance(exc, SchemaError):
            status = ProviderStatus.SCHEMA_ERROR
        else:
            status = ProviderStatus.API_ERROR
        if old:
            old.status, old.stale, old.error = ProviderStatus.STALE, True, str(exc)
            return old
        return ProviderUsage(provider.key.replace("opencode", "OpenCode Go").title(), None, status, None, None, None, datetime.now().astimezone(), error=str(exc))

    def refresh(self) -> dict[str, ProviderUsage]:
        with ThreadPoolExecutor(max_workers=len(self.providers) or 1) as executor:
            futures = {executor.submit(provider.fetch): provider for provider in self.providers}
            for future in as_completed(futures):
                provider = futures[future]
                try:
                    self.values[provider.key] = future.result()
                    self.logger.info("Provider refresh succeeded: %s", provider.key)
                except Exception as exc:  # Error is sanitized by adapters; never include response contents.
                    self.values[provider.key] = self._failure(provider, exc, self.values.get(provider.key))
                    detail = f" HTTP {exc.status_code}" if isinstance(exc, ProviderHTTPError) else ""
                    self.logger.warning("Provider refresh failed: %s (%s)%s", provider.key, type(exc).__name__, detail)
        self.cache.save(self.values)
        return self.values

    def lowest_remaining(self) -> float | None:
        values = [window.remaining_percent for usage in self.values.values() if usage.status == ProviderStatus.OK for window in usage.windows()]
        return min(values) if values else None
