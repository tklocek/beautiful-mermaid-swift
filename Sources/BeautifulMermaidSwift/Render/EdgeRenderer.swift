import Foundation
import CoreGraphics

public class EdgeRenderer {

    let config: RenderConfig

    public init(config: RenderConfig = RenderConfig.shared) {
        self.config = config
    }

    public func drawEdgePath(
        points: [CGPoint],
        style: EdgeStyle,
        in context: CGContext,
        theme: DiagramTheme
    ) {
        guard points.count >= 2 else { return }

        let color = theme.edgeColor(for: style)
        let baseLineWidth = config.strokeWidthConnector
        let lineWidth = style.strokeWidth ?? (baseLineWidth * style.lineStyle.widthMultiplier)

        // An arrowed end stops where that end's apex does. Run the line to its own last
        // point instead and the round cap shows past the apex as a spike, the head being
        // inset by `arrowHeadTipInset` and the line not.
        let reach = config.arrowHeadTipInset + lineWidth / 2
        let drawn = trimming(
            points,
            start: style.sourceArrow == .none ? 0 : reach,
            end: style.targetArrow == .none ? 0 : reach
        )
        guard drawn.count >= 2 else { return }

        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if let pattern = style.lineStyle.dashPattern {
            context.setLineDash(phase: 0, lengths: pattern)
        }

        context.move(to: drawn[0])
        for i in 1..<drawn.count {
            context.addLine(to: drawn[i])
        }
        context.strokePath()
        context.restoreGState()
    }

    public func drawArrowHeads(
        points: [CGPoint],
        style: EdgeStyle,
        in context: CGContext,
        theme: DiagramTheme
    ) {
        guard points.count >= 2 else { return }

        let arrowColor = style.color != nil ? theme.edgeColor(for: style) : theme.effectiveArrow()
        let baseLineWidth = config.strokeWidthConnector
        let lineWidth = style.strokeWidth ?? (baseLineWidth * style.lineStyle.widthMultiplier)

        let inset = config.arrowHeadTipInset

        if style.targetArrow != .none {
            let p0 = points[points.count - 2]
            let p1 = points[points.count - 1]
            let angle = atan2(p1.y - p0.y, p1.x - p0.x)
            let tip = retreating(from: p1, towards: p0, by: inset)
            drawArrowHead(style.targetArrow, at: tip, angle: angle, lineWidth: lineWidth, color: arrowColor, in: context)
        }

        if style.sourceArrow != .none {
            let p0 = points[1]
            let p1 = points[0]
            let angle = atan2(p1.y - p0.y, p1.x - p0.x)
            let tip = retreating(from: p1, towards: p0, by: inset)
            drawArrowHead(style.sourceArrow, at: tip, angle: angle, lineWidth: lineWidth, color: arrowColor, in: context)
        }
    }

    // MARK: - Endpoint geometry

    /// `point` pulled `distance` back along the segment arriving at it.
    func retreating(from point: CGPoint, towards previous: CGPoint, by distance: CGFloat) -> CGPoint {
        let dx = point.x - previous.x
        let dy = point.y - previous.y
        let length = hypot(dx, dy)
        guard length > 0 else { return point }
        let fraction = min(distance, length) / length
        return CGPoint(x: point.x - dx * fraction, y: point.y - dy * fraction)
    }

    /// The polyline with `start` and `end` worth of length taken off its two ends.
    ///
    /// Returned untouched when the edge is too short to give that up: a line poking past
    /// an arrow head is a smaller blemish than an edge that disappears.
    func trimming(_ points: [CGPoint], start: CGFloat, end: CGFloat) -> [CGPoint] {
        guard start > 0 || end > 0 else { return points }
        let length = zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        guard length > start + end else { return points }

        var result = points
        if start > 0 {
            result = trimmingFront(result, by: start)
        }
        if end > 0 {
            result = Array(trimmingFront(Array(result.reversed()), by: end).reversed())
        }
        return result
    }

    /// `points` with `distance` taken off the front, dropping whatever corners it passes.
    func trimmingFront(_ points: [CGPoint], by distance: CGFloat) -> [CGPoint] {
        var points = points
        var remaining = distance
        while points.count >= 2 {
            let dx = points[1].x - points[0].x
            let dy = points[1].y - points[0].y
            let length = hypot(dx, dy)
            if length > remaining {
                let fraction = remaining / length
                points[0] = CGPoint(x: points[0].x + dx * fraction, y: points[0].y + dy * fraction)
                break
            }
            remaining -= length
            points.removeFirst()
        }
        return points
    }

    private func drawArrowHead(
        _ style: ArrowHead,
        at point: CGPoint,
        angle: CGFloat,
        lineWidth: CGFloat,
        color: BMColor,
        in context: CGContext
    ) {
        let config = config
        let arrowWidth = config.arrowHeadWidth
        let arrowHeight = config.arrowHeadHeight

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.rotate(by: angle)
        context.setFillColor(color.cgColor)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)

        switch style {
        case .none:
            break

        case .arrow:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: -arrowWidth, y: -arrowHeight / 2))
            path.addLine(to: CGPoint(x: -arrowWidth, y: arrowHeight / 2))
            path.closeSubpath()
            context.setLineJoin(.round)
            context.setLineWidth(0.75)
            context.addPath(path)
            context.drawPath(using: .fillStroke)

        case .open:
            context.move(to: CGPoint(x: -arrowWidth, y: -arrowHeight / 2))
            context.addLine(to: CGPoint(x: 0, y: 0))
            context.addLine(to: CGPoint(x: -arrowWidth, y: arrowHeight / 2))
            context.strokePath()

        case .circle:
            let circleSize = arrowHeight * 0.8
            context.addEllipse(in: CGRect(x: -circleSize - lineWidth, y: -circleSize / 2, width: circleSize, height: circleSize))
            context.fillPath()

        case .cross:
            let crossSize = arrowHeight * 0.4
            context.move(to: CGPoint(x: -crossSize * 2 - lineWidth, y: -crossSize))
            context.addLine(to: CGPoint(x: -lineWidth, y: crossSize))
            context.move(to: CGPoint(x: -crossSize * 2 - lineWidth, y: crossSize))
            context.addLine(to: CGPoint(x: -lineWidth, y: -crossSize))
            context.strokePath()

        case .diamond:
            let diamondWidth = arrowWidth * 1.2
            let diamondHeight = arrowHeight
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: -diamondWidth / 2, y: -diamondHeight / 2))
            path.addLine(to: CGPoint(x: -diamondWidth, y: 0))
            path.addLine(to: CGPoint(x: -diamondWidth / 2, y: diamondHeight / 2))
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
        }

        context.restoreGState()
    }
}

// MARK: - LineStyle Extensions

extension LineStyle {
    public var dashPattern: [CGFloat]? {
        switch self {
        case .solid, .thick: return nil
        case .dotted: return [2, 4]
        case .dashed: return [8, 4]
        }
    }

    public var widthMultiplier: CGFloat {
        self == .thick ? 2.0 : 1.0
    }
}
