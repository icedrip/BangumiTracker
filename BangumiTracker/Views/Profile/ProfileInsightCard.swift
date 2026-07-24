import SwiftUI

// MARK: - Viewing profile card

/// Renders the derived viewing-profile insights: rating tendency (your avg vs
/// the site's), subject-type distribution, air-date recency, and the genres of
/// what you're currently watching. All four come precomputed from the VM — the
/// card only formats them.
struct ProfileInsightCard: View {
    let insights: ProfileInsights
    let genres: [String]

    private var hasData: Bool { !insights.typeBreakdown.isEmpty }

    var body: some View {
        if hasData {
            VStack(alignment: .leading, spacing: 14) {
                ratingRow
                Divider()
                typeRow
                Divider()
                yearRow
                if !genres.isEmpty {
                    Divider()
                    genreRow
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        } else {
            Text("看完一些作品后，这里会生成你的观看画像")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
    }

    // MARK: Rows

    private var ratingRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            rowLabel("评分倾向")
            if insights.ratedCount > 0 {
                HStack(spacing: 16) {
                    scorePair(label: "你", score: insights.userAvgScore)
                    scorePair(label: "站内", score: insights.siteAvgScore)
                    Spacer()
                    verdictBadge
                }
            } else {
                Text("还没有评分数据")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var typeRow: some View {
        let total = insights.typeBreakdown.reduce(0) { $0 + $1.count }
        return VStack(alignment: .leading, spacing: 6) {
            rowLabel("类型分布")
            if total > 0 {
                HStack(spacing: 6) {
                    ForEach(insights.typeBreakdown.prefix(4)) { tc in
                        let pct = Int(Double(tc.count) / Double(total) * 100)
                        chip("\(SubjectType(rawValue: tc.type)?.displayName ?? "其他") \(pct)%")
                    }
                }
            } else {
                Text("暂无数据")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var yearRow: some View {
        let total = insights.recentCount + insights.olderCount
        return VStack(alignment: .leading, spacing: 6) {
            rowLabel("年代分布")
            if total > 0 {
                HStack(spacing: 6) {
                    yearChip("近三年", insights.recentCount, total, .blue)
                    yearChip("更早", insights.olderCount, total, .gray)
                }
            } else {
                Text("暂无数据")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var genreRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            rowLabel("在追流派")
            // FlowLayout wraps chips to the next row instead of squeezing them
            // into one HStack. .lineLimit(1) is applied here — not inside chip()
            // — so only the flow's children are forced single-line; typeRow's
            // chips (which still use HStack) keep wrapping to a 2nd line when
            // squeezed instead of truncating with ….
            FlowLayout(spacing: 6) {
                ForEach(genres.prefix(8), id: \.self) { tag in
                    chip(tag).lineLimit(1)
                }
            }
        }
    }

    // MARK: Pieces

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.secondary)
    }

    private func scorePair(label: String, score: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            // Dynamic text style (not a fixed 18pt) so the score scales with
            // Dynamic Type instead of truncating at larger accessibility sizes.
            Text(String(format: "%.1f", score))
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
        }
    }

    private var verdictBadge: some View {
        let delta = insights.userAvgScore - insights.siteAvgScore
        let text: String
        let color: Color
        if abs(delta) < 0.1 {
            text = "持平"
            color = .secondary
        } else {
            // Format the magnitude once; both branches add the sign explicitly so
            // the negative side doesn't render the auto-sign "严格 -0.5".
            let mag = String(format: "%.1f", abs(delta))
            if delta > 0 {
                text = "宽松 +\(mag)"
                color = .green
            } else {
                text = "严格 -\(mag)"
                color = .orange
            }
        }
        return Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
    }

    private func yearChip(_ label: String, _ count: Int, _ total: Int, _ color: Color) -> some View {
        let pct = Int(Double(count) / Double(total) * 100)
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(pct)%")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }
}
