# Frostwall

Frostwall is a small, free, open-source macOS website blocker. It blocks YouTube by adding a clearly marked, reversible section to `/etc/hosts`.

It is intentionally transparent rather than pretending to be unbreakable: a determined administrator can remove the block, use a VPN, change DNS, or use another device. The goal is to add enough friction to stop the automatic “open YouTube” loop.

## Requirements

- macOS 13 or newer
- Swift 5.9+ toolchain (Xcode Command Line Tools are enough)
- `sudo` access when managing `/etc/hosts`

## Build and test

```sh
swift run frostwall-self-test
swift build -c release
```

The self-test executable exercises the real file-editing core against temporary hosts files, including idempotency, preservation of unrelated entries, custom domains, and malformed-section protection. It is used instead of XCTest so the project can be tested with Apple's standalone Command Line Tools without requiring the full Xcode app.

## Install

From a clone of this repository:

```sh
swift build -c release
sudo install -m 755 .build/release/frostwall /usr/local/bin/frostwall
```

## Use it

Block the default YouTube domains:

```sh
sudo frostwall block
```

Check the state:

```sh
frostwall status
```

Remove only Frostwall’s managed section:

```sh
sudo frostwall unblock
```

Preview the exact entries without changing anything:

```sh
frostwall block --dry-run
```

Block a custom set instead of the defaults:

```sh
sudo frostwall block \
  --domain youtube.com \
  --domain www.youtube.com \
  --domain reddit.com
```

The custom domain list is written into the same marked section, so `frostwall unblock` removes it safely.

## Test without touching `/etc/hosts`

Every command accepts `--hosts-file`, which makes local integration testing safe:

```sh
tmp_hosts="$(mktemp)"
printf '# local test\n127.0.0.1 localhost\n' > "$tmp_hosts"
.build/release/frostwall status --hosts-file "$tmp_hosts"
.build/release/frostwall block --hosts-file "$tmp_hosts"
.build/release/frostwall status --hosts-file "$tmp_hosts"
.build/release/frostwall unblock --hosts-file "$tmp_hosts"
rm "$tmp_hosts"
```

## Safety model

- Only the section between `BEGIN FROSTWALL` and `END FROSTWALL` is changed.
- Existing hosts entries are preserved.
- Re-running `block` is idempotent.
- A malformed managed section causes Frostwall to stop instead of guessing.
- `unblock` removes only Frostwall’s section.
- The file’s original POSIX permissions and ownership identifiers are restored after an atomic write when possible.

## License

MIT. See [LICENSE](LICENSE).
