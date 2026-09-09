# TripReel design QA

> September 8 update: First Cut is now always completed privately on-device.
> Its first playback is unobstructed except for progress and one Continue action;
> the next screen offers exactly two paths: improve with AI or edit the film.
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
- [P3] The source uses striped gradient placeholders for photographs; the implementation intentionally uses generated Da Nang travel photography because the supplied design contains no production image assets. Subject selection, amber grade, crop, and contrast remain consistent across the flow.
- [P3] The simulator shows the current system time and native status-bar rendering instead of the source prototype's fixed `9:41`. This is expected native platform behavior.

**Comparison target**

- Source visual truth: `/Users/prakash/Documents/TripReel - Codex/design-reference/TripReel.dc.html` and `/Users/prakash/Documents/TripReel - Codex/design-reference/Montage.dc.html`.
- Source captures: `/Users/prakash/Documents/TripReel - Codex/qa/reference-welcome.png`, `reference-access.png`, `reference-trips.png`, `reference-pace.png`, `reference-export.png`, `reference-done.png`, and `reference-cleanup.png`.
- Rendered implementation: native SwiftUI app screenshots in `/Users/prakash/Documents/TripReel - Codex/qa/*-final.png`.
- Revised AI flow evidence: `/Users/prakash/Documents/TripReel - Codex/qa/ai-consent-before-direction-final.png`, `/Users/prakash/Documents/TripReel - Codex/qa/ai-direction-photo-choice-final.png`, and `/Users/prakash/Documents/TripReel - Codex/qa/ai-photo-selection-final.png`.
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
- Accessibility and behavior: semantic buttons, selection values, descriptive labels, Reduced Motion handling, native photo permission/picker behavior, cut/undo state, export quality, and compact-height layout were checked. The new motion pass uses restrained shared springs, direct gesture tracking, brief fades for reduced motion, cancelable task-driven ambient effects, and matching eased motion/cross-dissolves in exported video. The revised consent-before-direction journey, exact-photo-selection journey, adaptive-title editor, and complete creation/export/cleanup flow pass on the iPhone 17 Pro simulator. Strict app and unit-test source checks pass.
- iCloud resilience: analysis retries and then uses source-data fallback before deferring an asset; unreadable assets remain recoverable outside the active cut; montage playback waits for sufficient preview pixels, holds the last valid frame, shows quiet progress, and skips unresolved slides for that loop; export stages all target-resolution frames with bounded retry, source-data fallback, visible preparation progress, and a one-tap recovery action before video encoding begins.

**Comparison history**

1. Pass 1 found safe-area double counting on Trips/Pace/Export, an undersized Film Ready preview, flat translucent surfaces, and background-glow drift. These were fixed by removing duplicate safe-area padding, resizing the preview to the source proportions, adding native Material beneath glass tints, and tuning per-state background centers. Evidence: `qa/compare-states-pass1.png` → `qa/compare-states-pass2.png`.
2. Pass 2 found remaining heading rhythm, Pace vertical offset, Cleanup spacing, and uneven Welcome multiline leading. Heading spacing and section padding were tightened, Cleanup was rebalanced, and Welcome was rebuilt as three individually controlled display lines. Evidence: `qa/compare-welcome-pass2.png`, `qa/compare-welcome-pass3.png`, and `qa/compare-welcome-final.png`.
3. Responsive review identified fixed-height pressure on Photo Access and Film Ready. Compact compositions were added and validated across the full compact workflow. Evidence: `qa/access-375x667.png`, `qa/done-375x667.png`, and `qa/responsive-375x667-final.png`.
4. Final pass found no actionable P0/P1/P2 visual differences. Evidence: `qa/compare-states-final.png`.
5. The latest flow removes the mandatory Refine → Pace → Edit sequence. First Watch is now an uncluttered full-screen playback with one Continue CTA. Continue opens a dedicated two-choice screen for AI Director or self-editing; the Film Studio then groups Photos, More Photos, Framing, Style, Titles, Music, and Pace into one native Edit film menu beside a single Export film CTA. Persistent Back and left-edge swipe return each screen to its explicit parent, and Export returns to the screen that opened it instead of relying on enum order. This pass is code-, UI-test-, and screenshot-backed.
6. The current pass removes the duplicate AI entry from Trips and changes the AI path to Consent → Choose Photos & Direction → Create AI cut. Visual comparison against the user-supplied problem screens confirms that provider/model disclosure is now unavoidable, explanatory copy is shorter, and photo choice is concrete rather than implied. Evidence: `qa/ai-consent-before-direction-final.png`, `qa/ai-direction-photo-choice-final.png`, and `qa/ai-photo-selection-final.png`.
7. The local-story pass replaces geocoder-first card names with time-and-place headlines, keeps exact location/date/count as secondary context, and derives editable title cards from on-device Vision categories. Middle cards are anchored after a real day or visual-theme boundary so preview and export insert them at the same meaningful moment. The final 402 × 874 simulator review found no truncation in the four-trip fixture list.

**Open Questions**

- StoreKit purchase validation remains a prototype interaction. Trip clustering, video rendering with music, Photos saving, system sharing, and user-confirmed destructive cleanup now use native production APIs.

**Implementation Checklist**

- [x] Match the supplied 402 × 874 visual source across the primary journey.
- [x] Replace absent photo assets with a coherent generated travel set and native app icon.
- [x] Implement all core navigation, gestures, sheets, selections, progress states, and branches.
- [x] Verify compact and large iPhone layouts.
- [x] Pass strict app, unit-test, and UI-test source checks plus asset, privacy-string, font, and app-icon validation.
- [x] Run the consent-before-direction and exact-photo-selection UI journeys on iPhone 17 Pro simulator.
- [x] Run all 119 unit tests and all 11 UI journeys on the iPhone 17 Pro simulator.
- [ ] Validate a long production-library video export on Xcode Cloud/TestFlight hardware.

**Follow-up Polish**

- Validate long 1080p exports, Photos saving, soundtrack muxing, App Attest, and pinch/drag editing on a physical iPhone/TestFlight build; the focused simulator checks do not replace real-device media and security validation.

final result: local story naming and adaptive title inserts passed strict source checks, 119 unit tests, all 11 UI journeys, and final simulator visual review
