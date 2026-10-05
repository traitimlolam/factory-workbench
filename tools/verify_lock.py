"""Bài thử APK trên emulator API 34; lỗi luôn ghi verify-result.json rồi fail job."""
from __future__ import annotations

import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from factory.apk_lock import lock_apk  # noqa: E402

PACKAGE = "vn.nguyentronghieu.factorysample"
ACTIVITY = PACKAGE + "/.MainActivity"
OUTPUT = ROOT / "verify-result.json"
CHECKS = ("dung_model", "sai_model", "trial_het_1_gio", "chinh_dong_ho_lui", "paid_khong_het_han")


def result_template() -> dict:
    return {"ngay": datetime.now(ZoneInfo("Asia/Ho_Chi_Minh")).date().isoformat(),
            "moi_truong": "android-emulator-API34",
            "cac_phep_thu": {name: False for name in CHECKS}}


def command(*args: str) -> str:
    try:
        run = subprocess.run(args, check=True, capture_output=True, text=True, timeout=90)
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        raise RuntimeError("Lệnh kiểm thử emulator thất bại") from None
    return run.stdout.strip()


def adb(*args: str) -> str:
    return command("adb", *args)


def device_seconds() -> int:
    return int(adb("shell", "date", "+%s"))


def set_device_time(seconds: int) -> None:
    adb("shell", "cmd", "alarm", "set-time", str(seconds * 1000))
    if abs(device_seconds() - seconds) > 15:
        raise RuntimeError("Emulator không đổi được đồng hồ; không thể xác nhận khóa thời gian")


def install(apk: Path) -> None:
    command("adb", "uninstall", PACKAGE) if PACKAGE in adb("shell", "pm", "list", "packages", PACKAGE) else None
    adb("install", str(apk))


def remains_open() -> bool:
    adb("shell", "am", "force-stop", PACKAGE)
    adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    time.sleep(2)
    activity = adb("shell", "dumpsys", "activity", "activities")
    focused = [line for line in activity.splitlines()
               if "mResumedActivity" in line or "topResumedActivity" in line]
    return bool(focused) and any(PACKAGE in line for line in focused)


def run_checks() -> dict:
    report = result_template()
    source = ROOT / "android-sample" / "app" / "build" / "outputs" / "apk" / "debug" / "app-debug.apk"
    model = adb("shell", "getprop", "ro.product.model")
    sdk = int(adb("shell", "getprop", "ro.build.version.sdk"))
    if not model or sdk != 34:
        raise RuntimeError("Máy ảo không đúng API 34 hoặc thiếu Build.MODEL")
    adb("root")
    adb("wait-for-device")
    adb("shell", "settings", "put", "global", "auto_time", "0")
    original = device_seconds()
    folder = ROOT / "build_out" / "verify"
    folder.mkdir(parents=True, exist_ok=True)
    trial = folder / "trial-correct.apk"
    wrong = folder / "trial-wrong-model.apk"
    paid = folder / "paid-correct.apk"
    try:
        lock_apk(source, trial, allowed_models=[model], allowed_sdk=[sdk],
                 kind="trial", license_id="VERIFY_TRIAL", trial_seconds=3600)
        lock_apk(source, wrong, allowed_models=["FACTORY_WRONG_MODEL"], allowed_sdk=[sdk],
                 kind="trial", license_id="VERIFY_WRONG", trial_seconds=3600)
        lock_apk(source, paid, allowed_models=[model], allowed_sdk=[sdk],
                 kind="paid", license_id="VERIFY_PAID")

        install(trial)
        report["cac_phep_thu"]["dung_model"] = remains_open()
        set_device_time(original + 3700)
        report["cac_phep_thu"]["trial_het_1_gio"] = not remains_open()
        set_device_time(original - 300)
        report["cac_phep_thu"]["chinh_dong_ho_lui"] = not remains_open()
        set_device_time(original)

        install(wrong)
        report["cac_phep_thu"]["sai_model"] = not remains_open()

        install(paid)
        paid_before = remains_open()
        set_device_time(original + 3700)
        report["cac_phep_thu"]["paid_khong_het_han"] = paid_before and remains_open()
    finally:
        try:
            set_device_time(int(time.time()))
        except RuntimeError:
            pass
    return report


def main() -> None:
    report = result_template()
    try:
        report = run_checks()
    except Exception as exc:
        report["loi"] = type(exc).__name__
    OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if not all(report["cac_phep_thu"].values()):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
