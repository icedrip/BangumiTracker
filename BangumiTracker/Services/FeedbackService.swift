import Foundation
import UIKit

// MARK: - Feedback Category

enum FeedbackCategory: String, CaseIterable, Codable, Sendable {
    case bug, suggestion, other

    var displayName: String {
        switch self {
        case .bug: "Bug"
        case .suggestion: "建议"
        case .other: "其他"
        }
    }
}

// MARK: - Payload

struct FeedbackMetadata: Codable, Sendable {
    let appVersion: String
    let iosVersion: String
    let deviceModel: String
    let bangumiUsername: String?
}

struct FeedbackPayload: Codable, Sendable {
    let category: FeedbackCategory
    let content: String
    let contact: String?
    let website: String          // honeypot,App 永远发空串
    let metadata: FeedbackMetadata
}

// MARK: - Device metadata

enum DeviceMetadata {
    /// 收集 App 版本 / iOS 版本 / 设备型号,附在每条反馈里便于排查。
    static func now(bangumiUsername: String?) -> FeedbackMetadata {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let appVersion = "\(short) (\(build))"
        let iosVersion = UIDevice.current.systemVersion
        let deviceModel = machineIdentifier() ?? UIDevice.current.model
        return FeedbackMetadata(
            appVersion: appVersion,
            iosVersion: iosVersion,
            deviceModel: deviceModel,
            bangumiUsername: bangumiUsername
        )
    }

    /// 经 uname 取硬件型号标识(如 "iPhone17,1"),取不到返回 nil。
    private static func machineIdentifier() -> String? {
        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else { return nil }
        // Bind size first: reading systemInfo.machine for MemoryLayout.size while
        // passing &systemInfo.machine as inout would overlap (Swift 6 exclusivity).
        let size = MemoryLayout.size(ofValue: systemInfo.machine)
        return withUnsafePointer(to: &systemInfo.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: size) {
                String(cString: $0)
            }
        }
    }
}

// MARK: - FeedbackService

/// 独立于 BangumiAPIClient 的反馈投递服务。App 仅持函数 URL(DevSecrets.feedbackEndpoint),
/// SMTP 授权码只在函数侧环境变量,不下发客户端。
@MainActor
@Observable
final class FeedbackService {
    var isSubmitting = false
    var errorMessage: String?

    @discardableResult
    func submit(
        category: FeedbackCategory,
        content: String,
        contact: String?,
        bangumiUsername: String?
    ) async -> Bool {
        let endpoint = DevSecrets.feedbackEndpoint
        guard !endpoint.isEmpty, let url = URL(string: endpoint) else {
            errorMessage = "反馈服务未配置"
            return false
        }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContact: String? = {
            guard let c = contact?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { return nil }
            return c
        }()
        let payload = FeedbackPayload(
            category: category,
            content: trimmedContent,
            contact: trimmedContact,
            website: "",
            metadata: DeviceMetadata.now(bangumiUsername: bangumiUsername)
        )

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        if !DevSecrets.feedbackKey.isEmpty {
            request.setValue(DevSecrets.feedbackKey, forHTTPHeaderField: "X-Feedback-Key")
        }
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            errorMessage = "提交失败,请稍后重试"
            return false
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "网络连接失败,请检查网络后重试"
                return false
            }
            if (200...299).contains(http.statusCode) {
                return true
            }
            errorMessage = message(for: http.statusCode)
            return false
        } catch {
            errorMessage = "网络连接失败,请检查网络后重试"
            return false
        }
    }

    private func message(for status: Int) -> String {
        switch status {
        case 400: "内容或邮箱格式有误,请检查后重试"
        case 429: "提交过于频繁,请稍后再试"
        case 500...: "服务器暂时不可用,请稍后重试"
        default: "提交失败,请稍后重试"
        }
    }
}
