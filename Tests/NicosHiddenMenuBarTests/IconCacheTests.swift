import CoreGraphics
import XCTest
@testable import NicosHiddenMenuBar

final class IconCacheTests: XCTestCase {
    func testCAP001CacheHitMissAndInvalidation() {
        let cache = MenuBarIconCache(maxEntries: 4, maxBytes: 1_000_000)
        let image = makeTestImage()
        let key = "v1:com.example:_:Status:0"
        let signature = MenuBarFrameSignature.make(CGRect(x: 1, y: 2, width: 3, height: 4), scale: 2)

        XCTAssertNil(cache.lookup(identityKey: key, frameSignature: signature))
        cache.store(identityKey: key, image: image, scale: 2, frameSignature: signature)

        let hit = cache.lookup(identityKey: key, frameSignature: signature)
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.1, 2)

        // Frame change misses.
        XCTAssertNil(cache.lookup(
            identityKey: key,
            frameSignature: MenuBarFrameSignature.make(CGRect(x: 9, y: 9, width: 3, height: 4), scale: 2)
        ))

        cache.invalidate(identityKey: key)
        XCTAssertNil(cache.lookup(identityKey: key, frameSignature: signature))

        let stats = cache.stats
        XCTAssertGreaterThanOrEqual(stats.hits, 1)
        XCTAssertGreaterThanOrEqual(stats.misses, 2)
    }

    func testCAP001EvictionRespectsCountAndByteBudgets() {
        let now = Date()
        let plan = MenuBarIconCache.evictionPlan(
            entries: [
                (key: "a", bytes: 100, lastAccess: now.addingTimeInterval(-3)),
                (key: "b", bytes: 100, lastAccess: now.addingTimeInterval(-2)),
                (key: "c", bytes: 100, lastAccess: now.addingTimeInterval(-1)),
                (key: "d", bytes: 100, lastAccess: now),
            ],
            maxEntries: 2,
            maxBytes: 10_000
        )
        XCTAssertEqual(Set(plan), Set(["c", "d"]))

        let bytePlan = MenuBarIconCache.evictionPlan(
            entries: [
                (key: "keep", bytes: 80, lastAccess: now),
                (key: "big", bytes: 900, lastAccess: now.addingTimeInterval(-1)),
            ],
            maxEntries: 10,
            maxBytes: 200
        )
        // Oldest oversized entry is dropped first; recent small entry survives.
        XCTAssertEqual(bytePlan, ["keep"])
    }

    func testCAP001LiveCacheEvictsOldestUnderMaxEntries() {
        let cache = MenuBarIconCache(maxEntries: 2, maxBytes: 10_000_000)
        let image = makeTestImage()
        cache.store(identityKey: "a", image: image, scale: 1, frameSignature: "1")
        cache.store(identityKey: "b", image: image, scale: 1, frameSignature: "1")
        // Touch a so b is older when c arrives... actually store sets lastAccess now for c;
        // a and b both old; eviction removes least recently accessed.
        _ = cache.lookup(identityKey: "a", frameSignature: "1")
        cache.store(identityKey: "c", image: image, scale: 1, frameSignature: "1")

        XCTAssertNotNil(cache.lookup(identityKey: "a", frameSignature: "1"))
        XCTAssertNotNil(cache.lookup(identityKey: "c", frameSignature: "1"))
        XCTAssertEqual(cache.stats.count, 2)
        XCTAssertGreaterThanOrEqual(cache.stats.evictions, 1)
    }

    private func makeTestImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
