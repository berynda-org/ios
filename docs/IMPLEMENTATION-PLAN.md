# Berynda iOS implementation plan

Status: catalog, work/edition, reader persistence and performance, cross-client publication resume, and the design-system token pass are implemented and CI-verified; authentication/library/profile are implemented with audited gaps (below); offline policy, localization/accessibility, product configuration, and release work remain
Written: 30 August 2026
Implementation target: this native SwiftUI repository
Reference architecture: `D:/lexykon/client/ios`
Normative visual prototype: `web/public/ios-mockups/index.html`
Primary backend contract: `api/v1/`

Mobile representation policy: when an edition has several published files,
the API selects `TXT/Markdown → EPUB → PDF`. DJVU is not returned to mobile
clients because the apps do not render it. The chosen format remains internal
and is never presented as a user-facing choice.

Implemented in the first Phase 0 slice:

- native SwiftUI app and `BeryndaCore` package scaffold;
- iPhone tab shell and iPad split-view shell using Berynda design tokens;
- live catalog search, work details, edition availability, and reader handoff;
- typed work/edition API models, transport errors, allow-listed deep links,
  fixtures, package tests, app smoke tests, and macOS CI;
- edition `readable_file_id`, `can_read`, `can_download`, and restriction fields;
- deterministic mobile representation selection without deleting siblings;
- preservation of the existing web reader's sibling-file switching; and
- fail-closed reader rights fallback.

Implemented in the first reader slice:

- full-screen reader presentation from an edition row;
- typed reader metadata, rights, reading-position, page-label, and TOC models;
- TXT/Markdown rendering with API-controlled text-selection permission;
- native reflowable and fixed-layout digital-publication rendering through an
  exact Readium 3.11.0 dependency, with approximate cross-client progress
  restoration;
- PDFKit rendering for permitted full and per-page PDFs;
- server-rendered image fallback whenever file/page download permission is
  absent, regardless of a more permissive delivery hint;
- bounded response sizes, content-type validation, page/width clamping,
  cancellable page turns, page restoration, zoom, and rights-aware sharing;
- transport/repository fixtures covering structured text, MIME confusion, and
  unsafe page parameters.

Downloaded publication packages use complete file protection in temporary,
non-backed-up storage and are deleted when the reader closes. Embedded remote
subresources are blocked, non-HTTPS external links are rejected, and
copy/share selection actions follow API rights. DJVU has no renderer and is
excluded by the mobile file-selection contract.

The Windows workspace cannot compile Xcode targets. The workflow in
`.github/workflows/ios.yml` is the authoritative clean macOS build gate and
runs on pushes to `main` and through manual dispatch.

## 0. Current implementation audit (11 September 2026)

This status is based on the code in this repository, not on the original sequencing
below. Some document work planned for Phase 5 was deliberately pulled forward
to de-risk the reader. A phase is not considered complete merely because one
of its later features exists.

### Implemented

- reproducible XcodeGen app definition, local `BeryndaCore` package, app/unit/UI
  test targets, privacy manifest, third-party notice, and macOS build workflow;
- fixed development and production API origins, allow-listed app/universal
  link parser, request IDs, language headers, typed public catalog transport,
  response-size/MIME checks, and cancellation-aware feature models;
- iPhone catalog tab flow and basic iPad sidebar shell;
- shared iPhone/iPad catalog route state, validated work and reader deep-link
  consumption, direct work loading, exact PDF-page opening, and selection restore
  across tab and size-class changes;
- anonymous search, work detail, edition availability, and full-screen reader
  launch without exposing stored file formats;
- server-controlled TXT/Markdown → EPUB → PDF selection with DJVU excluded;
- TXT/Markdown, Readium publication, full PDF, per-page PDF, and server-image
  rendering with deny-by-default rights routing;
- protected temporary publication storage, blocked embedded remote resources,
  HTTPS-only external publication links, and rights-aware copy/share behavior;
- restored PDF page, approximate publication progress restore, PDF page
  scrubber, custom page labels, page-addressable PDF contents navigation, and
  Dynamic Type-aware TXT/Markdown size and line-spacing controls; and
- backend mobile/reader contract suite passing locally (38 tests). Pure Swift
  navigation tests are present but require the macOS build gate to execute.
- final Apple team and explicit Bundle ID `org.berynda.ios`, Associated Domains
  capability, and App Store Connect application record `6808289031` are
  registered. Signing credentials, automated archive upload, and TestFlight
  distribution are not configured yet.

### Implemented 4–9 September 2026 (all CI-verified unless noted)

- work detail enriched from the full record, contributors by role, explained
  rights, one `CoverDesign` seeded by the work id with the web's hash;
- reader persistence complete, including the server's `recorded: false`
  refusal;
- bounded page cache, prefetch capped at two, lifecycle release/recovery, the
  past-last-page wedge fix, and iPad landscape spread mode;
- rights-aware download/print, persistent appearance, paged text over
  Unicode-scalar `page_offsets`, publication TOC navigation and type size;
- cross-client publication resume through the API's new `locator` position
  type — this also fixed a data-loss bug where closing a publication on iOS
  overwrote the reader's web position with an invented `page 1`;
- catalog recently-viewed offline fallback, recommended shelf, and collection
  membership on work pages, backed by three new API endpoints
  (`akrivonos/berynda` commit `504af15`);
- dark palette realigned to the normative mockups (five of seven tokens had
  drifted), Increase Contrast support, and tokens asserted by tests;
- a privacy leak — `RecentlyViewedStore` was never cleared on sign-out or
  when history was turned off, so one reader's history survived into the next
  account — and the language picker silently overwriting the server
  preference (commit `d4a1b0f`);
- anonymous readers are asked to sign in for a bookmark instead of never
  seeing the button, and the sign-in sheet opens over the book (`a4b62e4`);
- the profile's storage section measures what is actually on the device and
  can clear it, for signed-in and signed-out readers alike (`ab53c88`);
- saved collections can be unsaved, save buttons show saved state, and that
  state no longer survives sign-out or an account switch (`1780330`).

