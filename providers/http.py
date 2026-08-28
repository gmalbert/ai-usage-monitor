"""Small HTTP wrapper which deliberately never logs credentials or bodies."""
from __future__ import annotations

import json
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from config import HTTP_TIMEOUT_SECONDS


class ProviderHTTPError(RuntimeError):
    def __init__(self, status_code: int, message: str | None = None) -> None:
        self.status_code = status_code
        super().__init__(message or f"HTTP {status_code}")


def get_json(url: str, token: str, params: dict[str, object] | None = None) -> dict:
    if params:
        url = f"{url}?{urlencode({key: value for key, value in params.items() if value is not None})}"
    try:
        # CommandCode rejects Python's default urllib user agent with HTTP 403.
        # This identifies the local monitor without disclosing account data.
        request = Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": "AIUsageMonitor/1.0"})
        with urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
            payload = response.read().decode("utf-8")
    except HTTPError as exc:
        raise ProviderHTTPError(exc.code) from exc
    except (URLError, TimeoutError, OSError) as exc:
        raise ConnectionError("Network request failed") from exc
    try:
        value = json.loads(payload)
    except (ValueError, UnicodeDecodeError) as exc:
        raise ValueError("Provider returned invalid JSON") from exc
    if not isinstance(value, dict):
        raise ValueError("Provider returned an unexpected JSON value")
    return value
