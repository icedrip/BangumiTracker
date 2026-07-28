import SwiftUI

/// Parameters for a pushed browse page (PRD F3.3). `type == nil` means all
/// types; `year`/`month` narrow to a season. All variants map onto
/// `fetchSubjects(type:year:month:sort:)`.
struct BrowseConfig: Hashable {
    let title: String
    let type: Int?
    let year: Int?
    let month: Int?
    let sort: String
}

@MainActor
@Observable
final class BrowseViewModel {
    var subjects: [Subject] = []
    var isLoading = false
    var errorMessage: String?

    private let api: BangumiAPIClient
    let config: BrowseConfig

    init(api: BangumiAPIClient, config: BrowseConfig) {
        self.api = api
        self.config = config
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            subjects = try await api.fetchSubjects(
                type: config.type,
                year: config.year,
                month: config.month,
                sort: config.sort
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct BrowseView: View {
    let config: BrowseConfig
    @Environment(ExploreViewModel.self) private var exploreVM
    @State private var vm: BrowseViewModel

    init(config: BrowseConfig, api: BangumiAPIClient) {
        self.config = config
        _vm = State(initialValue: BrowseViewModel(api: api, config: config))
    }

    var body: some View {
        @Bindable var exploreBindable = exploreVM
        ScrollView {
            content
        }
        .navigationTitle(config.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .errorToast($exploreBindable.actionError)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.subjects.isEmpty {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in SkeletonCard(flexibleWidth: true) }
            }
            .padding(16)
        } else if vm.subjects.isEmpty {
            if let msg = vm.errorMessage {
                ErrorRetryView(message: msg) {
                    Task { await vm.load() }
                }
            } else {
                EmptyStateView(
                    icon: "square.grid",
                    title: "暂无作品",
                    description: "没有符合条件的作品"
                )
                .padding(.top, 40)
            }
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(vm.subjects) { subject in
                    SubjectCard(
                        subject: subject,
                        collectionType: exploreVM.collectionType(for: subject.id),
                        flexibleWidth: true
                    ) {
                        Task { await exploreVM.addToWishlist(subject) }
                    }
                }
            }
            .padding(16)
        }
    }

    private var columns: [GridItem] {
        // Two equal-width flexible columns so each card fills its cell. The old
        // `.adaptive(minimum: 140)` handed a ~174pt cell to a fixed 140pt card,
        // which centered and left a ~46pt dead strip down the middle of every
        // row. Mirrors the WatchingView grid fix; cards pass `flexibleWidth: true`.
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }
}