### Authoritative remaining plan

The dedicated `akrivonos/berynda-ios` repository is the canonical native-client
source. The older untracked `ios/` mirror in the web/backend checkout must not
receive further client changes; remove it after confirming that no unique work
remains, or replace it with a short pointer to this repository. Backend mobile
contracts and the production association file remain in `akrivonos/berynda`.

Delivery is split into four acceptance milestones. Items inside each milestone
are ordered by dependency and user value.

#### Milestone A — internal TestFlight alpha

Goal: let the product owner install the app and exercise the anonymous core
journey on a real iPhone and iPad.

Status on 2026-09-03:

1. **Complete.** The canonical production URL is committed. Package, unsigned
   app/test compilation, app-unit, and simulator gates pass in GitHub Actions
   (`iOS` run 16, commit `4d362d3`).
2. **Complete.** The production icon and launch presentation are in place.
   Reachable Library and account dead ends now explain their alpha status
   without fake or non-working actions.
3. **Complete.** Six deterministic UI journeys cover launch, Ukrainian search,
   pagination, work/edition opening and page turning, restricted reading, and
   missing-file behavior. They pass on the iPhone 16 Pro simulator in CI.
4. **In progress.** The association file for
   `KHMPLP3CXQ.org.berynda.ios` is committed in the web repository with work and
   reader routes. Production deployment and live universal-link verification
   remain required; the live endpoint still returned HTTP 404 before the
   deployment run started.
5. **In progress.** The Release archive, validation, dSYM retention, and upload
   workflow is committed. A Berynda-specific distribution certificate and
   active `Berynda App Store` provisioning profile now exist and the local
   password-protected signing package has been validated. A least-privilege
   App Store Connect key, encrypted GitHub secrets, and the first successful
   TestFlight upload remain required.
6. **Pending.** Run the real-device acceptance pass after the TestFlight build
   becomes installable and treat any crash, blocked core journey, data leak, or
   rights failure as release-blocking.

#### Milestone B — feature-complete beta

Goal: complete the user-facing v1.0 product rather than merely the anonymous
reader demo.

Status on 2026-09-03: implementation is in progress. The first beta slice adds
native sign-in/registration/password-recovery UI, Keychain-backed relaunch
restoration, profile editing, language/appearance/privacy controls, local and
server reading-position persistence, Continue Reading, bibliography lists,
duplicate-aware quick add and reader bookmarks, saved/featured collections,
catalog readability/language filters, and a selected-work column on iPad.
Native email-confirmation and password-reset completion links, protected local
resume restart coverage, and pre-save list reconciliation are included in the
second beta slice. The third beta slice preserves a pending work or public-
collection save across the sign-in sheet and completes it after successful
authentication. These changes require a green macOS CI run before the slices
are accepted.

1. **Complete except collection links.** Richer bibliography and rights
   summaries, removed/restricted/empty/retry states, stable covers, and true
   selected-work columns on iPad are delivered. Collection links await a
   backend route returning the collections that contain a work.
2. **Complete.** Add authentication UI for login, registration confirmation, password reset,
   logout, session expiry, relaunch persistence, and return-to-action behavior.
3. **Complete.** Reading-position persistence: quiet-interval PUT, background
   and dismiss flush, privacy-disabled handling for both the local policy and a
   server `recorded: false` refusal, local resume, and restart tests.
4. **Implemented with gaps (see slice 12).** Replace the Library placeholder with Continue Reading, bibliography lists,
   quick add, list-item reader bookmarks, and saved public collections with
   duplicate-safe reconciliation.
5. **Implemented with gaps (see slice 13).** Replace the Profile placeholder with account editing, language, appearance,
   reading-history privacy, storage management, logout, and local-resume cleanup.
6. **Complete.** Complete catalog discovery: readable/filter controls, featured collections,
   recommendations, saved collections, and recently viewed fallback.

#### Milestone C — reader, offline, and inclusive-quality hardening

Goal: make long reading sessions predictable on supported devices and under
poor connectivity.

1. Cap adjacent prefetch at two pages, bound decoded image/PDF caches, cancel
   obsolete work, recover across lifecycle transitions, and pass a 200-page
   memory/turn test.
2. Add persistent appearance settings, TXT paged/anchor navigation, native
   publication TOC/location and appearance controls, rights-aware download and
   print, exact resume interoperability, and iPad landscape spread mode.
3. Add a versioned, locale-isolated recently-viewed/document cache with
   corruption recovery, rights revalidation, and safe eviction. Permanent
   offline downloads are deferred to v1.1; v1.0 provides only bounded cache.
4. Move all user-facing strings into Ukrainian/English String Catalogs and pass
   pseudolocalization, VoiceOver order, 44-point targets, Dynamic Type, Reduce
   Motion, increased contrast, keyboard navigation, and narrow-screen audits.
5. Finish visual comparison with the approved HTML mockups on representative
   iPhone and iPad sizes, in light and dark appearances.

#### Milestone D — release candidate and App Store submission

Goal: produce an auditable v1.0 build that is ready for external beta and App
Review.

1. Add signed minimum/latest-build and maintenance configuration with safe
   caching plus forced-update and maintenance screens.
2. Expand CI to URLProtocol integration, full XCUITest journeys, staging
   contracts, performance/leak checks, and oldest/newest supported OS, iPhone,
   and iPad coverage.
3. Complete App Store description, keywords, support/privacy URLs, screenshots,
   age rating, export compliance, and privacy answers; then stage external
   TestFlight testing.
4. Audit the privacy manifest, transitive licenses, authentication storage,
   URLs, caches, document paths, logs, rights gates, universal links, archive
   provenance, and dSYM retention. Resolve every critical/high security issue
   and accessibility blocker.
5. Obtain product-owner sign-off against the HTML prototype and promote the
   accepted build to App Review.

### Explicitly deferred beyond v1.0

