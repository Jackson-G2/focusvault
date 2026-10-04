#!/usr/bin/env python3
"""Cheap source wiring checks; behavioural coverage lives in --self-test.

Search the entire app target, not old container filenames. Moving a view into
its own module must not make a smoke check fail or silently skip that control.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "Sources" / "FocusVaultApp"


def check_contracts() -> list:
    sources = {path.name: path.read_text() for path in sorted(APP.glob("*.swift"))}
    combined = "\n".join(sources.values())
    required = [
        "toggle-youtube-vault", "toggle-short-form-vault", "open-channel-vault-setup",
        "open-sleep-calculator", "start-task-clock", "pause-task-clock", "resume-task-clock",
        "end-task-clock", "learning-guide-action", "reset-dashboard-widgets", "arrange-dashboard-widgets",
        "add-local-tool", "manage-local-tools", "save-local-tool", "choose-unlock-gridShot",
        "choose-unlock-typingSprint", "choose-unlock-signalShift", "start-grid-shot",
        "confirm-grid-shot-unlock", "typing-sprint-input", "start-typing-sprint",
        "confirm-typing-sprint-unlock", "signal-cell-", "cancel-signal-shift", "start-signal-shift",
        "replay-signal-path", "confirm-signal-shift-unlock", "move-widget-", "resize-widget-", "widget-menu-",
    ]
    failures = ["missing accessibility identifier: " + key for key in required if key not in combined]
    if "repeatForever" in sources.get("AppBackground.swift", ""):
        failures.append("idle backdrop must not schedule continuous decorative animation")
    if "!materialSnapshot, !isProminent" not in sources.get("GlassUI.swift", ""):
        failures.append("native primary actions require an opaque high-contrast treatment")
    if "allowsHitTesting(false)" not in sources.get("GlassUI.swift", ""):
        failures.append("decorative glass layers must not intercept input")
    if "SleepCalculator.recommendations" not in combined:
        failures.append("sleep calculator must use the tested core")
    grid_shot = sources.get("GridShotChallengeView.swift", "")
    if "DragGesture(minimumDistance: 0)" not in grid_shot or "SpatialTapGesture" in grid_shot:
        failures.append("Grid Shot must accept mouse-down while moving")
    if "CapturedProcessTask(process)" not in sources.get("VideoResearch.swift", ""):
        failures.append("learning researcher must drain both process streams")
    if "interactiveDismissDisabled(model.isBusy)" not in sources.get("UnlockChallengeSheet.swift", ""):
        failures.append("in-flight unlock must keep its sheet transaction alive")
    return failures


if __name__ == "__main__":
    errors = check_contracts()
    for error in errors:
        print("FAIL: " + error, file=sys.stderr)
    if errors:
        raise SystemExit(1)
    print("PASS: modular app accessibility and service wiring contracts")
