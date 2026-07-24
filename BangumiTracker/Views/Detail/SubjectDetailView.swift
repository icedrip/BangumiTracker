import SwiftUI
import SwiftData

// MARK: - SubjectDetailView

struct SubjectDetailView: View {
    let subjectId: Int
    @State private var viewModel: SubjectDetailViewModel
    @Environment(AuthService.self) private var auth

    @AppStorage(PreferenceKey.scoreDisplay) private var scoreDisplay = ScoreDisplay.ten.rawValue
    @State private var showCommentEditor = false
    @State private var showTagEditor = false
    @State private var showFullCover = false
    @State private var commentDraft = ""
    @State private var tagDraft = ""

    init(subjectId: Int, api: BangumiAPIClient, modelContext: ModelContext) {
        self.subjectId = subjectId
        _viewModel = State(initialValue: SubjectDetailViewModel(
            api: api,
            cache: LocalCacheService(modelContext: modelContext)
        ))
    }

    var body: some View {
        ScrollView {
            if viewModel.subject != nil {
                VStack(spacing: 0) {
                    HeroSection(
                        imageURL: viewModel.subject?.imageURL,
                        displayName: viewModel.subject?.displayName ?? "",
                        metaText: metaText,
                        rating: viewModel.subject?.rating
                    ) {
                        showFullCover = true
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        if auth.isAuthenticated {
                            // Tracking surface — all of this writes to the user's
                            // collection, so it needs a login. Metadata sections
                            // (synopsis, tags, characters, persons, related) below
                            // stay browsable pre-login.
                            StatusPillsSection(
                                selectedStatus: viewModel.selectedStatus,
                                subjectType: viewModel.subjectType
                            ) { type in
                                Task { await viewModel.updateStatus(type) }
                            }

                            if let status = viewModel.selectedStatus, status != .wish {
                                ReviewSection(
                                    isFiveStar: isFiveStar,
                                    rating: displayRating,
                                    comment: viewModel.userComment,
                                    onRate: { newRating in
                                        Task { await viewModel.rate(isFiveStar ? newRating * 2 : newRating) }
                                    },
                                    onEditComment: openCommentEditor
                                )
                            }

                            if viewModel.isBook {
                                // Books track progress via ep_status/vol_status on the
                                // collection (no per-episode UI). Only meaningful once
                                // collected — before that the status pills collect it.
                                if viewModel.collection != nil {
                                    BookProgressSection(
                                        epStatus: viewModel.collection?.epStatus ?? 0,
                                        volStatus: viewModel.collection?.volStatus ?? 0,
                                        totalEps: viewModel.subject?.eps ?? 0
                                    ) { delta in
                                        Task { await viewModel.adjustBookProgress(.ep, by: delta) }
                                    } onAdjustVol: { delta in
                                        Task { await viewModel.adjustBookProgress(.vol, by: delta) }
                                    }
                                }
                            } else if viewModel.isMusic {
                                // Music uses disc-based grouping: each disc is a
                                // DisclosureGroup with a vertical track listing
                                // (number + name). Read-only — no per-track marking.
                                MusicDiscSections(
                                    episodes: viewModel.episodes
                                )
                            } else if viewModel.isGame {
                                // Games only need collection status + rating — the
                                // StatusPillsSection and ReviewSection above already
                                // cover everything. No per-episode grid or progress.
                                EmptyView()
                            } else {
                                ProgressSection(
                                    watchedEpisodeCount: viewModel.watchedEpisodeCount,
                                    totalEpisodes: viewModel.totalEpisodes
                                ) {
                                    Task { await viewModel.markNextEpisodeWatched() }
                                }

                                EpisodesSection(
                                    episodes: viewModel.episodes,
                                    watchedIds: viewModel.watchedEpisodeIds,
                                    subjectType: viewModel.subjectType,
                                    onToggle: { episodeId in
                                        Task { await viewModel.markEpisodeWatched(episodeId: episodeId) }
                                    },
                                    onMarkAll: { Task { await viewModel.markAllWatched() } },
                                    onUnmarkAll: { Task { await viewModel.unmarkAll() } }
                                )
                            }
                        } else {
                            LoginPromptCard(
                                icon: "person.crop.circle.badge.questionmark",
                                title: "登录后追踪你的观看进度",
                                description: "标记想看 / 在看、逐集打勾、评分评论、添加个人标签"
                            )
                        }

                        SynopsisSection(summary: viewModel.subject?.summary ?? "暂无简介")

                        TagsSection(tags: viewModel.subject?.metaTags ?? [])

                        if auth.isAuthenticated {
                            MyTagsSection(tags: viewModel.collection?.tags ?? [], onAddTag: openTagEditor)
                        }

                        if viewModel.hasCharacterData {
                            CharactersSection(characters: viewModel.characters)
                        }
                        if viewModel.hasPersonData {
                            PersonsSection(persons: viewModel.persons)
                        }
                        if viewModel.hasRelatedData {
                            RelatedSection(relatedSubjects: viewModel.relatedSubjects)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else if viewModel.isLoading {
                DetailSkeleton()
            } else if let error = viewModel.errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "加载失败",
                    description: error,
                    actionLabel: "重试"
                ) {
                    Task { await viewModel.loadSubject(id: subjectId) }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        // No horizontal safeAreaPadding on the ScrollView: the hero cover is a
        // direct child and must go edge-to-edge (full-bleed). Padded sections
        // below apply their own .padding(.horizontal, 16) — that lives inside
        // the safe area, so landscape notch inset still applies on top of it.
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("作品详情")
        // Keep the inline nav bar (back chevron + "作品详情") readable over the
        // immersive hero cover at any scroll position. The floating Tab Bar is
        // hidden for all pushed detail screens in ContentView.routeDestination.
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable { await viewModel.loadSubject(id: subjectId) }
        .errorToast($viewModel.actionError)
        .sheet(isPresented: $showCommentEditor) {
            CommentEditorSheet(commentDraft: $commentDraft, onSave: saveComment)
        }
        .sheet(isPresented: $showTagEditor) {
            TagEditorSheet(tagDraft: $tagDraft, onAdd: addTag)
        }
        .fullScreenCover(isPresented: $showFullCover) {
            FullScreenImageView(
                urlString: viewModel.subject?.images?.large?.httpsScheme ?? viewModel.subject?.imageURL,
                title: viewModel.subject?.displayName
            ) {
                showFullCover = false
            }
        }
        // Re-fire on auth flips so an in-place login via LoginPromptCard
        // immediately reloads collection/episode state — without this, the
        // tracking sections would render with the stale nil state from the
        // unauthenticated load until a manual pull-to-refresh. Mirrors
        // HomeView/WatchingView/ProfileView's .task(id: auth.isAuthenticated).
        .task(id: auth.isAuthenticated) { await viewModel.loadSubject(id: subjectId) }
    }

    // MARK: - Computed

    private var metaText: String {
        guard let subject = viewModel.subject else { return "" }
        var parts: [String] = []
        // Original name (only when it differs from the display title shown above).
        if subject.name != subject.displayName { parts.append(subject.name) }
        let typeName = SubjectType(rawValue: subject.type)?.displayName ?? ""
        if !typeName.isEmpty { parts.append(typeName) }
        if let date = subject.date, !date.isEmpty { parts.append(String(date.prefix(4))) }
        if !subject.platform.isEmpty { parts.append(subject.platform) }
        if subject.eps > 0 { parts.append("\(subject.eps) 话") }
        if subject.rank > 0 { parts.append("Rank #\(subject.rank)") }
        return parts.joined(separator: " · ")
    }

    private var isFiveStar: Bool { scoreDisplay == ScoreDisplay.fiveStar.rawValue }

    /// Display-scale rating derived from the ViewModel's 10-scale `userRating`
    /// (1-5 in 5-star mode, 1-10 otherwise). Single source of truth for both
    /// the star highlight and the score ring — avoids a `@State` mirror that
    /// flashed empty on first paint and could drift from the server value.
    private var displayRating: Int {
        isFiveStar ? (viewModel.userRating + 1) / 2 : viewModel.userRating
    }

    // MARK: - Actions

    private func openCommentEditor() {
        commentDraft = viewModel.userComment
        showCommentEditor = true
    }

    private func saveComment() {
        Task { await viewModel.updateComment(commentDraft) }
        showCommentEditor = false
    }

    private func openTagEditor() {
        tagDraft = ""
        showTagEditor = true
    }

    private func addTag() {
        let tag = tagDraft
        tagDraft = ""
        Task { await viewModel.addTag(tag) }
        showTagEditor = false
    }
}
