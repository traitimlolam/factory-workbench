"""Download a scan input through checked, pinned HTTPS connections."""
from __future__ import annotations

import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import urljoin, urlsplit

_HERE = Path(__file__).resolve()
# Repo workbench trên GitHub: data/ nằm cạnh tools/; repo xưởng: factory/data/.
SOURCES = next((c for c in (_HERE.parents[1] / "data" / "nguon_trinh_sat.json",
                            _HERE.parents[3] / "factory/data/nguon_trinh_sat.json") if c.exists()),
               _HERE.parents[1] / "data" / "nguon_trinh_sat.json")
MAX_REDIRECTS = 3


def allowed_host(url: str, source_host: str) -> tuple[str, int]:
    parsed = urlsplit(url)
    host = parsed.hostname
    if (parsed.scheme != "https" or not host or parsed.username or parsed.password
            or not (host == source_host or host.endswith("." + source_host))):
        raise ValueError("URL không thuộc nguồn HTTPS cho phép")
    try:
        port = parsed.port or 443
    except ValueError as exc:
        raise ValueError("Cổng URL không hợp lệ") from exc
    if port != 443:
        raise ValueError("Chỉ cho phép cổng HTTPS chuẩn")
    return host, port


def checked_ip(host: str) -> str:
    result = subprocess.run(["getent", "ahosts", host], capture_output=True, text=True, check=True)
    for line in result.stdout.splitlines():
        candidate = line.split()[0]
        try:
            ip = ipaddress.ip_address(candidate)
        except ValueError:
            continue
        if ip.is_global:
            return str(ip)
    raise ValueError("Không tìm được IP công cộng")


def fetch(url: str, source_host: str, destination: Path) -> None:
    for hop in range(MAX_REDIRECTS + 1):
        host, port = allowed_host(url, source_host)
        ip = checked_ip(host)
        pin = f"{host}:{port}:{'[' + ip + ']' if ':' in ip else ip}"
        with tempfile.TemporaryDirectory() as directory:
            headers = Path(directory) / "headers"
            result = subprocess.run([
                "curl", "--silent", "--show-error", "--proto", "=https",
                "--noproxy", "*", "--tlsv1.2", "--max-time", "120",
                "--max-filesize", "52428800", "--resolve", pin,
                "--dump-header", str(headers), "--output", str(destination),
                "--write-out", "%{http_code}", url,
            ], capture_output=True, text=True, check=True)
            status = int(result.stdout)
            if status in (301, 302, 303, 307, 308):
                if hop == MAX_REDIRECTS:
                    raise ValueError("Quá nhiều redirect")
                location = next((line.partition(":")[2].strip() for line in headers.read_text().splitlines()
                                 if line.lower().startswith("location:")), "")
                if not location:
                    raise ValueError("Redirect thiếu Location")
                url = urljoin(url, location)
                continue
            if status != 200:
                raise ValueError("Tải file thất bại")
            return
    raise ValueError("Quá nhiều redirect")


def main() -> None:
    source_id = os.environ["SOURCE_ID"]
    ticket_id = os.environ["TICKET_ID"]
    expected_hash = os.environ.get("EXPECTED_HASH", "")
    order_code = os.environ["ORDER_CODE"]
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", source_id):
        raise ValueError("source_id không hợp lệ")
    if not re.fullmatch(r"[0-9]+", ticket_id):
        raise ValueError("ticket_id không hợp lệ")
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", order_code):
        raise ValueError("order_code không hợp lệ")
    if expected_hash and not re.fullmatch(r"[0-9a-f]{64}", expected_hash):
        raise ValueError("Hash không hợp lệ")
    source = next((item for item in json.loads(SOURCES.read_text()) if item["id"] == source_id), None)
    if not source or not source.get("allow_download"):
        raise ValueError("Nguồn không được phép tải")
    source_url = urlsplit(source["url_goc"])
    if source_url.scheme != "https" or not source_url.hostname:
        raise ValueError("Nguồn không hỗ trợ HTTPS")
    output = Path("workspace/staging/downloaded_file.bin")
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        fetch(os.environ["URL"], source_url.hostname.lower(), output)
        if expected_hash:
            import hashlib
            if hashlib.sha256(output.read_bytes()).hexdigest() != expected_hash:
                raise ValueError("Mã băm không khớp")
    except Exception:
        output.unlink(missing_ok=True)
        raise


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
