"""Only a ticket's tweak source may differ from main; gate it before building."""
from __future__ import annotations
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from factory import code_gate  # noqa: E402


def main() -> None:
    branch = os.environ.get("WORKER_REF", "")
    if not re.fullmatch(r"ticket-[0-9]+", branch):
        raise ValueError("Chỉ nhận nhánh ticket-<số>")
    changed = subprocess.run(["git", "diff", "--name-only", "origin/main...HEAD"],
                             cwd=ROOT, capture_output=True, text=True, check=True).stdout.splitlines()
    allowed = {"ios-sample/Feature.xm"}
    if not changed or any(path not in allowed or (ROOT / path).is_symlink() for path in changed):
        raise ValueError("Nhánh ticket chỉ được sửa ios-sample/Tweak.xm")
    files = {"Feature.xm": (ROOT / "ios-sample/Feature.xm").read_text("utf-8")}
    violations = code_gate.scan(files, "ios_tweak")
    if code_gate.has_blockers(violations):
        raise RuntimeError("code_gate từ chối mã tweak trên nhánh ticket")
    print("code_gate iOS: đạt")


if __name__ == "__main__":
    main()
