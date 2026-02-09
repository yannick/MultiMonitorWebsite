import AppKit
import CoreGraphics

class ClockRenderer {

    // MARK: - Static Content Cache
    // Pre-rendered image containing bezel, face, markers, and glass effect
    // Only the hands need to be drawn each frame
    private var cachedStaticContent: CGImage?
    private var cachedSize: CGSize = .zero
    private var cachedIsPreview: Bool = false
    private var cachedClearBackground: Bool = false

    // SBB Official Colors (Pantone 485 C for red)
    private let faceColor = NSColor.white
    private let markerColor = NSColor.black
    private let handColor = NSColor.black
    // SBB Red: Pantone 485 C = #DA291C
    private let secondHandColor = NSColor(calibratedRed: 218.0/255.0, green: 41.0/255.0, blue: 28.0/255.0, alpha: 1.0)

    // Bezel colors (brushed aluminum)
    private let bezelColor = NSColor(calibratedRed: 200.0/255.0, green: 200.0/255.0, blue: 205.0/255.0, alpha: 1.0)
    private let bezelHighlight = NSColor(calibratedRed: 240.0/255.0, green: 240.0/255.0, blue: 245.0/255.0, alpha: 1.0)
    private let bezelShadow = NSColor(calibratedRed: 140.0/255.0, green: 140.0/255.0, blue: 145.0/255.0, alpha: 1.0)

    // Bezel thickness (relative to clock radius)
    private let bezelThickness: CGFloat = 0.08

    // Proportions matching original SBB Mondaine design (relative to clock radius)
    // Hour markers: bold rectangular blocks
    private let hourMarkerLength: CGFloat = 0.12
    private let hourMarkerWidth: CGFloat = 0.055

    // Minute markers: thin lines
    private let minuteMarkerLength: CGFloat = 0.05
    private let minuteMarkerWidth: CGFloat = 0.015

    // Hour hand
    private let hourHandLength: CGFloat = 0.66
    private let hourHandWidth: CGFloat = 0.065

    // Minute hand: reaches end of minute indicators (at 0.93)
    private let minuteHandLength: CGFloat = 0.93
    private let minuteHandWidth: CGFloat = 0.0675

    // Second hand: just inside minute indicators
    private let secondHandLength: CGFloat = 0.81
    private let secondHandTailLength: CGFloat = 0.18
    private let secondHandWidth: CGFloat = 0.022
    private let secondHandBallRadius: CGFloat = 0.07  // The iconic red ball

    // Hand shadows (light from upper-left, shadow falls lower-right)
    private let shadowOffsetX: CGFloat = 0.012
    private let shadowOffsetY: CGFloat = -0.012
    private let shadowBlur: CGFloat = 0.025  // Blur radius relative to clock radius
    private let shadowColor = NSColor(white: 0.0, alpha: 0.35)

    func draw(in rect: NSRect, timeState: TimeState, isPreview: Bool, clearBackground: Bool = false) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Calculate clock size with margin
        let margin: CGFloat = isPreview ? 4 : min(rect.height * 0.05, 40)
        let availableHeight = rect.height - (margin * 2)
        let availableWidth = rect.width
        let clockDiameter = min(availableWidth, availableHeight)
        let radius = clockDiameter / 2

        let centerX = rect.midX
        let centerY = rect.midY
        let center = CGPoint(x: centerX, y: centerY)
        let faceRadius = radius * (1.0 - bezelThickness)

        // Check if we need to re-render the static content cache
        if cachedStaticContent == nil || cachedSize != rect.size || cachedIsPreview != isPreview || cachedClearBackground != clearBackground {
            cachedStaticContent = renderStaticContent(rect: rect, center: center, radius: radius, faceRadius: faceRadius, isPreview: isPreview, clearBackground: clearBackground)
            cachedSize = rect.size
            cachedIsPreview = isPreview
            cachedClearBackground = clearBackground
        }

        context.saveGState()

        // Draw cached static content (background, bezel, face, markers, glass)
        if let cached = cachedStaticContent {
            context.draw(cached, in: rect)
        }

