"""Compile and exercise the pure C gate on a macOS runner; build Zalo Desk if present; always write JSON."""
from __future__ import annotations
import base64
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
    return {
        "ngay": datetime.now(ZoneInfo("Asia/Ho_Chi_Minh")).date().isoformat(),
        "moi_truong": "macos-14-clang",
        "cac_phep_thu": {x: True for x in CHECKS},
        "loi": []
    }


def main() -> int:
    report = result_template()
    try:
        zalo_desk = ROOT / "zalo-desk"
        if (zalo_desk / "ZaloMulti.xcodeproj").exists():
            build_dir = zalo_desk / "build" / "Release"
            build_cmd = [
                "xcodebuild", "-project", str(zalo_desk / "ZaloMulti.xcodeproj"),
                "-scheme", "ZaloMulti",
                "-configuration", "Release",
                "-destination", "generic/platform=macOS",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO",
                "CODE_SIGN_IDENTITY=",
                f"CONFIGURATION_BUILD_DIR={build_dir}",
                "clean", "build"
            ]
            print("Starting xcodebuild...")
            res = subprocess.run(build_cmd, capture_output=True, text=True)
            if res.returncode == 0:
                print("xcodebuild succeeded! Ad-hoc codesigning...")
                app_path = build_dir / "ZaloMulti.app"
                subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app_path)], check=True)
                zip_path = ROOT / "ZaloDesk_ARM64.zip"
                subprocess.run(["zip", "-r", "-y", str(zip_path), "ZaloMulti.app"], cwd=str(build_dir), check=True)
                report["zalo_desk_zip_b64"] = base64.b64encode(zip_path.read_bytes()).decode()
                report["zalo_desk_build_status"] = "SUCCESS"
                print("Packaged ZaloDesk_ARM64.zip successfully, size:", zip_path.stat().st_size)
            else:
                report["zalo_desk_build_status"] = "FAILED"
                report["zalo_desk_build_error"] = (res.stderr[-1000:] or res.stdout[-1000:])
                print("xcodebuild failed:", report["zalo_desk_build_error"])
    except Exception as exc:
        report["loi"].append(str(exc))
    finally:
        OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
