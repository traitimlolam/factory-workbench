"""Cá nhân hóa APK ngoại tuyến; chỉ nhận phôi đã được phép dùng."""
from __future__ import annotations

import os
import re
import shlex
import shutil
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET
from pathlib import Path

from . import catalog

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
GATE_CLASS = "Lcom/factory/LicenseGate;"


def _run(args: list[str], *, env: dict | None = None) -> None:
    try:
        subprocess.run(args, check=True, capture_output=True, timeout=180, env=env)
    except (subprocess.CalledProcessError, OSError, subprocess.TimeoutExpired) as exc:
        if args[0] == "apktool":
            stderr = getattr(exc, "stderr", "") or ""
            if isinstance(stderr, bytes):
                stderr = stderr.decode(errors="replace")
            code = getattr(exc, "returncode", None)
            raise RuntimeError(
                f"Lệnh {shlex.join(args)} thất bại (mã thoát: "
                f"{code if code is not None else 'không có'}; stderr cuối: {stderr[-400:]!r})"
            ) from None
        # Công cụ ký có thể in mật khẩu ra stderr; không chuyển stderr vào lỗi/log.
        raise RuntimeError(f"Công cụ xử lý APK thất bại: {Path(args[0]).name}") from None


def _signing(keystore: Path | None, ks_alias: str | None) -> tuple[Path, str, dict]:
    path = Path(keystore or os.environ.get("APK_KEYSTORE", ""))
    alias = ks_alias or os.environ.get("APK_KS_ALIAS", "")
    if not path.is_file() or not re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", alias):
        raise ValueError("Thiếu kho khóa hoặc alias ký APK")
    env = os.environ.copy()
    secret_file = env.get("APK_SIGNING_SECRET_FILE", "")
    if secret_file:
        secret_path = Path(secret_file)
        if secret_path.stat().st_mode & 0o077:
            raise ValueError("File mật khẩu ký APK phải có quyền 600")
        lines = secret_path.read_text().splitlines()
        env["APK_KS_PASS"] = lines[0] if lines else ""
        env["APK_KEY_PASS"] = lines[1] if len(lines) > 1 else env["APK_KS_PASS"]
    if not env.get("APK_KS_PASS"):
        raise ValueError("Thiếu mật khẩu ký APK")
    env.setdefault("APK_KEY_PASS", env["APK_KS_PASS"])
    return path, alias, env


def _launcher_classes(manifest: Path) -> list[str]:
    root = ET.parse(manifest).getroot()
    package = root.get("package", "")
    app = root.find("application")
    if not package or app is None:
        raise ValueError("Manifest APK không hợp lệ")
    result = []
    for node in app:
        if node.tag not in ("activity", "activity-alias"):
            continue
        launch = any(any(a.get(ANDROID_NS + "name") == "android.intent.action.MAIN" for a in f.findall("action"))
                     and any(c.get(ANDROID_NS + "name") == "android.intent.category.LAUNCHER" for c in f.findall("category"))
                     for f in node.findall("intent-filter"))
        if launch:
            name = node.get(ANDROID_NS + ("targetActivity" if node.tag == "activity-alias" else "name"), "")
            if name.startswith("."):
                name = package + name
            elif "." not in name:
                name = package + "." + name
            result.append(name)
    if not result:
        raise ValueError("APK không có Activity khởi chạy")
    return list(dict.fromkeys(result))


def _patch_activity(decoded: Path, class_name: str) -> None:
    relative = class_name.replace(".", "/") + ".smali"
    matches = list(decoded.glob("smali*/" + relative))
    if len(matches) != 1:
        raise ValueError("Không tìm được duy nhất Activity khởi chạy")
    path = matches[0]
    source = path.read_text()
    if GATE_CLASS in source:
        raise ValueError("Activity đã được chèn khóa")
    check = (f"\n    invoke-static {{p0}}, {GATE_CLASS}->allow(Landroid/app/Activity;)Z\n"
             "    move-result v0\n    if-nez v0, :factory_license_ok\n"
             "    return-void\n    :factory_license_ok\n")
    pattern = r"(?ms)^\.method[^\n]* onCreate\(Landroid/os/Bundle;\)V\n.*?^\.end method"
    match = re.search(pattern, source)
    if match:
        method = match.group(0)
        register = re.search(r"(?m)^    \.(locals|registers) (\d+)\s*$", method)
        super_call = re.search(r"(?m)^    invoke-super \{[^\n]+\}[^\n]*->onCreate\(Landroid/os/Bundle;\)V\s*$", method)
        if not register or not super_call:
            raise ValueError("Activity onCreate không có mẫu an toàn để chèn khóa")
        method = method[:register.start(2)] + str(int(register.group(2)) + 1) + method[register.end(2):]
        super_call = re.search(r"(?m)^    invoke-super \{[^\n]+\}[^\n]*->onCreate\(Landroid/os/Bundle;\)V\s*$", method)
        method = method[:super_call.end()] + check + method[super_call.end():]
        source = source[:match.start()] + method + source[match.end():]
    else:
        parent = re.search(r"(?m)^\.super (L[^;]+;)$", source)
        if not parent:
            raise ValueError("Activity không có lớp cha xác định")
        source += ("\n.method protected onCreate(Landroid/os/Bundle;)V\n"
                   "    .locals 1\n"
                   f"    invoke-super {{p0, p1}}, {parent.group(1)}->onCreate(Landroid/os/Bundle;)V\n"
                   + check + "    return-void\n.end method\n")
    path.write_text(source)


