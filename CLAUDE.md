# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

iOS app for tracking anime/film/drama watching progress, powered by Bangumi (bgm.tv) API.

MVVM app (~35 Swift files, ~3500 LOC) with real Bangumi API integration, SwiftData caching, OAuth authentication, and iOS widgets.

## Project Structure

```
BangumiTracker.xcodeproj/
BangumiTracker/                          # all Swift source
├── BangumiTrackerApp.swift              # @main + AppRootView (DI bootstrap)
├── Models/                              # API DTOs + SwiftData @Model classes
│   ├── BangumiModels.swift              # enums (SubjectType, CollectionType, etc.)
│   ├── Subject.swift                    # Subject DTO + CachedSubject @Model
│   ├── Character.swift                  # Character / Person DTOs
│   ├── Episode.swift                    # Episode DTO
│   ├── UserCollection.swift             # UserSubjectCollection DTO + CachedUserCollection @Model
│   └── SearchHistory.swift              # @Model
├── Services/
│   ├── BangumiAPIClient.swift           # actor — all API methods
│   ├── AuthService.swift                # @Observable — OAuth via ASWebAuthenticationSession + Keychain
│   ├── LocalCacheService.swift          # @MainActor — SwiftData CRUD
│   ├── Environment+Dependencies.swift   # EnvironmentKey for BangumiAPIClient
│   ├── FeedbackService.swift            # In-app feedback
│   ├── Preferences.swift                # AppTheme, StartPage, ScoreDisplay enums + keys
│   ├── WidgetDataService.swift          # Shared data for widgets
│   └── WidgetSharedTypes.swift
├── ViewModels/                          # @MainActor @Observable final class
│   ├── HomeViewModel.swift              # api + cache
│   ├── ExploreViewModel.swift           # api only
│   ├── WatchingViewModel.swift          # api + cache
│   ├── ProfileViewModel.swift           # api only
│   ├── SubjectDetailViewModel.swift     # api only
│   ├── SearchViewModel.swift            # api + cache (search history)
│   └── CalendarViewModel.swift          # api only
└── Views/
    ├── ContentView.swift                # TabView + AppRoute enum + NavigationStack×4
    ├── Components/                      # LargeNavHeader, SubjectCard, CachedAsyncImage, etc.
    ├── Home/HomeView.swift
    ├── Explore/ExploreView.swift, BrowseView.swift
    ├── Watching/WatchingView.swift
    ├── Profile/ProfileView.swift, ProfileInsightCard.swift
    ├── Detail/                          # SubjectDetailView + section files + CharacterDetailView + PersonDetailView
    ├── Search/SearchView.swift, SearchResultRows.swift
    ├── Calendar/CalendarView.swift
    └── Settings/SettingsView.swift, LoginView.swift, FeedbackView.swift, LicenseView.swift
BangumiWidgets/                          # iOS widgets
```

## Tech Stack

- Swift 6.0 + SwiftUI 5.0, iOS 18.0 deployment target
- MVVM + `@Observable` (not `@StateObject`/`@ObservedObject`)
- Project-wide `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — ViewModels don't need explicit `@MainActor` but have it for clarity; `BangumiAPIClient` must be `actor` to escape it
- Navigation: `AppRoute` enum + `.navigationDestination(for: AppRoute.self)` on each tab's `NavigationStack`
- SwiftData for local caching; `@AppStorage` for preferences; Keychain for OAuth tokens
- `ASWebAuthenticationSession` for OAuth 2.0
- Xcode project uses `objectVersion = 77` with `fileSystemSynchronizedGroups` — new files added under `BangumiTracker/` are picked up automatically, no need to edit `project.pbxproj`
- Kingfisher (SPM, ≥8.0.0) is the only third-party dependency, used for image caching — three tiers (memory raw / memory decoded / disk). Cache limits and expiration are configured in `BangumiTrackerApp.init`. All image rendering goes through `CachedAsyncImage` (wraps `KFImage`); pass `targetSize` (in points) for `DownsamplingImageProcessor` to keep decoded memory in check. `CachedAsyncImage` multiplies `targetSize` by `@Environment(\.displayScale)` (Kingfisher's `scaleFactor` defaults to 1.0) and bumps square frames by 1.5× so a portrait source's short side covers the frame after `.fill` — don't switch to `ResizingImageProcessor(.aspectFill)`, it upscales small sources at decode (memory bloat on the hero).

## Key Commands

```bash
# Build (adjust simulator name to match installed runtimes)
xcodebuild -project BangumiTracker.xcodeproj -scheme BangumiTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Open in Xcode
open BangumiTracker.xcodeproj
```

There is no test target — `xcodebuild test` will fail. Don't propose test commands until one is added.

After editing Swift files, SourceKit frequently reports stale "Cannot find 'X' in scope" diagnostics for symbols defined in sibling files. These are indexer lag, not real errors — trust `xcodebuild` (or `BUILD SUCCEEDED`) as the source of truth.

### Running on simulator without Xcode IDE

If `xcrun` errors with "unable to find utility 'simctl'", `xcode-select` is pointing at CommandLineTools, not Xcode.app. Either run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, or prefix one-off commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

```bash
# Install + launch on a booted simulator
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install <udid> BangumiTracker.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch <udid> z.zy.BangumiTracker  # Release
# Debug build: z.zy.BangumiTracker.dev

# Bundle id: z.zy.BangumiTracker (Release) / z.zy.BangumiTracker.dev (Debug)
# App display name: BanguMate (Release) / BanguMate β (Debug)
# OAuth URL scheme: `bangumitracker` — shared by Debug and Release

