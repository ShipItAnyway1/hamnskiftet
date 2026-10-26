"""Resize native Godot screenshots for a fixed-width readability review.

This is a screenshot proof, not a device build or a player usability test.
The source pixels are only resized; the manifest ties each proof to its source.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("screenshots", nargs="+", type=Path)
    parser.add_argument("--width", type=int, default=390)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    if args.width < 1:
        parser.error("width must be positive")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest = {"kind": "native-screenshot-resize", "device_build": False, "width": args.width, "proofs": []}
    for source in args.screenshots:
        with Image.open(source) as screenshot:
            native_size = screenshot.size
            target = (args.width, round(screenshot.height * args.width / screenshot.width))
            proof = screenshot.resize(target, Image.Resampling.LANCZOS)
            output = args.output_dir / source.name
            proof.save(output)
        manifest["proofs"].append({"source": str(source.resolve()), "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                                   "source_size": native_size, "output": str(output.resolve()), "proof_size": target})
        print(f"MOBILE_PROOF {source.name}: {native_size} -> {target}")
    (args.output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