def _gate_smali(models: list[str], sdk: list[int], kind: str, license_id: str,
                trial_seconds: int, valid_until_ms: int) -> str:
    model_checks = "\n".join(
        f'    const-string v1, "{model}"\n    invoke-virtual {{v0, v1}}, Ljava/lang/String;->equalsIgnoreCase(Ljava/lang/String;)Z\n'
        '    move-result v2\n    if-nez v2, :model_ok' for model in models)
    sdk_checks = "\n".join(
        f"    const/16 v1, 0x{value:x}\n    if-eq v0, v1, :sdk_ok" for value in sdk)
    trial = ""
    if kind == "trial":
        trial = f"""
    :try_start
    invoke-static {{}}, Ljava/lang/System;->currentTimeMillis()J
    move-result-wide v0
    invoke-virtual {{p0}}, Landroid/app/Activity;->getPackageManager()Landroid/content/pm/PackageManager;
    move-result-object v2
    invoke-virtual {{p0}}, Landroid/app/Activity;->getPackageName()Ljava/lang/String;
    move-result-object v3
    const/4 v4, 0x0
    invoke-virtual {{v2, v3, v4}}, Landroid/content/pm/PackageManager;->getPackageInfo(Ljava/lang/String;I)Landroid/content/pm/PackageInfo;
    move-result-object v2
    iget-wide v2, v2, Landroid/content/pm/PackageInfo;->firstInstallTime:J
    const-wide/32 v4, 0x{trial_seconds * 1000:x}
    add-long/2addr v2, v4
    cmp-long v4, v0, v2
    if-gez v4, :deny
    const-wide v2, 0x{valid_until_ms:x}L
    cmp-long v4, v0, v2
    if-gez v4, :deny
    invoke-static {{p0, v0, v1}}, {GATE_CLASS}->clockOk(Landroid/app/Activity;J)Z
    move-result v2
    if-eqz v2, :deny
    :try_end
    goto :allow
    .catch Ljava/lang/Exception; {{:try_start .. :try_end}} :catch_error
    :catch_error
    move-exception v0
    goto :deny
"""
    else:
        trial = "    goto :allow\n"
    return f""".class public final {GATE_CLASS}
.super Ljava/lang/Object;

.field public static final LICENSE_ID:Ljava/lang/String; = "{license_id}"

.method public static allow(Landroid/app/Activity;)Z
    .locals 6
    sget-object v0, Landroid/os/Build;->MODEL:Ljava/lang/String;
{model_checks}
    goto :deny
    :model_ok
    sget v0, Landroid/os/Build$VERSION;->SDK_INT:I
{sdk_checks}
    goto :deny
    :sdk_ok
{trial}
    :allow
    const/4 v0, 0x1
    return v0
    :deny
    const-string v0, "Bản này không dành cho thiết bị của bạn"
    const/4 v1, 0x0
    invoke-static {{p0, v0, v1}}, Landroid/widget/Toast;->makeText(Landroid/content/Context;Ljava/lang/CharSequence;I)Landroid/widget/Toast;
    move-result-object v0
    invoke-virtual {{v0}}, Landroid/widget/Toast;->show()V
    invoke-virtual {{p0}}, Landroid/app/Activity;->finish()V
    const/4 v0, 0x0
    return v0
.end method

.method private static clockOk(Landroid/app/Activity;J)Z
    .locals 8
    :try_start
    const-string v0, "factory_clock_a"
    const/4 v1, 0x0
    invoke-virtual {{p0, v0, v1}}, Landroid/app/Activity;->getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;
    move-result-object v2
    const-string v0, "factory_clock_b"
    invoke-virtual {{p0, v0, v1}}, Landroid/app/Activity;->getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;
    move-result-object v3
    const-string v4, "last"
    const-wide/16 v5, 0x0
    invoke-interface {{v2, v4, v5, v6}}, Landroid/content/SharedPreferences;->getLong(Ljava/lang/String;J)J
    move-result-wide v5
    cmp-long v0, p1, v5
    if-ltz v0, :bad
    const-wide/16 v5, 0x0
    invoke-interface {{v3, v4, v5, v6}}, Landroid/content/SharedPreferences;->getLong(Ljava/lang/String;J)J
    move-result-wide v5
    cmp-long v0, p1, v5
    if-ltz v0, :bad
    invoke-interface {{v2}}, Landroid/content/SharedPreferences;->edit()Landroid/content/SharedPreferences$Editor;
    move-result-object v2
    invoke-interface {{v2, v4, p1, p2}}, Landroid/content/SharedPreferences$Editor;->putLong(Ljava/lang/String;J)Landroid/content/SharedPreferences$Editor;
    move-result-object v2
    invoke-interface {{v2}}, Landroid/content/SharedPreferences$Editor;->commit()Z
    move-result v0
    if-eqz v0, :bad
    invoke-interface {{v3}}, Landroid/content/SharedPreferences;->edit()Landroid/content/SharedPreferences$Editor;
    move-result-object v3
    invoke-interface {{v3, v4, p1, p2}}, Landroid/content/SharedPreferences$Editor;->putLong(Ljava/lang/String;J)Landroid/content/SharedPreferences$Editor;
    move-result-object v3
    invoke-interface {{v3}}, Landroid/content/SharedPreferences$Editor;->commit()Z
    move-result v0
    if-eqz v0, :bad
    :try_end
    const/4 v0, 0x1
    return v0
    .catch Ljava/lang/Exception; {{:try_start .. :try_end}} :catch_error
    :catch_error
    move-exception v0
    :bad
    const/4 v0, 0x0
    return v0
.end method
"""


