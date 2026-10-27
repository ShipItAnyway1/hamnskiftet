#!/usr/bin/env python3
"""Import and test the current Godot V7 slice in a disposable project copy.

Example: GODOT_BIN=godot python3 tools/run_ci.py --log-dir ci-results
Only the Python standard library is required. No player profile is loaded.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

TESTS = (
    ("test_v7_rules.gd", "V7_RULES_TESTS_OK"),
    ("test_v7_save.gd", "V7_SAVE_TESTS_OK"),
    ("test_v7_rewards.gd", "V7_REWARDS_TESTS_OK"),
    ("test_v7_controller.gd", "V7_CONTROLLER_TESTS_OK"),
    ("test_v7_view_ui.gd", "V7_VIEW_UI_OK"),
    ("test_rescue.gd", "RESCUE_FX_TESTS_OK"),
    ("test_audio.gd", "TRUCK_AUDIO_V7_OK"),
    ("test_web_input.gd", "WEB_INPUT_TESTS_OK"),
    ("test_mobile_layout.gd", "MOBILE_LAYOUT_TESTS_OK"),
    ("test_mobile_harbor.gd", "MOBILE_HARBOR_TESTS_OK"),
    ("test_mobile_view.gd", "MOBILE_VIEW_TESTS_OK"),
    ("test_mobile_gestures.gd", "MOBILE_GESTURES_TESTS_OK"),
)
SCRIPT_ERROR = re.compile(r"SCRIPT ERROR|Parse Error|Failed to load script", re.I)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--log-dir", type=Path)
    parser.add_argument("--timeout", type=float, default=120, help="Seconds per test (default:120)")
    parser.add_argument("--import-timeout", type=float, default=180)
    args = parser.parse_args()
    if args.timeout <= 0 or args.import_timeout <= 0:
        parser.error("Timeouts must be positive")
    godot = shutil.which(args.godot)
    if not godot:
        parser.error("Godot editor executable not found; set GODOT_BIN or --godot")
    project = args.project.resolve()
    if not (project / "project.godot").is_file():
        parser.error(f"Missing project.godot in {project}")
    logs = args.log_dir.resolve() if args.log_dir else Path(tempfile.mkdtemp(prefix="hamnskiftet-ci-logs-"))
    logs.mkdir(parents=True, exist_ok=True)
    print(f"CI logs: {logs}", flush=True)
    failed = []
    with tempfile.TemporaryDirectory(prefix="hamnskiftet-ci-") as work:
        sandbox = Path(work)
        isolated = sandbox / "project"
        shutil.copytree(project, isolated, ignore=shutil.ignore_patterns(".godot", ".git", ".cache", "node_modules", "qa", "build", "builds", "web-build", "export", "exports", "ci-results", "__pycache__"))
        # Even an unforeseen user:// access belongs to a distinct CI app name.
        settings = isolated / "project.godot"
        source = settings.read_text(encoding="utf-8")
        source = re.sub(r'^config/name=.*$', f'config/name="Hamnskiftet CI {sandbox.name}"', source, flags=re.M)
        source = re.sub(r'^config/use_custom_user_dir=.*\n?', '', source, flags=re.M)
        source = re.sub(r'^config/custom_user_dir_name=.*\n?', '', source, flags=re.M)
        settings.write_text(source, encoding="utf-8")
        env = os.environ.copy()
        env["XDG_DATA_HOME"] = str(sandbox / "data")
        env["XDG_CONFIG_HOME"] = str(sandbox / "config")
        env["XDG_CACHE_HOME"] = str(sandbox / "cache")
        jobs = [("import", ["--editor", "--import"], None, args.import_timeout)]
        jobs += [(Path(name).stem, ["--script", f"res://tests/{name}"], marker, args.timeout) for name, marker in TESTS]
        for name, flags, marker, timeout in jobs:
            began = time.monotonic()
            command = [godot, "--headless", "--path", str(isolated), "--log-file", str(logs / f"{name}.godot.log"), *flags]
            timed_out = False
            try:
                result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", timeout=timeout, env=env)
                output, exit_code = result.stdout, result.returncode
            except subprocess.TimeoutExpired as error:
                partial = error.stdout or b""
                output = partial.decode("utf-8", errors="replace") if isinstance(partial, bytes) else partial
                output += f"\nCI TIMEOUT after {timeout:g}s\n"
                exit_code, timed_out = -1, True
            (logs / f"{name}.stdout.log").write_text(output, encoding="utf-8")
            engine_log = logs / f"{name}.godot.log"
            diagnostics = output + (engine_log.read_text(encoding="utf-8", errors="replace") if engine_log.is_file() else "")
            marker_found = marker is None or re.search(rf"^{re.escape(marker)}(?:[:\s]|$)", output, re.M) is not None
            ok = exit_code == 0 and not timed_out and not SCRIPT_ERROR.search(diagnostics) and marker_found
            print(f"{'PASS' if ok else 'FAIL'} {name} ({time.monotonic()-began:.1f}s, exit {exit_code})", flush=True)
            if marker and ok:
                print(next(line for line in output.splitlines() if line.startswith(marker)), flush=True)
            if not ok:
                failed.append(name)
                print(output[-10000:], flush=True)
                if name == "import":
                    break
    if failed:
        print("CI_FAILED: " + ", ".join(failed), file=sys.stderr)
        return 1
    print(f"CI_OK: clean import and all {len(TESTS)} V7 tests passed; logs: {logs}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
