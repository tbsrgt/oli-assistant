import SwiftUI

// MARK: - Oli, la mascotte
// A four-pointed star (tips up, down, left, right), a dark glossy visor with two glowing eyes,
// and a little satellite. Drawn with Canvas; animated only while on screen.

struct OliMascot: View {
    var mood: Mood
    var panic: Bool = false
    var size: CGFloat = 44

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                OliPainter(mood: mood, panic: panic, t: t).draw(in: &ctx, size: sz)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Oli")
    }
}

/// Pure drawing so the same Oli can be rendered at any size.
struct OliPainter {
    let mood: Mood
    let panic: Bool
    let t: Double

    // Body radius r(θ): 1 at the four tips, 0.56 between them.
    static func radius(_ a: Double) -> Double { 1 - 0.44 * pow(abs(sin(2 * a)), 0.85) }

    private var colors: (top: Color, bottom: Color, glow: Color) {
        switch mood {
        case .alarm:   return (Color(rgb: 0xFF6B6B), Color(rgb: 0xB0102B), Palette.alerte)
        case .waiting: return (Color(rgb: 0xFF9A55), Color(rgb: 0xE8461E), Palette.beurre)
        default:       return (Color(rgb: 0xFF8A4C), Color(rgb: 0xE04A1F), Palette.tomate)
        }
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height)
        let R = s * 0.36
        var cx = size.width / 2, cy = size.height / 2 + s * 0.03

        // Motion per mood
        var tilt = 0.0, squash = 1.0
        switch mood {
        case .calm:
            cy += sin(t * 1.6) * s * 0.025
        case .busy:
            cy += sin(t * 3.2) * s * 0.02
            tilt = sin(t * 2.4) * 0.06
        case .waiting:
            let hop = max(0, sin(t * 5.5))
            cy -= hop * s * 0.06
            squash = 1 - 0.06 * (1 - hop)
        case .happy:
            let b = abs(sin(t * 7))
            cy -= b * s * 0.05
            squash = 0.94 + 0.08 * b
        case .alarm:
            let amp = panic ? 0.055 : 0.018
            cx += (sin(t * 47) * 0.7 + sin(t * 29) * 0.3) * s * amp
            tilt = sin(t * (panic ? 13 : 5)) * (panic ? 0.16 : 0.05)
        }

        // Glow
        let c = colors
        let glowR = R * 1.5
        ctx.fill(Path(ellipseIn: CGRect(x: cx - glowR, y: cy - glowR, width: glowR * 2, height: glowR * 2)),
                 with: .radialGradient(Gradient(colors: [c.glow.opacity(mood == .alarm ? 0.45 : 0.22), .clear]),
                                       center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: glowR))

        var body = ctx
        body.translateBy(x: cx, y: cy)
        body.rotate(by: .radians(tilt))
        body.scaleBy(x: 1 / squash.squareRoot(), y: squash)

        // Star body
        var star = Path()
        let steps = 160
        for i in 0...steps {
            let a = Double(i) / Double(steps) * 2 * .pi
            let r = Self.radius(a) * R
            let p = CGPoint(x: cos(a) * r, y: sin(a) * r)
            i == 0 ? star.move(to: p) : star.addLine(to: p)
        }
        star.closeSubpath()
        body.fill(star, with: .linearGradient(Gradient(colors: [c.top, c.bottom]),
                                              startPoint: CGPoint(x: -R * 0.5, y: -R), endPoint: CGPoint(x: R * 0.5, y: R)))
        body.fill(Path(ellipseIn: CGRect(x: -R * 0.45, y: -R * 0.62, width: R * 0.5, height: R * 0.32)),
                  with: .color(.white.opacity(0.16)))

