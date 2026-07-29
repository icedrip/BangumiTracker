import SwiftUI

struct PersonDetailView: View {
    let personId: Int
    @Environment(\.bangumiAPI) private var api

    @State private var detail: PersonDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showFullImage = false

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 16) {
                    PersonHeaderSection(detail: detail) {
                        showFullImage = true
                    }
                    if let summary = detail.summary, !summary.isEmpty {
                        SynopsisSection(summary: summary)
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
        .navigationTitle("人物详情")
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
            detail = try await api.fetchPersonDetail(id: personId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Header

private struct PersonHeaderSection: View {
    let detail: PersonDetail
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
                    .font(.title2.weight(.bold))
                if detail.nameCn != detail.name, !detail.name.isEmpty {
                    Text(detail.name)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                if !detail.careerText.isEmpty {
                    Text(detail.careerText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
}
