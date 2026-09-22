# Vaulty — macOS Website Blocker

Vaulty is a free, open-source macOS website blocker that helps you vault in, block distractions, and get work done.

> Vault in. Get work done.

It keeps the original YouTube blocker and adds a separate short-form vault. Each feature writes its own clearly marked, reversible section to `/etc/hosts`; the short-form vault covers TikTok, Instagram, YouTube, and Facebook hostnames, while the browser companion adds path-level protection for Reels and Shorts. Vaulty is intentionally transparent rather than pretending to be impossible to bypass: a determined administrator can remove the block, use a VPN or secure DNS, or switch devices.

## Why Vaulty

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
- Python 3, `yt-dlp`, and an authenticated Pi CLI for the optional learning guide

## Build and test

Run the full local verification suite:

```sh
make test
```

This runs 92 Swift edge-case tests covering:

- Empty, missing, large, Unicode, LF, and CRLF hosts files
- Exact round-trip restoration, including files without final newlines
- Idempotent block/unblock cycles
- Custom domains, URL normalization, deduplication, and punycode
- Invalid hostnames, wildcards, IP literals, injection attempts, and oversized labels
- Duplicate, nested, reversed, mixed, indented, and malformed markers
- Legacy Frostwall migration
- Permission preservation and write/read failures
- 100 repeated block/unblock cycles
- Exact task estimates, invalid durations, pause/resume remainder preservation, completion, and early stop reset
- Password-free lock requests, one-use authorization rejection, fixed 2,700-second leases, no in-place extension, and short-form scope restoration
- Non-gating Signal Shift transforms/lives, Grid Shot scoring at 30 in 10 seconds, Typing Sprint accuracy/deadline, and a required rotation that excludes Signal Shift

Run the browser policy suites too:

```sh
make short-form-test
```

Or run the two browser suites directly:

```sh
node BrowserExtension/tests/policy.test.js
node BrowserExtension/tests/short-form.test.js
node BrowserExtension/tests/session-policy.test.js
```

The extension suites cover official YouTube channel identities, owner checks, feed blocking, malformed configuration, 12 short-form cases, and nine timed-session/native-bridge cases including exact expiry and the pinned extension identity.

Build the release binary:

```sh
swift build -c release
```

Run the compiled integration flow:

```sh
make integration
```

Run the packaged-app smoke test (build, model interaction self-test, button identifiers, bundled resources, and hit-test guard):

```sh
make app-test
```

## Standalone Mac app

The recommended entry point is the native `Vaulty.app` dashboard. It uses SwiftUI’s native Liquid Glass interface on macOS 26+ and a material fallback on older supported macOS versions. The UI direction, Tideglass palette, and addition gate live in [DESIGN.md](DESIGN.md).

Build and open it:

```sh
make app
open dist/Vaulty.app
```

Inside the app:

- Write a short local intention so the protected stretch has a reason.
- Set the exact task estimate in whole minutes, from 1 to 240, before starting the Task clock. The same clock works for short 10-minute tasks and longer 25-, 50-, or 90-minute stretches.
- Use `Arrange` to open a four-column Apple-style canvas. Drag a widget’s orange move label to any grid slot, keep intentional gaps, drag its bottom-right handle to resize continuously, or use its menu for Compact/Wide/Tall/Large presets and keyboard-friendly nudges. Exact positions and dimensions persist locally; `Reset` restores the default canvas.
- The first YouTube action installs a narrow local guard and asks for one administrator approval. After setup, `Lock now` never asks for a password.
- `Unlock` requires fresh macOS administrator authorization, then opens a fixed-size task hub where you choose Grid Shot, Typing Sprint, or optional Signal Shift. Winning leaves the stable game sheet open; `Unlock YouTube` explicitly submits the one-use authorization. The sheet closes only after Vaulty verifies both an active 45-minute guard lease and the removal of the hosts-file block. A failed or unverified submission stays visible with a retry explanation.
- Signal Shift is optional and never selected automatically or required for access.
- Available unlock tasks:
  - **Grid Shot** — three balls on a 6×6 grid, ten seconds, +1 per hit, −1 per miss, target score 30.
  - **Typing Sprint** — type an exact focus phrase within 24 seconds at a minimum 42 WPM.
  - **Signal Shift** — optional connected-cell spatial-memory path: a no-penalty three-cell practice room followed by progressive rooms. It is never required for access.
