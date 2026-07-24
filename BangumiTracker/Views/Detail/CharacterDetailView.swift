import SwiftUI

struct CharacterDetailView: View {
    let characterId: Int
    @Environment(\.bangumiAPI) private var api

    @State private var detail: CharacterDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showFullImage = false

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 16) {
                    CharacterHeaderSection(detail: detail) {
                        showFullImage = true
                    }
                    if let summary = detail.summary, !summary.isEmpty {
                        SynopsisSection(summary: summary)
                    }
                    if let actors = detail.actors, !actors.isEmpty {
                        CharacterActorsSection(actors: actors)
                    }
                    if let infobox = detail.infobox, !infobox.isEmpty {
                        InfoboxSection(infobox: infobox)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
            } else if let error = errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "加载失败",
                    description: error,
                    actionLabel: "重试"
                ) {
                    Task { await loadDetail() }
                }
            }
        }
        .navigationTitle("角色详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
        .fullScreenCover(isPresented: $showFullImage) {
            FullScreenImageView(
                urlString: detail?.images?.large?.httpsScheme ?? detail?.images?.imageURL,
                title: detail?.displayName
            ) {
                showFullImage = false
            }
        }
    }

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        do {
            detail = try await api.fetchCharacterDetail(id: characterId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Header

private struct CharacterHeaderSection: View {
    let detail: CharacterDetail
    let onTapAvatar: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            CachedAsyncImage(
                urlString: detail.images?.imageURL,
                fallbackText: detail.displayName,
                targetSize: CGSize(width: 80, height: 80)
            )
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .contentShape(Circle())
                .onTapGesture(perform: onTapAvatar)

            VStack(alignment: .leading, spacing: 4) {
                Text(detail.displayName)
                    .font(.system(size: 20, weight: .bold))
                if detail.nameCn != detail.name, !detail.name.isEmpty {
                    Text(detail.name)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Actors

private struct CharacterActorsSection: View {
    let actors: [CharacterActor]

    var body: some View {
        DetailSectionCard(spacing: 10) {
            Text("声优")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)

            ForEach(actors, id: \.id) { actor in
                NavigationLink(value: AppRoute.personDetail(id: actor.id)) {
                    ActorRow(actor: actor)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ActorRow: View {
    let actor: CharacterActor

    var body: some View {
        HStack(spacing: 10) {
            CachedAsyncImage(
                urlString: actor.images?.imageURL,
                fallbackText: actor.name,
                targetSize: CGSize(width: 36, height: 36)
            )
                .frame(width: 36, height: 36)
                .clipShape(Circle())

            Text(actor.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Infobox

// Uses shared InfoboxSection from Components/
