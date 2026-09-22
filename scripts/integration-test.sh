#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift run vaulty-self-test
node BrowserExtension/tests/short-form.test.js
node BrowserExtension/tests/session-policy.test.js
swift build -c release

BIN="$ROOT_DIR/.build/release/vaulty"
$BIN internal-verify-guard-config
HOSTS_FILE="$(mktemp -t vaulty-integration-hosts)"
trap 'rm -f "$HOSTS_FILE"' EXIT

printf '# preserved entry\n127.0.0.1 localhost\n' > "$HOSTS_FILE"

youtube_status_before="$($BIN status --hosts-file "$HOSTS_FILE")"
short_status_before="$($BIN short-form status --hosts-file "$HOSTS_FILE")"
[[ "$youtube_status_before" == *"unblocked"* ]]
[[ "$short_status_before" == *"unblocked"* ]]

# The original blocker must remain YouTube-only.
$BIN block --hosts-file "$HOSTS_FILE" >/dev/null
youtube_status_during="$($BIN status --hosts-file "$HOSTS_FILE")"
short_status_during="$($BIN short-form status --hosts-file "$HOSTS_FILE")"
[[ "$youtube_status_during" == *"blocked"* ]]
[[ "$short_status_during" == *"unblocked"* ]]
grep -Eq '^0\.0\.0\.0[[:space:]]+youtube\.com$' "$HOSTS_FILE"
if grep -Eq '^0\.0\.0\.0[[:space:]]+(tiktok\.com|instagram\.com|facebook\.com)$' "$HOSTS_FILE"; then
  printf 'integration test failed: YouTube blocker owns short-form mappings\n' >&2
  exit 1
fi

youtube_hash_before_repeat="$(shasum -a 256 "$HOSTS_FILE")"
$BIN block --hosts-file "$HOSTS_FILE" >/dev/null
youtube_hash_after_repeat="$(shasum -a 256 "$HOSTS_FILE")"
[[ "$youtube_hash_before_repeat" == "$youtube_hash_after_repeat" ]]

# The separate short-form blocker must coexist without replacing YouTube.
$BIN short-form block --hosts-file "$HOSTS_FILE" >/dev/null
short_status_on="$($BIN short-form status --hosts-file "$HOSTS_FILE")"
youtube_status_with_both="$($BIN status --hosts-file "$HOSTS_FILE")"
[[ "$short_status_on" == *"blocked"* ]]
[[ "$youtube_status_with_both" == *"blocked"* ]]

for domain in tiktok.com instagram.com youtube.com facebook.com; do
  if ! grep -Eq "^0\\.0\\.0\\.0[[:space:]]+$domain$" "$HOSTS_FILE"; then
    printf 'integration test failed: missing short-form host mapping for %s\n' "$domain" >&2
    exit 1
  fi
done

short_hash_before_repeat="$(shasum -a 256 "$HOSTS_FILE")"
$BIN short-form block --hosts-file "$HOSTS_FILE" >/dev/null
short_hash_after_repeat="$(shasum -a 256 "$HOSTS_FILE")"
[[ "$short_hash_before_repeat" == "$short_hash_after_repeat" ]]

$BIN short-form unblock --hosts-file "$HOSTS_FILE" >/dev/null
short_status_after="$($BIN short-form status --hosts-file "$HOSTS_FILE")"
youtube_status_after_short_unblock="$($BIN status --hosts-file "$HOSTS_FILE")"
[[ "$short_status_after" == *"unblocked"* ]]
[[ "$youtube_status_after_short_unblock" == *"blocked"* ]]
if grep -q "VAULTY SHORT-FORM MANAGED BLOCK" "$HOSTS_FILE"; then
  printf 'integration test failed: short-form managed block remains\n' >&2
  exit 1
fi
if grep -Eq '^0\.0\.0\.0[[:space:]]+(tiktok\.com|instagram\.com|facebook\.com)$' "$HOSTS_FILE"; then
  printf 'integration test failed: short-form mappings remain after independent unblock\n' >&2
  exit 1
fi

$BIN unblock --hosts-file "$HOSTS_FILE" >/dev/null
youtube_status_after="$($BIN status --hosts-file "$HOSTS_FILE")"
[[ "$youtube_status_after" == *"unblocked"* ]]

if grep -q "VAULTY MANAGED BLOCK" "$HOSTS_FILE" || grep -q "VAULTY SHORT-FORM MANAGED BLOCK" "$HOSTS_FILE"; then
  printf 'integration test failed: managed block remains\n' >&2
  exit 1
fi

if ! grep -q "# preserved entry" "$HOSTS_FILE"; then
  printf 'integration test failed: unrelated entry was lost\n' >&2
  exit 1
fi

printf 'integration test passed: independent YouTube and short-form blockers, idempotency, preservation, and unblock verified\n'
