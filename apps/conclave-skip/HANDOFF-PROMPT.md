# Kickoff prompt - Conclave native: total parity, visual excellence, production release

You are working on the Conclave **native** app at `apps/conclave-skip` - a Skip app: one Swift codebase, transpiled to Kotlin/Compose for Android, compiled natively for iOS. The web app (`apps/web`) is the design and behavior reference and is in good shape. Your goal is to take native to **total parity with the web, looking genuinely good, and performing like a native app should**, ready for a full production release on both stores. The bar is a first-time user thinking "this is a really good experience" - nothing less.

**Read `apps/conclave-skip/AGENTS.md` completely before writing any code.** It is the living playbook: build/install/verify commands, the Skip transpile gotchas, the SkipUI `onChange` crash pattern, sheet/Lottie/entry-overlay/game-stage rules, perf patterns, the device checklist, and two operational rules that will burn you if skipped (never run two Gradle invocations concurrently; prod rate-limits rapid room creation - reuse one room per test session). `HANDOFF.md` is historical; do not work from it.

---

## Ground truth (verified 2026-07-14 against git history)

### Verified working (iOS simulator vs production, screenshot-evidenced in prior sessions)
- Core loop: cold start → JoinView → guest create → branded Lottie entry overlay → settled meeting → controls/chat/sheets → hang up. Entry overlay has a policy-driven hard ceiling (never strands black); media state never self-flips.
- Chat: web-parity bubbles (own = coral right, no avatar; peers = raised left with avatar), grouping, no send flicker (optimistic echo dedupe), full-bleed dock with bounded edges, GIF picker vs prod, long-press actions.
- Transcript (as of the last verified pass): start-stage hero, status row, live listening state vs the prod worker.
- Games: full catalog (Trivia, Bluff, WYR, Most Likely To, Reaction, Imposter, Wordle, Chess), cross-client play verified (moves scored by prod server), stage takeover, self-tile lives in the strip, flat headers, keyboard never collapses the stage (iOS).
- Deep links (join-by-link → prejoin), bad-code error path, waiting room.
- **TestFlight build 2.0.0 (50) uploaded, VALID, live to the internal "Conclave Testing" group.** Cut before the work below - a new build is needed.

### Landed since (committed, builds green, but NOT runtime-verified anywhere)
These ~14k lines are the first thing to truth-pass:
- **WebRTC receiver-capacity system**: `Core/WebRTC/WebcamReceiverCapacity.swift` (policy-driven, heavily unit-tested), major rework in `WebRTCClient.swift` + `Skip/WebRTCClient+Android.kt`. Media-scale behavior - needs multi-client verification (tiles beyond capacity, layer switching, foreground/background).
- **Transcript Ask + Minutes tabs** (`TranscriptPanelView.swift` tripled) with `Shared/NativeStreamingMarkdown.swift` for streamed answers, expanded `TranscriptService`/`TranscriptState`. Verify: tab switching, ask-a-question streaming, minutes sections, viewer vs controller.
- **Animated reactions** (`Skip/AnimatedReactionAsset.kt`, `ReactionViews.swift`) and **native GIF picker sheet** (`Skip/FlexibleGifPickerSheetHost.kt`).
- **Admit-all** (ParticipantsSheet button + socket) and **host promotion** (ParticipantsSheet flow + socket) - web shipped these; native has them wired but unproven.
- Chat rework in `ChatViews.swift` (~900 lines churned), `MeetingBannerOverlay`, `PipManager`, `JoinView` deltas.

### Parity gaps vs the web (web moved; native has nothing for these)
1. **Chat image attachments** - the web sends images (clipboard paste + picker), renders `ChatImageAttachmentView`, and runs OpenAI moderation server-side. Native chat has zero image support (no model case, no renderer, no send path). This is the largest user-visible gap: images sent from web won't render on native today - confirm and fix rendering first, then add native send (photo picker; iOS paste).
2. **Chat link embeds** - web renders unfurled link cards + tweet media (`ChatLinkEmbedView`); native renders plain link chips only.
3. **Apps panel / Apps SDK** - web has an Apps dock (`AppsPanel.tsx`) with spin-the-wheel as the first app. Native renders an active app's stage (`ActiveAppLayoutView`) but check whether it can *launch* apps; build the picker if missing.
4. Smaller web deltas to review for relevance: `ConclaveMessage` (assistant chat), `ChatOverlay` preview changes, `GridLayout`/`ParticipantVideo` behavior changes tied to receiver capacity. Desktop-only web features (CommandPalette, DeviceCaretMenu, MeetSettingsPanel, update pill) are explicitly out of scope for phones.

