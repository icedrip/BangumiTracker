import SwiftUI

// MARK: - Status Pills

struct StatusPillsSection: View {
    let selectedStatus: CollectionType?
    let subjectType: SubjectType?
    let onSelect: (CollectionType) -> Void

    var body: some View {
        DetailSectionCard {
            // `.frame(maxWidth: .infinity)` is applied at the HStack-child
            // level (outside the Button/buttonStyle(.plain) wrapper) so each
            // pill claims an equal share of the row regardless of which one
            // is selected. Putting it inside the Button label doesn't always
            // propagate up to the HStack's flex distribution — the selected
            // pill could end up sized to its intrinsic content while the
            // unselected siblings filled their slots.
            HStack(spacing: 8) {
                ForEach(CollectionType.allCases, id: \.rawValue) { type in
                    StatusPill(
                        label: type.displayName(for: subjectType),
                        isSelected: selectedStatus == type
                    ) {
                        onSelect(type)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct StatusPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.systemBackground))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.blue : Color(.separator),
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Progress

struct ProgressSection: View {
    let watchedEpisodeCount: Int
    let totalEpisodes: Int
    let onMarkNext: () -> Void

    // Derived from the two counts rather than forwarded from the parent —
    // ProgressRow does the same, so this keeps the two progress views
    // consistent. progressRatio is clamped to 1.0 so the percentage can't
    // show >100% when watched exceeds a stale subject.totalEpisodes fallback
    // (the episodes fetch can fail silently, leaving totalEpisodes stale).
    private var progressRatio: Double {
        guard totalEpisodes > 0 else { return 0 }
        return min(1, Double(watchedEpisodeCount) / Double(totalEpisodes))
    }

    private var isComplete: Bool {
        totalEpisodes > 0 && watchedEpisodeCount >= totalEpisodes
    }

    var body: some View {
        DetailSectionCard(spacing: 6) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("第 \(watchedEpisodeCount) 集 / 共 \(totalEpisodes) 集")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        if totalEpisodes > 0 {
                            Text("\(Int(progressRatio * 100))%")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(isComplete ? .green : .secondary)
                        }
                    }
                    ProgressView(value: progressRatio)
                        .tint(isComplete ? .green : .blue)
                }

                Button(action: onMarkNext) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(isComplete ? Color.green : Color.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isComplete)
            }
        }
    }
}

// MARK: - Book Progress (ep_status / vol_status)

struct BookProgressSection: View {
    let epStatus: Int
    let volStatus: Int
    let totalEps: Int
    let onAdjustEp: (Int) -> Void
    let onAdjustVol: (Int) -> Void

    var body: some View {
        DetailSectionCard(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("阅读进度")
                        .font(.system(size: 15, weight: .semibold))
                    Text("已读 \(epStatus) 话\(totalEps > 0 ? " / 共 \(totalEps) 话" : "")")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Stepper("\(epStatus)") { onAdjustEp(1) } onDecrement: { onAdjustEp(-1) }
                    .labelsHidden()
                    .accessibilityLabel("话数进度")
                    .accessibilityValue("\(epStatus) 话")
            }
            HStack {
                Text("卷数")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Stepper("\(volStatus)") { onAdjustVol(1) } onDecrement: { onAdjustVol(-1) }
                    .labelsHidden()
                    .accessibilityLabel("卷数进度")
                    .accessibilityValue("\(volStatus) 卷")
            }
        }
    }
}

// MARK: - Episodes

struct EpisodesSection: View {
    let episodes: [Episode]
    let watchedIds: Set<Int>
    let subjectType: SubjectType?
    let onToggle: (Int) -> Void
    let onMarkAll: () -> Void
    let onUnmarkAll: () -> Void

