# TripReel design QA

> September 9 First Cut update: the initial full-screen film preview now starts
> its selected bundled soundtrack automatically and exposes one unobtrusive
> speaker control alongside the existing Back chrome. After Continue, the two
> creative routes remain visually dominant while a quieter “Export This” button
> lets a satisfied user skip Film Studio. Export Back returns
> to this choice screen. The updated 402 × 874-equivalent native render was
> compared directly with the supplied TestFlight screenshot; hierarchy, spacing,
> and safe-area behavior remain intact.
>
> September 9 transfer update: AI Director now visualizes the actual data path.
> Selected reduced preview cards move from “This iPhone” along a locked route
> to “OpenAI · GPT-5.6 Luna”; the screen simultaneously states that originals
> stay on the phone. Preparing and transmitting are distinct visual states,
> motion stops on failure, and Reduce Motion receives a clear static state.
> The former quiet text link is now one prominent “Cancel AI edit” control that
> cancels the task and returns to the unchanged First Cut.
>
> September 8 update: First Cut is now always completed privately on-device.
> Its first playback is unobstructed except for progress, soundtrack chrome, and
> one Continue action; the next screen offers two creative paths plus a quiet
> direct-export route for users who are already satisfied.
> The Trips collection no longer carries a duplicate Optional AI Remix card.
> Improve with AI now opens a concise permission screen before any direction or
> photo selection. It names OpenAI and GPT-5.6 Luna, states that small previews
> rather than originals are shared, and offers one explicit Allow action. Only
> after accepting can the user choose the exact eligible photos and a reel
> direction; nothing is prepared or uploaded until Create AI cut. The new
> consent, photo selection, direction, processing/failure, and First Cut vs AI Cut
> comparison screens preserve the existing cinematic language and Reduce Motion.
> The Film Studio continues to keep its 9:16 film completely
> unobstructed and reduces the screen to Edit film and Export film. Persistent
> Back, an edge swipe, and VoiceOver escape restore predictable reverse
> navigation without turning Back into another primary action. Titles now use
> one full-screen live canvas and timeline where every card's text, style,
> visibility, and duration can be edited. CapCut receives a rendered MPEG-4
> handoff rather than an incompatible timing file. Full-person safe framing, similarity
> clustering, directional navigation, cinematic montage transitions, and the
> accessible app-wide motion system pass strict source checks. Cloud
> consent now appears before an AI direction is chosen. AI Director can fairly
> reconsider privacy-safe More Photos, while small events keep every safe frame
> and repeated backdrops never collapse detected people. Internal title-type
> labels are no longer rendered into previews or exports. Cleanup exposes
> responsive Select all/Clear all controls with a live selected/total count.
> On-device story naming replaces raw administrative labels with readable trip
> headlines while preserving precise place context. Local Vision themes and
> capture-day boundaries create editable intro, story-beat, and ending cards at
> meaningful points in the actual montage timeline.
> The revised privacy flow was captured from the native iPhone 17 Pro simulator
> and the complete 11-journey UI suite passes.

**Findings**

- No actionable P0, P1, or P2 differences remain in the checked flow. The native build preserves the source hierarchy, Instrument Serif display typography, spacing rhythm, warm palette, glass surfaces, card geometry, controls, and app copy.
- The First Cut preview visibly reports active soundtrack playback and offers pause/resume without competing with Continue. The direct-export option is intentionally tertiary, fits without clipping, and returns to the correct parent screen when Back is used.
- The AI transmission panel keeps its heading, privacy explanation, moving cards, route, and endpoints visually separated at 402 × 874. Two successive native captures confirmed that the photo cards move; the focused UI journey confirmed that Cancel returns to First Cut options.
- [P3] The source uses striped gradient placeholders for photographs; the implementation intentionally uses generated Da Nang travel photography because the supplied design contains no production image assets. Subject selection, amber grade, crop, and contrast remain consistent across the flow.
- [P3] The simulator shows the current system time and native status-bar rendering instead of the source prototype's fixed `9:41`. This is expected native platform behavior.

**Comparison target**

