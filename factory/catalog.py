"""Danh sách phôi mẫu độc lập với data/sources.json của xưởng chính."""
from __future__ import annotations

import json
from pathlib import Path

SOURCES = Path(__file__).resolve().parents[1] / "SOURCES-MAU.json"


def is_source_allowed(filename: str) -> bool:
    entries = json.loads(SOURCES.read_text("utf-8"))
    entry = entries.get(filename, {})
    return entry.get("duoc_phep_dung") is True and entry.get("nguon_goc") == "tự viết"
