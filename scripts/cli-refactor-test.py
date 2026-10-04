#!/usr/bin/env python3
"""Black-box release CLI regressions. Temporary hosts and invalid native frames only."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / ".build/release/vaulty"


def run(*args, data=None, expected=0):
    result = subprocess.run([str(BIN), *args], input=data, capture_output=True, timeout=20)
    if result.returncode != expected:
        raise AssertionError((args, result.returncode, result.stdout, result.stderr))
    return result.stdout


def concurrent_scopes():
    invocations = 0
    with tempfile.TemporaryDirectory(prefix="vaulty-concurrent-hosts-") as scratch:
        hosts = Path(scratch) / "hosts"
        alias = Path(scratch) / "alias"
        alias.symlink_to(hosts)
        for original in [b"# preserved Unicode \xe2\x98\x83\n127.0.0.1 localhost", b"127.0.0.1 localhost\r\n", b""]:
            hosts.write_bytes(original)
            for action in ["block", "unblock"]:
                commands = [([action] if index % 2 == 0 else ["short-form", action])
                            + ["--hosts-file", str(hosts if index % 3 else alias)] for index in range(32)]
                with ThreadPoolExecutor(max_workers=12) as pool:
                    results = list(pool.map(lambda args: run(*args), commands))
                invocations += len(results)
                actual = hosts.read_bytes()
                if action == "block":
                    if b"# BEGIN VAULTY MANAGED BLOCK" not in actual or b"# BEGIN VAULTY SHORT-FORM MANAGED BLOCK" not in actual:
                        raise AssertionError("concurrent writers lost an independent scope")
                    run("status", "--hosts-file", str(hosts))
                    run("short-form", "status", "--hosts-file", str(hosts))
                elif actual != original:
                    raise AssertionError("concurrent unblock did not restore exact original bytes")
                if not alias.is_symlink():
                    raise AssertionError("concurrent mutation replaced the user's symlink")
        if sorted(path.name for path in Path(scratch).iterdir()) != ["alias", "hosts"]:
            raise AssertionError("hosts transactions leaked lock/staging sidecar files")
    print("PASS: %s concurrent CLI mutations preserve both scopes, symlink aliases, LF/CRLF/Unicode/empty bytes, and exact restoration" % invocations)


def malformed_native_frames():
    def frame(payload):
        return struct.pack("<I", len(payload)) + payload
    cases = [b"\x01", struct.pack("<I", 0), struct.pack("<I", 2), struct.pack("<I", 100) + b"{}",
             struct.pack("<I", 1_048_577), frame(b"not JSON"),
             frame(json.dumps({"id": "fixture", "command": "unlock"}).encode())]
    for data in cases:
        output = run("internal-native-host", data=data, expected=1)
        if len(output) < 4:
            raise AssertionError("native failure response lacks a frame")
        length = struct.unpack("<I", output[:4])[0]
        if len(output) != length + 4 or json.loads(output[4:]).get("ok") is not False:
            raise AssertionError("malformed native message did not fail closed")
    if run("internal-native-host", data=b""):
        raise AssertionError("clean EOF must not produce a native reply")
    print("PASS: %s malformed/oversized/truncated/unauthorized native frames reject; clean EOF succeeds" % len(cases))


if __name__ == "__main__":
    run("internal-refactor-self-test")
    concurrent_scopes()
    malformed_native_frames()
