# Memories: UX audit and proposed changes

Method: read the screen code (`TripReel/Screens/*`) and the design system, counted text sizes, contrast and accessibility hooks, and traced navigation in `TripReelModel.navigateBack()`. Not yet checked on a physical iPhone or with VoiceOver / the largest Dynamic Type sizes, so items marked (verify) need a device pass.

Severity: **High** = people get stuck or misled. **Medium** = slows people down or hurts some users. **Low** = polish.

## What already works (keep)

- Clear privacy language at the moment of choice (photo access, AI consent, link upload).
- A free, real preview, so the paywall never blocks the first success.
- Undo on removing a moment; "Nothing is deleted" wording on the cut screen.
- Reduce Motion is respected in 39 places.
- Failure states tell people what happened and whether progress is kept (export paused, resume).
- One shared look (`TripReelTheme`), so screens feel like one app.

## Cross-cutting findings

| # | Finding | Evidence | Severity | Proposed change |
|---|---|---|---|---|
| X1 | Text does not scale with Dynamic Type | `TR.ui` and `TR.mono` use `.system(size:)`; only the serif display font is `relativeTo:`. Only 8 scaling hooks in the whole app | **High** | Make `TR.ui` / `TR.mono` use `relativeTo: .body/.caption` (or `@ScaledMetric`). Then test at AX3 and fix clipped rows |
| X2 | Very small text | About 150 text styles at 11 pt or below (48 at 10 pt, 21 at 9 pt, 12 at 8 pt, 1 at 6 pt) | **High** | Floor of 12 pt for anything people must read (prices, expiry, status). Keep 10 pt only for decorative labels |
| X3 | Low-contrast secondary text | Many `white.opacity` values from 0.22 to 0.5 on dark photo backgrounds | **High** | Raise body and caption text to at least 0.7 opacity (4.5:1). Check the status and expiry lines first |
| X4 | Small tap targets | About 35 fixed frames under 40 pt (icon buttons, chips, pill buttons such as "Export film") | Medium | Minimum 44 × 44 pt hit area (`contentShape` + padding) even when the visual is smaller |
| X5 | Plain words that look like captions | Fixed on the main paths in `b184881` (Skip, Fine-tune, Select moments, Done, Not now) | Medium | Rule: one primary per screen, secondary = outlined, text links only for legal/help. Re-check sheets (Titles, Music, Photo editor) |
| X6 | Back behaviour differs by screen | Some screens have a back button, others rely on swipe; `.done` back goes to Export | Medium | One back control in the same top-left spot on every non-root screen, labelled with the destination ("‹ Trips") |
| X7 | Screen-reader coverage is thin outside the editor | `accessibilityLabel` counts: Editing 30, Export 3, Trips 2, Onboarding 1 | Medium | Label every icon-only button and the film preview; announce progress on Rendering (verify with VoiceOver) |
| X8 | Terminology drift | "Memory", "film", "story", "reel", "First Cut", "cut", "export", "trailer/preview" all appear | Medium | Pick: **memory** = the trip, **film** = the video, **First Cut** = first version, **preview** = free 720p. Replace the rest |
| X9 | Sheets stack many controls | Editing sheets (Photo editor, Titles, Music, Style) | Low | Keep one job per sheet; group advanced controls under "More" |

## Screen by screen

