# FocusVault — macOS Website Blocker

FocusVault is a free, open-source macOS website blocker that helps you vault in, block distractions, and get work done.

> Vault in. Get work done.

It blocks YouTube by adding a clearly marked, reversible section to `/etc/hosts`. FocusVault is intentionally transparent rather than pretending to be impossible to bypass: a determined administrator can remove the block, use a VPN or secure DNS, or switch devices. The goal is to add friction to the automatic “open YouTube” loop.

## Why FocusVault

- Simple macOS website blocker with no subscription
- Free and open source under the MIT license
- Focused on getting into a work vault quickly
- Safe, reversible edits to `/etc/hosts`
- Works across browsers that respect the system hosts file
- Migrates older Frostwall-managed sections safely
- Built-in dry-run mode and a broad edge-case test suite

## Requirements

- macOS 13 or newer
- Swift 5.9+ toolchain (Xcode Command Line Tools are enough)
- `sudo` access when managing `/etc/hosts`

## Build and test

Run the full local verification suite:

```sh
swift run focusvault-self-test
```

This runs 57 edge-case tests covering:

- Empty, missing, large, Unicode, LF, and CRLF hosts files
- Exact round-trip restoration, including files without final newlines
- Idempotent block/unblock cycles
- Custom domains, URL normalization, deduplication, and punycode
- Invalid hostnames, wildcards, IP literals, injection attempts, and oversized labels
- Duplicate, nested, reversed, mixed, indented, and malformed markers
- Legacy Frostwall migration
- Permission preservation and write/read failures
- 100 repeated block/unblock cycles

Build the release binary:

```sh
swift build -c release
```

Run the compiled integration flow:

```sh
./scripts/integration-test.sh
```

## Install

From a clone of this repository:

```sh
swift build -c release
sudo install -m 755 .build/release/focusvault /usr/local/bin/focusvault
```

## Use FocusVault

Vault in and block the default YouTube domains:

```sh
sudo focusvault block
```

Check whether the vault is engaged:

```sh
focusvault status
```

Open the vault and remove only FocusVault’s managed section:

```sh
sudo focusvault unblock
```

Preview the exact entries without changing anything:

```sh
focusvault block --dry-run
```

Block a custom set of sites instead of the defaults:

```sh
sudo focusvault block \
  --domain youtube.com \
  --domain www.youtube.com \
  --domain reddit.com
```

The custom domain list is written into the same marked section, so `focusvault unblock` removes it safely.

## Test without touching `/etc/hosts`

Every command accepts `--hosts-file`, which makes manual testing safe:

```sh
tmp_hosts="$(mktemp)"
printf '# local test\n127.0.0.1 localhost\n' > "$tmp_hosts"
.build/release/focusvault status --hosts-file "$tmp_hosts"
.build/release/focusvault block --hosts-file "$tmp_hosts"
.build/release/focusvault status --hosts-file "$tmp_hosts"
.build/release/focusvault unblock --hosts-file "$tmp_hosts"
rm "$tmp_hosts"
```

## Safety model

- Only the section between `BEGIN FOCUSVAULT` and `END FOCUSVAULT` is changed.
- Existing hosts entries are preserved byte-for-byte after unblocking.
- Re-running `block` is idempotent.
- A malformed, duplicated, nested, or mixed legacy section causes FocusVault to stop instead of guessing.
- `unblock` removes only a valid FocusVault or legacy Frostwall section.
- LF and CRLF line endings are preserved.
- The file’s original POSIX permissions and ownership identifiers are restored after an atomic write when possible.
- The old Frostwall marker format is recognized so upgrades remain reversible.

## Short command summary

```text
focusvault block      Engage the focus vault for YouTube.
focusvault unblock    Open the vault and remove its managed section.
focusvault status     Show whether the vault is engaged.
focusvault version    Print the installed version.
```

## License

MIT. See [LICENSE](LICENSE).
