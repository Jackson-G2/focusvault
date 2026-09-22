# Vaulty — Product & UI Design

## North star

Vaulty should feel like a quiet room around the user's attention: deliberate, warm, and easy to leave. The interface should help someone make one clear choice, then get out of the way.

The product is not a productivity dashboard. It is a small act of protection.

## Design principles

1. **One next action.** Every state has one obvious primary action. Secondary actions exist only when they are necessary to recover, configure, or leave.
2. **Status over explanation.** Use color, motion, and a short label before adding prose. Explain only the decision the user is making right now.
3. **No decorative UI.** If a card, label, icon, footer, badge, or button does not help someone protect attention, remove it.
4. **Reveal complexity only on demand.** The original YouTube blocker remains a distinct protection action; the separate short-form blocker, channel-vault setup, and sleep planning appear as focused controls rather than one combined mode.
5. **Emotional, not reward-loop gamified.** Unlock tasks exist only as deliberate friction: no streaks, rankings, currency, shame, or endless play.
6. **Private by default.** Intentions, sessions, activity, challenge state, and unlock leases remain local. No analytics, screenshots, keystrokes, window contents, or cloud account are needed.
7. **Honest boundaries.** The root guard controls the system-wide hosts-file vault and fixed lease; the browser companion is required to replace an already-loaded YouTube tab exactly at expiry.

## Visual direction: Tideglass

Tideglass is a deep blue-green / sea-glass system with a warm apricot signal. It deliberately avoids the familiar purple productivity palette while staying calm, legible, and memorable.

| Token | Hex | Use |
| --- | --- | --- |
| `canvas` | `#071B20` | Window background |
| `surface` | `#0E2B2F` | Glass cards and controls |
| `elevated` | `#143B3B` | Hover, selected, and raised surfaces |
| `ink` | `#F4F0E8` | Primary text |
| `muted` | `#9DB7B1` | Supporting text and inactive states |
| `signal` | `#FFB86A` | Primary action, active focus, warmth |
| `seafoam` | `#A7D9B4` | Safe, complete, and protected states |
| `coral` | `#F4846A` | Errors and irreversible-feeling warnings |
| `line` | `#B9E1D31F` | Quiet borders |

The background uses slow, barely perceptible sea-glass and apricot light. It must never compete with the focus action. Purple is not used in the product palette.

## Vaulty icon and mascot

The Dock/Finder icon is an original Tideglass interpretation of a classic safe: one rounded vault body, a readable combination dial, a three-spoke handle, and three simplified hinges. It keeps the supplied reference’s essential safe cues while using Vaulty’s own flat palette and geometry. Fine dial numbers, photographic steel, and perspective detail are deliberately removed so the icon survives at 16–32 px.

The in-app mark remains a small flat vault character, not a mascot universe. The silhouette is a rounded safe body with a small door dial, two restrained eyes, and a quiet smile. Both marks communicate “held safely” without looking like a security warning or uncanny 3D object.

The primary mark uses seafoam for protected state, Tideglass surface for open state, apricot for the door dial, and coral only for tiny state accents. The monochrome mark is available for documents, favicons, and contexts where color is not reliable.

Assets:

- `AppResources/Vaulty-AppIcon-1024.png`
- `AppResources/Vaulty.icns`
- `scripts/generate-app-icon.py`
- `Brand/Vaulty-Mascot.svg`
- `Brand/Vaulty-Mascot-Monochrome.svg`

The app uses the mark once in the top bar. No mascot cards, badges, onboarding illustrations, or state-variant collection ship until a concrete recognition or recovery need appears.

## Layout

The dashboard is a single calm workspace, not a settings catalogue:

- A small top bar: mark, product name, `Arrange`, and one compact protection status.
- An Apple-style four-column canvas that preserves exact widget slots and intentional gaps.
- Every widget is draggable in Arrange mode and directly resizable from its lower-right handle. A menu also exposes Compact, Wide, Tall, and Large presets plus directional nudges.
- Widgets may span two, three, or four columns and one to four rows; collision resolution moves affected neighbours down instead of overlapping them.
- Position and dimensions persist locally, legacy order-only layouts migrate automatically, and `Reset` restores the default canvas.
- No marketing footer, version badge, repeated status paragraph, or duplicate mode cards.
- Minimum window size remains comfortable on a laptop.

## New core features considered

### 0. Timed YouTube gate + chosen unlock task — selected

