"""Validate workflow inputs, generate the compile-time iOS license, build a rootless deb."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
UDID = re.compile(r"(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{8}-[0-9a-fA-F]{16})\Z")
LICENSE = re.compile(r"[A-Za-z0-9_-]{1,64}\Z")
MODEL = re.compile(r"[A-Za-z0-9._, -]{1,64}\Z")
SDK = re.compile(r"[0-9]{1,2}(?:\.[0-9]{1,2}){0,2}\Z")


def validated_config(env: dict[str, str]) -> dict[str, str | int]:
    udid = env.get("LOCK_UDID", "")
    kind = env.get("LOCK_KIND", "")
    license_id = env.get("LOCK_LICENSE_ID", "")
    seconds = env.get("LOCK_TRIAL_SECONDS", "")
    model = env.get("LOCK_MODEL", "")
    sdk = env.get("LOCK_SDK", "")
    if not UDID.fullmatch(udid):
        raise ValueError("UDID iOS phải là 40 hex hoặc 8 hex-16 hex (25 ký tự)")
    if kind not in ("trial", "paid"):
        raise ValueError("kind phải là trial hoặc paid")
    if not LICENSE.fullmatch(license_id):
        raise ValueError("license_id chỉ nhận chữ, số, _ và - (1-64 ký tự)")
    if not MODEL.fullmatch(model) or not SDK.fullmatch(sdk):
        raise ValueError("model hoặc sdk iOS không hợp lệ")
    if kind == "paid" and seconds == "":
        seconds = "0"
    if not re.fullmatch(r"[0-9]{1,5}", seconds):
        raise ValueError("trial_seconds phải là số nguyên giới hạn")
    number = int(seconds)
    if not 0 <= number <= 86400 or (kind == "trial" and number != 3600):
        raise ValueError("trial_seconds ngoài giới hạn hoặc trial không đúng 3600")
    return {"udid": udid.upper(), "kind": kind, "license_id": license_id, "seconds": number}


def write_config(project: Path, config: dict[str, str | int]) -> Path:
    path = project / "FactoryConfig.h"
    path.write_text(
        "/* Generated for one order; never commit. */\n"
        f'#define FACTORY_ALLOWED_UDID "{config["udid"]}"\n'
        f'#define FACTORY_KIND "{config["kind"]}"\n'
        f'#define FACTORY_LICENSE_ID "{config["license_id"]}"\n'
        f'#define FACTORY_TRIAL_SECONDS {config["seconds"]}LL\n', encoding="ascii")
    return path


def build(project: Path, out: Path, env: dict[str, str]) -> None:
    config = validated_config(env)
    if not project.is_dir() or not (project / "Makefile").is_file():
        raise ValueError("Thiếu project Theos")
    if not env.get("THEOS") or not Path(env["THEOS"]).is_dir():
        raise ValueError("Chưa cài Theos")
    out.parent.mkdir(parents=True, exist_ok=True)
    header = write_config(project, config)
    # Workflow chạy với umask 077 để bảo vệ bí mật, nhưng Theos đòi thư mục control 0755-0775.
    # Chỉ nới umask cho lần biên dịch này (không có bí mật nào đi qua make).
    old_umask = os.umask(0o022)
    try:
        subprocess.run(["make", "clean", "package", "FINALPACKAGE=1"], cwd=project,
                       env=env, check=True)
        packages = list((project / "packages").glob("*.deb"))
        if len(packages) != 1:
            raise RuntimeError("Theos phải tạo đúng một gói .deb")
        shutil.copy2(packages[0], out)
    finally:
        os.umask(old_umask)
        header.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, default=ROOT / "ios-sample")
    parser.add_argument("--out", type=Path, default=ROOT / "build_out" / "app.deb")
    args = parser.parse_args()
    build(args.project, args.out, dict(os.environ))


if __name__ == "__main__":
    main()
