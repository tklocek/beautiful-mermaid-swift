import XCTest
import CoreGraphics
@testable import BeautifulMermaid

/// An edge's last point sits on the target's boundary, and flowchart nodes are painted
/// after the edges that reach them. An arrow head whose apex was left on that point had
/// half the node's border stroke painted back over it — plus the overhang of its own
/// outline — and came out flat-topped: an arrow that reads as cut off rather than
/// pointed, ending under the node instead of at it.
final class ArrowHeadInsetTests: XCTestCase {

    private let config = RenderConfig.shared
    private lazy var renderer = EdgeRenderer(config: config)

    // MARK: - Ink

    /// Points per side of the test canvas, and the edge drawn down the middle of it.
    private static let canvas = CGSize(width: 40, height: 80)
    private static let start = CGPoint(x: 20, y: 8)
    private static let endpoint = CGPoint(x: 20, y: 64)
    /// Pixels per point. High enough that the antialiased fringe is under a tenth of a
    /// point, so it cannot swallow the distances being asserted.
    private static let scale: CGFloat = 16

    /// The deepest y, in canvas points, carrying any ink once `style` is drawn along
    /// `points`. Everything drawn here is grey on white, so one channel decides it.
    private func deepestInk(
        _ style: EdgeStyle,
        along points: [CGPoint] = [ArrowHeadInsetTests.start, ArrowHeadInsetTests.endpoint]
    ) throws -> CGFloat {
        let scale = Self.scale
        let width = Int(Self.canvas.width * scale)
        let height = Int(Self.canvas.height * scale)
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // The flip a host view applies, so canvas coordinates run top-down the way the
        // layout's do — and so bitmap row `r` is canvas y `r / scale`.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)

        renderer.drawEdgePath(points: points, style: style, in: context, theme: .default)
        renderer.drawArrowHeads(points: points, style: style, in: context, theme: .default)

        let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: width * height * 4)
        let inked = (0..<height).last { row in
            (0..<width).contains { column in pixels[(row * width + column) * 4] < 250 }
        }
        return CGFloat(try XCTUnwrap(inked, "nothing was drawn")) / scale
    }

    /// How far outside the target's boundary the node's own border stroke reaches. Ink
    /// left inside that is ink the node paints over.
    private var borderReach: CGFloat { config.strokeWidthInnerBox / 2 }

    func testArrowedEndStopsClearOfTheBorderTheNodePaints() throws {
        let deepest = try deepestInk(EdgeStyle(targetArrow: .arrow))
        XCTAssertLessThan(
            deepest,
            Self.endpoint.y - borderReach,
            "the arrow head reaches into the border stroke, which is painted over it"
        )
    }

    func testArrowedEndStillMeetsTheNodeItPointsAt() throws {
        let deepest = try deepestInk(EdgeStyle(targetArrow: .arrow))
        XCTAssertGreaterThan(
            deepest,
            Self.endpoint.y - borderReach - 1,
            "the arrow head has backed off far enough to float clear of its target"
        )
    }

    /// Only arrowed ends are pulled back: a bare end has nothing to make room for, and a
    /// line stopping short of its node would read as a broken connection.
    func testBareEndRunsAllTheWayToItsPoint() throws {
        let deepest = try deepestInk(EdgeStyle(targetArrow: .none))
        XCTAssertGreaterThanOrEqual(deepest, Self.endpoint.y)
    }

    /// The line has to be shortened along with the head. Left at full length its round
    /// cap shows past the inset apex as a spike.
    func testConnectorDoesNotOutrunTheHeadItFeeds() throws {
        let withHead = try deepestInk(EdgeStyle(targetArrow: .arrow))
        let headAlone = try deepestInk(EdgeStyle(lineStyle: .thick, targetArrow: .arrow))
        XCTAssertEqual(
            withHead,
            headAlone,
            accuracy: 0.1,
            "a thicker line reaches further than the head, so the line is setting the depth"
        )
    }

    // MARK: - Geometry

    func testRetreatingMovesBackAlongTheArrivingSegment() {
        let tip = renderer.retreating(from: CGPoint(x: 10, y: 40), towards: CGPoint(x: 10, y: 0), by: 1)
        XCTAssertEqual(tip.x, 10, accuracy: 0.0001)
        XCTAssertEqual(tip.y, 39, accuracy: 0.0001)
    }

    /// A segment shorter than the inset would otherwise put the apex behind the point it
    /// came from, pointing the head backwards.
    func testRetreatingStopsAtTheSegmentItHas() {
        let tip = renderer.retreating(from: CGPoint(x: 10, y: 0.5), towards: CGPoint(x: 10, y: 0), by: 1)
        XCTAssertEqual(tip.y, 0, accuracy: 0.0001)
    }

    func testTrimmingTakesLengthOffBothEnds() {
        let trimmed = renderer.trimming([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)], start: 10, end: 25)
        XCTAssertEqual(trimmed.map(\.x), [10, 75])
    }

    /// A trim deeper than the last segment has to drop the corner it passes, or the
    /// polyline doubles back on itself.
    func testTrimmingWalksPastCorners() {
        let corner = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 20), CGPoint(x: 30, y: 20)]
        let trimmed = renderer.trimming(corner, start: 0, end: 35)
        XCTAssertEqual(trimmed.count, 2)
        XCTAssertEqual(trimmed.last?.y ?? .nan, 15, accuracy: 0.0001)
    }

    /// An edge with no length to spare keeps what it has: a stub of line poking past a
    /// head is a smaller blemish than a segment that disappears.
    func testTrimmingLeavesAnEdgeTooShortToTrim() {
        let short = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1.5)]
        XCTAssertEqual(renderer.trimming(short, start: 1, end: 1), short)
    }
}
