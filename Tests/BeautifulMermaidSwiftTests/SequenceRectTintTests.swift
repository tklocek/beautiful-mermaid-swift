import XCTest
@testable import BeautifulMermaid

/// `rect` is Mermaid's way of tinting a run of messages, and its argument is a colour.
///
/// It was drawn like every other block: a frame with a tab reading
/// `rect [rgb(200, 150, 255)]` — a CSS expression printed onto the diagram, in a tab that
/// also pushed the frame wider than the messages it encloses.
final class SequenceRectTintTests: XCTestCase {

    private static let colors = DiagramColors(bg: "#FFFFFF", fg: "#27272A")

    private func lines(_ source: String) -> [String] {
        source
            .components(separatedBy: CharacterSet(charactersIn: "\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
    }

    private static let source = """
    sequenceDiagram
        A->>B: before
        rect rgb(200, 150, 255)
            A->>B: inside
        end
        A->>B: after
    """

    func testTheColourIsKeptAndIsNotALabel() throws {
        let parsed = try parseSequenceDiagram(lines(Self.source))

        XCTAssertEqual(parsed.blocks.count, 1)
        XCTAssertEqual(parsed.blocks[0].type, "rect")
        XCTAssertEqual(parsed.blocks[0].label, "", "nothing is written on a tint")
        XCTAssertEqual(parsed.blocks[0].fill, "rgb(200, 150, 255)")
        XCTAssertFalse(parsed.blocks[0].hasTab)
    }

    func testTheTintIsPaintedUnderTheStructureItHighlights() throws {
        let svg = try renderSequenceSvg(
            layoutSequenceDiagram(parseSequenceDiagram(lines(Self.source))), Self.colors)

        let tint = try XCTUnwrap(svg.range(of: "rgb(200, 150, 255)"))
        let firstLifeline = try XCTUnwrap(svg.range(of: "class=\"lifeline\""))
        XCTAssertLessThan(tint.lowerBound, firstLifeline.lowerBound,
                          "SVG paints in document order, so a background comes first")
    }

    func testTheSvgPaintsTheAuthorsColourAndDrawsNoTab() throws {
        let svg = try renderSequenceSvg(
            layoutSequenceDiagram(parseSequenceDiagram(lines(Self.source))),
            Self.colors
        )

        XCTAssertTrue(svg.contains("fill=\"rgb(200, 150, 255)\""), "the author's colour reaches the drawing")
        XCTAssertFalse(svg.contains("rect [rgb"), "no CSS expression is written onto the diagram")
        XCTAssertFalse(svg.contains(">rect<"), "and no tab says the word `rect` either")
    }

    func testAFrameNeedsNoRoomForATabItDoesNotHave() throws {
        func frame(_ opener: String) throws -> PositionedSequenceBlock {
            let laid = try layoutSequenceDiagram(parseSequenceDiagram(lines("""
            sequenceDiagram
                \(opener)
                    A->>A: x
                end
            """)))
            return try XCTUnwrap(laid.blocks.first)
        }

        // One actor and a self-call, so the messages take far less width than the text of
        // the colour would. A tab is what makes a frame wider than what it encloses.
        let tinted = try frame("rect rgba(200, 150, 255, 0.35)")
        let framed = try frame("opt rgba(200, 150, 255, 0.35)")
        XCTAssertEqual(tinted.width, 120, accuracy: 0.5, "as wide as the messages, and no wider")
        XCTAssertGreaterThan(framed.width, 200, "where a tab has to hold the same text")

        // And the tint's geometry cannot depend on how the colour was spelled.
        XCTAssertEqual(try frame("rect #eee").width, tinted.width)
        XCTAssertEqual(try frame("rect #eee").y, tinted.y)
    }

    func testAColourGoesThroughAsWrittenAndIsNeverLost() throws {
        // A named colour is passed to the drawing as the author wrote it. In SVG that is all
        // it takes — the name is CSS and the renderer of the page resolves it. Core Graphics
        // has no table of names, so `BMColor.css` answers nil there and the drawing falls
        // back to the theme's own heading tint: the region the author asked to stand out
        // still stands out, which is the part that must never be lost.
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            rect rebeccapurple
                A->>B: inside
            end
        """))
        XCTAssertEqual(parsed.blocks.first?.fill, "rebeccapurple")
        XCTAssertNil(BMColor.css("rebeccapurple"))

        let svg = try renderSequenceSvg(layoutSequenceDiagram(parsed), Self.colors)
        XCTAssertTrue(svg.contains("fill=\"rebeccapurple\" stroke=\"none\""))
    }

    func testARectWithNoColourAtAllStillMarksTheRegion() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            rect
                A->>B: inside
            end
        """))
        XCTAssertNil(parsed.blocks.first?.fill)

        let svg = try renderSequenceSvg(layoutSequenceDiagram(parsed), Self.colors)
        XCTAssertTrue(svg.contains("fill=\"var(--_group-hdr)\" stroke=\"none\""),
                      "the theme's own heading tint stands in when nothing was asked for")
    }

    func testCssColoursAreReadTheWayCssWritesThem() throws {
        XCTAssertNotNil(BMColor.css("#eef"))
        XCTAssertNotNil(BMColor.css("#EEFF00"))
        XCTAssertNotNil(BMColor.css("rgb(200, 150, 255)"))
        XCTAssertNotNil(BMColor.css("rgba(200, 150, 255, 0.5)"))
        XCTAssertNil(BMColor.css("var(--thing)"))
        XCTAssertNil(BMColor.css("#nothex"))

        let purple = try XCTUnwrap(BMColor.css("rgb(200, 150, 255)"))
        XCTAssertTrue(purple.bmColorEquals(BMColor(hex: "#C896FF")), "200,150,255 is #C896FF")
    }
}