- A successful unlock lasts exactly 45 minutes and cannot be extended in place. The root guard relocks even if the app closes; its in-memory monotonic deadline prevents a clock rollback from extending the session, and a guard restart fails closed.
- The games are deliberate friction, not a claim to improve general intelligence.
- Start the task clock to engage the YouTube blocker without another password; pause and resume it around real interruptions without spending paused time.
- Let the restrained timer and completion moment carry the task; ending early never changes the vault automatically.
- `Learn next` audits a redacted digest of local Hermes agent sessions, clusters current learning topics with GPT-5.6, researches YouTube transcripts, and opens grounded recommendations with notes and transcript-scoped Q&A.
- `Tools` is a configurable local launcher. It ships with `bb hub` and an example workspace hub (Dashboard, Analytics, and Marketing), lets you add/remove tools, exposes copyable local links, opens healthy services, and offers `End` only for process groups Vaulty started.
- Update checks are opt-in per tool: npm package lookup or a read-only comparison between the local Git HEAD and the matching `origin` branch.
- `YouTube blocker` uses the installed guard: lock immediately without a password, or authenticate, choose Grid Shot or Typing Sprint, win, and explicitly confirm a verified 45-minute unlock.
- `Short-form blocker` is a separate control that blocks or unblocks TikTok, Instagram, YouTube, and Facebook hostnames. Because `/etc/hosts` cannot see URL paths, native short-form mode conservatively blocks those supported hosts completely.
- `Sleep calculator` works backward from a wake time or forward from a bedtime using 90-minute cycles plus a 14-minute fall-asleep estimate.
- `Channel Vault` opens the bundled browser-companion folder for selective filtering in Chrome, Edge, or Brave.
- `Rhythm` shows a compact GitHub-style 13-week calendar. Each dot is one day; darker seafoam means more active minutes in coding/work apps.
- The calendar is a personal tracker, not an analysis dashboard. It stores one local daily total, counts only active minutes while Vaulty is running, and ignores idle time.

The hosts guard remains the cross-browser backstop. In Chrome, Edge, or Brave, the browser companion reads the same lease through a read-only native-messaging host, redirects an already-playing YouTube tab when the deadline arrives, blocks Shorts throughout the lease, and falls back to the exact channel allowlist before native pairing. The extension can read state and request an early lock; it cannot request an unlock.

The learning guide is on-demand and privacy-bounded. It does not run until clicked, sends only a compact redacted user-message digest and public transcript excerpts to `openai-codex/gpt-5.6-luna`, stores the result locally, and reports an honest partial state when the YouTube blocker or network blocks YouTube.

## Configurable local tools

Tool definitions are stored locally at:

```text
~/Library/Application Support/Vaulty/tools.json
```

Each definition contains a name, working directory, absolute executable, one argument per entry, local links, expected ports, and an optional update source. Vaulty never runs a shell command string: it launches the configured executable with a structured argument array.

The initial tools are:

- **bb hub** — starts `bb-app@latest` through `npx` when port `38886` is not already active; otherwise it safely reuses the existing service.
- **Workspace hub** — runs a `npm run workspace` launcher from `~/Documents/Workspace` (edit the tool to point at your own project), linking to the hub, dashboard, analytics, and marketing pages. Its launcher reuses services already listening on `4567`, `5173`, `3000`, and `3001`.

`End` appears only when Vaulty owns the supervisor process. The supervisor forwards termination to the child process group; the workspace launcher then stops only child services it started. A process found on an existing port is shown as running externally and is never terminated by Vaulty.

## Vaulty icon and mascot

The macOS app icon is an original Tideglass safe: rounded vault body, combination dial, three-spoke handle, and simplified hinges designed to survive small Dock/Finder sizes. It is inspired by classic safe hardware without copying the supplied reference image.

- Master icon: `AppResources/Vaulty-AppIcon-1024.png`
- Packaged icon: `AppResources/Vaulty.icns`
- Reproducible generator: `scripts/generate-app-icon.py`

Vaulty also keeps one small flat vault character inside the app. It appears in the top bar as a recognition mark, not as a second dashboard or decorative mascot system.

- Primary mark: `Brand/Vaulty-Mascot.svg`
- Monochrome mark: `Brand/Vaulty-Mascot-Monochrome.svg`
- Palette: Tideglass blue-green, warm apricot, seafoam, and coral; no purple

## Optional command-line mode

The CLI remains available for scripts and Terminal users. From a clone of this repository:

```sh
swift build -c release
sudo install -m 755 .build/release/vaulty /usr/local/bin/vaulty
```

## Use the CLI

Vault in and block the default YouTube domains:

```sh
sudo vaulty block
```

Check whether the YouTube blocker is engaged:

```sh
vaulty status
```

Open the YouTube blocker and remove only its managed section:

```sh
sudo vaulty unblock
```

Block short-form platforms separately:

```sh
sudo vaulty short-form block
vaulty short-form status
sudo vaulty short-form unblock
```

