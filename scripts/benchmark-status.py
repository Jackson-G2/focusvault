#!/usr/bin/env python3
"""Reproducible refresh-notification benchmark, including old checkout comparison.

Usage: python3 scripts/benchmark-status.py [checkout]
Requires `swift build --product vaulty-app` in that checkout first. Compiles a
non-GUI fixture harness; never prompts, changes hosts or touches user defaults.
Timings are diagnostic, not a noisy pass/fail threshold.
"""
from pathlib import Path
import json
import subprocess
import sys
import tempfile

HARNESS = r'''
import Combine
import Foundation
import VaultyCore

@main
struct StatusBenchmark {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let hosts = root.appendingPathComponent("hosts")
        try "127.0.0.1 localhost\n".write(to: hosts, atomically: true, encoding: .utf8)
        let storage = YouTubeGuardStorage(stateURL: root.appendingPathComponent("state.json"),
                                         requestDirectoryURL: root.appendingPathComponent("requests"),
                                         responseDirectoryURL: root.appendingPathComponent("responses"))
        let model = FocusVaultAppModel(hostsFileURL: hosts, guardInstalled: { false }, guardStorage: storage)
        var notifications = 0
        let subscriber = model.objectWillChange.sink { notifications += 1 }
        let samples = 1000
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<samples { model.refresh() }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        subscriber.cancel()
        let payload: [String: Any] = ["refreshes": samples, "notifications": notifications,
                                     "elapsedMilliseconds": Double(elapsed) / 1_000_000]
        print(String(decoding: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


def benchmark(root: Path) -> dict:
    sources = sorted((root / "Sources" / "FocusVaultApp").glob("*.swift"))
    objects = sorted((root / ".build" / "debug" / "VaultyCore.build").glob("*.swift.o"))
    modules = root / ".build" / "debug" / "Modules"
    if not objects or not modules.is_dir():
        raise RuntimeError("Build vaulty-app in this checkout before benchmarking it")
    with tempfile.TemporaryDirectory(prefix="vaulty-status-benchmark-") as scratch:
        scratch = Path(scratch)
        # Isolate every occurrence of preferences, including pre-refactor versions
        # whose constructors lack an injectable UserDefaults argument.
        replacements = []
        for source in sources:
            if source.name == "FocusVaultApp.swift":
                continue
            text = source.read_text()
            text = text.replace("UserDefaults.standard", 'UserDefaults(suiteName: "VaultyBenchmark.Isolated")!')
            text = text.replace("defaults: UserDefaults = .standard", 'defaults: UserDefaults = UserDefaults(suiteName: "VaultyBenchmark.Isolated")!')
            copy = scratch / source.name
            copy.write_text(text)
            replacements.append(copy)
        harness = scratch / "StatusBenchmark.swift"
        harness.write_text(HARNESS)
        executable = scratch / "benchmark"
        command = ["swiftc", "-O", "-parse-as-library", "-I", str(modules)]
        command += [str(path) for path in replacements + [harness] + objects]
        command += ["-o", str(executable)]
        compiled = subprocess.run(command, capture_output=True, text=True, timeout=180)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        result = subprocess.run([str(executable)], capture_output=True, text=True, check=True, timeout=30)
        return json.loads(result.stdout)


if __name__ == "__main__":
    checkout = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
    print(json.dumps({"checkout": str(checkout), **benchmark(checkout)}, indent=2))
