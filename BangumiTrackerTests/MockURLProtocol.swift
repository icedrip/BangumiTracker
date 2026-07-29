import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A minimal URLProtocol that intercepts network requests and returns canned responses.
/// Used to isolate BangumiAPIClient tests from the real Bangumi API.
final class MockURLProtocol: URLProtocol {

    /// The request handler must be set before each test. Marked nonisolated to
    /// match the runtime calling convention of URLProtocol; callers on the
    /// main actor synchronize access through the test's sequential flow.
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Ensures the handler is cleared after each test to prevent state leakage.
    static func reset() { requestHandler = nil }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("MockURLProtocol.requestHandler is nil — set it before the test")
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
