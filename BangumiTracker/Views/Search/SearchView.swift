import SwiftUI

struct SearchView: View {
    @Environment(SearchViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var manualIDText = ""
    @State private var manualIDLoading = false
    @State private var manualIDError: String?
    @State private var addSheetSubject: Subject?
    @State private var showClearHistoryConfirm = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            searchTabs
            resultsScrollView
        }
        .navigationBarHidden(true)
        .onAppear {
            isSearchFocused = true
            viewModel.loadHistory()
            // The cache may have been mutated by other tabs since init
            // (Home / Explore / Watching adds); re-seed so the "已收藏" marker
            // reflects the current collection state.
            viewModel.refreshCollectedSubjectIds()
        }
        .sheet(item: $addSheetSubject) { subject in
            AddToCollectionSheet(subject: subject) { payload in
                await viewModel.addCollection(subject: subject, payload: payload)
            }
        }
        .confirmationDialog(
            "清除全部搜索历史？",
            isPresented: $showClearHistoryConfirm,
            titleVisibility: .visible
        ) {
            Button("清除全部", role: .destructive) {
                viewModel.clearHistory()
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索作品、声优、导演...", text: $searchText)
                    .focused($isSearchFocused)
                    .font(.system(size: 16))
                    .submitLabel(.search)
                    .onSubmit(performSearch)
                    .onChange(of: searchText) { _, newValue in
                        onSearchTextChanged(newValue)
                    }
                if !searchText.isEmpty {
                    Button(action: clearSearch) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("清除搜索文字")
                }
            }
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("取消", action: cancelSearch)
                .font(.system(size: 16))
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    // MARK: - Search Tabs

    private var searchTabs: some View {
        HStack(spacing: 0) {
            ForEach(SearchTab.allCases, id: \.rawValue) { tab in
                Button(action: { selectTab(tab) }) {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(viewModel.selectedSearchTab == tab ? .blue : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(
                            Rectangle()
                                .fill(viewModel.selectedSearchTab == tab ? Color.blue : Color.clear)
                                .frame(height: 2),
                            alignment: .bottom
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Results

    private var resultsScrollView: some View {
        ScrollView {
            if searchText.isEmpty {
                historyContent
            } else if viewModel.isSearching {
                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonSearchRow(avatarShape: skeletonAvatarShape)
                    }
                }
                .padding(.top, 12)
            } else if let msg = viewModel.errorMessage, currentResultsEmpty {
                ErrorRetryView(message: msg) {
                    viewModel.searchImmediately()
                }
            } else {
                switch viewModel.selectedSearchTab {
                case .subject:
                    subjectResultsContent
                case .character:
                    characterResultsContent
                case .person:
                    personResultsContent
                }
            }
        }
    }

    private var currentResultsEmpty: Bool {
        switch viewModel.selectedSearchTab {
        case .subject: viewModel.searchResults.isEmpty
        case .character: viewModel.characterResults.isEmpty
        case .person: viewModel.personResults.isEmpty
        }
    }

    /// Match the skeleton's leading placeholder to the real row for the active
    /// tab so the loading → results swap doesn't reshape the avatar.
    private var skeletonAvatarShape: SkeletonSearchRow.AvatarShape {
        switch viewModel.selectedSearchTab {
        case .subject: .poster
        case .character, .person: .circle
        }
    }

    // MARK: - History

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.searchHistory.isEmpty {
                EmptyStateView(
                    icon: "clock",
                    title: "暂无搜索历史",
                    description: "在上方输入关键词开始搜索"
                )
            } else {
                SectionHeader(
                    title: "搜索历史",
                    trailingLabel: "清除全部"
                ) {
                    showClearHistoryConfirm = true
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                ForEach(viewModel.searchHistory) { history in
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                        Text(history.keyword)
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .onTapGesture { selectHistory(history.keyword) }
                }
            }
        }
    }

    // MARK: - Subject Results

    private var subjectResultsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.searchResults.isEmpty {
                Text("条目结果")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ForEach(viewModel.searchResults) { subject in
                    SearchResultRow(subject: subject, isCollected: viewModel.isCollected(subject.id)) {
                        Haptics.light()
                        Task { await viewModel.addToWishlist(subject) }
                    }
                }
            } else {
                noResultsView
            }

            ManualIDEntry(
                manualIDText: $manualIDText,
                isLoading: manualIDLoading,
                errorMessage: manualIDError
            ) { id in
                addManualID(id)
            }
        }
    }

    // MARK: - Character Results

    private var characterResultsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.characterResults.isEmpty {
                Text("角色结果")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ForEach(viewModel.characterResults) { character in
                    CharacterSearchRow(character: character)
                }
            } else {
                noResultsView
            }
        }
    }

    // MARK: - Person Results

    private var personResultsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.personResults.isEmpty {
                Text("人物结果")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ForEach(viewModel.personResults) { person in
                    PersonSearchRow(person: person)
                }
            } else {
                noResultsView
            }
        }
    }

    private var noResultsView: some View {
        Text("无相关结果")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    // MARK: - Actions

    private func performSearch() {
        viewModel.searchQuery = searchText
        viewModel.searchImmediately()
    }

    private func onSearchTextChanged(_ newValue: String) {
        viewModel.searchQuery = newValue
        if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
            viewModel.clearResults()
        } else {
            viewModel.debouncedSearch()
        }
    }

    private func clearSearch() {
        searchText = ""
        viewModel.searchQuery = ""
        viewModel.clearResults()
    }

    private func cancelSearch() {
        searchText = ""
        isSearchFocused = false
        dismiss()
    }

    private func selectTab(_ tab: SearchTab) {
        viewModel.selectedSearchTab = tab
        // History is per-tab — reload so the newly active tab's keywords show.
        viewModel.loadHistory()
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            viewModel.searchImmediately()
        }
    }

    private func selectHistory(_ keyword: String) {
        searchText = keyword
        viewModel.searchQuery = keyword
        viewModel.searchImmediately()
    }

    /// Manual ID/URL add: fetch the subject, then present the full add panel
    /// (PRD 5.2.11 manual-entry flow). A bad id / 404 surfaces inline under the
    /// input — the generic search error view only renders when there are no
    /// results, so a 404 with results on screen would otherwise be invisible.
    private func addManualID(_ id: Int) {
        Task {
            manualIDLoading = true
            manualIDError = nil
            defer { manualIDLoading = false }
            do {
                let subject = try await viewModel.fetchSubjectForAdd(id: id)
                addSheetSubject = subject
            } catch {
                manualIDError = error.localizedDescription
            }
        }
    }
}
