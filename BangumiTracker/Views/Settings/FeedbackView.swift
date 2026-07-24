import SwiftUI

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var service = FeedbackService()

    @State private var category: FeedbackCategory = .bug
    @State private var content: String = ""
    @State private var contact: String = ""

    private let username: String?
    private let onSuccess: () -> Void
    private let maxContent = 2000

    init(username: String?, onSuccess: @escaping () -> Void) {
        self.username = username
        self.onSuccess = onSuccess
    }

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedContact: String {
        contact.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var endpointConfigured: Bool {
        !DevSecrets.feedbackEndpoint.isEmpty
    }
    private var contactIsValid: Bool {
        trimmedContact.isEmpty || isValidEmail(trimmedContact)
    }
    private func isValidEmail(_ s: String) -> Bool {
        s.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
    private var canSubmit: Bool {
        endpointConfigured
            && !service.isSubmitting
            && !trimmedContent.isEmpty
            && trimmedContent.count <= maxContent
            && contactIsValid
    }
    private var submitButtonTitle: String {
        if !endpointConfigured { return "反馈服务未配置" }
        if service.isSubmitting { return "提交中…" }
        if service.errorMessage != nil { return "重试" }
        return "提交"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("类型") {
                    Picker("类型", selection: $category) {
                        ForEach(FeedbackCategory.allCases, id: \.self) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 120)
                        .accessibilityLabel("反馈内容")
                    HStack {
                        Spacer()
                        Text("\(trimmedContent.count)/\(maxContent)")
                            .font(.footnote)
                            .foregroundStyle(trimmedContent.count > maxContent ? Color.red : Color.secondary)
                    }
                } header: {
                    Text("内容")
                } footer: {
                    Text("必填,1–\(maxContent) 字")
                }

                Section {
                    TextField("回邮邮箱,方便回复", text: $contact)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("联系方式(选填)")
                } footer: {
                    if !trimmedContact.isEmpty && !contactIsValid {
                        Text("邮箱格式有误").foregroundStyle(.red)
                    }
                }

                Section {
                    Text("提交时将自动附带 App 版本、iOS 版本、设备型号、Bangumi 用户名(若已登录),用于排查问题。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = service.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("意见反馈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitButtonTitle) {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }

    private func submit() async {
        let ok = await service.submit(
            category: category,
            content: content,
            contact: contact,
            bangumiUsername: username
        )
        if ok {
            Haptics.success()
            onSuccess()
            dismiss()
        } else {
            Haptics.error()
        }
    }
}
