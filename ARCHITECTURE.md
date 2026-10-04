# Vaulty architecture

Vaulty is a native macOS app, a pure Swift policy library, a narrow CLI/root guard,
a Chromium companion, and an explicitly invoked Python learning researcher.
The SwiftPM target names are `Vaulty*`; the historical `Sources/FocusVault*`
paths remain stable. No additional dependency or service is required by this refactor.

## Boundaries

### `VaultyCore`

- `FocusVaultBlocker` / `ShortFormBlocker`: small public facades for independent
  managed sections. They share hostname validation, hosts-document parsing, and
  file mutation mechanics rather than duplicating them.
- `HostsFileTransaction` pins and locks the current regular inode, retries
  stale descriptors after atomic replacement, and serializes cooperating
  processes without persistent sidecar files. `HostsBlockCoverage` separates
  complete effective mappings from the preserved legacy marker-presence API.
- `HostnameNormalizer`, `ManagedHostsDocument`, `HostsFileStore`,
  `AtomicFileWriter`: validation, exact-text preservation, bounded file I/O and
  atomic writes are separate responsibilities.
- `YouTubeAccessGuard`, `YouTubeGuardEngine`, `YouTubeGuardStorage`: wire/data
  contracts, lease policy/transactions, and local persistence are separate.
- `ProductivityLog` / `ProductivityLogStore`: day aggregation and persistence.
- Task clocks, sleep calculation and unlock games are deterministic value types;
  platform authentication and UI timing never live inside game scoring.

Core APIs, marker families, state formats and legacy migration remain compatible.
Malformed managed sections fail closed. Tests use temporary files, not `/etc/hosts`.

### `VaultyCLI`

`FocusVaultCLI` is the entrypoint. `CLIArguments`, `CLICommands`,
`CLIInternalCommands` and `CLIUsage` separate parsing, dispatch and presentation.
Guard installation/configuration, daemon execution, native messaging and macOS
Authorization Services remain independent platform adapters.
The root guard still offers only the existing bounded operations; the browser
bridge can read state or request a lock, never authorize an unlock.

### `VaultyApp`

- `FocusVaultApp` owns the SwiftUI application and environment objects.
  `AppCommandDispatcher` routes non-GUI fixture/render/supervisor commands and
  rejects missing path arguments without accidentally starting the real UI.
- `FocusVaultDashboard` composes concrete widget views. Intention, task clock,
  YouTube, short-form, sleep and learning-guide widgets own their rendering and
  bindings instead of sharing one large view-builder implementation.
- `FocusVaultAppModel` holds state and status publication; focused extensions
  implement protection transactions and task-clock behaviour. The executable
  target's extensions own mutation; these are not exported library APIs.
- `DashboardWidgetDefinition`, `DashboardPlacementEngine`, `DashboardLayoutModel`
  and `DashboardWidgetGrid` separate data, pure bounded geometry, preference
  migration/persistence and SwiftUI drag/resize rendering.
- `UnlockChallengeSheet` keeps one fixed frame and prevents dismissing an
  in-flight unlock. Grid Shot, Typing Sprint and optional Signal Shift have
  separate screens and retain explicit final confirmation.
- `GlassUI`, `VaultyBrandViews`, `AppBackground` and `TaskClockVisuals` separate
  styling, artwork and focused motion. macOS 26 glass remains availability-guarded
  with the older-platform material fallback.
  Compilation checks the Swift 6.2+ compiler/SDK cohort rather than Swift
  language mode; mixed modern-compiler/older-SDK builds can explicitly define
  `VAULTY_FORCE_MATERIAL`.
- Local tools have separate model/catalog, launch, lifecycle, ownership, port
  probing, external-stop and update modules. Stop/restart never kill an arbitrary
  listener by port and must verify ownership and complete exit first.
- `ProcessOutputCapture` drains both child streams concurrently, bounds retained
  output, and continues draining on overflow. It is used off the UI thread by
  administrator and research helpers.
- `VideoResearchTypes`, `VideoResearchStore` and `VideoResearchModel` separate
  data contracts, local cache I/O and orchestration. Watch links are constrained
  to the declared HTTPS YouTube video; confidence is safely clamped for display;
  Q&A answers are scoped to the selected video.

The retired Rhythm renderer and unused app-side external-authorization path are
removed. Productivity tracking/storage and legacy widget decoding remain intact.

### Browser companion

Pure URL/channel/session policy remains separately testable from the browser
adapters. Content-script enforcement, native state synchronization, storage and
popup/options UI remain MV3-compatible. Every `BrowserExtension/tests/*.test.js`
suite is included by `make extension-test`, so newly added regressions cannot be
forgotten by a fixed three-file test list.

### Python researcher

`ResearchAgent/recommend.py` is the compatibility entrypoint. Sibling modules
separate common contracts, read-only session digest/redaction, AI subprocess
invocation, topic selection, YouTube/transcript access, evidence evaluation,
workflow and CLI handling. Packaging includes every runtime `.py` module.
Explicit user action remains required. Tests mock AI/network access; no real
history, transcript or provider request is needed for verification.

## Preserved contracts

- macOS 13+ and Swift tools version 5.9; compatibility executable aliases remain.
- Original bundle ID and local preference keys; dashboard layout version 3.
- Tool catalog/run records, reused-port bookkeeping and owned-process identity.
- Password-free lock after setup; task then fresh approval for a fixed 45-minute
  unlock; verify the actual lease and hosts postcondition before reporting success.
- Exact task estimate/pause/resume; completion/early stop never silently unlocks.
- Exact finite typing with count-up timing and observational WPM; Signal Shift optional.
- No new telemetry, background AI request, auto-update or account requirement.

## Verification workflow

```
make verify        # Python, core, legacy alias, browser, release CLI integration,
                   # signed packaged-app interaction suite, source wiring, whitespace
make benchmark     # build debug app then run isolated notification benchmark
```

Tests are split by responsibility, with the original self-test entrypoints retained.
New app regressions include idle publishing, deterministic clocks, false helper
success, extreme saved coordinates, bottom-edge collisions, no-op persistence,
large dual-stream output, bounded-output rejection and safe video cache handling.
Browser VM fixtures cover native reconnect/coalescing/stale callbacks, subtree
scanning, reused feed nodes, and accessibility-label restoration. Release CLI
fixtures cover concurrent independent hosts scopes and malformed native frames.
Fixture/render commands do not install the app or change live blocking state.
Offscreen bitmap snapshots explicitly use the material fallback through
`RenderingPreferences`; hardware-backed native glass is compiled and remains
enabled for real supported app windows, but is not claimed as live GUI QA from
an unattached `NSHostingView` capture.
Packaging stages and validates output before replacing only its exact artifact
paths; it no longer erases the complete `dist` directory before a build.

The status benchmark compiles the same isolated harness against any built checkout:

```
python3 scripts/benchmark-status.py /absolute/path/to/checkout
```

It counts notifications for 1,000 unchanged public status refreshes and records
elapsed time. Notification counts are deterministic; wall time depends on the
machine/load and is not a CI threshold or a whole-app speed claim.

Local verification is not remote CI, live administrator-flow QA, a notarized
release, or an update to an already-running app. Those require separate explicit
release/interaction approval; no commit, push, install or relaunch is implied.