- permanent offline downloads;
- OCR/full-text scan search and text overlays;
- annotations beyond bibliography list items;
- TTS/autoplay and advanced page-turn effects;
- widgets, extensions, App Clips, and Handoff;
- social login; and
- any user-selectable file representation.

### Delivery slices, in order

1. **Mac build gate — complete:** Xcode 16.4 resolves Readium, runs the core
   package tests, generates the project, and builds the unsigned simulator app
   on every push to `main`.
2. **Networking hardening — transport portion implemented:** bounded and
   cancellable 429/5xx retry, streaming body limits, structured safe API error
   context, stable request IDs across retries, hardened ephemeral URL sessions,
   reachability, an app-wide offline state, and unit coverage. Auth headers are
   owned by slice 3; persistent cache freshness/language isolation remains with
   the offline-data slices.
3. **Session foundation — implemented:** Berynda-specific non-synchronizing
   Keychain storage, atomic token-pair writes, coalesced refresh with stale-token
   race suppression, one-time 401 replay, explicit expiry, best-effort server
   revocation on logout, and credential-redaction tests. Authentication screens
   and profile presentation remain in slice 11.
4. **Navigation completion — app and association file implemented, deployment
   pending:** `pendingRoute` is consumed; work links route on both size classes;
   reader links validate their file UUID and PDF `p`/legacy `page`; and catalog
   selection survives tab and size-class changes. EPUB `cfi` links currently
   open the correct file but exact native publication-location interoperability
   remains in slice 10. Team `KHMPLP3CXQ` is configured and the web repository
   contains the AASA routes for works and readers; production deployment and
   end-to-end universal-link verification remain.
5. **Design-system completion — implemented except a visual screenshot pass:**
   shared spacing, twelve canonical cover palettes, uploaded-cover loading with
   a native generated fallback, and reusable loading/empty/error/offline states
   were already in place. The dark palette has now been diffed against the
   normative prototype token by token: it had drifted in five of seven values,
   most visibly `ink`, which was near-pure white where the design calls for a
   warm off-white. All seven now match `web/public/ios-mockups/styles.css`.
   Increase Contrast is supported, strengthening muted text past AAA and
   turning the prototype's decorative ~1.3:1 borders into perceivable 3:1
   boundaries. `BeryndaPalette` holds the raw values so all of this is asserted
   by tests rather than reviewed by eye — a resolved `Color` cannot be read
   back, which is how the drift went unnoticed. **Remaining:** side-by-side
   screenshot comparison at representative iPhone and iPad sizes, which needs
   a machine that can run the simulator.
6. **Catalog completion — implemented:** prefix search,
   debouncing, stale-response suppression, continuous pagination,
   de-duplication, pull-to-refresh, page-level retry, readable/language filter
   controls, and featured and saved public collections are all implemented and
   app-unit tested. Recently viewed is now kept on device and shown when a
   catalog request never completes — only then, since a 403 or 404 is a real
   answer and stale rows would imply those works are still available. That
   history follows the reading-history privacy setting: with it off nothing is
   written and anything stored is dropped. Recommendations are served by
   `/works/recommended/`, shown above an unfiltered catalog only. The server
   ranks the work, never the reader, so the shelf is the same for everyone and
   reveals nothing about what anyone has read.
7. **Work and edition completion — implemented:** the
   detail page now enriches a thin catalog row with the full work record
   (contributors by role, original title, literary form, genres, topics,
   additional languages, abstract) and degrades to the summary when that
   fetch fails; rights are presented as an explained summary bound to
   `rights_summary`, with per-edition availability stated separately;
   `CoverDesign` resolves tone/variant/glyph once per work, seeded by the work
   id with the web client's hash, so a work looks identical in the catalog,
   the detail header, and collection strips; editions have their own
   loading/empty/restricted/retry states with fixtures. True selected-work
   columns on iPad were already delivered with slice 4. Collection membership is served by
   `/works/<id>/collections/` and shown as a panel with the save action the
   catalog shelves already offer. The rows do not navigate: there is no
   collection screen in the app yet, and implying navigation that does not
   exist would be worse than showing the membership plainly. A collection
   detail screen remains.
8. **Reader persistence — implemented:** authenticated position PUT, one-second
   quiet-interval save, background and dismiss flush, protected local resume
   that survives a process restart, and both refusal paths. A locally known
   disabled history and a server answering `recorded: false` are treated the
   same way: the local resume copy is dropped and nothing further is sent for
   the session. A thrown save is a transient failure, says nothing about
   policy, and is retried.
9. **Reader performance/resilience — implemented:**
   `ReaderPageCache` bounds retained pages by both a page count (8) and a byte
   ceiling (24 MB), evicting least-recently-used, so a long session cannot grow
   without limit and paging back one page no longer re-downloads it. Prefetch
   warms at most the next and previous page and is cancelled the moment the
   reader moves elsewhere. Backgrounding and memory warnings release the cache
   while keeping the visible page; returning re-fetches only if that page was
   dropped. A page request past the last page is now clamped before it is
   issued — previously it left `pageIsLoading` true forever and both page
   buttons went dead. Covered by a 200-page turn test asserting bounded cache
   size and bounded per-page request counts. iPad landscape spread mode shows
   two facing pages on a regular-width landscape screen, advances two pages at
   a time, collapses to a single page at the end of a document, and is offered
   only where the app itself paginates — a full PDF is laid out by PDFKit, and
   text and publications reflow.