### Store state
- iOS listing metadata complete under `Darwin/fastlane/metadata/` (incl. corrected `app_privacy_details.json` - account data + product-interaction analytics; the old DATA_NOT_COLLECTED was false and must not return).
- Play listing text exists (`Android/fastlane/metadata/android/en-US/`). The Data Safety worksheet and the 6.9" screenshot set were removed in a repo cleanup - **screenshots must be recaptured** (the flow is documented in AGENTS.md; resize/validate per the asc-screenshot-resize skill; this macOS lacks the sRGB ICC profile at the documented path - sim captures are already sRGB, skip that step).
- Versions still `2.0.0 (50)` in the pbxproj (Skip propagates to Android). All post-50 work is not on TestFlight.
- Still user-gated: Android release keystore, Play/ASC submission go-ahead, one data-retention confirmation (nothing outside the repo retains meeting content).

---

## Priorities, in order

**A. Truth-pass the unverified work.** Sim harness first (see AGENTS.md: prod env overrides, `agent-device snapshot`/`click @ref`, one room per session). Cover: transcript Ask/Minutes end-to-end, animated reactions, GIF sheet, admit-all + host promotion (needs 2 clients - a headless web client via `playwright-core` + system Chrome works, guest flow reaches join), receiver-capacity sanity with 2+ publishers. On Android: the full AGENTS.md device checklist the moment a phone is present (`adb devices` first; a staged APK may be stale - rebuild). File every failure as a P0 and fix before moving on.

**B. Close the parity gaps.** In user-impact order: chat image rendering → native image send → link embeds → apps panel/wheel. Match the web component's design exactly (read its code first - colors, radii, spacing, states); reuse the native design tokens (`ACMColors`, `ACMFont`, `ACMRadius`, `ACMSpacing`).

**C. Experience pass.** Visual: sweep every surface against the web side-by-side (join, meeting grid/spotlight, all sheets, chat, transcript, games, waiting/error) and fix taste issues - alignment, spacing rhythm, type hierarchy, empty states. Performance: device-measured only (ConclavePerf + `setRequestedFrameRate` cadence; `pm compile -m speed` after installs) - idle meeting must be quiet, sheets/chat/lobby buttery. Never ship a speculative perf change without a device before/after.

**D. Release train.** Bump to `2.1.0 (51)` in the pbxproj when the truth pass is green. iOS: archive → TestFlight via `asc` (the flow that shipped build 50: cloud signing with the team + the ASC auth key from `~/.appstoreconnect/private_keys/`; `asc apps list` to confirm identity; export with `destination=upload --wait`). Recapture the 6.9" screenshot set from real flows. Android: signed AAB the moment the user provides the keystore. Surface the remaining user asks explicitly at the end of every session.

---

## Non-negotiable constraints

- **No gradients. Anywhere. Ever.** Flat solid surfaces, 1px borders, single coral accent. Run the AGENTS.md gradient scan before calling any UI work done. Functional state colors (success green, warning amber, transcript live-blue) are fine; a second brand accent is not.
- **No em dashes in anything you write** - code, comments, docs, commit messages, store copy. The user has banned them; grep before finishing.
- **Keep iOS green**: `swift build` + `swift test` (large suite - keep it passing; some tests assert source *shape*, e.g. cached-presentation rules - respect their intent rather than deleting them).
- **Android compile is part of done for every change**: `:Conclave:compileDebugKotlin` minimum, `assembleRelease` before device work. iOS-only validation has shipped Android-breaking Swift twice (`.map(String.init)`).
- **Do not re-enable R8/minification.** Documented SkipUI breakage.
- **Runtime proof or it did not happen.** Sim proof for iOS, device proof for Android; screenshots or accessibility dumps as evidence; report "verified on sim" vs "verified on device" vs "build-only" precisely.
- Use **agent-device only** for driving simulators (no computer-use). Prod SSH and anything credential-shaped needs the user's explicit approval.

## Working method

1. Recon before code: `git log --oneline -15`, `git status`, read AGENTS.md deltas. The codebase moves between sessions - never assume continuity.
2. Loop per change: implement → `swift build` → `:Conclave:compileDebugKotlin` → codex review (`codex exec -s read-only "..." < /dev/null`) → fix real findings → sim/device verify with evidence.
3. Sequential Gradle only. One prod room per test session. Space out creates.
4. Update AGENTS.md when you learn something durable (a gotcha, a pattern, a rule) - it is the only doc guaranteed to persist; standalone status docs get swept in cleanups.
5. End every session with: what is verified where, what is in flight, what the user must provide next.

## Definition of done

- Every AGENTS.md device-checklist item passes on a real Android device AND the iOS core loop passes on sim/device, all on a build containing the receiver-capacity + transcript-tabs work.
- The four parity gaps above are closed and verified cross-client against the web (web sends image → native renders it; native sends → web renders; embeds; apps).
- A side-by-side visual sweep of every surface finds nothing that reads worse than the web.
- Device-measured perf: quiet idle cadence, no jank on sheets/chat/lobby on the mid-range Android test phone.
- TestFlight has a build ≥ 51 containing all of it; the Play AAB is one keystore away; screenshots and listings are current; the user has a single short list of what only they can do (keystore, submissions, retention confirmation).
