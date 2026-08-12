# AGENTS.md

Instructions for ZCode agents working in this repository.

## Repository Purpose

iOS app (SwiftUI, MVVM) for tracking anime/film/drama watching progress, powered by the [Bangumi (bgm.tv)](https://bgm.tv) API. Real API integration, SwiftData caching, OAuth auth, iOS widgets.

**Read `CLAUDE.md` first** for deep architecture and API-gotcha detail — it is the authoritative project doc. `docs/PRD.md` has product requirements.

## Layout

- `BangumiTracker/` — app source. Subdirs: `Models/` (API DTOs + SwiftData `@Model` classes), `Services/` (API client, auth, cache), `ViewModels/`, `Views/` (tab roots + `Detail/`, `Components/`, etc.). Entry: `BangumiTrackerApp.swift` (DI bootstrap).
- `BangumiWidgets/` — iOS widget extension (own target, same scheme).
- `BangumiTrackerTests/` — unit tests (API client tests with `MockURLProtocol`, smoke tests).
- `function/` — standalone Node.js Tencent SCF cloud function for feedback (own `package.json` + tests, not part of the Xcode build).
- `website/` — static HTML landing page (not part of the app).
- `docs/` — PRD and engineering reports.

## Build / Test / Lint

```bash
# Build for simulator
xcodebuild -project BangumiTracker.xcodeproj -scheme BangumiTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run unit tests (repo root)
xcodebuild test -project BangumiTracker.xcodeproj -scheme BangumiTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BangumiTrackerTests

# Lint
swiftlint --strict
```

- CI (`.github/workflows/ci.yml`) runs build + tests + swiftlint on push/PR.
- `DevSecrets.swift` is gitignored (real tokens local-only); CI copies `DevSecrets.swift.example` — the example compiles with empty values.
- `function/`: `npm test` in that directory.

## Architecture & Conventions

Four layers: SwiftUI Views → `@Observable` `@MainActor` ViewModels → Service layer (`BangumiAPIClient` is an `actor`, `LocalCacheService` is `@MainActor` SwiftData CRUD) → Storage (SwiftData + `@AppStorage` + Keychain).

- Project-wide `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; `BangumiAPIClient` must remain an `actor` to escape it.
- Use `@Observable`, never `@StateObject`/`@ObservedObject`. ViewModels consume API DTOs (`Subject`, `UserSubjectCollection`), not SwiftData model types.
- DI: two-phase bootstrap in `BangumiTrackerApp.swift`; root injects services + ViewModels via `.environment()` and the API client via custom `EnvironmentKey`. `.sheet`/`.fullScreenCover` content does NOT inherit `@Observable` services on iOS 26.5 — re-inject via `.bangumiRootEnvironment(auth:api:)`.
- ViewModels that need cache (Home, Watching, Search) receive both `api` and `cache`; others (Explore, Profile) get only `api`. `CalendarViewModel`/`SubjectDetailViewModel` are created as `@State` in their views from `@Environment(\.bangumiAPI)`, not injected at root.
- Navigation: `AppRoute` enum in `ContentView.swift` defines 6 push destinations (`.subjectDetail(id:)`, `.characterDetail(id:)`, `.personDetail(id:)`, `.search`, `.calendar`, `.settings`); each tab's `NavigationStack` registers the same `.navigationDestination(for: AppRoute.self)`. Tab roots hide the nav bar and render `LargeNavHeader`; pushed detail screens hide the tab bar via `.toolbar(.hidden, for: .tabBar)`.
- State: `@State` = private transient UI state; `@Environment(ViewModelType.self)` = injected ViewModels; `@AppStorage` = preferences; `@Query` = SwiftData (reserved).
- New files under `BangumiTracker/` are picked up automatically (`fileSystemSynchronizedGroups`) — never edit `project.pbxproj` to add sources.
- All images go through `CachedAsyncImage` (Kingfisher wrapper); pass `targetSize` for downsampling (it multiplies by `displayScale` and bumps square frames 1.5×). Don't swap to `ResizingImageProcessor(.aspectFill)` (upscales small sources, memory bloat).
- OAuth: `ASWebAuthenticationSession`, tokens in Keychain. Authorize at `https://bgm.tv/oauth/authorize`, token at `https://bgm.tv/oauth/access_token`, API base `https://api.bgm.tv`. Bundle ids: `z.zy.BangumiTracker` (Release) / `z.zy.BangumiTracker.dev` (Debug); OAuth URL scheme `bangumitracker` shared by both.
- Optimistic updates: mutate state immediately → fire API in `Task` → roll back + set `errorMessage` on failure.
- Auth-gating: unauthenticated users never see collection UI; single login entry is `auth.presentLogin = true`.

## Gotchas

- SourceKit often reports stale "Cannot find 'X' in scope" for sibling-file symbols after edits — indexer lag, not real errors. Trust `xcodebuild` as source of truth.
- Local toolchain / simulator specifics (`xcode-select` → CommandLineTools, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, simctl install/launch, DerivedData path) are machine-specific — see `AGENTS.local.md` (not committed).
- Bangumi API: `User-Agent` header required on all requests; `-` username 404s on collection GETs (client caches `currentUsername` and substitutes); episode collections must be scoped by subject id; `fetchUserCollections` pages at limit=50 (use `fetchUserCollectionsCount(type:)` for totals).
- Bangumi enums: `SubjectType` 1=book, 2=anime, 3=music, 4=game, 6=real (no 5); `CollectionType` 1=wish, 2=watched, 3=watching, 4=onHold, 5=dropped; `EpisodeCollectionType` 0=none, 1=wish, 2=watched, 3=dropped. `ep_status`/`vol_status` apply only to books; `updated_at` is unreliable.
- `HomeViewModel`/`ProfileViewModel` seed first-paint state from `UserDefaults` JSON caches (`cache.home.*`, `cache.profile.*`) — don't remove or users see skeleton/flicker on cold start.
