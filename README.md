# BangumiTracker / BanguMate

iOS app for tracking anime, film, and drama watching progress, powered by the [Bangumi (bgm.tv)](https://bgm.tv) API.

## Features

- **Browse & Explore** — Discover anime, books, music, games, and real-world subjects by category and season
- **Weekly Calendar** — See what's airing today
- **Collection Management** — Track your watching status, rate, comment, and mark episodes
- **Search** — Full-text search with filters for type, tag, and more
- **Characters & Staff** — Browse character details and staff info per subject
- **Offline Cache** — SwiftData-backed caching for subjects, collections, and search history
- **Widgets** — iOS widgets for quick access to your watching list and recommendations
- **OAuth** — Login with your Bangumi account via ASWebAuthenticationSession

## Requirements

- iOS 18.0+
- Xcode 16+
- Swift 6.0

## Getting Started

1. Clone the repository
2. Open `BangumiTracker.xcodeproj` in Xcode
3. (Optional) Copy `DevSecrets.swift.example` to `DevSecrets.swift` and add a dev access token for debug builds
4. Build and run on simulator or device

### One-time build

```bash
xcodebuild -project BangumiTracker.xcodeproj -scheme BangumiTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Architecture

```
View Layer         SwiftUI Views — pure declarations
ViewModel Layer    @Observable + @MainActor — business logic
Service Layer      BangumiAPIClient (actor) + LocalCacheService
Storage Layer      SwiftData + Keychain + @AppStorage
```

Built with MVVM, SwiftUI 5.0, and Swift 6 strict concurrency checking.

## Tech Stack

- Swift 6.0, SwiftUI 5.0, iOS 18.0 deployment target
- SwiftData for local caching
- Kingfisher for image loading and caching
- ASWebAuthenticationSession for OAuth 2.0
- Keychain for secure token storage

## Dependencies

- [Kingfisher](https://github.com/onevcat/Kingfisher) (≥8.0.0) — image caching via Swift Package Manager

All other functionality uses system frameworks only.

## License

MIT License — see [LICENSE](LICENSE).