    var body: some View {
        DetailSectionCard(spacing: 10) {
            HStack {
                Text("逐集标记")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                batchButtons
            }

            let mainEpisodes = episodes.filter { $0.type == .main }
            if mainEpisodes.isEmpty {
                Text("暂无章节信息")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7),
                    spacing: 8
                ) {
                    ForEach(mainEpisodes) { episode in
                        CompactEpisodeButton(
                            episodeNumber: episode.episodeNumber ?? 0,
                            isWatched: watchedIds.contains(episode.id),
                            subjectType: subjectType
                        ) {
                            onToggle(episode.id)
                        }
                    }
                }
            }
        }
    }

    private var markAllLabel: String {
        let watched = CollectionType.watched.displayName(for: subjectType)  // "看过" / "玩过" / etc.
        return "全标\(watched)"
    }

    private var batchButtons: some View {
        HStack(spacing: 6) {
            Button(action: onMarkAll) {
                Text(markAllLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onUnmarkAll) {
                Text("全部取消")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Music Disc Track Listing (read-only)

/// Read-only disc-grouped track listing for music subjects. Music doesn't have
/// per-track marking — the section just shows track numbers and names grouped
/// by disc so the user can browse the album's content.
struct MusicDiscSections: View {
    let episodes: [Episode]

    @State private var expandedDiscs: Set<Int> = [1]

    /// Episodes grouped by disc, sorted by disc number, with tracks sorted
    /// by `sort` within each disc. Cached as a local let in `body` so the
    /// filter-group-sort pipeline runs once per render.
    private func buildDiscGroups() -> [(disc: Int, tracks: [Episode])] {
        let main = episodes.filter { $0.type == .main }
        let grouped = Dictionary(grouping: main) { $0.disc }
        return grouped
            .map { (disc: $0.key, tracks: $0.value.sorted { $0.sort < $1.sort }) }
            .sorted { $0.disc < $1.disc }
    }

    var body: some View {
        let discGroups = buildDiscGroups()

        if discGroups.isEmpty {
            DetailSectionCard {
                Text("暂无曲目信息")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        } else {
            VStack(spacing: 12) {
                ForEach(discGroups, id: \.disc) { group in
                    discSection(group)
                }
            }
        }
    }

    @ViewBuilder
    private func discSection(_ group: (disc: Int, tracks: [Episode])) -> some View {
        DetailSectionCard(spacing: 0) {
            DisclosureGroup(isExpanded: discExpandedBinding(group.disc)) {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.bottom, 8)

                    ForEach(Array(group.tracks.enumerated()), id: \.element.id) { item in
                        trackRow(track: item.element)
                        if item.offset < group.tracks.count - 1 {
                            Divider()
                        }
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Disc \(group.disc)")
                            .font(.system(size: 15, weight: .semibold))
                        Text("\(group.tracks.count) 曲")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func trackRow(track: Episode) -> some View {
        // Round sort (a Double) — truncation would misnumber fractional slots.
        let epNumber = Int(track.ep ?? track.sort.rounded())
        let trackNumber = String(format: "%02d", epNumber)
        let name = trackDisplayName(track)
        let duration = track.durationSeconds.map { $0 > 0 ? formatDuration($0) : "" } ?? ""

        HStack(spacing: 10) {
            Text(trackNumber)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)

            Text(name)
                .font(.system(size: 13))
                .foregroundColor(name.isEmpty ? .secondary : .primary)
                .lineLimit(1)

            Spacer()

            if !duration.isEmpty {
                Text(duration)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    /// Prefers `nameCn` over `name`; falls back to a placeholder when both
    /// are empty (shouldn't happen with real Bangumi data, but guards against
    /// missing fields).
    private func trackDisplayName(_ track: Episode) -> String {
        if !track.nameCn.isEmpty { return track.nameCn }
        if !track.name.isEmpty { return track.name }
        return "曲目 \(Int(track.ep ?? track.sort.rounded()))"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func discExpandedBinding(_ disc: Int) -> Binding<Bool> {
        Binding(
            get: { expandedDiscs.contains(disc) },
            set: { newValue in
                if newValue { expandedDiscs.insert(disc) }
                else { expandedDiscs.remove(disc) }
            }
        )
    }
}
