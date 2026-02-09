#!/usr/bin/env swift

import AppKit
import CoreGraphics

// TimeState struct
struct TimeState {
    let hours: Int
    let minutes: Int
    let seconds: Int
    let secondFraction: Double
    let isPaused: Bool
}

// Simplified ClockRenderer for preview generation
class PreviewRenderer {
    private let faceColor = NSColor.white
    private let markerColor = NSColor.black
    private let handColor = NSColor.black
    private let secondHandColor = NSColor(calibratedRed: 218.0/255.0, green: 41.0/255.0, blue: 28.0/255.0, alpha: 1.0)
    private let centerDotColor = NSColor.black

    private let hourMarkerLength: CGFloat = 0.14
    private let hourMarkerWidth: CGFloat = 0.058
    private let hourHandLength: CGFloat = 0.52
    private let hourHandWidth: CGFloat = 0.07
    private let minuteHandLength: CGFloat = 0.76
    private let minuteHandWidth: CGFloat = 0.055
    private let secondHandLength: CGFloat = 0.72
    private let secondHandTailLength: CGFloat = 0.20
    private let secondHandWidth: CGFloat = 0.018
    private let secondHandBallRadius: CGFloat = 0.065

    func render(size: CGSize, timeState: TimeState) -> NSImage? {
        let image = NSImage(size: size)
        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }

        let rect = CGRect(origin: .zero, size: size)
        let margin: CGFloat = size.height * 0.05
        let availableHeight = size.height - (margin * 2)
        let availableWidth = size.width
        let clockDiameter = min(availableWidth, availableHeight)
        let radius = clockDiameter / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // Black background
        context.setFillColor(NSColor.black.cgColor)
        context.fill(rect)

        // Clock face
        let faceRect = CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)
        context.setFillColor(faceColor.cgColor)
        context.fillEllipse(in: faceRect)

        // Glass effect
        drawGlassEffect(context: context, center: center, radius: radius)

        // Hour markers
        drawHourMarkers(context: context, center: center, radius: radius)

        // Hands
        drawHourHand(context: context, center: center, radius: radius, timeState: timeState)
        drawMinuteHand(context: context, center: center, radius: radius, timeState: timeState)
        drawSecondHand(context: context, center: center, radius: radius, timeState: timeState)

        // Center cap
        let capRadius = radius * 0.035
        let capRect = CGRect(x: center.x - capRadius, y: center.y - capRadius,
                            width: capRadius * 2, height: capRadius * 2)
        context.setFillColor(centerDotColor.cgColor)
        context.fillEllipse(in: capRect)

        image.unlockFocus()
        return image
    }

    private func drawGlassEffect(context: CGContext, center: CGPoint, radius: CGFloat) {
        context.saveGState()
        let clipRect = CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)
        context.addEllipse(in: clipRect)
        context.clip()

        let highlightCenter = CGPoint(x: center.x - radius * 0.3, y: center.y + radius * 0.3)
        let highlightRadius = radius * 0.9
        let colors = [NSColor(white: 1.0, alpha: 0.15).cgColor, NSColor(white: 1.0, alpha: 0.0).cgColor]
        let locations: [CGFloat] = [0.0, 1.0]

        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors as CFArray, locations: locations) {
            context.drawRadialGradient(gradient, startCenter: highlightCenter, startRadius: 0,
                                       endCenter: highlightCenter, endRadius: highlightRadius, options: [])
        }

        let edgeColors = [NSColor(white: 0.0, alpha: 0.0).cgColor, NSColor(white: 0.0, alpha: 0.08).cgColor]
        let edgeLocations: [CGFloat] = [0.85, 1.0]
        if let edgeGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: edgeColors as CFArray, locations: edgeLocations) {
            context.drawRadialGradient(edgeGradient, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: radius, options: [])
        }
        context.restoreGState()
    }

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
            let path = CGPath(roundedRect: markerRect, cornerWidth: markerWidth * 0.1,
                             cornerHeight: markerWidth * 0.1, transform: nil)
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }
    }

    private func drawHourHand(context: CGContext, center: CGPoint, radius: CGFloat, timeState: TimeState) {
        let hourAngle = .pi / 2 - (CGFloat(timeState.hours) + CGFloat(timeState.minutes) / 60.0) * (.pi / 6)
        drawHand(context: context, center: center, radius: radius, angle: hourAngle,
                 length: hourHandLength, width: hourHandWidth, tailLength: 0.14, color: handColor)
    }

    private func drawMinuteHand(context: CGContext, center: CGPoint, radius: CGFloat, timeState: TimeState) {
        let minuteAngle = .pi / 2 - CGFloat(timeState.minutes) * (.pi / 30)
        drawHand(context: context, center: center, radius: radius, angle: minuteAngle,
                 length: minuteHandLength, width: minuteHandWidth, tailLength: 0.16, color: handColor)
    }

    private func drawSecondHand(context: CGContext, center: CGPoint, radius: CGFloat, timeState: TimeState) {
        let totalSeconds = CGFloat(timeState.seconds) + CGFloat(timeState.secondFraction)
        let secondAngle = .pi / 2 - totalSeconds * (.pi / 30)

        let handLength = radius * secondHandLength
        let tailLength = radius * secondHandTailLength
        let lineWidth = radius * secondHandWidth
        let ballRadius = radius * secondHandBallRadius

        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: secondAngle)

        context.setStrokeColor(secondHandColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.butt)

        let ballCenterX = handLength - ballRadius
        context.move(to: CGPoint(x: -tailLength, y: 0))
        context.addLine(to: CGPoint(x: ballCenterX - ballRadius * 0.3, y: 0))
        context.strokePath()

        context.setFillColor(secondHandColor.cgColor)
        let ballRect = CGRect(x: ballCenterX - ballRadius, y: -ballRadius,
                             width: ballRadius * 2, height: ballRadius * 2)
        context.fillEllipse(in: ballRect)
        context.restoreGState()
    }

    private func drawHand(context: CGContext, center: CGPoint, radius: CGFloat,
                          angle: CGFloat, length: CGFloat, width: CGFloat,
                          tailLength: CGFloat, color: NSColor) {
        let handLength = radius * length
        let handWidth = radius * width
        let tail = radius * tailLength

        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: angle)

        let path = CGMutablePath()
        let halfWidth = handWidth / 2
        path.move(to: CGPoint(x: -tail, y: halfWidth))
        path.addLine(to: CGPoint(x: -tail, y: -halfWidth))
        path.addLine(to: CGPoint(x: handLength - halfWidth, y: -halfWidth))
        path.addArc(center: CGPoint(x: handLength - halfWidth, y: 0), radius: halfWidth,
                    startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        path.addLine(to: CGPoint(x: -tail, y: halfWidth))
        path.closeSubpath()

        context.setFillColor(color.cgColor)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
    }
}

// Generate preview at 10:10:30
let renderer = PreviewRenderer()
let timeState = TimeState(hours: 10, minutes: 10, seconds: 30, secondFraction: 0, isPaused: false)

// Generate both 1x and 2x versions
let sizes = [(512, "thumbnail.png"), (1024, "thumbnail@2x.png")]

for (dimension, filename) in sizes {
    let size = CGSize(width: dimension, height: dimension)
    if let image = renderer.render(size: size, timeState: timeState) {
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: "/Users/dave/gt/MultiMonitorWebsite/MultiMonitorWebsite/\(filename)")
            try? pngData.write(to: url)
            print("Generated \(filename)")
        }
    }
}

print("Done!")