- Source visual truth: `/Users/prakash/Documents/TripReel - Codex/design-reference/TripReel.dc.html` and `/Users/prakash/Documents/TripReel - Codex/design-reference/Montage.dc.html`.
- Source captures: `/Users/prakash/Documents/TripReel - Codex/qa/reference-welcome.png`, `reference-access.png`, `reference-trips.png`, `reference-pace.png`, `reference-export.png`, `reference-done.png`, and `reference-cleanup.png`.
- Rendered implementation: native SwiftUI app screenshots in `/Users/prakash/Documents/TripReel - Codex/qa/*-final.png`.
- Revised AI flow evidence: `/Users/prakash/Documents/TripReel - Codex/qa/ai-consent-before-direction-final.png`, `/Users/prakash/Documents/TripReel - Codex/qa/ai-direction-photo-choice-final.png`, and `/Users/prakash/Documents/TripReel - Codex/qa/ai-photo-selection-final.png`.
- AI transmission evidence: `/Users/prakash/Documents/TripReel - Codex/qa/ai-transfer-final.png`; reference/native comparison: `/Users/prakash/Documents/TripReel - Codex/qa/compare-ai-transfer-final.png`.
- First Cut soundtrack evidence: `/Users/prakash/Documents/TripReel - Codex/qa/first-watch-soundtrack.png`; direct-export evidence: `/Users/prakash/Documents/TripReel - Codex/qa/first-cut-direct-export.png`; supplied/native comparison: `/Users/prakash/Documents/TripReel - Codex/qa/compare-first-cut-direct-export.png`.
- Full-view comparison evidence: `/Users/prakash/Documents/TripReel - Codex/qa/compare-states-final.png`.
- States compared: Welcome, Photo Access, Trips, Pace, Export, Film Ready, and Cleanup. The cutting state was also checked in `/Users/prakash/Documents/TripReel - Codex/qa/compare-cut-pass1.png`; the full core journey was exercised by the UI test.

**Normalization**

- Design viewport and logical iOS viewport: 402 × 874 points/CSS pixels, portrait.
- Source captures: 402 × 874 pixels at density 1.
- Native captures: 1206 × 2622 pixels at simulator density 3, downsampled with Lanczos filtering to 402 × 874 before comparison.
- Device frame, browser canvas, and prototype navigation pills were excluded. Native status bar and home indicator were retained because they are system-owned screen content.
- Responsive evidence: `/Users/prakash/Documents/TripReel - Codex/qa/responsive-375x667-final.png` covers nine workflow states at 375 × 667 points; Photo Access and Film Ready were also checked at 430 × 932 points in `qa/access-430x932.png` and `qa/done-430x932.png`.

**Required fidelity surfaces**

- Fonts and typography: bundled Instrument Serif Regular/Italic matches the source display face; SF system text and monospaced metadata preserve hierarchy, wrapping, tracking, and optical weight. Welcome and Pace received focused full-resolution pair checks in `qa/compare-welcome-final.png` and `qa/compare-pace-final.png`.
- Spacing and layout rhythm: final headers, media frames, cards, sliders, CTAs, corner radii, and safe-area offsets visually align at 402 × 874. Compact variants keep persistent controls visible at 375 × 667.
- Colors and visual tokens: cream, ink, amber, keep green, cut red, translucent strokes, materials, shadows, and per-state warm gradients match the supplied palette and contrast balance.
- Image quality and asset fidelity: six coherent 1024 × 1536 generated travel images are bundled as raster assets with stable focal crops. The source provided only placeholder gradients, so the photography is an intentional asset completion rather than a missing-source substitution.
- Copy and content: all source app-specific labels, trip data, pricing, export descriptions, and cleanup language are represented. Native permission denial adds a necessary system Settings recovery path.
- Accessibility and behavior: semantic buttons, selection values, descriptive labels, Reduced Motion handling, native photo permission/picker behavior, cut/undo state, export quality, and compact-height layout were checked. The new motion pass uses restrained shared springs, direct gesture tracking, brief fades for reduced motion, cancelable task-driven ambient effects, and matching eased motion/cross-dissolves in exported video. The soundtrack control announces Play/Pause and its selected track; direct export has an explicit skip-editing hint and restores its parent on Back. The revised consent-before-direction journey, exact-photo-selection journey, adaptive-title editor, and complete creation/export/cleanup flow pass on the iPhone 17 Pro simulator. Strict app and unit-test source checks pass.
- iCloud resilience: analysis retries and then uses source-data fallback before deferring an asset; unreadable assets remain recoverable outside the active cut; montage playback waits for sufficient preview pixels, holds the last valid frame, shows quiet progress, and skips unresolved slides for that loop; export stages all target-resolution frames with bounded retry, source-data fallback, visible preparation progress, and a one-tap recovery action before video encoding begins.

