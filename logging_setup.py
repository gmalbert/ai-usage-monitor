from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler

from config import app_data_dir


def configure_logging(debug: bool = False) -> logging.Logger:
    logger = logging.getLogger("ai_usage_monitor")
    if logger.handlers:
        return logger
    logger.setLevel(logging.DEBUG if debug else logging.INFO)
    path = app_data_dir() / "logs" / "usage-monitor.log"
    path.parent.mkdir(parents=True, exist_ok=True)
    handler = RotatingFileHandler(path, maxBytes=1_000_000, backupCount=3, encoding="utf-8")
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    logger.addHandler(handler)
    if debug:
        logger.addHandler(logging.StreamHandler())
    return logger
