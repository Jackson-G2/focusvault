# FocusVault — Product & UI Design

## North star

FocusVault should feel like a quiet room around the user's attention: deliberate, warm, and easy to leave. The interface should help someone make one clear choice, then get out of the way.

The product is not a productivity dashboard. It is a small act of protection.

## Design principles

1. **One next action.** Every state has one obvious primary action. Secondary actions exist only when they are necessary to recover, configure, or leave.
2. **Status over explanation.** Use color, motion, and a short label before adding prose. Explain only the decision the user is making right now.
3. **No decorative UI.** If a card, label, icon, footer, badge, or button does not help someone protect attention, remove it.
4. **Reveal complexity only on demand.** Full vault is the default. Channel-vault setup appears only when selected.
5. **Emotional, not gamified.** The app should reinforce agency and relief, not streak anxiety, scores, rankings, or shame.
6. **Private by default.** Intentions, sessions, and activity remain local. No analytics, screenshots, keystrokes, window contents, or cloud account are needed.
7. **Honest boundaries.** The native app can control the system-wide hosts-file vault. Selective YouTube channels still require the browser companion.

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

## Layout

The dashboard is a single calm workspace, not a settings catalogue:

- A small top bar: mark, product name, and one compact protection status.
- A left focus surface: the editable personal intention and the timed focus ritual.
- A right utility rail: current protection control and the local activity rhythm.
- No marketing footer, version badge, repeated status paragraph, or duplicate mode cards.
- Minimum window size remains comfortable on a laptop; the layout collapses into a single column when narrow.

## New core features considered

### 1. Task clocks / quiet focus sessions — selected

A task clock begins only after the user sets the exact time the task should take. A 10, 20, or 40 minute estimate becomes one contained stretch of protected attention, rather than a vague preset. The countdown is large and quiet; the vault stays engaged when the timer completes so the user is never surprised by an automatic unblocking or a new administrator prompt.

Why it wins: it turns the existing block into a repeatable timeboxing behavior, gives an estimate a visible finish line, needs no account or setup, and creates the strongest opportunity for emotional arrival / progress / completion moments.

The task card has two modes:

- **Task clock:** enter the exact whole-minute estimate before starting.
- **Focus timer:** use the quick 25, 50, or 90 minute focus intervals.

Both modes use the same active, paused, completion, and early-stop behavior. The selector is visible in the ready/completed states and locked while a clock is active or paused, so a running commitment cannot be changed underneath the user.

#### Task-clock interaction

- **Set:** enter a whole-minute estimate from 1–240 before starting. The estimate is the commitment, not a suggested preset.
- **Start:** starting the clock engages the full vault when it is not already on.
- **Work:** show exact minutes and seconds remaining with a quiet progress ring.
- **Pause:** pause when the task is interrupted. Paused time does not consume the estimate.
- **Resume:** continue from the exact remaining time without changing the original estimate.
- **Finish:** when the clock reaches zero, show a brief acknowledgement and keep the vault engaged until the user explicitly changes it.
- **Stop early:** allow an early exit without shame or automatic unblocking; stopping changes only the clock.

### 2. Personal intention — selected

A short, local statement such as “finish the proposal” or “be present with the draft” sits at the heart of the dashboard. It is editable in place and shown as the reason for the protected stretch, not as a task-management system.

Why it wins: it makes the product emotionally specific with almost no additional UI, reinforces agency, and is private enough to store locally with no service dependency.

### 3. Vault schedules and profiles — deferred

Preset profiles such as “deep work,” “reading,” or automatic weekday schedules could make blocking more powerful, but they add configuration surfaces, persistence edge cases, unexpected administrator operations, and more ways for the product to become a settings app.

Why it loses today: the complexity cost is higher than the value of a third control. Revisit only after sessions and intentions prove that users need repeatable automation.

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
