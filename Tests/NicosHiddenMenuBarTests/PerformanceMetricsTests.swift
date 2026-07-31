import XCTest
@testable import NicosHiddenMenuBar

final class PerformanceMetricsTests: XCTestCase {
    func testPERF001RevealSamplesStayBounded() {
        var stats = HiddenBarPerformanceStats.default
        for index in 0..<75 {
            stats.append(
                RevealPerformanceSample(
                    shellMilliseconds: Double(index),
                    contentMilliseconds: Double(index + 1),
                    shellItemCount: index == 0 ? 0 : 8,
                    itemCount: 8,
                    imageCount: 0,
                    accessibilityTrusted: true,
                    screenRecordingGranted: false,
                    warm: index > 0,
                    observedAt: "2026-07-29T00:00:00Z"
                )
            )
        }

        XCTAssertEqual(stats.revealSamples.count, HiddenBarPerformanceStats.maxRevealSamples)
        XCTAssertEqual(stats.revealSamples.first?.shellMilliseconds, 25)
        XCTAssertEqual(stats.revealSamples.last?.shellMilliseconds, 74)
    }

    func testPERF001NearestRankPercentile() {
        XCTAssertEqual(
            HiddenBarPerformanceStats.percentile([1, 2, 3, 4, 5], percentile: 0.95),
            5
        )
        XCTAssertEqual(
            HiddenBarPerformanceStats.percentile([30, 10, 20], percentile: 0.50),
            20
        )
        XCTAssertNil(HiddenBarPerformanceStats.percentile([], percentile: 0.95))
    }

    func testPERF001OlderDiagnosticsDecodeWithoutPerformanceField() throws {
        let json = """
        {
          "markerOrderStatus": "unknown",
          "geometryReadable": true,
          "bridgeStatus": "unknown",
          "hotkeyStatus": "unknown",
          "updatedAt": "2026-07-29T00:00:00Z"
        }
        """

        let diagnostics = try JSONDecoder().decode(
            HiddenBarDiagnostics.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(diagnostics.performance)
    }
}
