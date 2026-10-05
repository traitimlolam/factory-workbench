"""Kiểu bằng chứng tối thiểu cho bộ khóa APK mang theo workbench."""
from dataclasses import dataclass


@dataclass(frozen=True)
class BuildProof:
    udid_bound: bool
    trial_seconds: int | None
