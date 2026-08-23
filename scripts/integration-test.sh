#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift run frostwall-self-test
swift build -c release

BIN="$ROOT_DIR/.build/release/frostwall"
HOSTS_FILE="$(mktemp -t frostwall-integration-hosts)"
trap 'rm -f "$HOSTS_FILE"' EXIT

printf '# preserved entry\n127.0.0.1 localhost\n' > "$HOSTS_FILE"

status_before="$($BIN status --hosts-file "$HOSTS_FILE")"
[[ "$status_before" == *"unblocked"* ]]

$BIN block --hosts-file "$HOSTS_FILE" >/dev/null
status_during="$($BIN status --hosts-file "$HOSTS_FILE")"
[[ "$status_during" == *"blocked"* ]]

first_hash="$(shasum -a 256 "$HOSTS_FILE")"
$BIN block --hosts-file "$HOSTS_FILE" >/dev/null
second_hash="$(shasum -a 256 "$HOSTS_FILE")"
[[ "$first_hash" == "$second_hash" ]]

$BIN unblock --hosts-file "$HOSTS_FILE" >/dev/null
status_after="$($BIN status --hosts-file "$HOSTS_FILE")"
[[ "$status_after" == *"unblocked"* ]]

if grep -q "FROSTWALL MANAGED BLOCK" "$HOSTS_FILE"; then
  printf 'integration test failed: managed block remains\n' >&2
  exit 1
fi

if ! grep -q "# preserved entry" "$HOSTS_FILE"; then
  printf 'integration test failed: unrelated entry was lost\n' >&2
  exit 1
fi

printf 'integration test passed: block, idempotency, preservation, and unblock verified\n'
