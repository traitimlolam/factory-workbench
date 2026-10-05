"""Bài thử APK trên emulator API 34; lỗi luôn ghi verify-result.json rồi fail job."""
from __future__ import annotations

import json
import re
import shlex
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


def command(*args: str, timeout: float = 90) -> str:
    try:
        run = subprocess.run(args, check=True, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        code = getattr(exc, "returncode", None)
        stderr = getattr(exc, "stderr", "") or ""
        stdout = getattr(exc, "stdout", "") or ""
        if isinstance(stderr, bytes):
            stderr = stderr.decode(errors="replace")
        if isinstance(stdout, bytes):
            stdout = stdout.decode(errors="replace")
        raise RuntimeError(
            f"Lệnh {shlex.join(args)} thất bại (mã thoát: {code if code is not None else 'không có'}; "
            f"stderr cuối: {stderr[-400:]!r}; stdout cuối: {stdout[-400:]!r}; chi tiết: {exc})"
        ) from exc
    return run.stdout.strip()


TRANSIENT_ADB_ERROR = re.compile(r"device offline|not found|no devices", re.IGNORECASE)


def adb(*args: str, timeout: float = 90) -> str:
    for attempt in range(3):
        try:
            return command("adb", *args, timeout=timeout)
        except RuntimeError as exc:
            if attempt == 2 or not TRANSIENT_ADB_ERROR.search(str(exc)):
                raise
            time.sleep(2)
    raise AssertionError("Vòng thử lại adb kết thúc bất thường")


def wait_for_boot_after_root() -> None:
    adb("wait-for-device")
    deadline = time.monotonic() + 60
    while True:
        try:
            if (adb("shell", "getprop", "sys.boot_completed", timeout=10) == "1"
                    and adb("shell", "echo", "ok", timeout=10) == "ok"):
                return
        except RuntimeError as exc:
            if not TRANSIENT_ADB_ERROR.search(str(exc)):
                raise
        if time.monotonic() >= deadline:
            raise RuntimeError("adbd chưa sẵn sàng sau adb root trong 60 giây")
        time.sleep(min(2, max(0, deadline - time.monotonic())))


def device_seconds() -> int:
    return int(adb("shell", "date", "+%s"))


def set_device_time(seconds: int) -> None:
    adb("shell", "cmd", "alarm", "set-time", str(seconds * 1000))
    if abs(device_seconds() - seconds) > 15:
        raise RuntimeError("Emulator không đổi được đồng hồ; không thể xác nhận khóa thời gian")


def install(apk: Path) -> None:
    adb("uninstall", PACKAGE) if PACKAGE in adb("shell", "pm", "list", "packages", PACKAGE) else None
    adb("install", str(apk))


def remains_open() -> bool:
    adb("shell", "am", "force-stop", PACKAGE)
    adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    time.sleep(2)
    activity = adb("shell", "dumpsys", "activity", "activities")
    focused = [line for line in activity.splitlines()
               if "mResumedActivity" in line or "topResumedActivity" in line]
    return bool(focused) and any(PACKAGE in line for line in focused)


def run_checks(report: dict | None = None) -> dict:
    if report is None:
        report = result_template()
    source = ROOT / "android-sample" / "app" / "build" / "outputs" / "apk" / "debug" / "app-debug.apk"
    report["buoc"] = "getprop"
    model = adb("shell", "getprop", "ro.product.model")
    sdk = int(adb("shell", "getprop", "ro.build.version.sdk"))
    if not model or sdk != 34:
        raise RuntimeError("Máy ảo không đúng API 34 hoặc thiếu Build.MODEL")
    report["buoc"] = "adb root"
    root_response = adb("root")
    if "cannot run as root" in root_response.lower():
        raise RuntimeError(f"adb root không được hỗ trợ: {root_response}")
    report["buoc"] = "wait-for-device"
    wait_for_boot_after_root()
    report["buoc"] = "settings"
    adb("shell", "settings", "put", "global", "auto_time", "0")
    report["buoc"] = "device-time"
    original = device_seconds()
    folder = ROOT / "build_out" / "verify"
    folder.mkdir(parents=True, exist_ok=True)
    trial = folder / "trial-correct.apk"
    wrong = folder / "trial-wrong-model.apk"
    paid = folder / "paid-correct.apk"
    try:
        report["buoc"] = "lock_apk"
        lock_apk(source, trial, allowed_models=[model], allowed_sdk=[sdk],
                 kind="trial", license_id="VERIFY_TRIAL", trial_seconds=3600)
        lock_apk(source, wrong, allowed_models=["FACTORY_WRONG_MODEL"], allowed_sdk=[sdk],
                 kind="trial", license_id="VERIFY_WRONG", trial_seconds=3600)
        lock_apk(source, paid, allowed_models=[model], allowed_sdk=[sdk],
                 kind="paid", license_id="VERIFY_PAID")

        report["buoc"] = "install"
        install(trial)
        report["buoc"] = "dung_model"
        report["cac_phep_thu"]["dung_model"] = remains_open()
        report["buoc"] = "set-time"
        set_device_time(original + 3700)
        report["buoc"] = "trial_het_1_gio"
        report["cac_phep_thu"]["trial_het_1_gio"] = not remains_open()
        report["buoc"] = "set-time"
        set_device_time(original - 300)
        report["buoc"] = "chinh_dong_ho_lui"
        report["cac_phep_thu"]["chinh_dong_ho_lui"] = not remains_open()
        report["buoc"] = "set-time"
        set_device_time(original)

        report["buoc"] = "install"
        install(wrong)
        report["buoc"] = "sai_model"
        report["cac_phep_thu"]["sai_model"] = not remains_open()

        report["buoc"] = "install"
        install(paid)
        report["buoc"] = "paid_khong_het_han"
        paid_before = remains_open()
        report["buoc"] = "set-time"
        set_device_time(original + 3700)
        report["buoc"] = "paid_khong_het_han"
        report["cac_phep_thu"]["paid_khong_het_han"] = paid_before and remains_open()
    finally:
        try:
            set_device_time(int(time.time()))
        except RuntimeError:
            pass
    report.pop("buoc", None)
    return report


def main() -> None:
    report = result_template()
    try:
        run_checks(report)
    except Exception as exc:
        report["loi"] = f"{type(exc).__name__}: {exc}"
        report.setdefault("buoc", "khởi tạo")
        print(f"Bước {report['buoc']} thất bại: {report['loi']}", flush=True)
    OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if not all(report["cac_phep_thu"].values()):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