After one administrator-approved setup, `Lock now` is immediate and password-free. Unlocking requires fresh macOS administrator authorization and then presents a fixed-size three-card task hub. The user chooses Grid Shot, Typing Sprint, or optional Signal Shift. Winning does not dismiss the stable sheet or mutate system state; it reveals an explicit `Unlock YouTube` button. That button sends the one-use authorization to the guard, remains disabled while submitting, and closes the sheet only after Vaulty independently verifies an active 45-minute lease and an unblocked hosts file. A rejected or false-success response stays visible with a close-and-reauthenticate path.

The task hub contains three bounded tasks:

- **Grid Shot:** three balls continuously refill on a 6×6 grid; ten seconds, +1 per hit, −1 per miss, hard target 30.
- **Typing Sprint:** reproduce one exact 85–89-character focus phrase within 24 seconds, effectively requiring at least 42 WPM with corrections allowed.

- **Signal Shift:** optional spatial-memory path with a connected three-cell no-penalty practice room followed by progressive rooms; it is never required for access.

Signal Shift is offered only when the user chooses it from the hub. It is not automatic, not part of the required rotation, and cannot block access if the user selects another task.

These are deliberate friction mechanisms. Vaulty makes no claim that one short run raises general intelligence.

Evidence boundary: a healthy-adult systematic review examined task switching/multitasking and mental spatial rotation and found game-training effects varied by task and study ([Frontiers in Psychology, 2018](https://pmc.ncbi.nlm.nih.gov/articles/PMC6234876/)). A second-order meta-analysis emphasizes that near transfer is more common than far transfer ([Collabra: Psychology, 2019](https://online.ucpress.edu/collabra/article/5/1/18/113004/Near-and-Far-Transfer-in-Cognitive-Training-A)). The Stanford/Max Planck consensus cautions that brain-game research does not justify broad everyday-cognition claims ([Stanford Center on Longevity](https://longevity.stanford.edu/a-consensus-on-the-brain-training-industry-from-the-scientific-community/)). Vaulty therefore describes the exact skills used, not a general “brain improvement” outcome.

The native guard keeps `/etc/hosts` as the cross-browser backstop. The Chromium companion reads the same state through a read-only/lock-only native host, keeps Shorts blocked during a long-form lease, and replaces an already-playing tab when time expires.

### 1. Short-form vault — selected

The short-form blocker is separate from the original YouTube blocker. It covers TikTok, Instagram, YouTube Shorts, and Facebook Reels. Its native `/etc/hosts` implementation conservatively blocks those platform hosts completely because it cannot distinguish URL paths; the browser companion adds path-level route and feed-link filtering for Reels and Shorts. The dashboard states this boundary plainly instead of implying that a hosts file can inspect page content.

### 2. Sleep calculator — selected

The sleep calculator is a small, on-demand planning sheet rather than a health dashboard. It calculates recommended bedtimes from a wake time or wake times from a bedtime using 90-minute cycles and a 14-minute fall-asleep estimate. It stores nothing and presents a planning caveat so the result is not mistaken for medical advice.

### 3. Task clocks / quiet focus sessions — selected

A task clock begins only after the user sets the exact time the task should take. A 10, 20, or 40 minute estimate becomes one contained stretch of protected attention, rather than a vague preset. The countdown is large and quiet; the vault stays engaged when the timer completes so the user is never surprised by an automatic unblocking or a new administrator prompt.

Why it wins: it turns the existing block into a repeatable timeboxing behavior, gives an estimate a visible finish line, needs no account or setup, and creates the strongest opportunity for emotional arrival / progress / completion moments.

The task card has one mode by design: an exact Task clock. The old fixed Focus timer is not a separate mode because the same clock can be set to 25, 50, or 90 minutes when those intervals are useful. Removing the duplicate mode avoids a needless choice before the user starts.

#### Task-clock interaction

- **Set:** enter a whole-minute estimate from 1–240 before starting. The estimate is the commitment, not a suggested preset.
- **Start:** starting the clock engages the YouTube blocker when it is not already on.
- **Work:** show exact minutes and seconds remaining with a quiet progress ring.
- **Pause:** pause when the task is interrupted. Paused time does not consume the estimate.
- **Resume:** continue from the exact remaining time without changing the original estimate.
- **Finish:** when the clock reaches zero, show a brief acknowledgement and keep the vault engaged until the user explicitly changes it.
- **Stop early:** allow an early exit without shame or automatic unblocking; stopping changes only the clock.

### Configurable local tools — selected

The old single-purpose bb card becomes one compact Tools widget. It starts or reuses separately owned local projects without merging their repositories. Initial entries are `bb hub` and an example workspace launcher, whose hub links to a dashboard, analytics, and marketing pages.

Each tool exposes one primary open action, a copyable local URL, optional secondary links, and an `End` action only when Vaulty started the process supervisor. Existing listeners are labeled external and never killed. Add/remove lives behind the widget’s manage control so the main dashboard remains calm. Update checks are explicit and read-only: npm registry version lookup or Git `ls-remote`, never an automatic install, pull, or source edit.

### 4. Personal intention — selected

A short, local statement such as “finish the proposal” or “be present with the draft” sits at the heart of the dashboard. It is editable in place and shown as the reason for the protected stretch, not as a task-management system.

Why it wins: it makes the product emotionally specific with almost no additional UI, reinforces agency, and is private enough to store locally with no service dependency.

### 5. Vault schedules and profiles — deferred

Preset profiles such as “deep work,” “reading,” or automatic weekday schedules could make blocking more powerful, but they add configuration surfaces, persistence edge cases, unexpected administrator operations, and more ways for the product to become a settings app.

Why it loses today: the complexity cost is higher than the value of a third control. Revisit only after sessions and intentions prove that users need repeatable automation.

## Session-aware learning guide — selected

The dashboard gets one explicit `Learn next` action. It is an on-demand research workflow, not an always-on recommender. When invoked, a background agent:

1. Reads all available Hermes session databases for the local profile and sibling profiles, across CLI, subagent, cron, API, and other agent sources.
2. Uses only user-authored session text plus session titles/metadata to build a compact, redacted digest of active goals, work, and learning themes. Tool output, credentials, and raw session transcripts are not sent wholesale.
3. Uses the GPT-5.6 subscription route (`openai-codex/gpt-5.6-luna`) to cluster the digest into a small set of current learning topics and explain why each topic was selected.
4. Searches YouTube for candidates, fetches public English captions with `yt-dlp`, and skips videos without usable transcripts or with obvious low-value formats such as compilations and ads.
5. Sends the public candidate metadata and transcript excerpts to GPT-5.6 for usefulness evaluation. A recommendation must have a source URL, transcript evidence, a concrete “why this helps,” and short notes or further explanation.
6. Saves the result locally so the user can open the source, read the notes, and ask a follow-up question about a selected transcript.

The result surface should show the topic reason first, then a small ranked list of videos. Q&A is scoped to the selected video transcript and the user’s question; it is not a general chat panel. If YouTube is unavailable because the YouTube blocker or short-form blocker is engaged, the app reports that honestly instead of weakening the vault or inventing recommendations.

Privacy and trust rules:

- Nothing runs until the user clicks `Learn next`.
- The user sees that a compact session digest and public transcript excerpts are sent to the configured GPT-5.6 subscription.
- Store recommendations, transcript excerpts, and Q&A locally; do not add analytics or background collection.
- Preserve source URLs and transcript availability in the result contract so a recommendation can be checked.
- Never present a video as helpful when its transcript was unavailable or the evaluator returned no evidence.

## Emotional interaction model

- **Arrival:** the primary action warms from quiet sea-glass to apricot, the room subtly brightens, and the intention becomes the visual anchor.
- **During:** a small ambient pulse breathes once every few seconds; the timer is the only moving information. No confetti, badges, or noisy alerts.
- **Completion:** the pulse resolves into a soft ring and a short acknowledgement such as “You kept the room.” The moment is brief and respectful.
- **Leaving early:** ending a session is always possible and never framed as failure. The system vault remains in its current state unless the user explicitly changes it.
- **Reduced motion:** all ambient pulses and completion effects degrade to opacity/color changes under Reduce Motion; controls must remain fully understandable without animation.

## Content rules

- Use fragments and short verbs: `Set estimate`, `Start task`, `Pause`, `Resume`, `Open vault`, `Browser setup`.
- Prefer one meaningful sentence over multiple explanatory paragraphs.
- Do not repeat the same state in a badge, heading, body, and button.
- Do not add a button when a row, menu, keyboard return, or direct manipulation is sufficient.
- Never add a counter, streak, leaderboard, social proof, or pressure language without a separate product decision.

## Addition gate

Before adding any UI element, answer all four questions:

1. What user decision or recovery path does it enable?
2. Can the existing element or a system affordance do the same job?
3. Does it introduce a new mental model, permission, or privacy cost?
4. If removed, what concrete task becomes impossible?

If the answer to the fourth question is “nothing important,” the element does not ship.

## Accessibility and platform

- Keep text and status colors readable against `canvas` and `surface`.
- Every icon-only control gets an accessibility label and tooltip.
- Preserve keyboard focus and visible focus indication for the intention field and primary action.
- Respect macOS Reduce Motion for ambient and completion animation.
- Use native Liquid Glass on supported macOS versions and a visually coherent material fallback on older supported versions.
- Keep `/etc/hosts` mutations reversible and outside the main UI thread.
