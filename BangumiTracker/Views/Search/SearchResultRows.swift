import SwiftUI

// MARK: - Manual ID Entry

struct ManualIDEntry: View {
    @Binding var manualIDText: String
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var onAdd: ((Int) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("或直接输入 Bangumi 条目 ID / URL")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                TextField("条目ID 或 URL", text: $manualIDText)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.subheadline)
                    .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separator), lineWidth: 1)
                    )

                Button {
                    if let id = parsedSubjectId { onAdd?(id) }
                } label: {
                    Text(isLoading ? "查找中…" : "添加")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, .tightSpacing)
                        .background(parsedSubjectId == nil ? Color.gray : Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(parsedSubjectId == nil || isLoading)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .padding(16)
    }

    private var parsedSubjectId: Int? {
        let trimmed = manualIDText.trimmingCharacters(in: .whitespaces)
        if let id = Int(trimmed) { return id }
        if let match = trimmed.range(of: #"subject/(\d+)"#, options: .regularExpression) {
            let s = trimmed[match]
            if let idStr = s.split(separator: "/").last, let id = Int(idStr) { return id }
        }
        return nil
    }
}

// MARK: - Search Result Rows

struct SearchResultRow: View {
    let subject: Subject
    var isCollected: Bool = false
    var onQuickAdd: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink(value: AppRoute.subjectDetail(id: subject.id)) {
                HStack(spacing: 10) {
                    CachedAsyncImage(
                        urlString: subject.imageURL,
                        fallbackText: subject.displayName,
                        targetSize: CGSize(width: 44, height: 62)
                    )
                        .frame(width: 44, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(subject.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                        Text(metaText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let rating = subject.rating, rating.score > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                Text(String(format: "%.1f", rating.score))
                            }
                            .foregroundColor(.orange)
                            .font(.caption.weight(.semibold))
                        }
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isCollected {
                Text("已收藏")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            } else if let onQuickAdd {
                Button(action: onQuickAdd) {
                    Text("+ \(CollectionType.wish.displayName(for: SubjectType(rawValue: subject.type)))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, .horizontalPadding)
        .padding(.vertical, 10)
    }

    private var metaText: String {
        let typeName = SubjectType(rawValue: subject.type)?.displayName ?? ""
        let year = subject.date?.prefix(4) ?? ""
        let parts = [String(year), typeName, subject.platform].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}

struct CharacterSearchRow: View {
    let character: CharacterSearchResult

    var body: some View {
        NavigationLink(value: AppRoute.characterDetail(id: character.id)) {
            HStack(spacing: 10) {
                CachedAsyncImage(
                    urlString: character.images?.imageURL,
                    fallbackText: character.displayName,
                    targetSize: CGSize(width: 44, height: 44)
                )
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(character.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    if character.nameCn != character.name, !character.name.isEmpty {
                        Text(character.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let actor = character.actors?.first {
                        Text("CV: \(actor.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, .horizontalPadding)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

struct PersonSearchRow: View {
    let person: PersonSearchResult

    var body: some View {
        NavigationLink(value: AppRoute.personDetail(id: person.id)) {
            HStack(spacing: 10) {
                CachedAsyncImage(
                    urlString: person.images?.imageURL,
                    fallbackText: person.displayName,
                    targetSize: CGSize(width: 44, height: 44)
                )
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(person.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    if !person.careerText.isEmpty {
                        Text(person.careerText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, .horizontalPadding)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Skeleton

/// Loading placeholder that mirrors the layout of the real search result rows
/// (avatar + two text lines, full width, same padding). Swapping the old
/// 140×200 centered `SkeletonCard` for this keeps width/height/alignment stable
/// across the loading → results transition, so the list doesn't jump.
struct SkeletonSearchRow: View {
    enum AvatarShape {
        case poster   // 条目: 44×62 圆角矩形
        case circle   // 角色/人物: 44×44 圆形
    }

    let avatarShape: AvatarShape

    var body: some View {
        HStack(spacing: 10) {
            avatarPlaceholder

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemGray5))
                    .frame(height: 14)
                    .frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemGray5))
                    .frame(width: 120, height: 12)
            }
        }
        .padding(.horizontal, .horizontalPadding)
        .padding(.vertical, 10)
        .shimmer()
    }

    @ViewBuilder
    private var avatarPlaceholder: some View {
        switch avatarShape {
        case .poster:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray5))
                .frame(width: 44, height: 62)
        case .circle:
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 44, height: 44)
        }
    }
}
