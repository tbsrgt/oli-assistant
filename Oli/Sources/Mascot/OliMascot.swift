import SwiftUI

// MARK: - Oli, la mascotte
// Oli's character: a soft four-pointed star (rounded astroid, tips up/down/left/right) in a tomato
// gradient, a dark glossy visor with two glowing cream eyes, and a little orange satellite at the
// top right. `tint` draws a flat-coloured mini Oli (one per section in the pill grid).

struct OliMascot: View {
    var mood: Mood
    var panic: Bool = false
    var size: CGFloat = 44
    var tint: Color? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                OliPainter(mood: mood, panic: panic, t: t, tint: tint).draw(in: &ctx, size: sz)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Oli")
    }
}

/// The star outline: superellipse-like astroid (exponent 0.70) smoothed over ±12°, tips normalised to 1.
enum StarOutline {
    static let samples = 360
    static let radii: [Double] = {
        let p = 0.70
        var raw = [Double](repeating: 0, count: samples)
        for i in 0..<samples {
            let a = Double(i) / Double(samples) * 2 * .pi
            raw[i] = 1 / pow(pow(abs(cos(a)), p) + pow(abs(sin(a)), p), 1 / p)
        }
        let k = 12                                   // ±12° of smoothing (1 sample per degree)
        var out = raw
        for i in 0..<samples {
            var s = 0.0
            for j in -k...k { s += raw[(i + j + samples) % samples] }
            out[i] = s / Double(2 * k + 1)
        }
        let m = out.max() ?? 1
        return out.map { $0 / m }
    }()