# Tail unified logs from the app (use OSLog/Logger)
xcrun simctl spawn <udid> log show --last 3m \
  --predicate 'subsystem == "z.zy.BangumiTracker"' --style compact

# DerivedData path (verified):
# ~/Library/Developer/Xcode/DerivedData/BangumiTracker-flmvctmmdyeyopeiawormfdmxyuj/
```

## Architecture

Four layers:

```
View Layer         SwiftUI Views, pure declaration
ViewModel Layer    @Observable + @MainActor, calls Service layer
Service Layer      BangumiAPIClient (actor) + LocalCacheService (@MainActor)
Storage Layer      SwiftData (ModelContainer) + @AppStorage + Keychain
```

### DI Bootstrap Pattern

Two-phase in `BangumiTrackerApp.swift`:

1. `BangumiTrackerApp` owns the `BangumiAPIClient` actor, `AuthService`, registers `.modelContainer(for:)`
2. `AppRootView` reads `@Environment(\.modelContext)`, creates `LocalCacheService`, then injects AuthService + 5 ViewModels via `.environment()` plus `BangumiAPIClient` via custom `EnvironmentKey`
3. On launch, loads OAuth token from Keychain (or DEV fallback token in DEBUG) and sets it on the API client

`DevSecrets.swift` is a gitignored file (template at `DevSecrets.swift.example`) that holds the development access token. Release builds ignore it entirely.

ViewModels needing cache (Home, Watching, Search) receive both `api` and `cache`. Others (Explore, Profile) receive only `api`. CalendarViewModel and SubjectDetailViewModel are created as `@State` in their views from `@Environment(\.bangumiAPI)` — not injected at root.

### Navigation

`AppRoute` enum in `ContentView.swift` defines 6 push destinations: `.subjectDetail(id:)`, `.characterDetail(id:)`, `.personDetail(id:)`, `.search`, `.calendar`, `.settings`. Each tab's `NavigationStack` registers the same `.navigationDestination(for: AppRoute.self)` handler.

The four tab roots hide the system nav bar (`.toolbar(.hidden, for: .navigationBar)`) and render `LargeNavHeader` instead. Pushed detail screens hide the floating TabBar via `.toolbar(.hidden, for: .tabBar)`. `SubjectDetailView`'s hero cover is full-bleed (no `.safeAreaPadding(.horizontal)` on the `ScrollView`); padded sections use `.padding(.horizontal, 16)`. The inline nav bar uses `.toolbarBackground(.visible, for: .navigationBar)`.

### State Management Rules

- `@State` — private transient UI state only
- `@Environment(ViewModelType.self)` — injected ViewModels
- `@AppStorage` — simple preferences
- `@Query` — SwiftData fetches (reserved for future)
- ViewModels use API DTO types (`Subject`, `UserSubjectCollection`), not SwiftData model types
- `.sheet` / `.fullScreenCover` content does NOT reliably inherit `@Observable` services from the presenting view (iOS 26.5). Root-presented sheets must re-inject via `.bangumiRootEnvironment(auth:api:)`. `@Environment(\.bangumiAPI)` won't trap (has `defaultValue`) but binds a tokenless client — re-inject it too.

### Optimistic Update Pattern

Mutate `@Observable` state immediately → fire API in `Task` → on failure, roll back + set `errorMessage`.

### Auth-gating collection UI

Unauthenticated users never see collection-interaction UI. The single login entry point is `auth.presentLogin = true`, bound to a root `LoginView` sheet. `SubjectCard.statusButton`, `SubjectDetailView` tracking surface, and `WatchingView` content are gated on `auth.isAuthenticated` via `@Environment(AuthService.self)`.

## Bangumi API

- Base URL: `https://api.bgm.tv`
- OAuth 2.0: authorize at `https://bgm.tv/oauth/authorize`, token at `https://bgm.tv/oauth/access_token`
- Auth header: `Authorization: Bearer {token}`
- **User-Agent header is required** on all requests
- API docs: `https://bangumi.github.io/api`

### Key types

- `SubjectType`: 1=book, 2=anime, 3=music, 4=game, 6=real (no 5)
- `CollectionType`: 1=wish, 2=watched, 3=watching, 4=onHold, 5=dropped
- `EpisodeCollectionType`: 0=none, 1=wish, 2=watched, 3=dropped

`ep_status`/`vol_status` only apply to books. Anime/real use per-episode collections. `updated_at` is unreliable.

### API Gotchas

- **`-` username fails for collection GETs** — `/v0/users/-/collections` and `/v0/users/-/collections/{subject_id}` return 404 with `-`. `BangumiAPIClient` caches `currentUsername` (populated via `/v0/me`, cleared on `setToken`) and auto-substitutes it for reads.
- **Episode collection list must be scoped by subject**: `/v0/users/-/collections/{subject_id}/episodes`, not the query-param form.
- **`sort` in search**: `match` (default), `rank`, `score`, `heat`. Use `heat` for trends-like ordering.
- **`loadSubject` clears user state at entry** — `collection`, `episodeCollections`, `selectedStatus`, `userRating`, `userComment`. Don't remove.
- **`fetchUserCollections` is paged at limit=50** — use `fetchUserCollectionsCount(type:)` for accurate totals (reads `total` from a `limit=1` response).

### View-side caches for first-paint

`HomeViewModel` and `ProfileViewModel` seed state from `UserDefaults` (JSON-encoded DTOs) at init, then refresh from network. Cache keys: `cache.home.*`, `cache.profile.*`. Skip this and the user sees skeleton/flicker on cold start.
