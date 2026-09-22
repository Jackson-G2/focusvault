# Vaulty browser companion

The Vaulty browser companion protects attention in three layers:

- **Timed YouTube gate:** after Vaulty’s one-time native-guard setup, every non-Shorts YouTube page follows the same locked/45-minute lease as the Mac app.
- **Active-tab relock:** a local timer, Chrome alarm, and native-state check replace an already-playing YouTube tab with Vaulty’s lock page when the lease expires.
- **Short-form guard:** blocks TikTok, Instagram Reels/Stories, YouTube Shorts, and Facebook Reels before a direct URL opens. Known short-form links are also intercepted in supported feeds.

The extension can read the root guard’s state and request an early lock. It cannot request an unlock. Unlocking always returns to Vaulty for the macOS administrator password, a user-selected Grid Shot, Typing Sprint, or optional Signal Shift task, and an explicit native confirmation. Signal Shift is never automatic or required.

## Install in Chrome, Edge, or Brave

1. Open the browser’s extensions page, for example `chrome://extensions`.
2. Turn on Developer mode.
3. Choose **Load unpacked**.
4. Select this `BrowserExtension` directory.
5. Keep the extension enabled.
6. In Vaulty, use the YouTube control once and approve the one-time guard setup. Vaulty installs the local native-messaging manifest for Chrome, Edge, and Brave.
7. Reload the extension after updating its source.

The manifest contains a pinned public key, giving this unpacked extension the stable ID required by Chrome native messaging:

```text
apgojdoelgpjfpmiohffnbkfcbjhjhob
```

## Fallback channel vault

Before the native guard is paired, Vaulty fails down to an exact YouTube channel allowlist rather than opening all of YouTube. The defaults are:

- Alex Hormozi — `@AlexHormozi` — `UCUyDOdBWhC1MCxEjC46d-zw`
- MoreMozi — `@MoreMozi` — `UCrvchO1h6lWZAuGaa1LqX9Q`

Open the extension settings to edit one channel per line:

```text
Name | @handle | channel ID
```

When the native guard is paired and locked, fallback edits are disabled. If the paired native host later disappears, the extension fails closed.

## Tests

```sh
node BrowserExtension/tests/policy.test.js
node BrowserExtension/tests/short-form.test.js
node BrowserExtension/tests/session-policy.test.js
```

The suites cover exact handles/IDs, owner inspection, impersonators, feeds, supported short-form routes, fixed-deadline decisions, native-host fallback, and the pinned extension identity.

## Security and limitations

- This is strong self-binding friction, not MDM or tamper-proof parental control.
- An administrator can remove the hosts rule/helper; a user can disable the extension, use another browser profile, another resolver/VPN, or another device.
- Hosts-file enforcement is the cross-browser backstop, but only the extension can immediately replace an already-loaded encrypted YouTube page.
- Social sites can change their DOM, so feed-link selectors may need maintenance.
- Vaulty never receives, stores, or logs the macOS password. Authorization is handled by macOS Authorization Services.
