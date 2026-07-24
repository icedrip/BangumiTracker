import SwiftUI
import SwiftData

enum AppRoute: Hashable {
    case subjectDetail(id: Int)
    case characterDetail(id: Int)
    case personDetail(id: Int)
    case search
    case calendar
    case settings
    case license
    case browse(BrowseConfig)
}

struct ContentView: View {
    @Environment(\.bangumiAPI) private var api
    @Environment(\.modelContext) private var modelContext

    @AppStorage(PreferenceKey.startPage) private var startPage = StartPage.home.rawValue
    @State private var selectedTab: Int = {
        switch StartPage(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.startPage) ?? "") ?? .home {
        case .home: 0
        case .discover: 1
        case .watching: 2
        }
    }()
    @State private var homeNavPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $homeNavPath) {
                HomeView()
                    .navigationDestination(for: AppRoute.self) { route in
                        routeDestination(route)
                    }
            }
            .tabItem {
                Label("首页", systemImage: "square.grid.2x2")
            }
            .tag(0)

            NavigationStack {
                ExploreView()
                    .navigationDestination(for: AppRoute.self) { route in
                        routeDestination(route)
                    }
            }
            .tabItem {
                Label("发现", systemImage: "magnifyingglass")
            }
            .tag(1)

            NavigationStack {
                WatchingView()
                    .navigationDestination(for: AppRoute.self) { route in
                        routeDestination(route)
                    }
            }
            .tabItem {
                Label("在看", systemImage: "play.rectangle")
            }
            .tag(2)

            NavigationStack {
                ProfileView()
                    .navigationDestination(for: AppRoute.self) { route in
                        routeDestination(route)
                    }
            }
            .tabItem {
                Label("我的", systemImage: "person.circle")
            }
            .tag(3)
        }
        .environment(\.tabSelection, $selectedTab)
        .onReceive(NotificationCenter.default.publisher(for: .widgetOpenSubject)) { note in
            guard let subjectId = note.userInfo?["subjectId"] as? Int else { return }
            selectedTab = 0
            homeNavPath.append(AppRoute.subjectDetail(id: subjectId))
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: AppRoute) -> some View {
        // iOS 26's floating Tab Bar overlaps the bottom of scroll content on
        // pushed detail screens — hide it for the immersive detail destinations
        // so the last section stays readable. List/util screens (search,
        // calendar, settings, browse) keep the tab bar for in-context switching.
        switch route {
        case .subjectDetail(let id):
            SubjectDetailView(subjectId: id, api: api, modelContext: modelContext)
                .toolbar(.hidden, for: .tabBar)
        case .characterDetail(let id):
            CharacterDetailView(characterId: id)
                .toolbar(.hidden, for: .tabBar)
        case .personDetail(let id):
            PersonDetailView(personId: id)
                .toolbar(.hidden, for: .tabBar)
        case .search:
            SearchView()
        case .calendar:
            CalendarView()
        case .settings:
            SettingsView()
        case .license:
            LicenseView()
        case .browse(let config):
            BrowseView(config: config, api: api)
        }
    }
}
