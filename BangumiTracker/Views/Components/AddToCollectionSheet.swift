import SwiftUI

/// Bottom add-to-collection panel (PRD 5.2.11). Composes status / tags /
/// comment / private into a single `updateCollection` POST. Used by the search
/// manual-ID-entry flow; the quick-add `[+想看]` buttons elsewhere bypass this
/// and add directly as 想看.
///
/// Decoupled from `SearchViewModel` via the `onConfirm` closure (and re-injects
/// nothing) to avoid the iOS 26.5 sheet-doesn't-inherit-@Observable-env trap —
/// see CLAUDE.md "Sheet doesn't inherit Observable env".
struct AddToCollectionSheet: View {
    let subject: Subject
    /// Performs the add; returns nil on success or an error message on failure.
    var onConfirm: (UserSubjectCollectionModifyPayload) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedStatus: CollectionType = .wish
    @State private var tags: [String] = []
    @State private var newTagText: String = ""
    @State private var comment: String = ""
    @State private var isPrivate: Bool = false
    @State private var isSubmitting = false
    @State private var errorText: String?

    private let statuses: [CollectionType] = [.wish, .watching, .watched, .onHold, .dropped]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CachedAsyncImage(
                            urlString: subject.imageURL,
                            fallbackText: subject.displayName,
                            targetSize: CGSize(width: 44, height: 62)
                        )
                        .frame(width: 44, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        Text(subject.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)
                    }
                }

                Section("收藏状态") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(statuses, id: \.rawValue) { status in
                                Button {
                                    Haptics.selection()
                                    selectedStatus = status
                                } label: {
                                    Text(status.displayName(for: SubjectType(rawValue: subject.type)))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(selectedStatus == status ? .white : .primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(selectedStatus == status ? Color.blue : Color(.systemGray6))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("标签") {
                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag)
                                            .font(.system(size: 13))
                                        Button {
                                            tags.removeAll { $0 == tag }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 13))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray6))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    HStack {
                        TextField("添加标签", text: $newTagText)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            .onSubmit(addTag)
                        Button("添加", action: addTag)
                            .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("评价") {
                    TextEditor(text: $comment)
                        .frame(minHeight: 80)
                        .font(.system(size: 15))
                }

                Section {
                    Toggle("仅自己可见", isOn: $isPrivate)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("添加到片库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "添加中…" : "确认添加") { confirm() }
                        .disabled(isSubmitting)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        newTagText = ""
    }

    private func confirm() {
        guard !isSubmitting else { return }
        isSubmitting = true
        var payload = UserSubjectCollectionModifyPayload()
        payload.type = selectedStatus.rawValue
        payload.comment = comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : comment
        payload.tags = tags
        payload.isPrivate = isPrivate
        Task {
            let err = await onConfirm(payload)
            isSubmitting = false
            if let err {
                errorText = err
            } else {
                dismiss()
            }
        }
    }
}
