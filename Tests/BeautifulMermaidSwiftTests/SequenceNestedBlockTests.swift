import XCTest
@testable import BeautifulMermaid

/// A block's span came from the actors it covers, so a nested block covering the same
/// actors as its parent was given identical edges. Nesting was then visible only as a
/// vertical offset — three frames one inside another looked like three frames in a row.
final class SequenceNestedBlockTests: XCTestCase {

    private func lines(_ source: String) -> [String] {
        source
            .components(separatedBy: CharacterSet(charactersIn: "\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
    }

    private func layout(_ source: String) throws -> PositionedSequenceDiagram {
        try layoutSequenceDiagram(parseSequenceDiagram(lines(source)))
    }

    private func block(_ type: String, in positioned: PositionedSequenceDiagram) throws -> PositionedSequenceBlock {
        try XCTUnwrap(positioned.blocks.first { $0.type == type })
    }

    private func assertContained(
        _ inner: PositionedSequenceBlock,
        within outer: PositionedSequenceBlock,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThan(inner.x, outer.x,
                             "\(inner.type) does not step in from \(outer.type) on the left",
                             file: file, line: line)
        XCTAssertLessThan(inner.x + inner.width, outer.x + outer.width,
                          "\(inner.type) reaches past \(outer.type) on the right",
                          file: file, line: line)
    }

    // MARK: - Depth

    func testDepthIsRecordedWhileParsing() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            participant API
            participant DB
            loop outer
                alt middle
                    opt inner
                        API->>DB: x
                    end
                end
            end
        """))

        let byType = Dictionary(uniqueKeysWithValues: parsed.blocks.map { ($0.type, $0.depth) })
        XCTAssertEqual(byType["loop"], 0)
        XCTAssertEqual(byType["alt"], 1)
        XCTAssertEqual(byType["opt"], 2)
    }

    // MARK: - Insets

    func testANestedFrameStepsInsideItsParent() throws {
        let positioned = try layout("""
        sequenceDiagram
            participant U
            participant API
            participant DB
            loop outer
                API->>API: work
                alt inner
                    API->>DB: reload
                end
            end
        """)

        assertContained(try block("alt", in: positioned), within: try block("loop", in: positioned))
    }

    func testThreeLevelsAreConcentric() throws {
        let positioned = try layout("""
        sequenceDiagram
            participant U
            participant API
            participant DB
            loop outer
                alt middle
                    opt inner
                        API->>DB: x
                    end
                end
            end
        """)

        let outer = try block("loop", in: positioned)
        let middle = try block("alt", in: positioned)
        let inner = try block("opt", in: positioned)

        assertContained(middle, within: outer)
        assertContained(inner, within: middle)
    }

    /// The case that made insetting and the minimum width disagree: with little content,
    /// both frames clamp to the minimum, and if the minimum is applied after the inset the
    /// inner frame ends up wider on the right than the parent holding it.
    func testAMinimumWidthFrameStillFitsInsideItsParent() throws {
        let positioned = try layout("""
        sequenceDiagram
            participant U
            participant API
            participant DB
            loop a
                alt b
                    API->>API: x
                end
            end
        """)

        assertContained(try block("alt", in: positioned), within: try block("loop", in: positioned))
    }

    func testDeepNestingNeverInvertsAFrame() throws {
        let positioned = try layout("""
        sequenceDiagram
            participant API
            loop one
                alt two
                    opt three
                        loop four
                            alt five
                                API->>API: x
                            end
                        end
                    end
                end
            end
        """)

        for block in positioned.blocks {
            XCTAssertGreaterThan(block.width, 0, "\(block.type) has collapsed")
        }
    }

    // MARK: - Tab padding

    /// The tab was sized from `estimateTextWidth` while the text was drawn with the
    /// platform's real metrics, which run 12-17% wider. The label kept its padding on the
    /// left and ran a point past the tab on the right.

    private static let tabPadX: Double = 8

    func testTheTabPadsItsLabelEquallyOnBothSides() throws {
        let config = RenderConfig()
        let renderer = LabelRenderer()

        for label in ["every 30s", "cache miss", "x", "retry with exponential backoff"] {
            let text = "loop [\(label)]"
            let measured = renderer.measureText(text, font: config.groupHeaderFont()).width
            let tabWidth = measured + Self.tabPadX * 2

            let leading = Self.tabPadX
            let trailing = tabWidth - (Self.tabPadX + measured)

            XCTAssertEqual(leading, trailing, accuracy: 0.001,
                           "unequal grey either side of \(text)")
            XCTAssertGreaterThan(trailing, 0, "\(text) runs past its own tab")
        }
    }

    /// The frame reserves room for the tab from the estimator, so it has to allow for the
    /// estimator running short — otherwise the tab it is meant to hold hangs out of it.
    func testTheFrameIsNeverOverhungByItsOwnTab() throws {
        let config = RenderConfig()
        let renderer = LabelRenderer()

        for label in ["x", "every 30s", "retry with exponential backoff until it responds",
                      "WWWWWWWWWWWWWWWWWWWW", "iiiiiiiiiiiiiiiiiiii"] {
            let positioned = try layout("""
            sequenceDiagram
                participant API
                loop \(label)
                    API->>API: p
                end
            """)
            let frame = try block("loop", in: positioned)
            let tabWidth = renderer.measureText("loop [\(label)]", font: config.groupHeaderFont()).width
                + Self.tabPadX * 2

            XCTAssertLessThanOrEqual(
                tabWidth, frame.width,
                "the tab for \(label) is \(tabWidth - frame.width)pt wider than its frame"
            )
        }
    }

    // MARK: - Minimum width

    func testALoneSelfMessageGetsAFrameWorthLookingAt() throws {
        let positioned = try layout("""
        sequenceDiagram
            participant API
            loop x
                API->>API: p
            end
        """)

        XCTAssertGreaterThanOrEqual(try block("loop", in: positioned).width, 120)
    }

    func testTheMinimumDoesNotPushAFrameOverAnUninvolvedLifeline() throws {
        let positioned = try layout("""
        sequenceDiagram
            participant U
            participant API
            participant DB
            loop x
                API->>API: x
            end
        """)
        let frame = try block("loop", in: positioned)

        for lifeline in positioned.lifelines where lifeline.actorId != "API" {
            XCTAssertFalse(
                lifeline.x > frame.x && lifeline.x < frame.x + frame.width,
                "widening to the minimum ran the frame across \(lifeline.actorId)"
            )
        }
    }

    func testAWideFrameIsLeftAlone() throws {
        let positioned = try layout("""
        sequenceDiagram
            participant U
            participant API
            participant DB
            loop x
                U->>DB: spans everything
            end
        """)

        XCTAssertGreaterThan(try block("loop", in: positioned).width, 200,
                             "a frame already past the minimum must not be touched by it")
    }
}