        // Visor
        let vw = R * 0.98, vh = R * 0.5
        let visor = Path(roundedRect: CGRect(x: -vw / 2, y: -vh / 2 + R * 0.04, width: vw, height: vh), cornerRadius: vh / 2)
        body.fill(visor, with: .linearGradient(Gradient(colors: [Color(rgb: 0x2A2A2E), Color(rgb: 0x0B0B0D)]),
                                               startPoint: CGPoint(x: 0, y: -vh / 2), endPoint: CGPoint(x: 0, y: vh / 2)))
        drawEyes(&body, R: R, visorY: R * 0.04)

        // Satellite
        drawSatellite(&ctx, cx: cx, cy: cy, R: R, s: s)

        // Panic extras: sweat drop
        if mood == .alarm && panic {
            let phase = (t * 1.6).truncatingRemainder(dividingBy: 1)
            let dx = cx + R * 0.95, dy = cy - R * 0.55 + phase * R * 0.9
            var drop = Path()
            drop.move(to: CGPoint(x: dx, y: dy - s * 0.06))
            drop.addQuadCurve(to: CGPoint(x: dx, y: dy + s * 0.03), control: CGPoint(x: dx + s * 0.05, y: dy))
            drop.addQuadCurve(to: CGPoint(x: dx, y: dy - s * 0.06), control: CGPoint(x: dx - s * 0.05, y: dy))
            ctx.fill(drop, with: .color(Palette.ciel.opacity(1 - phase)))
        }
    }

    private func drawEyes(_ ctx: inout GraphicsContext, R: Double, visorY: Double) {
        let eye = Color(rgb: 0xFFF4E2)
        let gap = R * 0.22
        // Blink every few seconds, never while panicking
        let blinkPhase = (t * 0.27).truncatingRemainder(dividingBy: 1)
        let blinking = mood != .alarm && blinkPhase > 0.965
        var look = 0.0, lookY = 0.0
        switch mood {
        case .busy:    look = sin(t * 1.3) * R * 0.08
        case .waiting: lookY = -R * 0.05
        default: break
        }
        for side in [-1.0, 1.0] {
            let x = side * gap + look, y = visorY + lookY
            if mood == .happy {
                var arc = Path()
                arc.addArc(center: CGPoint(x: x, y: y + R * 0.05), radius: R * 0.09,
                           startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                ctx.stroke(arc, with: .color(eye), style: StrokeStyle(lineWidth: R * 0.07, lineCap: .round))
                continue
            }
            let wide = mood == .alarm && panic
            let w = R * (wide ? 0.17 : 0.13)
            let h = blinking ? R * 0.03 : R * (wide ? 0.34 : 0.28)
            let rect = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
            var glow = ctx
            glow.addFilter(.blur(radius: R * 0.06))
            glow.fill(Path(roundedRect: rect, cornerRadius: w / 2), with: .color(eye.opacity(0.7)))
            ctx.fill(Path(roundedRect: rect, cornerRadius: w / 2), with: .color(eye))
        }
    }

    private func drawSatellite(_ ctx: inout GraphicsContext, cx: Double, cy: Double, R: Double, s: Double) {
        var x = cx + R * 0.95, y = cy - R * 0.95
        var r = s * 0.045
        var color = Palette.tomate
        switch mood {
        case .busy:
            let a = t * 3.4
            x = cx + cos(a) * R * 1.25; y = cy + sin(a) * R * 1.25 * 0.55
        case .waiting:
            r *= 1 + 0.35 * abs(sin(t * 4)); color = Palette.beurre
        case .happy:
            color = Palette.beurre
        case .alarm:
            color = Palette.alerte; r *= 1 + 0.4 * abs(sin(t * 9))
        case .calm:
            x += sin(t * 0.9) * R * 0.08; y += cos(t * 1.1) * R * 0.06
        }
        ctx.fill(Path(ellipseIn: CGRect(x: x - r * 1.8, y: y - r * 1.8, width: r * 3.6, height: r * 3.6)),
                 with: .radialGradient(Gradient(colors: [color.opacity(0.45), .clear]), center: CGPoint(x: x, y: y),
                                       startRadius: 0, endRadius: r * 1.8))
        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color))
    }
}
