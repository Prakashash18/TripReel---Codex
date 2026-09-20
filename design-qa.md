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

---

# First Cut / AI Director design QA

- Source visual truth: `/Users/prakash/.codex/generated_images/01a06f8e-3baf-7df1-9a63-285792e8cab1/exec-15465587-be5d-48f2-8a7c-acf74e8e2ca9.png`
- Native implementation capture: `/tmp/memories-first-cut-option2.png`
- State: First Cut decision, Da Nang demo memory, iPhone 16 Pro simulator on iOS 18.3.1.
- Viewport: approximately 402 × 874 pt at 3×; native screenshot 1206 × 2622 px. Generated concept 853 × 1844 px, approximately the same aspect ratio. Compared app-owned content, allowing for iOS status and home areas in the native capture.
- Full-view evidence: the selected concept and simulator capture were opened together in the same image comparison. Both use a full-bleed memory image, large serif First Cut title, filmstrip, one cream primary action, and a distinct lower AI invitation.
- Focused-region evidence: the title, action labels, privacy copy, and bottom panel were legible in the full-size image views; a separate crop was not required.

## Findings

- No actionable P0/P1/P2 visual mismatch. The implementation retains the concept's local-first hierarchy and optional AI branch.
- P3, expected content difference: the native screen uses the person's actual selected memory image, not the mockup's stock boat image. This is intentional and more truthful to the product.
- P3, intentional product addition: “Edit this cut myself” is a quiet supporting action because manual editing already exists in this flow.

## Fidelity checks

- Fonts and typography: existing Memories serif display and sans/mono UI styles match the concept's editorial hierarchy. The on-device and optional-AI labels remain readable.
- Spacing and layout: filmstrip, main action, and lower AI panel fit without clipping on the tested iPhone viewport. The native status/home areas account for the small vertical shift from the app-content-only mockup.
- Colors and tokens: existing warm black, cream, gold, and restrained green status styles are preserved. AI is differentiated by copy and placement as well as color.
- Imagery: the dynamic trip cover and first-cut thumbnails replace mock travel images while preserving the photographic emphasis.
- Copy: the First Cut explicitly says it is made on the iPhone. AI is labeled optional, requires selected moments and a clue, and states that previews are sent only with permission.

## Interaction checks

- iPhone app build passed.
- Focused UI tests passed for the First Cut options, AI consent, and the unsaved-video exit choices.
- Live Supabase account re-download requires a signed-in TestFlight/device check with an active linked video; it was not exercised by the demo simulator.

## Comparison history

1. Initial source-versus-simulator comparison found no P0/P1/P2 visual issues. No visual iteration was needed.

final result: passed