10. **Reader feature parity — partial:** rights-aware download and print
    affordances are implemented, both deny-by-default and offered only for a
    document the app holds whole — per-page delivery never yields a complete
    file, so it offers neither. Exported bytes reuse the publication path's
    protected temporary storage (`ProtectedTemporaryFile`, extracted so there
    is one implementation rather than two) and are deleted when the reader
    closes. Text size and line spacing now persist across readers and launches
    instead of resetting each time. TXT paged mode reads a text derivative page
    at a time using the API's `page_offsets`, which are Unicode-scalar indices
    and are walked as such — neither `Character` nor `utf16` agrees with
    Python's `str` indexing, and for Ukrainian text one decomposed character
    would shift every later page. The body is fetched once and paging is pure
    slicing; malformed offsets from the network are repaired rather than
    trusted. Publications now expose their own table of contents — flattened to
    one indented list, so a reader looking for a chapter expands nothing — and
    a type-size control that persists across books. **Remaining:** anchor
    navigation inside a text body, which needs the body split into addressable
    blocks and so trades away selection across block boundaries; that
    trade-off should be decided rather than assumed.

    Publication resume is now cross-client. The API gained a `locator` position
    type (`apps.reader.locators`) carrying `href`, `progression`,
    `total_progression`, and an optional `cfi`: each client writes what it can
    produce and reads what it understands, falling back to `total_progression`,
    which every renderer can approximate. This client writes no `cfi` — Readium
    3.11 exposes only a `partialCFI`, which is not what an epub.js client can
    resolve, so writing one would look like interoperability while producing
    something the other reader cannot use — but it preserves a `cfi` written by
    the web reader across a round trip. Restoring prefers the exact resource and
    falls back to overall progress.

11. **Authentication UI — implemented; thin journey coverage:**
    login, registration, confirmation and password-reset link handoff, logout
    with device-first clearing, Keychain relaunch persistence, and return to
    the prompting action are all in code (audited 9 September against
    `AuthenticationView`, `AuthenticationLinkView`, `AccountViewModel`,
    `SessionController`). The reader bookmark, formerly hidden from anonymous
    readers, now prompts sign-in and resumes on the captured page with the
    sheet presented over the book (`a4b62e4`). **Remaining:** registration,
    reset, confirmation, and logout have contract tests but no UI journey.
12. **Library — implemented with gaps:** Continue Reading distinguishes empty
    from disabled history; lists load and can be created; quick add and reader
    bookmarks work and round-trip back to the page. Saved collections can be
    unsaved, a repeat save is answered `.alreadySaved` without a network call,
    and saved state is keyed by slug and cleared on sign-out (`1780330`).
    Lists can be renamed (title validated client-side to the server's limit:
    non-blank, at most 255 code points — Django's `max_length` counts code
    points, not characters), deleted behind a confirmation, and have items
    removed; the wire contract is asserted at the transport level, and the
    library reloads after each mutation without blanking the screen
    (`ab675ee`). The duplicate check is now tested, and the interleaving window
    is closed — every mutation claims `isMutating` before its first `await`,
    with a deterministic test that parks one mutation mid-fetch and shows a
    second is refused. **Gaps:** items cannot be reordered (the API requires
    every item id exactly once in `PUT lists/<id>/items/reorder/`);
    reconciliation has no offline queue or retry; save buttons can show a
    previous account's saved state after an account switch if the Library tab
    was never opened, until something reloads the library. `LibraryUnavailableView.swift`
    holds the real `LibraryView` under a stale name.
13. **Profile/settings — implemented with gaps:** account editing, appearance,
    the history-privacy toggle, and local-resume removal on sign-out /
    privacy-off / forced expiry are in code (the recently-viewed store is now
    cleared alongside positions, commit `d4a1b0f`). The storage section now
    measures reading positions, recently viewed works, and leftover reader
    files, and clears them behind a confirmation (`ab53c88`). **Gaps:** the
    language picker stores a preference but changes
    no strings — there is no String Catalog yet (slice 15), and it must not be
    presented as working until there is; session/account actions stop at
    sign-out (no change-password entry, no deletion, no sign-out-everywhere);
    and no unit test targets `AccountViewModel` or `ProfileView` directly
    beyond the three privacy tests.
14. **Offline document policy:** background-safe cache, schema/version/locale
    metadata, corruption recovery, rights revalidation and eviction, plus the
    v1.0 versus v1.1 decision for permanent downloads.
15. **Localization/accessibility:** String Catalog for Ukrainian and English,
    pseudolocalization, VoiceOver order, 44-point targets, Reduce Motion,
    keyboard/iPad navigation, narrow-screen and accessibility-size audits.
16. **Automated quality gates — partial:** core package tests, an unsigned app
    build, and the app unit-test target run in CI. Meaningful URLProtocol
    integration coverage, stable identifier alignment, full XCUITest journeys,
    performance/leak checks, staging contracts, and the oldest/newest supported
    OS and device matrix remain.
17. **Product configuration:** signed/static minimum/latest build, App Store
    URL and maintenance state, forced-update/maintenance screens, and safe
    configuration caching.
18. **Release/security hardening — Apple registration partial:** the Apple team,
    explicit Bundle ID, Associated Domains capability, and App Store Connect app
    record are complete. App icon and launch assets, signing credentials,
    signed archive/TestFlight upload, screenshots and metadata, production
    universal-link verification, privacy answers, transitive-license audit,
    archive/dSYM retention, final URL/auth/cache/log/rights review, and
    remediation of every critical/high or accessibility-blocking finding remain.

Post-MVP items remain the features in section 13: OCR/full-text scan search,
text overlays, annotations beyond list items, TTS/autoplay, advanced page-turn
effects, extensions/widgets/App Clips/Handoff, social login, and any
user-selectable file representation.

### Next work, in order (11 September 2026)

The three fixes interrupted on 9 September are done and CI-verified (run
34615510011 on `1780330`): storage summary and eviction (`ab53c88`),
collection unsave and saved-state buttons (`1780330`), and the reader
bookmark sign-in prompt (`a4b62e4`). Next, in this order:

Library list editing (rename, delete, remove item), the duplicate-check test,
and the mutation race fix are done and CI-verified (run 34619988762 on `ab675ee`).

4. Slice 14, offline document policy, per §5.3 — versioned, locale-isolated
   cache with corruption recovery and rights revalidation; permanent downloads
   stay deferred to v1.1.
5. Slice 15, localization and accessibility — the String Catalog is what makes
   the profile's language picker honest; do it before any further copy is
   added.
6. Slice 16 quality gates, then 17 product configuration. Item reordering and
   the library's offline write queue can be picked up alongside slice 14.

