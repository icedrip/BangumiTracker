import Testing
import Foundation
@testable import BangumiTracker

// MARK: - BangumiAPIClient Tests

@Suite("BangumiAPIClient")
struct BangumiAPIClientTests {

    // MARK: - Error Descriptions

    @Test("userFacingMessage returns non-empty messages for all error types")
    func allErrorTypesHaveMessages() {
        let errors: [BangumiAPIError] = [
            .notImplemented, .unauthorized, .networkTimeout,
            .networkUnavailable, .serverUnreachable,
            .networkError(URLError(.unknown)),
            .decodingError(URLError(.cannotDecodeContentData)),
            .httpError(503), .httpError(404), .rateLimited, .invalidURL,
        ]
        for error in errors {
            #expect(!error.userFacingMessage.isEmpty)
        }
    }

    // MARK: - Error Mapping (network mocking)

    @Test("HTTP 429 is retryable == false")
    func rateLimitedIsNotRetryable() {
        #expect(!BangumiAPIError.rateLimited.isRetryable)
    }

    @Test("networkTimeout is retryable")
    func networkTimeoutIsRetryable() {
        #expect(BangumiAPIError.networkTimeout.isRetryable)
    }

    @Test("serverError5xx is retryable")
    func serverError5xxIsRetryable() {
        #expect(BangumiAPIError.httpError(503).isRetryable)
        #expect(!BangumiAPIError.httpError(403).isRetryable)
    }

    @Test("from() maps URLError codes correctly")
    func urlErrorMapping() {
        let timeout = BangumiAPIError.from(URLError(.timedOut))
        if case .networkTimeout = timeout {} else { Issue.record("Expected .networkTimeout") }

        let noNetwork = BangumiAPIError.from(URLError(.notConnectedToInternet))
        if case .networkUnavailable = noNetwork {} else { Issue.record("Expected .networkUnavailable") }

        let dnsFail = BangumiAPIError.from(URLError(.dnsLookupFailed))
        if case .serverUnreachable = dnsFail {} else { Issue.record("Expected .serverUnreachable") }
    }
}