Preview the exact entries without changing anything:

```sh
vaulty block --dry-run
```

Block a custom set of sites instead of the defaults:

```sh
sudo vaulty block \
  --domain youtube.com \
  --domain www.youtube.com \
  --domain reddit.com
```

The custom domain list is written into the same marked section, so `vaulty unblock` removes it safely.

## Browser companion and timed YouTube sessions

Use the bundled browser companion if you want an already-open YouTube tab to be replaced by Vaulty’s lock screen at the 45-minute deadline:

1. Open the app and click `Show companion`, or open the `BrowserExtension` directory.
2. In Chrome, Edge, or Brave, open `chrome://extensions`.
3. Turn on Developer mode and choose Load unpacked.
4. Select the bundled `BrowserExtension` directory.
5. Keep the extension enabled. Its pinned development key gives it the stable ID required by native messaging.
6. Complete Vaulty’s one-time guard setup from the app. Setup installs the read-only native-host manifests for Chrome, Edge, and Brave.

When paired, the extension enforces the root guard’s lock/lease state and never accepts an unlock command. Its popup can request `Lock now`, while `Unlock` always returns to the native app for password, a user-selected Grid Shot or Typing Sprint task, and an explicit verified `Unlock YouTube` confirmation. YouTube Shorts remain blocked during a long-form YouTube lease.

Before native pairing, the companion retains its exact channel allowlist fallback. The defaults are Alex Hormozi (`@AlexHormozi`) and MoreMozi (`@MoreMozi`); unknown owners, feeds, search, playlists, and impersonators fail closed. Once paired, losing the native host also fails closed instead of silently reverting to a weaker mode.

If native short-form protection was active before an unlock, Vaulty keeps TikTok, Instagram, and Facebook blocked during the YouTube lease, then restores the complete short-form scope when the lease ends.

## Test without touching `/etc/hosts`

Every command accepts `--hosts-file`, which makes manual testing safe:

```sh
tmp_hosts="$(mktemp)"
printf '# local test\n127.0.0.1 localhost\n' > "$tmp_hosts"
.build/release/vaulty status --hosts-file "$tmp_hosts"
.build/release/vaulty block --hosts-file "$tmp_hosts"
.build/release/vaulty status --hosts-file "$tmp_hosts"
.build/release/vaulty unblock --hosts-file "$tmp_hosts"
rm "$tmp_hosts"
```

## Safety model

- The YouTube section is between `BEGIN VAULTY` and `END VAULTY`; the independent short-form section is between `BEGIN VAULTY SHORT-FORM` and `END VAULTY SHORT-FORM`.
- Existing hosts entries are preserved byte-for-byte after unblocking either section.
- Re-running either blocker is idempotent.
- A malformed, duplicated, nested, or mixed legacy section causes Vaulty to stop instead of guessing.
- `unblock` removes only a valid YouTube Vaulty, legacy FocusVault, or legacy Frostwall section; `short-form unblock` removes only the short-form section.
- LF and CRLF line endings are preserved.
- The file’s original POSIX permissions and ownership identifiers are restored after an atomic write when possible.
- The old FocusVault and Frostwall marker formats are recognized so upgrades remain reversible.
- The automatic guard accepts only `lock` or a one-use macOS-authorized 45-minute unlock request; its browser bridge is read/lock-only.
- A daemon restart or reboot during an unlock fails closed and restores the protected scopes.

Administrator recovery/removal is explicit:

```sh
vaulty guard status
sudo vaulty guard uninstall
```

Uninstalling stops the daemon, removes its helper/native-host manifests and authorization right, and removes only Vaulty’s managed YouTube section. It does not touch unrelated hosts-file content.

## FocusVault compatibility

The rename is intentionally additive:

- `focusvault` remains an executable compatibility alias for scripts and existing installs.
- Existing `# BEGIN FOCUSVAULT MANAGED BLOCK` sections are detected, safely removed, and migrated to Vaulty markers on the next block.
- The legacy `~/Library/Application Support/FocusVault/productivity.json` file is copied into the Vaulty path without deleting the old file.
- The original bundle identifier remains `com.jacksongb.focusvault` so existing macOS preferences and permissions stay attached.

## Short command summary

```text
vaulty block      Engage the YouTube blocker.
vaulty unblock    Open the YouTube blocker.
vaulty status     Show whether the YouTube blocker is engaged.
vaulty short-form block   Engage the separate short-form blocker.
vaulty short-form status  Show whether the short-form blocker is engaged.
vaulty allowlist  Show the default selective YouTube channels.
vaulty version    Print the installed version.
```

## License

MIT. See [LICENSE](LICENSE).
