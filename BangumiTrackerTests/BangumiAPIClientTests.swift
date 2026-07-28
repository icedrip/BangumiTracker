import XCTest
@testable import BangumiTracker

final class BangumiAPIClientTests: XCTestCase {
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

    private func jsonResponse(_ json: String, status: Int = 200) -> @Sendable (URLRequest) async throws -> (HTTPURLResponse, Data) {
        { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }
    }

    // MARK: - Token Management

    func testHasTokenInitiallyFalse() async {
        let has = await client.hasToken()
        XCTAssertFalse(has)
    }

    func testSetTokenMakesHasTokenTrue() async {
        await client.setToken("test-token")
        let has = await client.hasToken()
        XCTAssertTrue(has)
    }

    func testSetNilTokenMakesHasTokenFalse() async {
        await client.setToken("test-token")
        await client.setToken(nil)
        let has = await client.hasToken()
        XCTAssertFalse(has)
    }

    func testGenerationBumpsOnAccountChange() async {
        await client.setToken("token-a")
        let gen1 = await client.currentGeneration()
        await client.setToken("token-b")
        let gen2 = await client.currentGeneration()
        XCTAssertGreaterThan(gen2, gen1)
    }

    func testGenerationDoesNotBumpOnSameToken() async {
        await client.setToken("token-a")
        await client.setToken("token-a")
        let gen1 = await client.currentGeneration()
        await client.setToken("token-a")
        let gen2 = await client.currentGeneration()
        XCTAssertEqual(gen1, gen2)
    }

    // MARK: - Request & Decoding

