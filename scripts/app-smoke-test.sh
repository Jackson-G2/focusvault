#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

scripts/package-app.sh >/dev/null

"$ROOT_DIR/dist/Vaulty.app/Contents/MacOS/Vaulty" --self-test

DASHBOARD="$ROOT_DIR/Sources/FocusVaultApp/FocusVaultDashboard.swift"
GLASS_UI="$ROOT_DIR/Sources/FocusVaultApp/GlassUI.swift"
SLEEP_VIEW="$ROOT_DIR/Sources/FocusVaultApp/SleepCalculatorView.swift"
TOOLS_VIEW="$ROOT_DIR/Sources/FocusVaultApp/LocalToolsView.swift"
CHALLENGE_VIEW="$ROOT_DIR/Sources/FocusVaultApp/UnlockChallengeViews.swift"
WIDGET_GRID="$ROOT_DIR/Sources/FocusVaultApp/DashboardWidgetGrid.swift"

for identifier in \
  toggle-youtube-vault \
  toggle-short-form-vault \
  open-channel-vault-setup \
  open-sleep-calculator \
  start-task-clock \
  pause-task-clock \
  resume-task-clock \
  end-task-clock \
  learning-guide-action \
  reset-dashboard-widgets \
  arrange-dashboard-widgets; do
  grep -q "accessibilityIdentifier(\"$identifier\")" "$DASHBOARD" || {
    printf 'app smoke test failed: missing button identifier %s\n' "$identifier" >&2
    exit 1
  }
done

grep -q 'allowsHitTesting(false)' "$GLASS_UI" || {
  printf 'app smoke test failed: decorative glass layers remain interactive\n' >&2
  exit 1
}
grep -q 'SleepCalculator.recommendations' "$SLEEP_VIEW" || {
  printf 'app smoke test failed: sleep calculator view is not wired to core logic\n' >&2
  exit 1
}
for identifier in add-local-tool manage-local-tools save-local-tool; do
  grep -q "accessibilityIdentifier(\"$identifier\")" "$TOOLS_VIEW" || {
    printf 'app smoke test failed: missing tools identifier %s\n' "$identifier" >&2
    exit 1
  }
done
grep -q 'DragGesture(minimumDistance: 0)' "$CHALLENGE_VIEW" || {
  printf 'app smoke test failed: grid shot must use press-based click capture, not a movement-sensitive tap\n' >&2
  exit 1
}
if grep -q 'SpatialTapGesture' "$CHALLENGE_VIEW"; then
  printf 'app smoke test failed: SpatialTapGesture eats clicks made while the mouse is moving\n' >&2
  exit 1
fi
for identifier in \
  choose-unlock-gridShot \
  choose-unlock-typingSprint \
  choose-unlock-signalShift \
  start-grid-shot \
  confirm-grid-shot-unlock \
  typing-sprint-input \
  start-typing-sprint \
  confirm-typing-sprint-unlock; do
  grep -q "$identifier" "$CHALLENGE_VIEW" || {
    printf 'app smoke test failed: missing unlock-game identifier %s\n' "$identifier" >&2
    exit 1
  }
done

grep -q 'accessibilityIdentifier("signal-cell-' "$ROOT_DIR/Sources/FocusVaultApp/SignalShiftChallengeView.swift" || {
  printf 'app smoke test failed: Signal Shift cells are not exposed to accessibility\n' >&2
  exit 1
}
grep -q 'accessibilityIdentifier("cancel-signal-shift")' "$ROOT_DIR/Sources/FocusVaultApp/SignalShiftChallengeView.swift" || {
  printf 'app smoke test failed: Signal Shift cancel action is missing\n' >&2
  exit 1
}

grep -q 'accessibilityIdentifier("start-signal-shift")' "$ROOT_DIR/Sources/FocusVaultApp/SignalShiftChallengeView.swift" || {
  printf 'app smoke test failed: Signal Shift start action is missing\n' >&2
  exit 1
}
grep -q 'accessibilityIdentifier("replay-signal-path")' "$ROOT_DIR/Sources/FocusVaultApp/SignalShiftChallengeView.swift" || {
  printf 'app smoke test failed: Signal Shift replay action is missing\n' >&2
  exit 1
}
grep -q 'accessibilityIdentifier("confirm-signal-shift-unlock")' "$ROOT_DIR/Sources/FocusVaultApp/SignalShiftChallengeView.swift" || {
  printf 'app smoke test failed: Signal Shift confirmation action is missing\n' >&2
  exit 1
}
for identifier in move-widget- resize-widget- widget-menu-; do
  grep -q "accessibilityIdentifier(\"$identifier" "$WIDGET_GRID" || {
    printf 'app smoke test failed: missing dynamic widget affordance %s\n' "$identifier" >&2
    exit 1
  }
done

printf 'PASS: packaged Vaulty self-test exercises verified explicit unlock, selectable task hub, free-position resizing, button targets, and non-interactive glass decoration\n'
