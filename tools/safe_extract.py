"""Extract untrusted ZIP, tar, or Debian ar archives without creating links."""
from __future__ import annotations

import argparse
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import tarfile
import zipfile

MAX_FILES = int(os.environ.get("SCAN_MAX_FILES", "50000"))
MAX_SIZE = int(os.environ.get("SCAN_MAX_SIZE", str(2 * 1024**3)))
MAX_DEPTH = int(os.environ.get("SCAN_MAX_DEPTH", "32"))
MAX_NAME = int(os.environ.get("SCAN_MAX_NAME", "255"))
CHUNK = 64 * 1024


class Extractor:
    def __init__(self, root: Path):
        self.root = root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.files = 0
        self.bytes = 0
        self.skipped = 0
        self.skipped_links = 0

    def destination(self, name: str) -> Path | None:
        name = name.replace("\\", "/")
        path = PurePosixPath(name)
        if (not name or name.startswith("/") or re.match(r"^[A-Za-z]:", name)
                or "\x00" in name or ".." in path.parts or len(path.parts) > MAX_DEPTH
                or any(len(part) > MAX_NAME for part in path.parts)):
            self.skipped += 1
            return None
        destination = (self.root / path).resolve()
        if not destination.is_relative_to(self.root):
            self.skipped += 1
            return None
        return destination

    def _parents(self, destination: Path) -> bool:
        relative = destination.relative_to(self.root)
        current = self.root
        for part in relative.parts[:-1]:
            current = current / part
            if current.is_symlink() or (current.exists() and not current.is_dir()):
                self.skipped += 1
                return False
            current.mkdir(exist_ok=True)
        return True

    def directory(self, name: str) -> None:
        destination = self.destination(name)
        if destination is None or not self._parents(destination):
            return
        if destination.is_symlink() or (destination.exists() and not destination.is_dir()):
            self.skipped += 1
            return
        destination.mkdir(exist_ok=True)

    def file(self, name: str, source) -> None:
        destination = self.destination(name)
        if destination is None or not self._parents(destination):
            return
        if self.files >= MAX_FILES:
            raise ValueError("Archive vượt giới hạn số file")
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
        try:
            fd = os.open(destination, flags, 0o600)
        except FileExistsError:
            self.skipped += 1
            return
        self.files += 1
        try:
            with os.fdopen(fd, "wb") as output:
                while chunk := source.read(CHUNK):
                    if self.bytes + len(chunk) > MAX_SIZE:
                        raise ValueError("Archive vượt giới hạn dung lượng giải nén")
                    output.write(chunk)
                    self.bytes += len(chunk)
        except BaseException:
            destination.unlink(missing_ok=True)
            raise

    def skip_link(self) -> None:
        self.skipped += 1
        self.skipped_links += 1


def _zip(archive: Path, extractor: Extractor) -> None:
    with zipfile.ZipFile(archive) as members:
        for item in members.infolist():
            mode = item.external_attr >> 16
            kind = stat.S_IFMT(mode)
            if kind == stat.S_IFLNK:
                extractor.skip_link()
            elif kind not in (0, stat.S_IFREG, stat.S_IFDIR):
                extractor.skipped += 1
            elif item.is_dir() or kind == stat.S_IFDIR:
                extractor.directory(item.filename)
            else:
                with members.open(item) as source:
                    extractor.file(item.filename, source)


def _tar(stream, extractor: Extractor) -> None:
    with tarfile.open(fileobj=stream, mode="r|*") as members:
        for item in members:
            if item.issym() or item.islnk():
                extractor.skip_link()
            elif item.isdir():
                extractor.directory(item.name)
            elif item.isfile():
                source = members.extractfile(item)
                if source is None:
                    raise ValueError("Không đọc được file trong tar")
                with source:
                    extractor.file(item.name, source)
            else:
                extractor.skipped += 1


class _LimitedReader:
    def __init__(self, stream, remaining: int):
        self.stream = stream
        self.remaining = remaining

    def read(self, amount=-1):
        if amount < 0 or amount > self.remaining:
            amount = self.remaining
        data = self.stream.read(amount)
        self.remaining -= len(data)
        return data


def _deb(stream, extractor: Extractor) -> None:
    if stream.read(8) != b"!<arch>\n":
        raise ValueError("Debian ar không hợp lệ")
    found = False
    while header := stream.read(60):
        if len(header) != 60 or header[58:] != b"`\n":
            raise ValueError("Debian ar header không hợp lệ")
        try:
            size = int(header[48:58].strip())
        except ValueError as exc:
            raise ValueError("Debian ar size không hợp lệ") from exc
        name = header[:16].decode("ascii", "replace").strip().rstrip("/")
        if size < 0:
            raise ValueError("Debian ar size không hợp lệ")
        member = _LimitedReader(stream, size)
        if name.startswith("data.tar") and not found:
            _tar(member, extractor)
            found = True
        while member.remaining:
            if not member.read(min(CHUNK, member.remaining)):
                raise ValueError("Debian ar bị cắt")
        if size % 2:
            stream.read(1)
    if not found:
        raise ValueError("Debian ar thiếu data.tar")


def extract(archive: Path, root: Path) -> Extractor:
    extractor = Extractor(root)
    if zipfile.is_zipfile(archive):
        _zip(archive, extractor)
    else:
        with archive.open("rb") as source:
            if source.read(8) == b"!<arch>\n":
                source.seek(0)
                _deb(source, extractor)
            else:
                source.seek(0)
                _tar(source, extractor)
    return extractor


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    result = extract(args.archive, args.destination)
    print(f"files={result.files} bytes={result.bytes} skipped={result.skipped} links={result.skipped_links}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, tarfile.TarError, zipfile.BadZipFile) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
