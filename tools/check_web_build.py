#!/usr/bin/env python3
"""Validate the real export and publish a commit/hash manifest beside it."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import struct


def pack_files(data: bytes) -> set[str]:
    # Godot 4.6 PCK v3 stores its unencrypted resource directory at the end.
    if struct.unpack_from("<I", data, 4)[0] != 3:
        raise SystemExit("Unexpected Godot pack version")
    offset = struct.unpack_from("<Q", data, 32)[0]
    count = struct.unpack_from("<I", data, offset)[0]
    position = offset+4
    names = set()
    for _ in range(count):
        length = struct.unpack_from("<I", data, position)[0]
        position += 4
        names.add(data[position:position+length].rstrip(b"\0").decode())
        position += length+36  # Offset, size, MD5 and file flags.
    return names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=Path("build/web"))
    parser.add_argument("--log", type=Path)
    args = parser.parse_args()
    output = args.build_dir
    if args.log and re.search(r"SCRIPT ERROR|(?:^|\n)ERROR:", args.log.read_text(), re.I):
        raise SystemExit("Web export log contains an engine/script error")
    html = (output/"index.html").read_text()
    if "$GODOT_" in html or "Spela" not in html:
        raise SystemExit("Web shell was not exported correctly")
    wasm = output/"index.wasm"
    if wasm.read_bytes()[:8] != b"\0asm\x01\0\0\0":
        raise SystemExit("Missing or invalid WebAssembly runtime")
    pack = (output/"index.pck").read_bytes()
    if pack[:4] != b"GDPC":
        raise SystemExit("Missing or invalid Godot resource pack")
    names = pack_files(pack)
    for required in ["assets/audio/v7/harbor_groove.wav.import", "assets/art/harbor-hero-v4.png.import", "main.gd.remap"]:
        if required not in names:
            raise SystemExit(f"Required packaged asset missing: {required!r}")
    audio_count = sum(name.startswith("assets/audio/v7/") and name.endswith(".wav.import") for name in names)
    if audio_count != 22:
        raise SystemExit(f"Expected all22 runtime audio resources, found{audio_count}")
    for name in names:
        if name.startswith(("qa/", "tests/", "tools/", "node_modules/")) or "before-v7.cfg" in name:
            raise SystemExit("Local player/test evidence must not be exported")
    commit = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True)
    manifest = {"commit": commit.stdout.strip() if commit.returncode == 0 else "local-preview", "godot": "4.6.2", "platform": "web-single-thread", "files": {}}
    for name in ["index.html", "index.js", "index.pck", "index.wasm"]:
        data = (output/name).read_bytes()
        manifest["files"][name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    (output/"build-info.json").write_text(json.dumps(manifest, indent=2)+"\n")
    (output/".nojekyll").touch()
    print("WEB_BUILD_OK "+json.dumps({"commit":manifest["commit"], "files":len(manifest["files"])}))


if __name__ == "__main__":
    main()