        // Draw only the dynamic content: hands and center cap
        drawHand(context: context, center: center, radius: faceRadius, angle: timeState.hourAngle,
                 length: hourHandLength, width: hourHandWidth, tailLength: 0.14, color: handColor, withShadow: true)
        drawHand(context: context, center: center, radius: faceRadius, angle: timeState.minuteAngle,
                 length: minuteHandLength, width: minuteHandWidth, tailLength: 0.16, color: handColor, withShadow: true)
        drawSecondHand(context: context, center: center, radius: faceRadius, angle: timeState.secondAngle)

        // Center cap (red to match second hand)
        drawCenterCap(context: context, center: center, radius: faceRadius)

        context.restoreGState()
    }

    // MARK: - Static Content Caching

    /// Pre-renders all static clock elements to a CGImage for efficient reuse.
    /// This eliminates per-frame rendering of: background, bezel, face, markers, glass effect.
    private func renderStaticContent(rect: NSRect, center: CGPoint, radius: CGFloat, faceRadius: CGFloat, isPreview: Bool, clearBackground: Bool = false) -> CGImage? {
        let width = Int(rect.width)
        let height = Int(rect.height)
        guard width > 0 && height > 0 else { return nil }

        // Create bitmap context for offscreen rendering
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmapContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else {
            return nil
        }

        // Background: transparent when overlaying web content, black otherwise
        if clearBackground {
            bitmapContext.clear(rect)
        } else {
            bitmapContext.setFillColor(NSColor.black.cgColor)
            bitmapContext.fill(rect)
        }

        // Brushed aluminum bezel
        drawBezel(context: bitmapContext, center: center, radius: radius)

        // Clock face (inside bezel)
        drawFace(context: bitmapContext, center: center, radius: faceRadius)

        // Minute markers (thin lines)
        drawMinuteMarkers(context: bitmapContext, center: center, radius: faceRadius)

        // Hour markers (SBB style - bold blocks)
        drawHourMarkers(context: bitmapContext, center: center, radius: faceRadius)

        // Glass reflection effect (subtle)
        drawGlassEffect(context: bitmapContext, center: center, radius: faceRadius)

        return bitmapContext.makeImage()
    }

    // MARK: - Bezel (Brushed Aluminum)

    private func drawBezel(context: CGContext, center: CGPoint, radius: CGFloat) {
        context.saveGState()

        let outerRect = CGRect(x: center.x - radius, y: center.y - radius,
                               width: radius * 2, height: radius * 2)
        let innerRadius = radius * (1.0 - bezelThickness)
        let innerRect = CGRect(x: center.x - innerRadius, y: center.y - innerRadius,
                               width: innerRadius * 2, height: innerRadius * 2)

        // Create bezel path (ring shape)
        let bezelPath = CGMutablePath()
        bezelPath.addEllipse(in: outerRect)
        bezelPath.addEllipse(in: innerRect)

        // Base bezel color
        context.addPath(bezelPath)
        context.setFillColor(bezelColor.cgColor)
        context.fillPath(using: .evenOdd)

        // Add brushed metal gradient effect
        context.saveGState()

        // Clip to bezel ring
        context.addPath(bezelPath)
        context.clip(using: .evenOdd)

        // Angular gradient simulation using multiple arcs
        // 36 segments provides visually identical results with 40% fewer draw calls
        let segments = 36
        for i in 0..<segments {
            let startAngle = CGFloat(i) * (2 * .pi / CGFloat(segments))
            let endAngle = CGFloat(i + 1) * (2 * .pi / CGFloat(segments))

            // Vary brightness based on angle to simulate brushed metal reflection
            let brightness = 0.5 + 0.5 * sin(startAngle * 2 + .pi / 4)
            let segmentColor = NSColor(
                calibratedRed: (bezelColor.redComponent * 0.8 + 0.2 * brightness),
                green: (bezelColor.greenComponent * 0.8 + 0.2 * brightness),
                blue: (bezelColor.blueComponent * 0.8 + 0.2 * brightness),
                alpha: 1.0
            )

            let segmentPath = CGMutablePath()
            segmentPath.move(to: center)
            segmentPath.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            segmentPath.addLine(to: center)
            segmentPath.closeSubpath()

            context.addPath(segmentPath)
            context.setFillColor(segmentColor.cgColor)
            context.fillPath()
        }

        context.restoreGState()

        // Add subtle inner shadow on bezel
        context.saveGState()
        context.addPath(bezelPath)
        context.clip(using: .evenOdd)

        // Inner edge highlight (top-left)
        let highlightPath = CGMutablePath()
        highlightPath.addArc(center: center, radius: innerRadius + radius * 0.01,
                            startAngle: .pi * 0.75, endAngle: .pi * 1.75, clockwise: false)
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.4).cgColor)
        context.setLineWidth(radius * 0.008)
        context.addPath(highlightPath)
        context.strokePath()

        // Inner edge shadow (bottom-right)
        let shadowPath = CGMutablePath()
        shadowPath.addArc(center: center, radius: innerRadius + radius * 0.01,
                         startAngle: -.pi * 0.25, endAngle: .pi * 0.75, clockwise: false)
        context.setStrokeColor(NSColor(white: 0.0, alpha: 0.3).cgColor)
        context.addPath(shadowPath)
        context.strokePath()

        // Outer edge effects
        let outerHighlight = CGMutablePath()
        outerHighlight.addArc(center: center, radius: radius - radius * 0.005,
                             startAngle: .pi * 0.75, endAngle: .pi * 1.75, clockwise: false)
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.5).cgColor)
        context.setLineWidth(radius * 0.01)
        context.addPath(outerHighlight)
        context.strokePath()

        context.restoreGState()
        context.restoreGState()
    }

    // MARK: - Clock Face

    private func drawFace(context: CGContext, center: CGPoint, radius: CGFloat) {
        let faceRect = CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)

        context.setFillColor(faceColor.cgColor)
        context.fillEllipse(in: faceRect)
    }

    // MARK: - Glass Effect (subtle reflection)

    private func drawGlassEffect(context: CGContext, center: CGPoint, radius: CGFloat) {
        context.saveGState()

        // Clip to clock face
        let clipRect = CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)
        context.addEllipse(in: clipRect)
        context.clip()

        // Subtle highlight in upper-left quadrant
        let highlightCenter = CGPoint(x: center.x - radius * 0.3, y: center.y + radius * 0.3)
        let highlightRadius = radius * 0.9

        let colors = [
            NSColor(white: 1.0, alpha: 0.15).cgColor,
            NSColor(white: 1.0, alpha: 0.0).cgColor
        ]
        let locations: [CGFloat] = [0.0, 1.0]

        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors as CFArray,
                                     locations: locations) {
            context.drawRadialGradient(gradient,
                                       startCenter: highlightCenter,
                                       startRadius: 0,
                                       endCenter: highlightCenter,
                                       endRadius: highlightRadius,
                                       options: [])
        }

        // Subtle edge darkening
        let edgeColors = [
            NSColor(white: 0.0, alpha: 0.0).cgColor,
            NSColor(white: 0.0, alpha: 0.08).cgColor
        ]
        let edgeLocations: [CGFloat] = [0.85, 1.0]

        if let edgeGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: edgeColors as CFArray,
                                         locations: edgeLocations) {
            context.drawRadialGradient(edgeGradient,
                                       startCenter: center,
                                       startRadius: 0,
                                       endCenter: center,
                                       endRadius: radius,
                                       options: [])
        }

        context.restoreGState()
    }

    // MARK: - Minute Markers

    private func drawMinuteMarkers(context: CGContext, center: CGPoint, radius: CGFloat) {
        context.setFillColor(markerColor.cgColor)

        for minute in 0..<60 {
            // Skip hour positions
            if minute % 5 == 0 { continue }

            let angle = .pi / 2 - CGFloat(minute) * (.pi / 30)

            let outerRadius = radius * 0.93
            let innerRadius = outerRadius - (radius * minuteMarkerLength)
            let markerWidth = radius * minuteMarkerWidth

            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: angle)

            let markerRect = CGRect(x: innerRadius, y: -markerWidth / 2,
                                   width: outerRadius - innerRadius, height: markerWidth)
            context.fill(markerRect)

            context.restoreGState()
        }
    }

    // MARK: - Hour Markers

    private func drawHourMarkers(context: CGContext, center: CGPoint, radius: CGFloat) {
        context.setFillColor(markerColor.cgColor)

        for hour in 0..<12 {
            let angle = .pi / 2 - CGFloat(hour) * (.pi / 6)

            let outerRadius = radius * 0.93
            let innerRadius = outerRadius - (radius * hourMarkerLength)
            let markerWidth = radius * hourMarkerWidth

            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: angle)

            let markerRect = CGRect(x: innerRadius, y: -markerWidth / 2,
                                   width: outerRadius - innerRadius, height: markerWidth)
            context.fill(markerRect)

            context.restoreGState()
        }
    }

    // MARK: - Hand Drawing

    private func drawHand(context: CGContext, center: CGPoint, radius: CGFloat,
                          angle: CGFloat, length: CGFloat, width: CGFloat,
                          tailLength: CGFloat, color: NSColor, withShadow: Bool = false) {
        let handLength = radius * length
        let handWidth = radius * width
        let tail = radius * tailLength

        context.saveGState()

        // Apply blurry shadow if requested
        if withShadow {
            context.setShadow(offset: CGSize(width: radius * shadowOffsetX, height: radius * shadowOffsetY),
                             blur: radius * shadowBlur,
                             color: shadowColor.cgColor)
        }

        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: angle)

        // Mondaine hands: tapered shape (thicker at base, slightly tapered at tip)
        let path = CGMutablePath()
        let baseHalfWidth = handWidth * 0.75  // wider at center end
        let tipHalfWidth = handWidth * 0.48   // wider at outer end

        path.move(to: CGPoint(x: -tail, y: baseHalfWidth))
        path.addLine(to: CGPoint(x: -tail, y: -baseHalfWidth))
        path.addLine(to: CGPoint(x: handLength, y: -tipHalfWidth))
        path.addLine(to: CGPoint(x: handLength, y: tipHalfWidth))
        path.addLine(to: CGPoint(x: -tail, y: baseHalfWidth))
        path.closeSubpath()

        context.setFillColor(color.cgColor)
        context.addPath(path)
        context.fillPath()

        context.restoreGState()
    }

    // MARK: - Second Hand

    private func drawSecondHand(context: CGContext, center: CGPoint, radius: CGFloat, angle: CGFloat) {
        let handLength = radius * secondHandLength
        let tailLength = radius * secondHandTailLength
        let lineWidth = radius * secondHandWidth
        let ballRadius = radius * secondHandBallRadius

        context.saveGState()

        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: angle)

        let ballCenterX = handLength - ballRadius
        let halfWidth = lineWidth / 2

        // Create a single combined path for shaft + ball so they share one shadow
        let combinedPath = CGMutablePath()

        // Shaft as a rectangle
        combinedPath.addRect(CGRect(x: -tailLength, y: -halfWidth,
                                    width: ballCenterX + tailLength, height: lineWidth))

        // Ball
        combinedPath.addEllipse(in: CGRect(x: ballCenterX - ballRadius, y: -ballRadius,
                                           width: ballRadius * 2, height: ballRadius * 2))

        // Apply shadow and fill the combined path
        context.setShadow(offset: CGSize(width: radius * shadowOffsetX, height: radius * shadowOffsetY),
                         blur: radius * shadowBlur,
                         color: shadowColor.cgColor)

        context.setFillColor(secondHandColor.cgColor)
        context.addPath(combinedPath)
        context.fillPath()

        context.restoreGState()
    }

    // MARK: - Center Cap

    private func drawCenterCap(context: CGContext, center: CGPoint, radius: CGFloat) {
        let capRadius = radius * 0.04
        let capRect = CGRect(x: center.x - capRadius, y: center.y - capRadius,
                            width: capRadius * 2, height: capRadius * 2)

        context.setFillColor(secondHandColor.cgColor)
        context.fillEllipse(in: capRect)
    }
}
