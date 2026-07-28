import XCTest
@testable import BangumiTracker

final class ErrorHandlingTests: XCTestCase {

    // MARK: - BangumiAPIError Localized Messages (A8 UX Spec)

    func testTimeoutErrorMessage() {
        let error = BangumiAPIError.networkError(URLError(.timedOut))
        XCTAssertEqual(error.errorDescription, "请求超时，请检查网络后重试")
    }

    func testNotConnectedErrorMessage() {
        let error = BangumiAPIError.networkError(URLError(.notConnectedToInternet))
        XCTAssertEqual(error.errorDescription, "网络连接不可用，请检查网络设置")
    }

    func testConnectionLostErrorMessage() {
        let error = BangumiAPIError.networkError(URLError(.networkConnectionLost))
        XCTAssertEqual(error.errorDescription, "网络连接不可用，请检查网络设置")
    }

    func testCannotFindHostErrorMessage() {
        let error = BangumiAPIError.networkError(URLError(.cannotFindHost))
        XCTAssertEqual(error.errorDescription, "无法连接到服务器，请稍后重试")
    }

    func testCannotConnectToHostErrorMessage() {
        let error = BangumiAPIError.networkError(URLError(.cannotConnectToHost))
        XCTAssertEqual(error.errorDescription, "无法连接到服务器，请稍后重试")
    }

    func testDNSLookupFailedErrorMessage() {
        let error = BangumiAPIError.networkError(URLError(.dnsLookupFailed))
        XCTAssertEqual(error.errorDescription, "无法连接到服务器，请稍后重试")
    }

    func testGenericNetworkErrorMessage() {
        let error = BangumiAPIError.networkError(URLError(.badServerResponse))
        XCTAssertEqual(error.errorDescription, "网络请求失败，请稍后重试")
    }

    func testNonURLErrorNetworkErrorMessage() {
        struct CustomError: Error {}
        let error = BangumiAPIError.networkError(CustomError())
        XCTAssertEqual(error.errorDescription, "网络请求失败，请稍后重试")
    }

    func testUnauthorizedErrorMessage() {
        let error = BangumiAPIError.unauthorized
        XCTAssertEqual(error.errorDescription, "登录已过期，请重新登录")
    }

    func testDecodingErrorMessage() {
        let underlying = NSError(domain: "test", code: 1)
        let error = BangumiAPIError.decodingError(underlying)
        XCTAssertEqual(error.errorDescription, "数据解析异常，请稍后重试")
    }

    func testRateLimitErrorMessage() {
        let error = BangumiAPIError.httpError(429)
        XCTAssertEqual(error.errorDescription, "请求过于频繁，请稍后再试")
    }

    func testServerErrorMessages() {
        XCTAssertEqual(BangumiAPIError.httpError(500).errorDescription, "服务器暂时不可用，请稍后重试")
        XCTAssertEqual(BangumiAPIError.httpError(502).errorDescription, "服务器暂时不可用，请稍后重试")
        XCTAssertEqual(BangumiAPIError.httpError(503).errorDescription, "服务器暂时不可用，请稍后重试")
    }

    func testClientErrorMessage() {
        let error = BangumiAPIError.httpError(404)
        XCTAssertEqual(error.errorDescription, "请求失败 (404)，请稍后重试")
    }

    func testInvalidURLErrorMessage() {
        let error = BangumiAPIError.invalidURL
        XCTAssertEqual(error.errorDescription, "请求地址无效")
    }

    // MARK: - Retryable Classification

    func testNetworkErrorsAreRetryable() {
        XCTAssertTrue(BangumiAPIError.networkError(URLError(.timedOut)).isRetryable)
        XCTAssertTrue(BangumiAPIError.networkError(URLError(.notConnectedToInternet)).isRetryable)
        XCTAssertTrue(BangumiAPIError.networkError(URLError(.cannotFindHost)).isRetryable)
    }

    func testServerErrorsAreRetryable() {
        XCTAssertTrue(BangumiAPIError.httpError(500).isRetryable)
        XCTAssertTrue(BangumiAPIError.httpError(502).isRetryable)
        XCTAssertTrue(BangumiAPIError.httpError(503).isRetryable)
    }

    func testClientErrorsAreNotRetryable() {
        XCTAssertFalse(BangumiAPIError.httpError(404).isRetryable)
        XCTAssertFalse(BangumiAPIError.httpError(429).isRetryable)
        XCTAssertFalse(BangumiAPIError.httpError(401).isRetryable)
    }

    func testOtherErrorsAreNotRetryable() {
        XCTAssertFalse(BangumiAPIError.unauthorized.isRetryable)
        XCTAssertFalse(BangumiAPIError.decodingError(NSError(domain: "", code: 0)).isRetryable)
        XCTAssertFalse(BangumiAPIError.invalidURL.isRetryable)
        XCTAssertFalse(BangumiAPIError.notImplemented.isRetryable)
    }

    // MARK: - Error Integration with API Client

    private var session: URLSession!
    private var client: BangumiAPIClient!

    override func setUp() {
        super.setUp()
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let cacheFile = cacheDir.appendingPathComponent("bangumi_response_cache.json")
        try? FileManager.default.removeItem(at: cacheFile)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        client = BangumiAPIClient(session: session, baseURLs: ["https://mock.test"])
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session = nil
        client = nil
        super.tearDown()
    }

    func testHTTP500ThrowsRetryableErrorWithChineseMessage() async {
        await client.clearResponseCache()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        do {
            _ = try await client.fetchCalendar()
            XCTFail("Should have thrown")
        } catch let error as BangumiAPIError {
            XCTAssertTrue(error.isRetryable)
            XCTAssertEqual(error.errorDescription, "服务器暂时不可用，请稍后重试")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testHTTP429ThrowsNonRetryableErrorWithChineseMessage() async {
        await client.clearResponseCache()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        do {
            _ = try await client.fetchCalendar()
            XCTFail("Should have thrown")
        } catch let error as BangumiAPIError {
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(error.errorDescription, "请求过于频繁，请稍后再试")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