Decisions waiting on the product owner, not on code:

- **Text anchor navigation** (slice 10): needs the text body split into
  addressable blocks, which costs selection across block boundaries. Accept
  per-section selection, rely on paged mode instead, or find a third way.
- **Slice 5 screenshot comparison** at representative iPhone and iPad sizes
  needs a machine that can run the simulator.
- **`recompute_pd_status` on production.** The recommended shelf and the PD
  badge both gate on `pd_status=CONFIRMED`; on the dev database that count is
  0 of ~72k readable public-domain works, so the shelf is empty until the
  command runs. Do not loosen the gate.

## 1. Objective

Build a native Berynda application for iPhone and iPad that preserves the web
application's core logic while behaving like an iOS application rather than a
wrapped website.

The first production release must let a reader:

1. discover and search public works;
2. open a work and choose a specific edition;
3. see whether that edition has a readable file, without exposing the file
   format as a product choice;
4. read the edition with native page navigation and rights-aware actions;
5. sign in when a personal feature requires it;
6. resume reading, manage bibliography lists, and change profile/privacy
   settings; and
7. use the same flows on iPad through a real `NavigationSplitView`.

This plan covers the reader-facing app. Uploading, catalog editing, moderation,
partner administration, and other staff workflows remain web-only.

## 2. Non-negotiable product contracts

### 2.1 Edition and file ownership

- A work may have many editions.
- An edition may have several stored representations for preservation and the
  web reader.
- The catalog and work-detail UI show editions, not file formats.
- An edition row may say only whether a file is available and whether it can be
  read or downloaded under the effective rights policy.
- Mobile automatically chooses TXT/Markdown first, EPUB second, and PDF third.
- DJVU is unavailable in mobile applications and never selected as their
  `readable_file_id`.
- MIME type and rendering format are internal reader implementation details.
  They may select a renderer but must not appear as ePUB/PDF/TXT choices.
- The reader opens the preferred mobile file ID returned for the selected
  edition.

This policy is specific to native mobile clients. The web reader may continue
to build `mode_files` from sibling representations.

### 2.2 Authority boundaries

- Django remains authoritative for visibility, rights, search results, user
  identity, reading-history policy, and downloadable content.
- The iOS app never reconstructs rights decisions locally. It renders the
  `ReaderRights` response and defaults to deny when a permission is absent.
- Anonymous browsing and reading remain supported where the API allows them.
- Authentication is requested only when the user invokes a personal action.
- Ukrainian is the primary locale and the primary layout test. English is the
  second locale; additional locales can follow without restructuring views.
- No production data, sample counts, or invented API behavior may be copied
  from the HTML prototype.

### 2.3 Platform baseline

- SwiftUI application, iOS/iPadOS 17 or later.
- Swift concurrency for networking and repositories.
- No embedded web application and no cross-platform UI layer.
- `NavigationStack` on iPhone, `NavigationSplitView` on iPad.
- Portrait and landscape reader support; the general iPhone interface is
  portrait-first.
- String Catalog localization, Dynamic Type, VoiceOver, Reduce Motion, and
  high-contrast behavior are included from the first slice.

## 3. What to reuse from Lexykon

Reuse the proven shape, not Lexykon's dictionary domain code.

### Reuse

- Main app target plus a local Swift package (`BeryndaCore`).
- An actor-based API client with request IDs, language headers, bounded retry,
  and coalesced token refresh.
- An injected `AppEnvironment` that owns app-wide dependencies.
- Optional authentication and session-expired handling.
- iPhone `TabView` / iPad `NavigationSplitView` adaptation.
- Design-system tokens in dedicated files.
- Accessibility identifiers as a stable UI-test contract.
- Unit tests in the local package and Maestro/XCUITest smoke flows in CI.
- Deep-link routing as a pure, unit-tested component.
- Privacy manifest and explicit production/development configuration.

### Do not copy unchanged

- Lexykon API routes, models, captcha flows, dictionary cache, or removed tools.
- Lexykon bundle IDs, Keychain service names, associated domains, or signing
  configuration.
- Its UserDefaults token fallback in production. Berynda should use an
  injectable in-memory store for unsigned simulator tests and Keychain for
  real builds.
- Entry-centric full-screen presentation. Berynda navigates work → edition →
  full-screen reader.
- Any assumption that multiple file formats are choices within one edition.

## 4. Proposed repository structure

```text
Berynda.xcodeproj  # generated by XcodeGen
Berynda/
    BeryndaApp.swift
    AppEnvironment.swift
    ContentView.swift
    Configuration/
      AppConfiguration.swift
    DesignSystem/
      BeryndaColor.swift
      BeryndaFont.swift
      BeryndaLayout.swift
      BeryndaComponents.swift
    Features/
      Catalog/
      WorkDetail/
      Reader/
      Library/
      Profile/
      Auth/
    Resources/
      Assets.xcassets/
      Localizable.xcstrings
      PrivacyInfo.xcprivacy
    Services/
BeryndaCore/
    Package.swift
    Sources/BeryndaCore/
      API/
      Auth/
      Networking/
      Persistence/
      Repositories/
      Routing/
    Tests/BeryndaCoreTests/
      Fixtures/
BeryndaTests/
BeryndaUITests/
mobile-tests/flows/
README.md
```

`BeryndaCore` must have no SwiftUI dependency. Views depend on repository
protocols; URLSession, Keychain, and local persistence stay behind concrete
implementations.

## 5. Application architecture

### 5.1 Navigation

Three stable root destinations:

| Tab | iPhone | iPad |
| --- | --- | --- |
| Catalog | `NavigationStack` with discovery/search | Sidebar destination plus catalog and selected-work columns |
| Library | Continue reading, lists, saved collections | Sidebar destination with two-column library layout |
| Profile | Account, appearance, privacy, storage | Sidebar destination with grouped settings detail |

Work detail is pushed on iPhone and selected in the iPad detail column. The
reader is presented full-screen on both devices so navigation chrome cannot
compete with the document.

Supported deep links:

