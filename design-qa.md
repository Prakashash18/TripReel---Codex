# Design QA — Memories New Flow

## Source of truth

- Design handoff: `/Users/prakash/Downloads/design_handoff_memories_loop/Memories New Flow.dc.html`
- Supporting review documents: `Memories UI Review.dc.html` and `Memories Accounts and Links.dc.html`
- Supporting assets: the six supplied travel photographs in the handoff `img` directory
- Reference render: `Docs/memories-new-flow-reference.png` (1440 × 2200)

## Implementation captures

- Memories list: `Docs/memories-new-flow-simulator.png` (1206 × 2622)
- Story clue: `Docs/memories-story-clue.png` (1206 × 2622)
- Side-by-side comparison: `Docs/memories-new-flow-comparison.png`
- Test viewport: iPhone 17 simulator, iOS 26.5, portrait
- Test state: deterministic demo library with four memories, including a one-year anniversary memory

## Comparison history

### Pass 1

- Compared the complete handoff overview against the full simulator capture.
- Found a premature cleanup banner on the main memories list. This competed with the anniversary card and did not belong in the supplied target state.
- Classified as P2 because it disrupted hierarchy without blocking the flow.
- Fixed by showing cleanup only when there are actual cut photos to review.

### Pass 2

- Re-captured the full memories list and inspected the header, anniversary hero, memory-card hierarchy, dates, imagery, spacing, and bottom safe area.
- Inspected the new clue screen independently for image legibility, contrast, keyboard-safe layout, button prominence, and optional skip affordance.
- Confirmed the animated card implementation respects Reduce Motion and does not create a continuously looping video preview.
- No P0, P1, or P2 visual issues remain.
- Remaining P3 differences are platform-native adaptations: Dynamic Island/safe-area spacing, native typography metrics, and a taller device viewport than the browser handoff.

## Functional QA

- The new story flow is: memory → optional clue → First Watch → Story Pass decision → export → saved Memory Card.
- First Watch stops at the end and exposes explicit replay/edit actions.
- Free trailer and paid full-story paths are distinct; rewarded-ad export code has been removed.
- Paid export remains gated by RevenueCat's Story Pass entitlement.
- Rendered films auto-save to Photos once, while the Film Ready screen provides named sharing destinations.
- AI comparison now asks one direct question and lets the user choose either cut.
- All 162 unit tests pass. All 18 UI journeys pass; the one assertion updated after rebasing onto the newer First Watch implementation was rerun and passed.

## Deferred handoff scope

Public memory links, accounts, view counts, and earned-pass referrals require backend identity, storage, moderation/privacy rules, and deletion semantics. They are intentionally not represented as working UI in this client-only pass.

## Final result

passed
