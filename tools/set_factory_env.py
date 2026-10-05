"""Cập nhật hai biến workbench; đọc PAT từ stdin, không đưa bí mật lên argv/log."""
from __future__ import annotations

import os
import re
import sys
import tempfile
from pathlib import Path


def update_env(path: Path, repo: str, token: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError("WORKBENCH_REPO không hợp lệ")
    if not token or any(char in token for char in "\r\n\x00"):
        raise ValueError("GITHUB_TOKEN không hợp lệ")
    old = path.read_text("utf-8").splitlines() if path.exists() else []
    kept = [line for line in old if not line.startswith(("GITHUB_TOKEN=", "WORKBENCH_REPO="))]
    text = "\n".join([*kept, f"GITHUB_TOKEN={token}", f"WORKBENCH_REPO={repo}"]) + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".factory-env-", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Cú pháp: python3 set_factory_env.py OWNER/factory-workbench < PAT")
    token = sys.stdin.readline().rstrip("\n")
    target = Path(os.environ.get("FACTORY_ENV_PATH", "/opt/factory/factory.env"))
    update_env(target, sys.argv[1], token)
    print("Đã cập nhật GITHUB_TOKEN và WORKBENCH_REPO; quyền file 600")


if __name__ == "__main__":
    main()