- `https://berynda.org/works/<slug>`
- `berynda://works/<slug>`
- `https://berynda.org/read/<file-id>` with an optional page or location value
- email-confirmation and password-reset links when the backend link format is
  finalized

### 5.2 State and dependencies

- `AppEnvironment`: API client, token store, repositories, network monitor,
  auth state, selected root tab, and pending deep link.
- Feature view models are `@MainActor` and expose explicit loading, loaded,
  empty, and error states.
- API and persistence implementations are actors where mutable shared state is
  involved.
- Avoid a global state library. Shared state is limited to authentication,
  settings, connectivity, and navigation.
- Cancellation follows view lifetime. Search tasks are cancelled when a new
  query replaces them.

### 5.3 Local persistence

Use a small repository-backed cache, not a second source of truth.

- Cache recently viewed works, edition summaries, public collections, and the
  last successful continue-reading response.
- Store appearance, language, and non-sensitive preferences in
  `UserDefaults`/`AppStorage`.
- Store access and refresh tokens only in Keychain.
- Store downloaded editions only after rights and offline behavior are in
  scope. Downloads must use file protection and be removed when access is
  revoked or the user requests deletion.
- Cache entries carry schema version, fetched-at time, and language. A cached
  Ukrainian response must not be reused for an English request.

## 6. API contract map

All routes are relative to `/api/v1/`.

| App capability | Endpoint | Authentication | Client behavior |
| --- | --- | --- | --- |
| Health/offline banner | `GET health/` | No | Poll only while offline; do not use as a data-health guarantee |
| Catalog list/search | `GET works/` | No | Debounced query, pagination, readable-only filter when requested |
| Cross-entity search | `GET search/cross/` | No | Optional people/publishers results; MVP work search may stay on `works/` |
| Work detail | `GET works/<slug-or-id>/` | No | Decode work metadata and rights summary |
| Work editions | `GET works/<work-id>/editions/` | No | Render edition rows; requires Phase 0 readable-file reference |
| Edition detail | `GET editions/<id>/` | No | Bibliographic metadata, no format choice |
| Public collections | `GET collections/` and `GET collections/<slug>/` | No | Discovery and saved-collection source |
| Reader bootstrap | `GET files/<file-id>/reader-info/` | Conditional | Select renderer internally, apply server-provided rights |
| Reader content | `GET files/<file-id>/reader-content/` | Conditional | Full-source delivery only when policy allows it |
| Page image/PDF | `GET files/<file-id>/pages/<n>/` or `<n>.pdf` | Conditional | On-demand page cache with prefetch window |
| Text layer | `GET files/<file-id>/pages/<n>/text-layer/` | Conditional | Post-MVP selection/search unless already cheap to support |
| Table of contents | `GET editions/<edition-id>/toc/` | No/conditional | Hierarchical navigation |
| Reading position | `GET/PUT files/<file-id>/reading-position/` | PUT requires login | Debounce saves; respect `recorded: false` |
| Continue reading | `GET auth/me/reading/` | Yes | Distinguish empty history from disabled history |
| Lists | `GET/POST lists/` | Yes | Personal library and bibliography lists |
| List items/bookmarks | `POST lists/<id>/items/` | Yes | Reader bookmarks use bibliography items; do not call removed bookmark endpoints |
| Saved collections | `GET auth/me/saved-collections/` | Yes | Display after login |
| Login/register | `POST auth/login/`, `POST auth/register/` | No | Store tokens in Keychain; registration may require email confirmation |
| Refresh/logout | `POST auth/token/refresh/`, `POST auth/logout/` | Refresh token / access token | Send refresh in JSON for native flow; store rotated pair atomically |
| Profile/privacy | `GET/PATCH auth/me/` | Yes | Includes `reading_history_enabled` privacy setting |

### Required Phase 0 API additions/changes

1. Add an edition-level mobile summary that provides:
   - `id`, display title, year, language, publisher, page count;
   - `readable_file_id` or `null`;
   - `can_read`, `can_download`, and an optional restriction reason; and
   - no user-facing format label.
2. Select the mobile file deterministically: TXT/Markdown, then EPUB, then PDF.
   Return no mobile-readable file when an edition contains only DJVU.
3. Keep sibling-file switching as a web-reader behavior. Native clients must
   ignore `mode_files` and open only the edition's preferred mobile file.
4. Add contract fixtures for work list, work detail, edition summary,
   reader-info for every delivery strategy, auth rotation, continue reading,
   and API errors.
5. Add an app-configuration endpoint or static signed configuration containing
   minimum supported build, latest build, App Store URL, and maintenance state.

## 7. Reader design

The reader is the highest-risk feature and must use the delivery strategy sent
by the API rather than guessing from file extensions.

### 7.1 Internal renderer routing

| Server response | Native implementation |
| --- | --- |
| `client_full` PDF | Download through an authorized URLSession task, open with PDFKit, discard or retain according to rights |
| `client_per_page` | Fetch a small page PDF on demand, render through PDFKit, cache a bounded page window |
| `server_pages` | Display server-rendered page images with native zoom/pan and bounded prefetch |
| EPUB | Use one audited EPUB renderer, isolated behind `DocumentRenderer`; do not expose the word EPUB in catalog UI |
| TXT/Markdown | Native attributed-text renderer with paged and scrolling modes |
| DJVU | Unsupported on mobile; the edition summary must not select it |

### 7.2 Reader behavior

- Single-page portrait view first; optional spread view on iPad/landscape.
- Page slider, previous/next, TOC, appearance, page labels, and resume position.
- Prefetch at most the adjacent two pages and cancel obsolete requests.
- Save authenticated reading position after a quiet interval, on background,
  and on reader dismissal. Never write history when the API returns
  `recorded: false`.
- Show download/share/copy/print only when the corresponding `rights` flag is
  true. Disabled actions explain `restriction_reason`.
- Reader memory is tested with large documents and repeated page turns; no
  unbounded `UIImage`, `PDFPage`, or response-data retention.
- App lifecycle transitions must not leave a partially written file presented
  as a completed offline download.

