"""Quét lại mã trên nhánh ticket trước khi build trên Actions."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from factory import code_gate  # noqa: E402


def allowed_worker_change(path: str) -> bool:
    return (path.startswith("android-sample/app/src/main/")
            and Path(path).suffix.lower() in (".java", ".kt", ".xml")
            and ".." not in Path(path).parts)


def main() -> None:
    branch = os.environ.get("WORKER_REF", "")
    if not branch.startswith("ticket-") or not branch[7:].isdigit():
        raise ValueError("Workflow thợ chỉ nhận nhánh ticket-<số>")
    changed = subprocess.run(["git", "diff", "--name-only", "origin/main...HEAD"],
                             cwd=ROOT, capture_output=True, text=True, check=True).stdout.splitlines()
    if not changed or any(not allowed_worker_change(path) or (ROOT / path).is_symlink()
                          or not (ROOT / path).is_file() for path in changed):
        raise ValueError("Nhánh ticket sửa file ngoài mã app Android được phép")
    project = ROOT / "android-sample"
    paths = [path for path in project.rglob("*") if path.is_file() and path.suffix.lower() in
             (".java", ".kt", ".xml", ".gradle") and "build" not in path.parts]
    if any(path.is_symlink() for path in paths):
        raise ValueError("Không nhận liên kết mềm trong mã thợ")
    files = {str(path.relative_to(project)): path.read_text("utf-8") for path in paths}
    violations = code_gate.scan(files, "android_app")
    if code_gate.has_blockers(violations):
        raise RuntimeError("Cổng code_gate từ chối mã trên nhánh ticket")
    print("Cổng code_gate: đạt")


if __name__ == "__main__":
    main()
