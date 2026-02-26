"""Configure logging for training and launcher scripts."""

from __future__ import annotations

import logging
import os
import sys

_LEVEL_NAMES = {
    "DEBUG": logging.DEBUG,
    "INFO": logging.INFO,
    "WARNING": logging.WARNING,
    "WARN": logging.WARNING,
    "ERROR": logging.ERROR,
    "CRITICAL": logging.CRITICAL,
}


def get_log_level(level_name: str | None = None) -> int:
    """Resolve level name to logging constant. If None, read LOG_LEVEL env (default INFO)."""
    if level_name is None:
        level_name = os.environ.get("LOG_LEVEL", "INFO")
    key = (level_name or "INFO").strip().upper()
    if key not in _LEVEL_NAMES:
        return logging.INFO
    return _LEVEL_NAMES[key]


def configure_logging(
    level: int | str | None = None,
    format_string: str = "%(message)s",
    stream: object | None = None,
) -> None:
    """Configure the root logger with a single stream handler (stdout by default).
    level: int (e.g. logging.INFO), level name (e.g. 'DEBUG'), or None to use LOG_LEVEL env.
    """
    if stream is None:
        stream = sys.stdout
    if isinstance(level, int):
        resolved = level
    else:
        resolved = get_log_level(level)
    handler = logging.StreamHandler(stream)
    handler.setLevel(resolved)
    handler.setFormatter(logging.Formatter(format_string))
    root = logging.getLogger()
    root.setLevel(resolved)
    root.handlers.clear()
    root.addHandler(handler)


def get_logger(name: str) -> logging.Logger:
    """Return a logger for the given module name."""
    return logging.getLogger(name)