### 7.3 Deferred reader features

OCR search, selectable text overlays, annotations, TTS, autoplay, complex page
turn animation, and permanent offline downloads are post-MVP unless the base
reader is already stable and the release budget remains.

## 8. Security and privacy requirements

- ATS requires HTTPS for production. Local HTTP is a debug-only configuration.
- `API_BASE_URL` is build configuration, not a user-editable arbitrary host.
- Access and rotated refresh tokens use a Berynda-specific Keychain service
  with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` or stricter.
- Token writes are atomic from the app's perspective: never persist a new
  access token with an old refresh token after rotation.
- A refresh actor coalesces concurrent 401 responses into one refresh request.
- A 401 refresh failure clears the session; network and 5xx errors do not.
- Disable ambient cookie storage if the native body-token flow is used.
- Never log credentials, authorization headers, full private URLs, emails,
  document contents, or raw API bodies in production.
- Decode API errors into stable codes plus a request ID; user-visible text is
  localized and contains no server internals.
- All local download filenames are generated UUIDs. Server filenames are
  metadata, never paths.
- Validate MIME response, HTTP status, expected length where available, and
  safe storage destination before opening content.
- Rights are rechecked before a persisted download is opened after a material
  cache age.
- Reading history is opt-in according to the existing account default and can
  be disabled from Profile. Disabling it must remove or suppress local resume
  state as specified by the backend policy.
- Ship `PrivacyInfo.xcprivacy`; declare only APIs actually used.
- No analytics or advertising SDK in MVP. Add telemetry only after a separate
  data-minimization and consent decision.
- Universal links accept only allow-listed hosts and validated UUID/slug/page
  parameters.

Certificate pinning is not part of MVP because it adds a production outage
risk during certificate rotation. Reconsider only with a documented rotation
and recovery process.

## 9. Design implementation

The HTML prototype is the visual baseline, translated into native components.

Core tokens:

- paper background `#F4F3ED`;
- raised surface `#FFFDF8`;
- ink `#251F1D`;
- muted ink `#6B6660`;
- border `#D9D8CD`;
- oxblood accent `#95271D`;
- deep accent `#60241E`;
- dark background `#171312`;
- dark accent `#E77B49`.

Use semantic colors and asset-catalog variants rather than hardcoded values in
feature views. Large editorial titles use the approved serif; controls and
metadata use the system font unless a licensed bundled family is selected.

Every non-trivial control receives an accessibility identifier. Every screen
must pass:

- Dynamic Type through accessibility sizes;
- VoiceOver order and meaningful labels;
- 44-point minimum touch targets;
- light/dark and increased-contrast review;
- Reduce Motion behavior;
- Ukrainian long-label and narrow-screen review; and
- keyboard navigation on iPad where applicable.

## 10. Delivery phases

Each phase ends with working software and an explicit gate. Do not start the
next phase while the current gate is red.

### Phase 0 — Contract and project foundation (1 week)

Backend:

- Implement and test the mobile representation priority without deleting or
  reassigning existing files.
- Add the edition mobile summary/readable file reference.
- Preserve sibling-file behavior for the web while keeping it outside the
  native mobile contract.
- Freeze representative JSON fixtures and regenerate the OpenAPI schema.
- Add API tests proving anonymous visibility, authenticated rights, the unique
  edition-file invariant, and safe behavior when no file exists.

iOS foundation:

- Generate `Berynda.xcodeproj`, app target, `BeryndaCore`, test targets, and
  development/production configurations.
- Set the final bundle ID, deployment target, team placeholder, URL scheme,
  and associated-domain placeholders.
- Add CI on a macOS runner immediately; the Windows workspace cannot validate
  Xcode builds.

Gate:

- Backend contract tests pass.
- Mobile selection fixtures prove TXT/Markdown → EPUB → PDF and exclude DJVU.
- Empty SwiftUI shell builds and tests on a clean macOS CI runner.

### Phase 1 — Design system, networking, and app shell (1 week)

- Port Berynda tokens, typography, cover component, buttons, panels, loading,
  empty, error, and offline states.
- Implement iPhone tabs and iPad split navigation.
- Implement `BeryndaAPIClient` actor, typed requests, error mapping, language
  header, request ID, bounded 429/5xx retry, and cancellation.
- Implement network reachability and cached-content banner.
- Implement Keychain token store and refresh actor, but keep login UI behind a
  development route until Phase 4.
- Add deep-link router unit tests.

Gate:

- Shell matches the HTML prototype at representative iPhone and iPad sizes.
- API client fixture tests cover success, malformed JSON, 401 refresh,
  concurrent refresh, 403, 404, 429, 5xx, cancellation, and offline errors.
- No secrets or tokens appear in logs.

### Phase 2 — Catalog, search, work, and editions (1–2 weeks)

- Catalog discovery with featured collections and recommended readable works.
- Debounced work search, pagination, filters, empty/error/retry states, and
  request cancellation.
- Work detail with authors, metadata, rights summary, and edition list.
- Edition rows show year/language/publisher plus availability; no file format.
- Reader opens only from the edition's `readable_file_id`.
- Generated and uploaded covers share one stable native component.
- Work and collection deep links.

Gate:

- Anonymous launch → search → work → edition works on iPhone and iPad.
- A work with no editions, an edition with no file, a restricted file, and a
  removed work all degrade safely.
- Search and detail fixtures match the current API schema.

### Phase 3 — Core reader (2 weeks)

- Reader bootstrap and rights handling.
- PDF client-full, per-page, and server-page strategies.
- Native zoom/pan, page navigation, page labels, TOC, loading and retry.
- Reader position restore for authenticated users.
- Debounced position save with privacy-history handling.
- iPad landscape spread after single-page behavior is stable.
- Internal renderer abstraction ready for EPUB/text without exposing formats.

Gate:

- The same edition opens correctly under all three PDF delivery strategies.
- Resume survives app background/foreground and process restart.
- Rights-disabled actions cannot be invoked through UI or deep links.
- Memory and scrolling remain stable during a 200-page automated turn test.
- Reader works with VoiceOver and Reduce Motion.

