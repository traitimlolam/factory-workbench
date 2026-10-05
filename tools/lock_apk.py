"""Khóa APK bằng các giá trị workflow chuyển qua biến môi trường."""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from factory.apk_lock import lock_apk  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    kind = os.environ["LOCK_KIND"]
    trial_seconds = int(os.environ.get("LOCK_TRIAL_SECONDS") or "3600")
    if kind == "trial" and trial_seconds != 3600:
        raise ValueError("Bản thử workbench phải đúng 3600 giây")
    proof = lock_apk(
        args.source, args.out,
        allowed_models=[os.environ["LOCK_MODEL"]],
        allowed_sdk=[int(os.environ["LOCK_SDK"])],
        kind=kind,
        license_id=os.environ["LOCK_LICENSE_ID"],
        trial_seconds=trial_seconds,
    )
    if not proof.udid_bound or (kind == "trial" and proof.trial_seconds != 3600) or (kind == "paid" and proof.trial_seconds is not None):
        raise RuntimeError("Bằng chứng khóa APK không hợp lệ")
    print("Đã tạo APK và kiểm chữ ký/manifest")


if __name__ == "__main__":
    main()