    static func path(R: Double) -> Path {
        var p = Path()
        for i in 0...samples {
            let a = Double(i % samples) / Double(samples) * 2 * .pi
            let r = radii[i % samples] * R
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

struct OliPainter {
    let mood: Mood
    let panic: Bool
    let t: Double
    var tint: Color? = nil

    static let top    = Color(rgb: 0xFF8A52)
    static let bottom = Color(rgb: 0xE8431A)
    static let eye    = Color(rgb: 0xFFF3E0)
    static let visorTop = Color(rgb: 0x2A2420)
    static let visorBottom = Color(rgb: 0x0E0C0A)
    static let satellite = Color(rgb: 0xFF7A45)

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let W = min(size.width, size.height)
        let R = W * 0.30 * 1.08
        var cx = size.width / 2
        var cy = size.height / 2 + W * 0.03
        var tilt = 0.0, sx = 1.0, sy = 1.0

        // Motion
        switch mood {
        case .calm:
            sy = 1 + sin(t * 2.2) * 0.012; sx = 2 - sy                 // slow breathing
        case .busy:
            cy += sin(t * 3) * W * 0.012
        case .waiting:
            let hop = max(0, sin(t * 5.2))
            cy -= hop * W * 0.05
            sy = 1 - 0.05 * (1 - hop); sx = 2 - sy
        case .happy:
            let b = abs(sin(t * 6.5))
            cy -= b * W * 0.04
            sy = 0.95 + 0.07 * b; sx = 2 - sy
        case .alarm:
            let amp = panic ? 0.05 : 0.016
            cx += (sin(t * 47) * 0.7 + sin(t * 29) * 0.3) * W * amp
            tilt = sin(t * (panic ? 13 : 5)) * (panic ? 0.15 : 0.05)
        }

        var body = ctx
        body.translateBy(x: cx, y: cy)
        body.rotate(by: .radians(tilt))
        body.scaleBy(x: sx, y: sy)
        let star = StarOutline.path(R: R)

        if let tint {
            // Mini Oli: flat colour, no gloss
            body.fill(star, with: .color(mood == .alarm ? Palette.alerte : tint))
        } else {
            let (c0, c1) = mood == .alarm ? (Color(rgb: 0xFF5A5F), Color(rgb: 0xB3122B)) : (Self.top, Self.bottom)
            body.fill(star, with: .linearGradient(Gradient(colors: [c0, c1]),
                                                  startPoint: CGPoint(x: R * 0.7, y: -R * 0.85),
                                                  endPoint: CGPoint(x: -R * 0.8, y: R * 0.9)))
            // shadow rim
            body.fill(star, with: .radialGradient(Gradient(stops: [.init(color: .clear, location: 0),
                                                                   .init(color: .clear, location: 0.6),
                                                                   .init(color: .black.opacity(0.2), location: 1)]),
                                                  center: .zero, startRadius: R * 0.15, endRadius: R * 1.25))
            // soft inner light
            body.fill(star, with: .radialGradient(Gradient(colors: [.white.opacity(0.20), .clear]),
                                                  center: CGPoint(x: -R * 0.15, y: -R * 0.25), startRadius: 0, endRadius: R * 0.9))
        }

        // Visor
        let k = tint == nil ? 1.0 : 1.18
        let vw = R * 1.05 * k, vh = R * 0.62 * k, vcy = R * 0.06
        let visor = Path(roundedRect: CGRect(x: -vw / 2, y: vcy - vh / 2, width: vw, height: vh), cornerRadius: vh / 2)
        body.fill(visor, with: .linearGradient(Gradient(colors: [Self.visorTop, Self.visorBottom]),
                                               startPoint: CGPoint(x: 0, y: vcy - vh / 2), endPoint: CGPoint(x: 0, y: vcy + vh / 2)))
        var gloss = body
        gloss.clip(to: visor)
        gloss.fill(Path(ellipseIn: CGRect(x: -vw * 0.42, y: vcy - vh * 0.48, width: vw * 0.84, height: vh * 0.34)),
                   with: .color(.white.opacity(0.10)))
        drawEyes(&body, R: R, k: k, vcy: vcy)

        if tint == nil { drawSatellite(&ctx, R: R, cx: cx, cy: cy) }

        if mood == .alarm && panic && tint == nil {
            let ph = (t * 1.6).truncatingRemainder(dividingBy: 1)
            let dx = cx + R * 1.05, dy = cy - R * 0.5 + ph * R * 0.8
            var drop = Path()
            drop.move(to: CGPoint(x: dx, y: dy - W * 0.06))
            drop.addQuadCurve(to: CGPoint(x: dx, y: dy + W * 0.03), control: CGPoint(x: dx + W * 0.05, y: dy))
            drop.addQuadCurve(to: CGPoint(x: dx, y: dy - W * 0.06), control: CGPoint(x: dx - W * 0.05, y: dy))
            ctx.fill(drop, with: .color(Palette.ciel.opacity(1 - ph)))
        }
    }

    private func drawEyes(_ ctx: inout GraphicsContext, R: Double, k: Double, vcy: Double) {
        let blink = mood != .alarm && (t * 0.27).truncatingRemainder(dividingBy: 1) > 0.965
        let lookX = mood == .busy ? sin(t * 1.3) * R * 0.06 : 0
        let lookY = mood == .waiting ? -R * 0.04 : 0
        let wide = mood == .alarm && panic
        let ew = R * (wide ? 0.17 : 0.14) * k
        let eh = blink ? R * 0.04 : R * (wide ? 0.40 : 0.34) * k
        for sd in [-1.0, 1.0] {
            let x = sd * R * 0.22 * k + lookX, y = vcy + lookY
            if mood == .happy {
                var arc = Path()
                arc.addArc(center: CGPoint(x: x, y: y + R * 0.06), radius: ew * 0.75,
                           startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                ctx.stroke(arc, with: .color(Self.eye), style: StrokeStyle(lineWidth: ew * 0.55, lineCap: .round))
                continue
            }
            let rect = CGRect(x: x - ew / 2, y: y - eh / 2, width: ew, height: eh)
            let pill = Path(roundedRect: rect, cornerRadius: min(ew, eh) / 2)
            var glow = ctx
            glow.addFilter(.blur(radius: R * 0.06))
            glow.opacity = 0.55
            glow.fill(pill, with: .color(Self.eye))
            ctx.fill(pill, with: .color(Self.eye))
        }
    }

    private func drawSatellite(_ ctx: inout GraphicsContext, R: Double, cx: Double, cy: Double) {
        var ang = -0.76
        var rad = R * 0.10
        var color = Self.satellite
        switch mood {
        case .busy:    ang = -0.76 + t * 1.6
        case .waiting: rad *= 1 + 0.25 * sin(t * 7)
        case .happy:   color = Palette.beurre
        case .alarm:   color = Palette.alerte; rad *= 1 + 0.3 * abs(sin(t * 9))
        case .calm:    break
        }
        let dist = R * 1.40
        let px = cx + cos(ang) * dist
        let py = cy + sin(ang) * dist + sin(t * 1.6) * R * 0.04
        ctx.fill(Path(ellipseIn: CGRect(x: px - rad * 2.4, y: py - rad * 2.4, width: rad * 4.8, height: rad * 4.8)),
                 with: .radialGradient(Gradient(colors: [color.opacity(0.35), .clear]), center: CGPoint(x: px, y: py),
                                       startRadius: 0, endRadius: rad * 2.4))
        ctx.fill(Path(ellipseIn: CGRect(x: px - rad, y: py - rad, width: rad * 2, height: rad * 2)), with: .color(color))
    }
}
