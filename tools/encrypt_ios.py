"""Reuse the Android artifact envelope for the iOS deb without changing its CLI."""
import os
from pathlib import Path
from encrypt_artifact import encrypt

if __name__ == "__main__":
    encrypt(Path("build_out/app.deb"), os.environ.get("ORDER_CODE", ""), os.environ.get("ARTIFACT_SECRET", ""))
