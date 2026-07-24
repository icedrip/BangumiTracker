import SwiftUI

// MARK: - Sheets

struct CommentEditorSheet: View {
    @Binding var commentDraft: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("我的评价") {
                    TextEditor(text: $commentDraft)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("编辑评价")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TagEditorSheet: View {
    @Binding var tagDraft: String
    let onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("添加标签") {
                    TextField("标签名称", text: $tagDraft)
                }
            }
            .navigationTitle("添加标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        onAdd()
                        dismiss()
                    }
                    .disabled(tagDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
