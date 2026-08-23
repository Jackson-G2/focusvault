# FocusVault YouTube Channel Vault

This browser extension is the selective mode for FocusVault. It blocks YouTube home, search, Shorts, recommendations, playlists, and videos from channels that are not on your allowlist.

The defaults are:

- Alex Hormozi — `@AlexHormozi` — `UCUyDOdBWhC1MCxEjC46d-zw`
- MoreMozi — `@MoreMozi` — `UCrvchO1h6lWZAuGaa1LqX9Q`

It allows channel pages from those identities and checks video-owner metadata before allowing a watch, Shorts, live, or shortened-URL page through.

## Install in Chrome, Edge, Brave, or another Chromium browser

1. Open the browser’s extensions page, for example `chrome://extensions`.
2. Turn on Developer mode.
3. Choose Load unpacked.
4. Select this `BrowserExtension` directory.
5. Open the FocusVault extension menu and choose Manage allowed channels if you want to add trusted channels.
6. Keep the extension enabled. Do not also run `sudo focusvault block` if you want allowlisted YouTube channels to work; the hosts-file mode blocks all YouTube domains.

## Add a channel

Open the extension settings and add one channel per line:

```text
Name | @handle | channel ID
```

Examples:

```text
Alex Hormozi | @AlexHormozi | UCUyDOdBWhC1MCxEjC46d-zw
MoreMozi | @MoreMozi | UCrvchO1h6lWZAuGaa1LqX9Q
A trusted work channel | @example | UCxxxxxxxxxxxxxxxxxxxxxx
```

The extension matches the exact handle or channel ID. A similar-looking impersonator is not allowed.

## Security and limitations

- This is browser-level URL and page-owner filtering, not a network firewall.
- Someone who disables or removes the extension can bypass it.
- YouTube can change its DOM, so the owner-metadata check may need maintenance if YouTube changes its page structure.
- For a total block across browsers, use the native CLI hosts-file mode instead.