def lock_apk(source: Path, out: Path, *, allowed_models: list[str], allowed_sdk: list[int],
             kind: str, license_id: str, trial_seconds: int = 3600, deadline_hours: int = 24,
             keystore: Path | None = None, ks_alias: str | None = None):
    """Build và ký bản APK theo model/SDK; trả bằng chứng cho builder."""
    source, out = Path(source), Path(out)
    if not catalog.is_source_allowed(source.name):
        raise ValueError("Phôi APK chưa được phép sử dụng")
    if not source.is_file() or source.suffix.lower() != ".apk":
        raise ValueError("Cần phôi APK hợp lệ")
    if kind not in ("trial", "paid") or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", license_id):
        raise ValueError("Loại bản hoặc mã giấy phép không hợp lệ")
    if not allowed_models or any(not re.fullmatch(r"[A-Za-z0-9 _.-]{2,50}", x) for x in allowed_models):
        raise ValueError("Thiếu Build.MODEL hợp lệ")
    if not allowed_sdk or any(type(x) is not int or not 1 <= x <= 100 for x in allowed_sdk):
        raise ValueError("Thiếu Android SDK hợp lệ")
    if not 1 <= trial_seconds <= 86400 or not 1 <= deadline_hours <= 168:
        raise ValueError("Thời hạn bản thử không hợp lệ")
    ks_path, alias, env = _signing(keystore, ks_alias)
    valid_until_ms = int((time.time() + deadline_hours * 3600) * 1000)
    with tempfile.TemporaryDirectory(prefix="factory-apk-") as temp:
        root = Path(temp)
        decoded = root / "decoded"
        built, aligned = root / "built.apk", root / "aligned.apk"
        _run(["apktool", "d", "-f", str(source), "-o", str(decoded)])
        launchers = _launcher_classes(decoded / "AndroidManifest.xml")
        for name in launchers:
            _patch_activity(decoded, name)
        smali_dir = next(iter(sorted(decoded.glob("smali*"))), None)
        if smali_dir is None:
            raise ValueError("APK không có mã smali")
        gate = smali_dir / "com" / "factory" / "LicenseGate.smali"
        if gate.exists():
            raise ValueError("APK đã có lớp khóa trùng tên")
        gate.parent.mkdir(parents=True, exist_ok=True)
        gate.write_text(_gate_smali(allowed_models, allowed_sdk, kind, license_id,
                                    trial_seconds, valid_until_ms))
        _run(["apktool", "b", str(decoded), "-o", str(built)])
        _run(["zipalign", "-f", "-p", "4", str(built), str(aligned)])
        out.parent.mkdir(parents=True, exist_ok=True)
        try:
            _run(["apksigner", "sign", "--ks", str(ks_path), "--ks-key-alias", alias,
                  "--ks-pass", "env:APK_KS_PASS", "--key-pass", "env:APK_KEY_PASS",
                  "--out", str(out), str(aligned)], env=env)
            _run(["apksigner", "verify", str(out)])
            _run(["aapt", "dump", "badging", str(out)])
            if not out.is_file() or out.stat().st_size == 0:
                raise ValueError("APK đầu ra rỗng")
        except BaseException:
            out.unlink(missing_ok=True)
            raise
    from .builder import BuildProof
    return BuildProof(udid_bound=True, trial_seconds=trial_seconds if kind == "trial" else None)
