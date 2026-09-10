import XCTest
@testable import BeautifulMermaid

/// Mermaid spells activation two ways: `->>+` / `->>-` suffixes on an arrow, and
/// `activate` / `deactivate` on lines of their own. Only the suffixes were understood —
/// the statements were dropped without trace, so a diagram written in the second style
/// drew no activation bars at all.
final class SequenceActivationStatementTests: XCTestCase {

    private func lines(_ source: String) -> [String] {
        source
            .components(separatedBy: CharacterSet(charactersIn: "\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
    }

    private func layout(_ source: String) throws -> PositionedSequenceDiagram {
        try layoutSequenceDiagram(parseSequenceDiagram(lines(source)))
    }

    // MARK: - Parsing

    func testStatementsAreNotMistakenForMessagesOrActors() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            participant API
            activate API
            API->>API: work
            deactivate API
        """))

        XCTAssertEqual(parsed.messages.count, 1)
        XCTAssertEqual(parsed.actors.map(\.id), ["API"])
        XCTAssertEqual(parsed.activationEvents.count, 2)
        XCTAssertEqual(parsed.activationEvents.map(\.isActivate), [true, false])
    }

    func testAStatementNamesAnActorNotYetDeclared() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            activate API
            API->>API: work
        """))

        XCTAssertEqual(parsed.actors.map(\.id), ["API"])
    }

    func testTheKeywordsAreCaseInsensitive() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            participant API
            Activate API
            API->>API: work
            DEACTIVATE API
        """))

        XCTAssertEqual(parsed.activationEvents.map(\.isActivate), [true, false])
    }

    // MARK: - Layout

    func testStatementsProduceAnActivationBar() throws {
        let positioned = try layout("""
        sequenceDiagram
            participant U
            participant API
            U->>API: a
            activate API
            API->>API: work
            deactivate API
            API-->>U: b
        """)

        XCTAssertEqual(positioned.activations.count, 1)
        let bar = try XCTUnwrap(positioned.activations.first)
        XCTAssertEqual(bar.actorId, "API")
        XCTAssertLessThan(bar.topY, bar.bottomY)
    }

    func testTheTwoSpellingsCanNest() throws {
        let positioned = try layout("""
        sequenceDiagram
            participant U
            participant API
            U->>+API: a
            activate API
            API->>API: inner
            deactivate API
            API-->>-U: b
        """)

        XCTAssertEqual(positioned.activations.count, 2)

        // The inner bar opens later and closes no later than the outer one.
        let sorted = positioned.activations.sorted { $0.topY < $1.topY }
        XCTAssertLessThanOrEqual(sorted[0].topY, sorted[1].topY)
        XCTAssertGreaterThanOrEqual(sorted[0].bottomY, sorted[1].bottomY)

        // Nested bars are offset so both remain visible.
        XCTAssertNotEqual(sorted[0].x, sorted[1].x)
    }

    func testAnUnclosedActivationIsStillDrawn() throws {
        let positioned = try layout("""
        sequenceDiagram
            participant U
            participant API
            U->>API: a
            activate API
            API-->>U: b
        """)

        XCTAssertEqual(positioned.activations.count, 1, "a missing `deactivate` must not lose the bar")
    }

    func testADeactivateWithoutAnActivateIsIgnored() throws {
        let positioned = try layout("""
        sequenceDiagram
            participant U
            participant API
            U->>API: a
            deactivate API
        """)

        XCTAssertTrue(positioned.activations.isEmpty)
    }

    // MARK: - Arrows meet the bar, not the lifeline under it

    /// An activation bar covers its lifeline, so an arrow drawn to the lifeline's centre
    /// ends up buried inside the bar. Arrows terminate on the bar's edge instead — except
    /// where no bar is open at that row, which still means the lifeline itself.

    private func message(_ label: String, in positioned: PositionedSequenceDiagram) throws -> PositionedSequenceMessage {
        try XCTUnwrap(positioned.messages.first { $0.label == label })
    }

    private func lifelineX(_ actorId: String, in positioned: PositionedSequenceDiagram) throws -> Double {
        try XCTUnwrap(positioned.lifelines.first { $0.actorId == actorId }).x
    }

    private static let activatedRun = """
    sequenceDiagram
        participant U as User
        participant API
        participant DB
        U->>API: before
        activate API
        API->>DB: rightwards
        DB-->>API: leftwards
        API->>API: self
        API-->>U: outwards
        deactivate API
    """

    func testAnArrowLeavingAnActivatedActorStartsAtTheBarEdge() throws {
        let positioned = try layout(Self.activatedRun)
        let bar = try XCTUnwrap(positioned.activations.first { $0.actorId == "API" })

        let rightwards = try message("rightwards", in: positioned)
        XCTAssertEqual(rightwards.x1, bar.x + bar.width, accuracy: 0.001)

        let outwards = try message("outwards", in: positioned)
        XCTAssertEqual(outwards.x1, bar.x, accuracy: 0.001, "a leftward arrow leaves the left edge")
    }

    func testAnArrowArrivingAtAnActivatedActorStopsAtTheBarEdge() throws {
        let positioned = try layout(Self.activatedRun)
        let bar = try XCTUnwrap(positioned.activations.first { $0.actorId == "API" })

        let leftwards = try message("leftwards", in: positioned)
        XCTAssertEqual(leftwards.x2, bar.x + bar.width, accuracy: 0.001)
    }

    func testWithNoBarOpenTheArrowStillMeetsTheLifeline() throws {
        let positioned = try layout(Self.activatedRun)
        let before = try message("before", in: positioned)

        XCTAssertEqual(before.x2, try lifelineX("API", in: positioned), accuracy: 0.001,
                       "`before` precedes the activation, so there is no bar to meet")
    }

    func testASelfMessageLeavesAndReturnsOnTheBarEdge() throws {
        let positioned = try layout(Self.activatedRun)
        let bar = try XCTUnwrap(positioned.activations.first { $0.actorId == "API" })
        let selfMessage = try message("self", in: positioned)

        XCTAssertEqual(selfMessage.x1, bar.x + bar.width, accuracy: 0.001)
        XCTAssertEqual(selfMessage.x2, bar.x + bar.width, accuracy: 0.001)
    }

    /// An activating arrow creates the bar it points at, so it has to land on it rather
    /// than pass through where the bar is about to be.
    func testAnActivatingArrowLandsOnTheBarItOpens() throws {
        let positioned = try layout("""
        sequenceDiagram
            participant U
            participant API
            U->>+API: opens it
            API-->>-U: closes it
        """)
        let bar = try XCTUnwrap(positioned.activations.first)
        let opening = try message("opens it", in: positioned)

        XCTAssertEqual(opening.x2, bar.x, accuracy: 0.001)
        XCTAssertNotEqual(opening.x2, try lifelineX("API", in: positioned))
    }

    // MARK: - Placement

    /// The layout hands over the bar's left edge, having already taken half its width off
    /// the lifeline centre. CoreGraphics subtracted that a second time, so every bar hung
    /// to the left of its lifeline instead of straddling it; SVG never did.
    func testTheBarStraddlesItsLifeline() throws {
        let positioned = try layout("""
        sequenceDiagram
            participant U
            participant API
            U->>+API: a
            API-->>-U: b
        """)

        let bar = try XCTUnwrap(positioned.activations.first)
        let lifeline = try XCTUnwrap(positioned.lifelines.first { $0.actorId == "API" })

        XCTAssertEqual(bar.x + bar.width / 2, lifeline.x, accuracy: 0.001)
    }

    func testBothRenderersPlaceTheBarAtTheSameX() throws {
        let source = """
        sequenceDiagram
            participant U
            participant API
            U->>+API: a
            API-->>-U: b
        """
        let positioned = try layout(source)
        let bar = try XCTUnwrap(positioned.activations.first)

        let svg = try renderMermaidSVG(source)
        let rect = try XCTUnwrap(svg.components(separatedBy: "class=\"activation\"").dropFirst().first)
        let x = try XCTUnwrap(rect.components(separatedBy: "x=\"").dropFirst().first?
            .components(separatedBy: "\"").first)

        XCTAssertEqual(try XCTUnwrap(Double(x)), bar.x, accuracy: 0.001)
    }
}
