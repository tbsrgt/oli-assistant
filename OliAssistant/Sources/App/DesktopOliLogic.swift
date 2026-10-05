import Foundation
import CoreGraphics

// MARK: - Alert state machine phase

/// Phase of the desktop Oli lifecycle.
enum DesktopPhase: Equatable {
    /// No panel on screen; `UserDefaults["oliOnDesktop"]` is `false`.
    case home
    /// Panel animating from notch to saved desktop position.
    case flyingOut
    /// Panel live on the desktop — normal operating state.
    case onDesktop
    /// `pendingApproval`/`pendingQuestion` just went non-nil; panel animating toward notch.
    case retracting
    /// Alert cleared while retract animation was still running.
    case alertResolvedDuringRetract
    /// Retract complete; notch Oli is showing the alert.
    case atNotchForAlert
}

// MARK: - Pure geometry / logic (no AppKit — fully unit-testable)

/// Stateless helpers for `DesktopOliController`.
enum DesktopOliLogic {
    static let panelSize:          CGFloat      = 120
    static let sleepTimeout:       TimeInterval = 120
    static let sleepMouseDistance: CGFloat      = 150
    static let clampMargin:        CGFloat      = 24
    static let bodyRadiusFraction: CGFloat      = 0.24

    /// Whether Oli should enter sleeping state.
    static func shouldSleep(lastAgentActiveInterval: TimeInterval,
                             mouseDistanceToPanelCenter: CGFloat) -> Bool {
        lastAgentActiveInterval > sleepTimeout && mouseDistanceToPanelCenter >= sleepMouseDistance
    }

    /// Hit-test the circular body inside a square panel (AppKit y-up local coords).
    static func isOverBody(localPoint: CGPoint, panelSize: CGFloat) -> Bool {
        let cx = panelSize / 2
        let cy = panelSize / 2
        let r  = panelSize * bodyRadiusFraction
        let dx = localPoint.x - cx
        let dy = localPoint.y - cy
        return dx * dx + dy * dy <= r * r
    }

    /// Eye-tracking origin: panel center in screen-space with y-down from top of screen.
    /// Matches the coordinate space of `AppState.mousePosition`.
    static func lookOrigin(panelMinX:    CGFloat,
                            panelMinY:    CGFloat,
                            screenMinX:   CGFloat,
                            screenHeight: CGFloat,
                            panelSize:    CGFloat) -> CGPoint {
        let cx = panelMinX + panelSize / 2
        let cy = panelMinY + panelSize / 2
        return CGPoint(x: cx - screenMinX, y: screenHeight - cy)
    }

    /// Whether Oli should immediately retract after landing (alert was active during the flight).
    static func shouldRetractOnLanding(alertActive: Bool) -> Bool { alertActive }

    /// Clamp a panel origin so the panel stays inside `visibleFrame` with `margin` on each side.
    static func clampOrigin(_ origin:      CGPoint,
                             panelSize:    CGFloat,
                             visibleFrame: CGRect,
                             margin:       CGFloat) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, visibleFrame.minX + margin), visibleFrame.maxX - panelSize - margin),
            y: min(max(origin.y, visibleFrame.minY + margin), visibleFrame.maxY - panelSize - margin)
        )
    }
}

// MARK: - Motion (Me suit / Se promène)

/// Pure movement maths (unit-testable, no AppKit).
enum DesktopOliMotionLogic {
    /// Where Oli wants to sit when following: down-right of the cursor (AppKit y-up).
    static let followOffset = CGSize(width: 72, height: -72)
    /// Cursor this close to Oli's center: Oli stops, so he can be clicked.
    static let catchRadius: CGFloat = 70

    /// Next center when following the cursor. Returns nil when Oli should not move.
    static func followStep(center: CGPoint, mouse: CGPoint, ease: CGFloat = 0.08) -> CGPoint? {
        if hypot(mouse.x - center.x, mouse.y - center.y) < catchRadius { return nil }
        let target = CGPoint(x: mouse.x + followOffset.width, y: mouse.y + followOffset.height)
        let dx = target.x - center.x, dy = target.y - center.y
        guard hypot(dx, dy) > 2 else { return nil }
        return CGPoint(x: center.x + dx * ease, y: center.y + dy * ease)
    }

    /// One step toward `target` at `speed` px per frame, slowing down on arrival.
    static func walkStep(center: CGPoint, target: CGPoint, speed: CGFloat = 1.8) -> CGPoint? {
        let dx = target.x - center.x, dy = target.y - center.y
        let d = hypot(dx, dy)
        guard d > 1.5 else { return nil }
        let v = min(speed, max(0.6, d * 0.06))
        return CGPoint(x: center.x + dx / d * v, y: center.y + dy / d * v)
    }

    /// A random spot within `radius` of `center`, kept inside `bounds` (center coordinates).
    static func wanderTarget(from center: CGPoint, bounds: CGRect, radius: CGFloat = 280,
                             random: () -> CGFloat = { CGFloat.random(in: 0...1) }) -> CGPoint {
        let angle = random() * 2 * .pi
        let dist = 80 + random() * (radius - 80)
        let p = CGPoint(x: center.x + cos(angle) * dist, y: center.y + sin(angle) * dist)
        return CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
    }
}
