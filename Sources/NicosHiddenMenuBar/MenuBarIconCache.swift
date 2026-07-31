import CoreGraphics
import Foundation

/// Bounded icon cache keyed by stable item identity (CAP-001 / ADR-0004).
final class MenuBarIconCache: @unchecked Sendable {
    struct Entry: Sendable {
        var identityKey: String
        var image: CGImage
        var scale: Double
        var frameSignature: String
        var byteEstimate: Int
        var lastAccess: Date
    }

    struct Stats: Equatable, Sendable {
        var count: Int
        var bytes: Int
        var hits: Int
        var misses: Int
        var evictions: Int
    }

    private let maxEntries: Int
    private let maxBytes: Int
    private var store: [String: Entry] = [:]
    private var hits = 0
    private var misses = 0
    private var evictions = 0
    private let lock = NSLock()

    init(maxEntries: Int = 128, maxBytes: Int = 16 * 1024 * 1024) {
        self.maxEntries = max(1, maxEntries)
        self.maxBytes = max(64 * 1024, maxBytes)
    }

    var stats: Stats {
        lock.lock()
        defer { lock.unlock() }
        let bytes = store.values.reduce(0) { $0 + $1.byteEstimate }
        return Stats(count: store.count, bytes: bytes, hits: hits, misses: misses, evictions: evictions)
    }

    func lookup(identityKey: String, frameSignature: String) -> (CGImage, Double)? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = store[identityKey], entry.frameSignature == frameSignature else {
            misses += 1
            return nil
        }
        hits += 1
        entry.lastAccess = Date()
        store[identityKey] = entry
        return (entry.image, entry.scale)
    }

    func store(identityKey: String, image: CGImage, scale: Double, frameSignature: String) {
        let bytes = max(1, image.width * image.height * 4)
        lock.lock()
        defer { lock.unlock() }
        store[identityKey] = Entry(
            identityKey: identityKey,
            image: image,
            scale: scale,
            frameSignature: frameSignature,
            byteEstimate: bytes,
            lastAccess: Date()
        )
        evictIfNeededLocked()
    }

    func invalidate(identityKey: String) {
        lock.lock()
        defer { lock.unlock() }
        store.removeValue(forKey: identityKey)
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        store.removeAll(keepingCapacity: false)
    }

    /// Pure eviction helper for unit tests — given entry sizes, returns survivors.
    static func evictionPlan(
        entries: [(key: String, bytes: Int, lastAccess: Date)],
        maxEntries: Int,
        maxBytes: Int
    ) -> [String] {
        var sorted = entries.sorted { $0.lastAccess > $1.lastAccess }
        var total = sorted.reduce(0) { $0 + $1.bytes }
        while sorted.count > maxEntries || total > maxBytes {
            guard let removed = sorted.popLast() else { break }
            total -= removed.bytes
        }
        return sorted.map(\.key)
    }

    private func evictIfNeededLocked() {
        var totalBytes = store.values.reduce(0) { $0 + $1.byteEstimate }
        while store.count > maxEntries || totalBytes > maxBytes {
            guard let victim = store.values.min(by: { $0.lastAccess < $1.lastAccess }) else {
                break
            }
            store.removeValue(forKey: victim.identityKey)
            totalBytes -= victim.byteEstimate
            evictions += 1
        }
    }
}

enum MenuBarFrameSignature {
    static func make(_ frame: CGRect, scale: Double) -> String {
        let x = Int(frame.origin.x.rounded())
        let y = Int(frame.origin.y.rounded())
        let w = Int(frame.size.width.rounded())
        let h = Int(frame.size.height.rounded())
        let s = Int((scale * 100).rounded())
        return "\(x),\(y),\(w),\(h)@\(s)"
    }
}