**Comparison history**

1. Pass 1 found safe-area double counting on Trips/Pace/Export, an undersized Film Ready preview, flat translucent surfaces, and background-glow drift. These were fixed by removing duplicate safe-area padding, resizing the preview to the source proportions, adding native Material beneath glass tints, and tuning per-state background centers. Evidence: `qa/compare-states-pass1.png` → `qa/compare-states-pass2.png`.
2. Pass 2 found remaining heading rhythm, Pace vertical offset, Cleanup spacing, and uneven Welcome multiline leading. Heading spacing and section padding were tightened, Cleanup was rebalanced, and Welcome was rebuilt as three individually controlled display lines. Evidence: `qa/compare-welcome-pass2.png`, `qa/compare-welcome-pass3.png`, and `qa/compare-welcome-final.png`.
3. Responsive review identified fixed-height pressure on Photo Access and Film Ready. Compact compositions were added and validated across the full compact workflow. Evidence: `qa/access-375x667.png`, `qa/done-375x667.png`, and `qa/responsive-375x667-final.png`.
4. Final pass found no actionable P0/P1/P2 visual differences. Evidence: `qa/compare-states-final.png`.
5. The latest flow removes the mandatory Refine → Pace → Edit sequence. First Watch is now an uncluttered full-screen playback with one Continue CTA. Continue opens a dedicated two-choice screen for AI Director or self-editing; the Film Studio then groups Photos, More Photos, Framing, Style, Titles, Music, and Pace into one native Edit film menu beside a single Export film CTA. Persistent Back and left-edge swipe return each screen to its explicit parent, and Export returns to the screen that opened it instead of relying on enum order. This pass is code-, UI-test-, and screenshot-backed.
6. The current pass removes the duplicate AI entry from Trips and changes the AI path to Consent → Choose Photos & Direction → Create AI cut. Visual comparison against the user-supplied problem screens confirms that provider/model disclosure is now unavoidable, explanatory copy is shorter, and photo choice is concrete rather than implied. Evidence: `qa/ai-consent-before-direction-final.png`, `qa/ai-direction-photo-choice-final.png`, and `qa/ai-photo-selection-final.png`.
7. The local-story pass replaces geocoder-first card names with time-and-place headlines, keeps exact location/date/count as secondary context, and derives editable title cards from on-device Vision categories. Middle cards are anchored after a real day or visual-theme boundary so preview and export insert them at the same meaningful moment. The final 402 × 874 simulator review found no truncation in the four-trip fixture list.
8. The AI transfer pass replaces the abstract fanned-photo loader with an explicit iPhone → secure route → OpenAI animation. The first comparison exposed moving cards overlapping the explanatory heading; lowering the route removed that collision before the final capture. The final state preserves the source screen's hierarchy while making transmission and cancellation immediately understandable.
9. The First Cut completion pass restores audible soundtrack playback on the initial preview and adds a symmetric speaker control opposite Back. The supplied/native side-by-side review showed enough room for a subdued direct-export control without weakening the two creative routes. Direct export and return navigation passed focused and full-journey UI checks.

**Open Questions**

- StoreKit purchase validation remains a prototype interaction. Trip clustering, video rendering with music, Photos saving, system sharing, and user-confirmed destructive cleanup now use native production APIs.

**Implementation Checklist**

