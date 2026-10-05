"""Encrypt a build output for one order before uploading a public Actions artifact."""
import hashlib
import hmac
import os
from pathlib import Path
import subprocess


def encrypt(source: Path, order_code: str, secret: str) -> Path:
    if not secret or not order_code:
        raise RuntimeError("Thiếu ARTIFACT_SECRET hoặc order_code")
    key = hmac.new(secret.encode(), order_code.encode(), hashlib.sha256).hexdigest()
    target = source.with_name(source.name + ".enc")
    env = {**os.environ, "ARTIFACT_KEY": key}
    try:
        subprocess.run(["openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-salt",
                        "-in", str(source), "-out", str(target), "-pass", "env:ARTIFACT_KEY"],
                       env=env, check=True, capture_output=True)
        ciphertext = target.read_bytes()
        target.with_name(target.name + ".sha256").write_text(hashlib.sha256(ciphertext).hexdigest() + "\n")
        mac_key = hmac.new(bytes.fromhex(key), b"artifact-auth", hashlib.sha256).digest()
        target.with_name(target.name + ".hmac").write_text(hmac.new(mac_key, ciphertext, hashlib.sha256).hexdigest() + "\n")
    except Exception:
        for path in (target, target.with_name(target.name + ".sha256"), target.with_name(target.name + ".hmac")):
            path.unlink(missing_ok=True)
        raise RuntimeError("Mã hóa artifact thất bại") from None
    source.unlink()
    return target


if __name__ == "__main__":
    encrypt(Path("build_out/app.apk"), os.environ.get("ORDER_CODE", ""), os.environ.get("ARTIFACT_SECRET", ""))
