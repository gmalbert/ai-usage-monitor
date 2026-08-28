from __future__ import annotations

import argparse

from config import load_settings
from logging_setup import configure_logging
from providers import CodexProvider, CommandCodeProvider, OpenCodeGoProvider
from service import UsageService
from ui.tray import TrayApplication


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()
    logger = configure_logging(args.debug)
    settings = load_settings()
    TrayApplication(UsageService([CommandCodeProvider(), OpenCodeGoProvider(), CodexProvider()], logger=logger), settings).run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
