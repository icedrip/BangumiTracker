import Testing
import Foundation
@testable import BangumiTracker

// MARK: - Smoke tests

/// Verify that the API error types conform to expected contracts.
struct BangumiTrackerSmokeTests {

    @Test("BangumiAPIError isRetryable returns correct values")
    func apiErrorIsRetryable() {
        // These cases don't throw — just validate the enum contract
        #expect(BangumiAPIError.httpError(503).isRetryable)
        #expect(BangumiAPIError.httpError(500).isRetryable)
        #expect(BangumiAPIError.httpError(502).isRetryable)
        #expect(BangumiAPIError.networkError(URLError(.notConnectedToInternet)).isRetryable)
        #expect(BangumiAPIError.httpError(400).isRetryable == false)
        #expect(BangumiAPIError.httpError(403).isRetryable == false)
        #expect(BangumiAPIError.httpError(404).isRetryable == false)
        #expect(BangumiAPIError.unauthorized.isRetryable == false)
        #expect(BangumiAPIError.decodingError(URLError(.cannotDecodeContentData)).isRetryable == false)
        #expect(BangumiAPIError.invalidURL.isRetryable == false)
        #expect(BangumiAPIError.notImplemented.isRetryable == false)
    }

    @Test("BangumiAPIError provides non-empty error descriptions")
    func apiErrorDescriptions() {
        let errors: [BangumiAPIError] = [
            .notImplemented,
            .unauthorized,
            .networkError(URLError(.timedOut)),
            .decodingError(URLError(.cannotDecodeContentData)),
            .httpError(503),
            .invalidURL,
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}