    func testFetchCalendarDecodesResponse() async throws {
        let json = """
        [{"weekday":{"en":"Monday","cn":"星期一","ja":"月曜日","id":1},"items":[]}]
        """
        MockURLProtocol.requestHandler = jsonResponse(json)
        let days = try await client.fetchCalendar()
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].weekday.en, "Monday")
        XCTAssertEqual(days[0].weekday.id, 1)
    }

    func testFetchSubjectDecodesResponse() async throws {
        let json = """
        {"id":1,"type":2,"name":"Test","name_cn":"测试","summary":"","ep":12,"eps":12,
         "score":8.5,"rank":10,"date":"2024-01-01","platform":"TV",
         "images":{"large":"https://x/l.jpg","medium":"https://x/m.jpg","small":"https://x/s.jpg"},
         "infobox":[],"tags":[],"rating":{"total":100,"count":{"1":1,"2":1,"3":1,"4":1,"5":1,"6":1,"7":1,"8":1,"9":1,"10":1},"score":8.5}}
        """
        MockURLProtocol.requestHandler = jsonResponse(json)
        let subject = try await client.fetchSubject(id: 1)
        XCTAssertEqual(subject.id, 1)
        XCTAssertEqual(subject.name, "Test")
    }

    func testHTTPErrorThrows() async {
        await client.clearResponseCache()
        MockURLProtocol.requestHandler = jsonResponse("{}", status: 500)
        do {
            _ = try await client.fetchCalendar()
            XCTFail("Should have thrown")
        } catch let error as BangumiAPIError {
            if case .httpError(let code) = error {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testUnauthorizedThrows() async {
        await client.setToken("expired-token")
        await client.clearResponseCache()
        MockURLProtocol.requestHandler = jsonResponse("{}", status: 401)
        do {
            _ = try await client.fetchMe()
            XCTFail("Should have thrown")
        } catch let error as BangumiAPIError {
            guard case .unauthorized = error else {
                XCTFail("Expected unauthorized, got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Cache Behavior

    func testSecondRequestServedFromCache() async throws {
        let json = """
        [{"weekday":{"en":"Monday","cn":"星期一","ja":"月曜日","id":1},"items":[]}]
        """
        let requestCount = ActorCounter()
        MockURLProtocol.requestHandler = { request in
            await requestCount.increment()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }
        _ = try await client.fetchCalendar()
        _ = try await client.fetchCalendar()
        let count = await requestCount.value
        XCTAssertEqual(count, 1, "Second call should be served from cache")
    }

    func testClearCacheForcesRefetch() async throws {
        let json = """
        [{"weekday":{"en":"Monday","cn":"星期一","ja":"月曜日","id":1},"items":[]}]
        """
        let requestCount = ActorCounter()
        MockURLProtocol.requestHandler = { request in
            await requestCount.increment()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }
        _ = try await client.fetchCalendar()
        await client.clearResponseCache()
        _ = try await client.fetchCalendar()
        let count = await requestCount.value
        XCTAssertEqual(count, 2, "After cache clear, should refetch from network")
    }

    // MARK: - Concurrency Safety

    func testConcurrentRequestsDeduped() async throws {
        let json = """
        [{"weekday":{"en":"Monday","cn":"星期一","ja":"月曜日","id":1},"items":[]}]
        """
        let requestCount = ActorCounter()
        MockURLProtocol.requestHandler = { request in
            await requestCount.increment()
            try await Task.sleep(for: .milliseconds(50))
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }
        let apiClient = client!
        async let r1 = apiClient.fetchCalendar()
        async let r2 = apiClient.fetchCalendar()
        _ = try await (r1, r2)
        let count = await requestCount.value
        XCTAssertLessThanOrEqual(count, 2, "Concurrent identical requests should be deduped or cached")
    }

    func testTokenChangeInvalidatesCachePreventingCrossAccountBleed() async throws {
        let json = """
        [{"weekday":{"en":"Monday","cn":"星期一","ja":"月曜日","id":1},"items":[]}]
        """
        let requestCount = ActorCounter()
        MockURLProtocol.requestHandler = { request in
            await requestCount.increment()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }
        let apiClient = client!
        await apiClient.setToken("token-a")
        _ = try await apiClient.fetchCalendar()
        let countAfterFirst = await requestCount.value
        XCTAssertEqual(countAfterFirst, 1)

        await apiClient.setToken("token-b")
        _ = try await apiClient.fetchCalendar()
        let countAfterSecond = await requestCount.value
        XCTAssertEqual(countAfterSecond, 2, "Token change must invalidate cache to prevent cross-account data bleed")
    }

    // MARK: - Pagination Safety

    func testPaginationStopsAtMaxPages() async throws {
        let requestCount = ActorCounter()
        // Always return a full page (50 items) with a huge total to simulate infinite data
        MockURLProtocol.requestHandler = { request in
            await requestCount.increment()
            let items = (0..<50).map { "{\"subject_id\":\($0),\"subject_type\":2,\"rate\":0,\"type\":3,\"tags\":[],\"ep_status\":0,\"vol_status\":0,\"private\":false}" }
            let json = "{\"data\":[\(items.joined(separator: ","))],\"total\":99999}"
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }
        let result = try await client.fetchUserCollections(username: "maxpages-user", type: nil, maxPages: 3)
        let count = await requestCount.value
        XCTAssertEqual(count, 3, "Should stop after maxPages requests")
        XCTAssertEqual(result.count, 150, "Should have 3 pages × 50 items")
    }

    func testPaginationDefaultMaxPagesIs50() async throws {
        let requestCount = ActorCounter()
        MockURLProtocol.requestHandler = { request in
            await requestCount.increment()
            let items = (0..<50).map { "{\"subject_id\":\($0),\"subject_type\":2,\"rate\":0,\"type\":3,\"tags\":[],\"ep_status\":0,\"vol_status\":0,\"private\":false}" }
            let json = "{\"data\":[\(items.joined(separator: ","))],\"total\":99999}"
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }
        let result = try await client.fetchUserCollections(username: "default-maxpages-user")
        let count = await requestCount.value
        XCTAssertEqual(count, 50, "Default maxPages should be 50")
        XCTAssertEqual(result.count, 2500, "Should have 50 pages × 50 items")
    }

    func testPaginationStopsEarlyWhenDataExhausted() async throws {
        let requestCount = ActorCounter()
        MockURLProtocol.requestHandler = { request in
            await requestCount.increment()
            // Return only 10 items (less than pageSize) to signal end of data
            let items = (0..<10).map { "{\"subject_id\":\($0),\"subject_type\":2,\"rate\":0,\"type\":3,\"tags\":[],\"ep_status\":0,\"vol_status\":0,\"private\":false}" }
            let json = "{\"data\":[\(items.joined(separator: ","))],\"total\":10}"
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }
        let result = try await client.fetchUserCollections(username: "exhausted-user", type: nil, maxPages: 50)
        let count = await requestCount.value
        XCTAssertEqual(count, 1, "Should stop after first page when data < pageSize")
        XCTAssertEqual(result.count, 10)
    }

    // MARK: - Error Properties

    func testRetryableErrors() {
        XCTAssertTrue(BangumiAPIError.networkError(URLError(.timedOut)).isRetryable)
        XCTAssertTrue(BangumiAPIError.httpError(502).isRetryable)
        XCTAssertFalse(BangumiAPIError.unauthorized.isRetryable)
        XCTAssertFalse(BangumiAPIError.httpError(404).isRetryable)
        XCTAssertFalse(BangumiAPIError.invalidURL.isRetryable)
    }
}

private actor ActorCounter {
    var value = 0
    func increment() { value += 1 }
}