### Phase 4 — Authentication, Library, and Profile (1–2 weeks)

- Optional login, registration, email-confirmation handoff, password reset,
  logout, and session-expired state.
- Continue Reading with disabled-history and empty-history distinctions.
- Bibliography lists, quick add, and reader-position bookmarks through list
  items.
- Saved public collections.
- Profile editing, language, appearance, reading-history privacy, local storage
  summary, and account actions.
- Login prompts return the user to the action that required authentication.

Gate:

- Anonymous reading remains functional.
- Login, refresh rotation, logout, and relaunch persistence pass.
- Turning reading history off suppresses remote and local resume behavior.
- Library changes reconcile after offline/retry without duplicate list items.

### Phase 5 — Additional documents and resilience (1–2 weeks)

- EPUB and TXT/Markdown renderers behind the common reader protocol.
- Background-safe document cache and bounded page prefetch.
- Offline catalog fallback for recently viewed material.
- Decide whether rights-compliant permanent downloads belong in v1.0 or v1.1.
- Polish split-view selection restoration and multitasking widths.
- Complete Ukrainian and English strings; pseudolocalization pass.

Gate:

- Renderer selection is invisible to catalog/work UI.
- Airplane-mode behavior is deterministic and explains what is cached.
- Storage eviction does not delete an open document or leave corrupt entries.
- No horizontal clipping in either supported locale.

### Phase 6 — Release hardening (1 week)

- App icon, launch screen, screenshots, description, support and privacy URLs.
- Privacy manifest review and App Store privacy answers.
- Unit, integration, UI, accessibility, performance, and memory gates in CI.
- TestFlight internal group, staged external group, crash-symbol upload, and
  release checklist.
- Minimum/latest-build configuration and forced-update screen.
- Universal-link association and production deep-link verification.
- Security review of auth storage, URL handling, document caching, logs, and
  rights gates.

Gate:

- Clean archive from CI with production configuration and no debug hosts.
- All critical Maestro/XCUITest journeys pass on the oldest and newest
  supported iOS versions, iPhone, and iPad.
- No unresolved critical/high security findings or accessibility blockers.
- Product owner signs off against the interactive HTML prototype.

## 11. Testing strategy

### Unit and contract tests

- JSON decoding for every API model, with missing optional fields and unknown
  enum values.
- API client retry, cancellation, auth refresh, and error-code mapping.
- Deep-link parsing and rejection of malicious or malformed routes.
- Reader navigation math, page-label mapping, prefetch bounds, and resume
  serialization.
- Repository cache expiry, language isolation, migrations, and corruption
  recovery.
- Rights action visibility and deny-by-default behavior.

### Integration tests

- URLProtocol-backed API flows in `BeryndaCoreTests`.
- Backend mobile-contract tests using the same fixture scenarios.
- One staging suite for login/refresh, work editions, reader-info, reading
  position, and bibliography list operations.

### UI smoke flows

Stable identifiers should cover at least:

- `tab_catalog`, `tab_library`, `tab_profile`;
- `catalog_search_field`, `catalog_result_primary`;
- `work_edition_<id>`, `edition_read_button`;
- `reader_previous`, `reader_next`, `reader_page_slider`, `reader_toc`;
- `library_continue_primary`, `library_list_<id>`;
- `profile_login_button`, auth fields, privacy-history toggle, and logout.

Required journeys:

1. launch anonymously and browse catalog;
2. search Ukrainian text and open an edition;
3. read, turn pages, close, and resume;
4. handle an edition without a file;
5. handle a rights-restricted file;
6. login and survive token rotation;
7. continue reading and add a reader bookmark to a list;
8. disable reading history;
9. switch theme and language; and
10. repeat catalog/work navigation on iPad split view.

## 12. CI and distribution

CI begins in Phase 0, not at release time.

- Pull requests run `swift test`, simulator build, app unit
  tests, and the fast UI smoke suite on macOS.
- Nightly builds run the full Maestro/XCUITest matrix and staging contract
  tests.
- Archive workflow uses manual signing credentials stored in repository
  secrets and never writes certificates/profiles into the checkout.
- Use TestFlight for product acceptance. Firebase App Distribution can be
  added only if the team already relies on it; it is not required for MVP.
- Release artifacts retain dSYMs and a mapping from build number to commit.

## 13. Scope explicitly deferred from v1.0

- Uploading or editing works/editions/files.
- Moderation, partner, author-claim, and administration surfaces.
- Full catalog mirroring for offline use.
- Annotations independent of bibliography list bookmarks.
- OCR full-text search inside scans.
- TTS, autoplay, widgets, share extensions, App Clips, and Handoff.
- Social login unless the product separately approves and configures it.
- User-selectable file format. The edition remains the selectable product
  object even if internal storage capabilities change later.

## 14. Schedule and staffing assumption

For one experienced iOS engineer with backend help available for Phase 0:

- reader-capable anonymous MVP: approximately 5–6 weeks;
- authenticated library and additional renderer support: another 2–3 weeks;
- release hardening: approximately 1 week.

Expected total: 8–10 weeks. A second engineer helps most by owning the Phase 0
API contract and reader fixtures, not by building a parallel UI architecture.

The estimate assumes access to a macOS CI runner and Apple signing assets in
the first week. Without those, work may continue locally but no phase can be
declared complete.

## 15. Definition of done for v1.0

The iOS app is complete when:

- catalog, search, work detail, edition selection, reader, Library, Profile,
  and optional auth work on supported iPhone and iPad devices;
- the edition-file invariant is enforced and format is absent from product UI;
- reader rights, reading-history privacy, and token rotation are correctly
  enforced;
- Ukrainian and English layouts pass accessibility and localization review;
- offline and server-error states are explicit and recoverable;
- all required CI and UI flows pass from a clean checkout;
- a production archive is accepted by TestFlight; and
- the product owner approves visual parity with the HTML prototype.
