import SwiftUI

struct CalendarView: View {
    @Environment(\.bangumiAPI) private var api
    @Environment(WatchingViewModel.self) private var watching
    @State private var viewModel: CalendarViewModel?
    @State private var showOnlyFollowing = false
    // Expand/collapse (PRD 5.2.4): nil = all collapsed; a weekday id = that
    // day's list is expanded. Defaults to today so something shows on entry.
    @State private var expandedWeekday: Int? = CalendarView.todayWeekdayId()

    private static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        // Build the followed-subject id set once per render and thread it
        // through the weekday counts, the day list, and each row's progress
        // lookup — otherwise filteredCount rebuilds it 7× per render and
        // followingProgress does an O(N) scan per row.
        let watchingIds = watchingSubjectIds
        return ScrollView {
            VStack(spacing: 16) {
                if let vm = viewModel {
                    if let msg = vm.errorMessage, vm.days.isEmpty {
                        ErrorRetryView(message: msg) {
                            Task { await vm.load() }
                        }
                    } else {
                        headerControls
                        weekdaySelector(vm: vm, watchingIds: watchingIds)
                        if let expanded = expandedWeekday {
                            dayContent(vm: vm, watchingIds: watchingIds, weekdayId: expanded)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle("开播日历")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel?.load()
        }
        .task {
            if viewModel == nil {
                viewModel = CalendarViewModel(api: api)
                await viewModel?.load()
            }
            // The watching list is SwiftData-seeded in WatchingViewModel.init,
            // so the "仅看我在追的" filter renders without a refetch. What's
            // missing on a cold session is the per-subject episode progress
            // (in-memory only) — so only pull the Watching tab's full load once,
            // when that progress is empty. Repeat visits reuse what's already in
            // memory instead of re-bursting N concurrent episode-collection
            // fetches every time Calendar is pushed.
            if watching.episodeProgress.isEmpty {
                await watching.loadAll()
            }
        }
    }

    private var watchingSubjectIds: Set<Int> {
        showOnlyFollowing ? Set(watching.watchingList.map(\.subjectId)) : []
    }

    private var headerControls: some View {
        HStack(spacing: 8) {
            Spacer()
            Text("仅看我在追的")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Toggle("", isOn: $showOnlyFollowing)
                .labelsHidden()
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 16)
    }

    private func weekdaySelector(vm: CalendarViewModel, watchingIds: Set<Int>) -> some View {
        HStack(spacing: 0) {
            ForEach(1...7, id: \.self) { weekdayId in
                let count = filteredCount(vm: vm, weekdayId: weekdayId, watchingIds: watchingIds)
                let isExpanded = expandedWeekday == weekdayId
                let isToday = weekdayId == Self.todayWeekdayId()
                Button {
                    // Tap toggles: expand a collapsed day, collapse an expanded one.
                    expandedWeekday = isExpanded ? nil : weekdayId
                } label: {
                    VStack(spacing: 4) {
                        Text(Self.weekdayLabels[weekdayId - 1])
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fontWeight(.semibold)
                        Text("\(dateNumber(for: weekdayId))")
                            .font(.system(size: 15, weight: isExpanded ? .bold : .medium))
                            .foregroundColor(isExpanded ? .white : (isToday ? .blue : .primary))
                            .frame(width: 36, height: 36)
                            .background(isExpanded ? Color.blue : Color.clear)
                            .clipShape(Circle())
                        // Dot marks days with updates (PRD 5.2.4 calendar legend).
                        Circle()
                            .fill(count > 0 ? Color.blue : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .padding(.horizontal, 16)
    }

    private func dayContent(vm: CalendarViewModel, watchingIds: Set<Int>, weekdayId: Int) -> some View {
        let items = filteredDayItems(vm: vm, weekdayId: weekdayId, watchingIds: watchingIds)
        return VStack(alignment: .leading, spacing: 8) {
            Text(weekdayTitle(weekdayId))
                .font(.system(size: 20, weight: .bold, design: .default))
                .padding(.horizontal, 16)

            if items.isEmpty {
                Text(emptyStateText(for: weekdayId))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(items, id: \.id) { slim in
                        calendarEventRow(slim: slim, watchingIds: watchingIds)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func filteredCount(vm: CalendarViewModel, weekdayId: Int, watchingIds: Set<Int>) -> Int {
        filteredDayItems(vm: vm, weekdayId: weekdayId, watchingIds: watchingIds).count
    }

    private func filteredDayItems(vm: CalendarViewModel, weekdayId: Int, watchingIds: Set<Int>) -> [SlimSubject] {
        let items = vm.items(for: weekdayId)
        guard showOnlyFollowing else { return items }
        return items.filter { watchingIds.contains($0.id) }
    }

    private func emptyStateText(for weekdayId: Int) -> String {
        let dayWord = weekdayId == Self.todayWeekdayId() ? "今日" : "该日"
        return showOnlyFollowing ? "在追的作品中\(dayWord)无更新" : "\(dayWord)无更新"
    }

    private func calendarEventRow(slim: SlimSubject, watchingIds: Set<Int>) -> some View {
        NavigationLink(value: AppRoute.subjectDetail(id: slim.id)) {
            HStack(spacing: 10) {
                CachedAsyncImage(
                    urlString: slim.imageURL,
                    fallbackText: slim.displayName,
                    targetSize: CGSize(width: 48, height: 67)
                )
                    .frame(width: 48, height: 67)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(slim.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text("\(slim.date ?? "") · \(SubjectType(rawValue: slim.type)?.displayName ?? "")")
                        if let rating = slim.rating, rating.score > 0 {
                            Text("·")
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                Text(String(format: "%.1f", rating.score))
                            }
                            .foregroundColor(.orange)
                        }
                        if slim.rank > 0 {
                            Text("·")
                            Text("#\(slim.rank)")
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                    if let progress = followingProgress(for: slim.id, type: slim.type, watchingIds: watchingIds) {
                        HStack(spacing: 4) {
                            ProgressView(value: progress.fraction)
                                .tint(progress.fraction >= 1.0 ? .green : .blue)
                                .frame(maxWidth: 120)
                            Text(progress.text)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    /// Episode progress for a subject the user is watching, or nil when the
    /// subject isn't in the watching list (e.g. filter is off). `watchingIds`
    /// is the precomputed followed-id set from `body` so this is an O(1) lookup
    /// instead of a per-row linear scan.
    private func followingProgress(for subjectId: Int, type: Int, watchingIds: Set<Int>) -> (fraction: Double, text: String)? {
        guard showOnlyFollowing, watchingIds.contains(subjectId) else {
            return nil
        }
        let progress = watching.progress(for: subjectId)
        guard progress.total > 0 else {
            return (0, "暂无集数")
        }
        let fraction = Double(progress.watched) / Double(progress.total)
        let isComplete = progress.watched >= progress.total
        let st = SubjectType(rawValue: type)
        let text = isComplete ? "\(progress.watched)/\(progress.total) 已\(st?.completionForm ?? "看完")" : "\(progress.watched)/\(progress.total)"
        return (fraction, text)
    }

    private func weekdayTitle(_ weekday: Int) -> String {
        let labels = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        return weekday >= 1 && weekday <= 7 ? labels[weekday] : ""
    }

    /// Day-of-month for a weekday, relative to today (the calendar payload is
    /// the current week, grouped by weekday — no explicit dates, so derive them).
    private func dateNumber(for weekdayId: Int) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let today = Date()
        let offset = weekdayId - Self.todayWeekdayId()
        let date = cal.date(byAdding: .day, value: offset, to: today) ?? today
        return cal.component(.day, from: date)
    }

    private static func todayWeekdayId() -> Int {
        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: Date())
        return weekday == 1 ? 7 : weekday - 1
    }
}