- [x] Match the supplied 402 × 874 visual source across the primary journey.
- [x] Replace absent photo assets with a coherent generated travel set and native app icon.
- [x] Implement all core navigation, gestures, sheets, selections, progress states, and branches.
- [x] Verify compact and large iPhone layouts.
- [x] Pass strict app, unit-test, and UI-test source checks plus asset, privacy-string, font, and app-icon validation.
- [x] Run the consent-before-direction and exact-photo-selection UI journeys on iPhone 17 Pro simulator.
- [x] Run the AI transmission and cancellation UI journey on iPhone 17 Pro simulator.
- [x] Run all 119 unit tests and all 13 UI journeys on the iPhone 17 Pro simulator; all 132 checks pass in their current suites.
- [ ] Validate a long production-library video export on Xcode Cloud/TestFlight hardware.

**Follow-up Polish**

- Validate long 1080p exports, Photos saving, soundtrack muxing, App Attest, and pinch/drag editing on a physical iPhone/TestFlight build; the focused simulator checks do not replace real-device media and security validation.

prior result: passed — First Cut soundtrack playback and direct export passed the native build, supplied/native visual comparison, all 119 unit tests, and all 13 UI journeys.

## September 11 AI recipe density update

**Comparison target**

- Source visual truth: `/tmp/codex-remote-attachments/01a06f8e-3baf-7df1-9a63-285792e8cab1/80C45482-651C-4A56-A558-E5BA163473F4/1-Photo-1.jpg`.
- Source dimensions: 588 × 1280 pixels; supplied TestFlight capture with native system chrome.
- Intended state: AI Director photo/direction screen immediately after permission, with the recommended recipe selected.
- Rendered implementation screenshot: unavailable for this pass.
- Intended logical viewport: current iPhone portrait layout; density normalization cannot be completed without a revised native capture.

**Full-view and focused comparison evidence**

- The source capture was opened at original resolution. Its main density issue is the five-card recipe list consuming the remaining viewport beneath the story field.
- The implementation now defaults to one selected/recommended recipe card with a clear `Change` affordance. Expanding shows all five recipes; selecting one collapses the list again. The screen heading, card action, and selection sheet consistently use `Edit photos` language.
- A post-change native screenshot could not be captured because CoreSimulatorService still aborts while loading the obsolete `/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 9.0.simruntime`. No device runtime was altered or deleted.
- Focused visual comparison is blocked for the same reason; source compilation is not a substitute for rendered evidence.

**Required fidelity surfaces**

- Fonts and typography: existing Instrument Serif and SF typography are unchanged; revised labels compile without truncation diagnostics, but rendered wrapping remains unverified.
- Spacing and layout rhythm: the collapsed state removes four recipe cards by default and preserves the existing 11-point card rhythm; exact native spacing remains unverified.
- Colors and visual tokens: existing cream, amber, glass, and semantic selection tokens are reused unchanged.
- Image quality and asset fidelity: existing real photo previews and SF Symbols are unchanged; no new assets or placeholders were introduced.
- Copy and content: `Choose photos & direction`, the card's `Choose`, and the sheet's `Choose photos` are now `Edit photos & direction`, `Edit photos`, and `Edit photos`.

**Findings**

- [P2] Revised native capture unavailable.
  Location: AI Director photo/direction screen.
  Evidence: the source TestFlight screenshot is available, but CoreSimulator cannot launch the updated build.
  Impact: typography wrapping, compact-device spacing, and the expanded/collapsed transition cannot be visually certified in this environment.
  Fix: capture the default collapsed state and expanded state from the next TestFlight build at the same device size, then compare both against the supplied screen.

**Comparison history**

1. The supplied screen showed all five full recipe cards by default and used `Choose` language for an editing action.
2. The implementation now shows one recipe summary by default, exposes all recipes only after `Change`, collapses after selection, and uses `Edit photos` consistently. Strict app and UI-test source checks pass.
3. Post-fix visual comparison is pending because no native runtime is available on this Mac.

**Implementation Checklist**

- [x] Collapse the full recipe list by default.
- [x] Keep the selected/recommended recipe visible as the summary.
- [x] Expand on `Change` and collapse after a selection.
- [x] Rename the heading, card action, sheet title, and accessibility hint to `Edit photos`.
- [x] Add UI-test coverage for the initial collapsed state and expansion.
- [ ] Capture and compare the collapsed and expanded states in the next TestFlight build.

**Follow-up Polish**

- Confirm the longer `Edit photos` trailing label does not compress the selected-count copy on the smallest supported iPhone.

final result: blocked
