import Foundation

/// Lightweight file-based JSON cache for first-paint seed data (recommendation
/// rails, profile stats, etc.). Replaces UserDefaults for large JSON blobs
/// (Subject arrays, profile insights) to avoid synchronous plist I/O on the
/// main thread on every write.
///
/// Data is stored in Caches directory — not iCloud-backed, purgeable under
/// storage pressure, and regenerable from the network on first access.
struct FileCache {
    private let dir: URL

    init(subdirectory: String = "dev.bangumi.cache") {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        dir = caches.appendingPathComponent(subdirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func read<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        let url = dir.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func write<T: Encodable>(_ value: T, forKey key: String) {
        let url = dir.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func remove(forKey key: String) {
        let url = dir.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
        try? FileManager.default.removeItem(at: url)
    }

    func clear() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
