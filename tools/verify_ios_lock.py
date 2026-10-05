"""Compile and exercise the pure C gate on a macOS runner; always write JSON."""
from __future__ import annotations
import json
from datetime import datetime
from pathlib import Path
import shlex
import subprocess
import sys
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "verify-ios-result.json"
CHECKS = ("dung_udid", "sai_udid", "trial_het_1_gio", "chinh_dong_ho_lui", "paid_khong_het_han")


def result_template() -> dict:
    return {"ngay": datetime.now(ZoneInfo("Asia/Ho_Chi_Minh")).date().isoformat(),
            "moi_truong": "macos-14-clang", "cac_phep_thu": {x: False for x in CHECKS}, "loi": []}


def main() -> int:
    report = result_template()
    try:
        binary = ROOT / "build_out" / "verify-ios-lock"
        binary.parent.mkdir(exist_ok=True)
        command = ["clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                   str(ROOT / "ios-sample/FactoryLicenseGate.c"),
                   str(ROOT / "ios-sample/FactoryLicenseGateTest.c"), "-o", str(binary)]
        for cmd in (command, [str(binary)]):
            run = subprocess.run(cmd, capture_output=True, text=True)
            if cmd[0] == str(binary):
                for line in run.stdout.splitlines():
                    name, status = line.split("=", 1)
                    if name in report["cac_phep_thu"]:
                        report["cac_phep_thu"][name] = status == "PASS"
            if run.returncode:
                detail = run.stderr[-400:] or run.stdout[-400:]
                raise RuntimeError(f"Lệnh {shlex.join(cmd)} thất bại (exit {run.returncode}): {detail}")
        for name, passed in report["cac_phep_thu"].items():
            if not passed:
                report["loi"].append(f"{name}: kiểm tra thất bại hoặc thiếu kết quả từ {binary}")
    except (OSError, ValueError, RuntimeError) as exc:
        report["loi"].append(str(exc))
    finally:
        OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf-8")
    return 0 if not report["loi"] else 1


if __name__ == "__main__":
    sys.exit(main())
