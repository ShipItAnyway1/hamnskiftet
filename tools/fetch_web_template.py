#!/usr/bin/env python3
"""Fetch only the single-threaded Web template from the official Godot TPZ.

HTTP byte ranges avoid downloading 1.2 GB of unrelated mobile/desktop templates.
ZIP central-directory metadata and CRC validation come from Python's zipfile.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import urllib.request
import zipfile

PINNED_SHA256 = {"4.6.2": "7d91986ea27d901b37963ace014a88ab6ba8e4bfe830031043bcf89ebac307dc"}

class RemoteZip(io.RawIOBase):
    def __init__(self, url: str, size: int):
        self.url, self.size, self.position = url, size, 0

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=io.SEEK_SET):
        self.position = offset if whence == io.SEEK_SET else (self.position if whence == io.SEEK_CUR else self.size) + offset
        if self.position < 0:
            raise ValueError("Negative ZIP offset")
        return self.position

    def read(self, size=-1):
        size = min(self.size-self.position, size if size >= 0 else self.size-self.position)
        if size <= 0:
            return b""
        start, end = self.position, self.position+size-1
        request = urllib.request.Request(self.url, headers={"Range": f"bytes={start}-{end}", "Accept-Encoding": "identity", "User-Agent": "Hamnskiftet-build"})
        with urllib.request.urlopen(request, timeout=90) as response:
            if response.status != 206 or not response.headers.get("Content-Range", "").startswith(f"bytes {start}-"):
                raise RuntimeError("Official asset server did not honor byte-range request")
            data = response.read(size+1)
        if len(data) != size:
            raise RuntimeError("Incomplete template byte range")
        self.position += len(data)
        return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="4.6.2")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1]/".cache/godot/web_nothreads_release.zip")
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.is_file() and zipfile.is_zipfile(args.output) and hashlib.sha256(args.output.read_bytes()).hexdigest() == PINNED_SHA256.get(args.version):
        print(f"WEB_TEMPLATE_CACHED {args.output}")
        return
    release = f"https://api.github.com/repos/godotengine/godot-builds/releases/tags/{args.version}-stable"
    with urllib.request.urlopen(urllib.request.Request(release, headers={"User-Agent": "Hamnskiftet-build"}), timeout=30) as response:
        metadata = json.load(response)
    asset = next(item for item in metadata["assets"] if item["name"] == f"Godot_v{args.version}-stable_export_templates.tpz")
    with zipfile.ZipFile(RemoteZip(asset["browser_download_url"], asset["size"])) as archive:
        entry = next(name for name in archive.namelist() if name.endswith("/web_nothreads_release.zip"))
        data = archive.read(entry)
    if args.version in PINNED_SHA256 and hashlib.sha256(data).hexdigest() != PINNED_SHA256[args.version]:
        raise RuntimeError("Official web template does not match the pinned version hash")
    temporary = args.output.with_suffix(".tmp")
    temporary.write_bytes(data)
    with zipfile.ZipFile(temporary) as template:
        if template.testzip() is not None:
            raise RuntimeError("Web template failed ZIP CRC validation")
    temporary.replace(args.output)
    provenance = {"godot": args.version, "source": asset["browser_download_url"], "entry": entry,
                  "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
    args.output.with_suffix(".json").write_text(json.dumps(provenance, indent=2)+"\n")
    print("WEB_TEMPLATE_READY "+json.dumps(provenance))


if __name__ == "__main__":
    main()
