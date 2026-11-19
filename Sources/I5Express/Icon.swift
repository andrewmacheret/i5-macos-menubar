import AppKit
import I5Core
import SwiftUI

extension LaneStatus {
    var nsColor: NSColor {
        switch self {
        case .northbound: .systemGreen
        case .southbound: .systemBlue
        case .closed: .systemRed
        case .unknown: .systemGray
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// Closed reads better as a quiet gray on the timeline
    var timelineColor: Color {
        self == .closed ? Color.secondary.opacity(0.22) : color
    }
}

enum Icon {
    /// The icon for the current trust state. A direction only shows when it's confirmed.
    static func current(_ check: Assessment, height: CGFloat, soon: Bool) -> NSImage {
        switch check.verdict {
        case .confident: badge(check.scheduled, height: height, soon: soon)
        case .checking: badge(.unknown, height: height)
        case .uncertain: warning(height: height)
        }
    }

    /// An amber warning triangle, shaped differently from the badges so it can't be misread.
    static func warning(height: CGFloat = 16) -> NSImage {
        let size = NSSize(width: round(height * 1.15), height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            let w = rect.width, h = rect.height
            let tri = NSBezierPath()
            tri.move(to: NSPoint(x: w / 2, y: h - 0.5))
            tri.line(to: NSPoint(x: w - 0.5, y: 0.5))
            tri.line(to: NSPoint(x: 0.5, y: 0.5))
            tri.close()
            tri.lineJoinStyle = .round
            tri.lineWidth = height * 0.12
            NSColor.systemOrange.setFill()
            NSColor.systemOrange.setStroke()
            tri.fill()
            tri.stroke()

            let font = NSFont.systemFont(ofSize: height * 0.66, weight: .black)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let text = "!" as NSString
            let ts = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: rect.midX - ts.width / 2, y: h * 0.42 - ts.height / 2), withAttributes: attrs)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "I-5 express lanes status can't be confirmed"
        return image
    }

    /// A colored rounded badge with a white N, S or ✕.
    /// `soon` adds a small amber dot when the lanes are about to flip.
    static func badge(_ status: LaneStatus, height: CGFloat = 16, soon: Bool = false) -> NSImage {
        let size = NSSize(width: round(height * 1.15), height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            let body = rect.insetBy(dx: 0.5, dy: 0.5)
            let radius = height * 0.26
            status.nsColor.setFill()
            NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius).fill()

            let font = NSFont.systemFont(ofSize: height * (status == .closed ? 0.62 : 0.74), weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let text = status.letter as NSString
            let textSize = text.size(withAttributes: attrs)
            let origin = NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2 + height * 0.02)
            text.draw(at: origin, withAttributes: attrs)

            if soon {
                let d = height * 0.34
                let dot = NSRect(x: rect.maxX - d, y: rect.maxY - d, width: d, height: d)
                NSColor.white.setFill()
                NSBezierPath(ovalIn: dot).fill()
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: dot.insetBy(dx: d * 0.18, dy: d * 0.18)).fill()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "I-5 express lanes \(status.title.lowercased())"
        return image
    }
}
