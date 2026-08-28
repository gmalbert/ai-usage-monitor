from __future__ import annotations

import argparse
import json

from models import usage_to_dict
from providers import CodexProvider, CommandCodeProvider, OpenCodeGoProvider
from service import UsageService
from usage import format_local_time


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="usage-monitor", description="Show local AI provider usage without browser scraping.")
    parser.add_argument("provider", nargs="?", choices=("commandcode", "opencode", "codex"), help="Limit output to one provider")
    parser.add_argument("--json", action="store_true", dest="as_json", help="Emit normalized JSON")
    parser.add_argument("--refresh", action="store_true", help="Force a live refresh (default for CLI)")
    return parser


def _render_window(window) -> list[str]:
    if not window:
        return []
    lines = [f"{window.name}\n  {window.remaining_percent:.1f}% remaining"]
    if window.used is not None and window.cap is not None:
        lines.append(f"  {window.used:.2f} / {window.cap:.2f} credits used")
    if window.remaining is not None:
        lines.append(f"  {window.remaining:.2f} credits remaining")
    if window.reset_at:
        lines.append("  " + format_local_time(window.reset_at, "Renews" if window.name == "Monthly" else "Resets"))
    return lines


def render_text(values) -> str:
    chunks = []
    for usage in values.values():
        if usage.status.value not in ("ok", "stale"):
            chunks.append(f"{usage.provider}\n  {usage.error or usage.status.value}")
            continue
        heading = usage.provider + (f" — {usage.plan}" if usage.plan else "")
        lines = [heading]
        for window in usage.windows():
            lines.extend(_render_window(window))
            lines.append("")
        if usage.credit_balance is not None:
            lines.append(f"Extra credits\n  ${usage.credit_balance:.2f} remaining")
        if usage.reset_credits_available is not None:
            lines.append(f"Resets available: {usage.reset_credits_available}")
        if usage.stale:
            lines.append(f"Stale data: {usage.error}")
        chunks.append("\n".join(lines).rstrip())
    return "\n\n".join(chunks) or "No cached usage is available."


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    providers = {"commandcode": CommandCodeProvider(), "opencode": OpenCodeGoProvider(), "codex": CodexProvider()}
    selected = [providers[args.provider]] if args.provider else list(providers.values())
    values = UsageService(selected).refresh()
    if args.as_json:
        print(json.dumps({key: usage_to_dict(value) for key, value in values.items()}, indent=2))
    else:
        print(render_text(values))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