### 1. Welcome
- Good: single "Get started" button.
- Change: add one line saying the photos stay on the phone (it's the main trust point) above the button, not only on the next screen. Low.

### 2. Photo access / Limited access
- Good: plain explanation, Terms and Privacy reachable.
- Change: the two paths are now both buttons; keep "Allow access" as the only filled button. Move "I agree to the Terms" wording to a smaller line, since it appears before any action. Medium.
- Limited access: say what is missing ("Trips from other photos won't appear") before offering "Expand access". Medium.

### 3. Trips list (home)
- Good: tabs for overseas/local, a "This day last year" card.
- Change: "My films" is now always shown; make it a top-bar button instead of a card so the list is not pushed down. Medium.
- Empty / failed scan: show how to rescan and what "usual places" means in one sentence (the Library scan panel is gone, so there is no other explanation). Medium.
- Pull to refresh: add a visible "Last updated" timestamp so a missing trip is explained. Low.

### 4. Story clue ("What was this day?")
- Good: skippable.
- Change: show 3 tappable example chips ("Family day out", "Birthday", "Beach") so people don't face a blank box. Medium.

### 5. Building
- Change: show a Cancel button and a rough time ("about a minute"). Medium.

### 6. First Cut watch and options
- Good: "Use this film" is the clear next step.
- Change: three routes appear at once (use, edit myself, AI Director). Show **Use this film** as primary, **Edit** as secondary, and fold AI Director under "Try another version". Medium.
- "Skip to the end" appears next to the player: rename "Jump to the end" and give it a button shape. Low.

### 7. AI Director (direction, processing, comparison)
- Good: consent names the provider and says nothing is sent yet.
- Change: the comparison screen's instruction "The whole card is your answer" is easy to miss; add two explicit buttons under the cards, "Use this version". Medium.
- Failure reference codes ("Reference · …") should sit behind a "Copy details" button, not in the main text. Low.

### 8. Cut (choose what stays)
- Good: "Nothing is deleted".
- Change: the swipe/tap model is not explained after the first view. Add a persistent one-line hint and an "Undo" that is always visible. Medium.

### 9. Pace
- Good: slider with live preview.
- Change: add word markers at the ends ("Slower" / "Faster") and a "Reset" control. Low.

### 10. Film Studio (second watch)
- Highest density screen. Change: the top bar has title, counts and Export; keep Export as the one filled button and move Moments, Style, Titles and Music to a labelled bottom toolbar (icon + word). Medium.
- Label the timeline's drag handles for VoiceOver. Medium.

### 11. Choose your export (Export + Paywall)
- Good: price from StoreKit, preview stays free.
- Change: put the three options side by side with one sentence each ("Free preview · 720p · watermark", "Monthly free export · 1080p", "Story Pass · 1080p · no watermark"). Reset date for the 3 monthly exports should be bold. Medium.
- Edit-after-export is free: say so here too. Low.

### 12. Rendering
- Good: progress, cancel, resume after pause.
- Change: say plainly "You can leave the app; it will carry on" and show estimated time left once available. Medium.

### 13. Memory ready
- Done in `b184881` and `0a1033a`: top bar, labelled buttons, "Get link" says cloud and 7 days.
- Remaining: after Save to Photos, show a gentle "Open in Photos" instead of a disabled grey button. Medium.

### 14. Cleanup
- Good: destructive delete is warned about.
- Change: show how much space will be freed. Say "Delete from Photos" moves items to Recently Deleted (30 days) if that is what iOS does here (verify). Medium.

### 15. My films sheet
- Good: expiry per film, delete confirmation.
- Change: show "Expires in 3 days" in amber under 24 h. Low.

### 16. Account, link ready, account deletion
- Change: make "Delete account" visually distinct but last, with the consequences listed (links stop working). Low.

### 17. Privacy, Terms
- Change: add an in-app summary at the top (3 bullets) before the long text. Low.

## Suggested order of work

1. Dynamic Type, minimum text size and contrast (X1–X3). One shared change in `TripReelTheme.swift`, then screen fixes.
2. Back button and button rules across all screens (X4–X6).
3. Film Studio toolbar and First Cut routes (screens 6, 10).
4. Copy: terminology (X8), story clue examples, comparison buttons.
5. VoiceOver pass (X7), then a TestFlight round with 3–5 people who have not seen the app.

## Suggested checks before claiming "user friendly"

- Run each screen at the largest accessibility text size and with VoiceOver.
- Time five first-time users: open the app → ready film. Note where they pause.
- Ask them where they would go next on the Ready screen, without hints.
