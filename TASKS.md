# Vaulty task list

- [x] Audit the existing Vaulty app, CLI, hosts-file blocker, and browser companion.
- [x] Define one short-form policy for TikTok, Instagram Reels/Stories, YouTube Shorts, and Facebook Reels.
- [x] Add the reversible native short-form vault for system-wide coverage across browsers.
- [x] Keep the original YouTube blocker in its own independent hosts-file section and restore its original controls/commands.
- [x] Extend the browser companion to block direct short-form URLs and known feed links.
- [x] Validate TikTok, Instagram, YouTube Shorts, and Facebook Reels with automated policy tests.
- [x] Add the sleep calculator with wake-time and bedtime calculations, 90-minute cycles, and fall-asleep time.
- [x] Add the sleep calculator to the Vaulty dashboard with working controls and accessibility identifiers.
- [x] Fix button hit-testing by making decorative glass layers non-interactive.
- [x] Add task-clock, vault, sleep, and browser-setup accessibility identifiers for UI verification.
- [x] Add a packaged-app interaction smoke path that exercises independent YouTube/short-form toggles plus start, pause, resume, and end actions against a temporary hosts file.
- [x] Run Swift core tests, browser policy tests, JSON validation, release build, and hosts-file integration tests.
- [x] Build the signed `dist/Vaulty.app` and verify the dashboard launches with the new controls.
- [x] Add a bb hub launcher card that reuses installed bb or the official npx launcher and opens the local UI when ready.
- [x] Replace the single-purpose bb card with a configurable Tools widget.
- [x] Seed bb plus an example workspace hub with direct Dashboard, Analytics, and Marketing links.
- [x] Add local tool persistence, add/remove controls, copyable links, safe owned-process stop, and optional read-only update checks.
- [x] Add the password-plus-chosen-task YouTube unlock and fixed 45-minute automatic relock guard.
- [x] Add an original Tideglass safe app icon with a reproducible `.icns` generator.
- [x] Upgrade the dashboard to a persisted free-position four-column canvas with direct resize handles, size presets, collision resolution, intentional gaps, and legacy-order migration.
- [x] Remove Signal Shift from every required unlock after user testing showed it remained inaccessible; keep it optional in the task hub.
- [x] Restore Signal Shift as an optional task-hub choice while keeping it non-mandatory.
- [x] Use one fixed-size challenge canvas so hub/game transitions and timer updates cannot move the game vertically.
- [x] Keep successful game sheets open, require explicit `Unlock YouTube`, and verify the guard lease plus hosts-file state before closing.

## Verification commands

```sh
make test
make build
make integration
make app
```

The platform-specific short-form checks cover 12 direct/route cases and are in:

- `Sources/FocusVaultSelfTest/FocusVaultSelfTest.swift`
- `BrowserExtension/tests/short-form.test.js`
- `scripts/integration-test.sh`
- `scripts/app-smoke-test.sh` (dashboard/button smoke check)
