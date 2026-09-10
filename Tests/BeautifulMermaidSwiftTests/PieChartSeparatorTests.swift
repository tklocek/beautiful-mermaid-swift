import XCTest
@testable import BeautifulMermaid

/// Slices used to be filled and stroked in one pass, with the stroke following the whole
/// wedge outline. That put a mitred join on the very sharp centre vertex — beyond the
/// miter limit, so it was bevelled off and the slices met in a notch rather than a point —
/// and let each wedge's fill paint over the previous wedge's stroke, so the gaps came out
/// uneven. Separators are now drawn on their own, as plain radii.
final class PieChartSeparatorTests: XCTestCase {

    private func svg(_ source: String) throws -> String {
        try renderMermaidSVG(source)
    }

    private static let threeSlices = """
    pie title Traffic
        "Direct" : 60
        "Search" : 30
        "Referral" : 10
    """

    func testSlicesCarryNoStroke() throws {
        let out = try svg(Self.threeSlices)

        XCTAssertTrue(out.contains(".piechart-slice { stroke: none; }"),
                      "a stroked wedge outline is what notched the centre")
    }

    /// Butt caps end flush and perpendicular to their own radius, so three of them meeting
    /// at the centre leave slivers of slice colour between them. Round caps overlap into a
    /// disc and close the junction.
    func testSeparatorsUseRoundCaps() throws {
        let out = try svg(Self.threeSlices)

        XCTAssertTrue(out.contains("stroke-linecap: round"),
                      "butt caps leave a notch where the slices meet")
    }

    func testOneSeparatorPerSliceBoundary() throws {
        let out = try svg(Self.threeSlices)
        let separators = out.components(separatedBy: "class=\"piechart-separator\"").count - 1

        XCTAssertEqual(separators, 3)
    }

    func testEverySeparatorStartsAtTheExactCentre() throws {
        let out = try svg(Self.threeSlices)

        // Each separator is a radius, so x1/y1 must be the centre for all of them.
        // A shared origin is precisely what the old wedge outlines failed to give.
        let lines = out.components(separatedBy: "<line class=\"piechart-separator\"").dropFirst()
        XCTAssertEqual(lines.count, 3)

        let origins = Set(lines.compactMap { line -> String? in
            guard let x1 = line.components(separatedBy: "x1=\"").dropFirst().first?.components(separatedBy: "\"").first,
                  let y1 = line.components(separatedBy: "y1=\"").dropFirst().first?.components(separatedBy: "\"").first
            else { return nil }
            return "\(x1),\(y1)"
        })

        XCTAssertEqual(origins.count, 1, "separators must share one origin, got \(origins)")
    }

    func testASingleSliceGetsNoSeparator() throws {
        let out = try svg("""
        pie title Everything
            "All" : 100
        """)

        // The CSS rule is always emitted; it is the elements that must be absent.
        XCTAssertFalse(out.contains("<line class=\"piechart-separator\""),
                       "a whole-circle pie has no boundary to separate")
    }

    func testSeparatorsSurviveASliceThatWrapsPastHalf() throws {
        let out = try svg("""
        pie title Lopsided
            "Most" : 95
            "Rest" : 5
        """)

        XCTAssertEqual(out.components(separatedBy: "class=\"piechart-separator\"").count - 1, 2)
    }
}
