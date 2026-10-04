import SwiftUI

// MARK: - Oli, version statique pour le widget
// Reprend le dessin de BotEngine (OliShape, drawBody, drawEyes, drawSatellite) sans animation :
// l'étoile à quatre branches tomate, la visière sombre, deux yeux crème et le petit satellite.
// En alerte (un site en panne), Oli passe au rouge et ses yeux s'aplatissent, comme dans l'encoche.

enum OliWidgetColors {
    static let baseTop     = Color(red: 1.0,   green: 0.541, blue: 0.322)   // #FF8A52
    static let baseBottom  = Color(red: 0.910, green: 0.263, blue: 0.102)   // #E8431A
    static let alarmTop    = Color(red: 1.0,   green: 0.353, blue: 0.373)   // #FF5A5F
    static let alarmBottom = Color(red: 0.702, green: 0.071, blue: 0.169)   // #B3122B
    static let eyeLight    = Color(red: 1.0,   green: 0.953, blue: 0.878)   // #FFF3E0
    static let visorTop    = Color(red: 0.165, green: 0.141, blue: 0.125)   // #2A2420
    static let visorBottom = Color(red: 0.055, green: 0.047, blue: 0.039)   // #0E0C0A
    static let satellite   = Color(red: 1.0,   green: 0.478, blue: 0.271)   // #FF7A45
    static let cream       = Color(red: 0.984, green: 0.973, blue: 0.949)   // #FBF8F2
    static let ink         = Color(red: 0.082, green: 0.075, blue: 0.059)   // #15130F
    static let butter      = Color(red: 1.0,   green: 0.839, blue: 0.361)   // #FFD65C
    static let down        = Color(red: 0.957, green: 0.314, blue: 0.369)   // #F4505E
    static let ok          = Color(red: 0.133, green: 0.773, blue: 0.369)   // #22C55E
    static let muted       = Color(red: 0.557, green: 0.576, blue: 0.612)   // #8E939C
}

/// Rayon de l'étoile (même astroïde lissée que `OliShape` dans BotEngine.swift).
private enum OliWidgetShape {
    static let p: CGFloat = 0.70
    static let smooth: CGFloat = 12
    static let samples = 180
    static let radii: [CGFloat] = {
        var raw = [CGFloat](repeating: 0, count: samples)
        for i in 0..<samples {
            let t = CGFloat(i) / CGFloat(samples) * .pi * 2
            raw[i] = 1 / pow(pow(abs(cos(t)), p) + pow(abs(sin(t)), p), 1 / p)
        }
        let k = Int(smooth / 360 * CGFloat(samples))
        var out = raw
        for i in 0..<samples {
            var s: CGFloat = 0
            for j in -k...k { s += raw[(i + j + samples) % samples] }
            out[i] = s / CGFloat(2 * k + 1)
        }
        let m = out.max() ?? 1
        return out.map { $0 / m }
    }()

    static func path(rx: CGFloat, ry: CGFloat, cx: CGFloat, cy: CGFloat) -> Path {
        var path = Path()
        for i in 0..<samples {
            let t = CGFloat(i) / CGFloat(samples) * .pi * 2
            let r = radii[i]
            let pt = CGPoint(x: cx + rx * r * cos(t), y: cy + ry * r * sin(t))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

struct OliStarView: View {
    var alarm: Bool = false
    /// Oli dort quand l'app ne tourne plus : yeux fermés, satellite pâle.
    var asleep: Bool = false

    var body: some View {
        Canvas { ctx, size in
            let W = min(size.width, size.height)
            let R = W * 0.3
            let rx = R * 1.08, ry = R * 1.08
            let cx = size.width / 2, cy = size.height / 2 + R * 0.06
            let body = OliWidgetShape.path(rx: rx, ry: ry, cx: cx, cy: cy)

            // Corps : dégradé, ombre de bord, lumière intérieure
            let top = alarm ? OliWidgetColors.alarmTop : OliWidgetColors.baseTop
            let bottom = alarm ? OliWidgetColors.alarmBottom : OliWidgetColors.baseBottom
            ctx.fill(body, with: .linearGradient(Gradient(colors: [top, bottom]),
                                                 startPoint: CGPoint(x: cx + rx * 0.7, y: cy - ry * 0.85),
                                                 endPoint: CGPoint(x: cx - rx * 0.8, y: cy + ry * 0.9)))
            ctx.fill(body, with: .radialGradient(
                Gradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.6),
                                 .init(color: .black.opacity(0.2), location: 1)]),
                center: CGPoint(x: cx, y: cy), startRadius: R * 0.15, endRadius: R * 1.25))
            ctx.fill(body, with: .radialGradient(
                Gradient(colors: [.white.opacity(0.20), .clear]),
                center: CGPoint(x: cx - rx * 0.15, y: cy - ry * 0.25), startRadius: 0, endRadius: R * 0.9))

            // Visière
            var face = ctx
            face.clip(to: body)
            let vw = R * 1.05, vh = R * 0.62
            let vcx = cx, vcy = cy + R * 0.06
            let visorRect = CGRect(x: vcx - vw / 2, y: vcy - vh / 2, width: vw, height: vh)
            let visor = Path(roundedRect: visorRect, cornerRadius: vh / 2)
            face.fill(visor, with: .linearGradient(Gradient(colors: [OliWidgetColors.visorTop, OliWidgetColors.visorBottom]),
                                                   startPoint: CGPoint(x: vcx, y: visorRect.minY),
                                                   endPoint: CGPoint(x: vcx, y: visorRect.maxY)))
            var gloss = face
            gloss.clip(to: visor)
            gloss.fill(Path(ellipseIn: CGRect(x: vcx - vw * 0.42, y: vcy - vh * 0.48, width: vw * 0.84, height: vh * 0.34)),
                       with: .color(.white.opacity(0.10)))

            // Yeux : pilules (calme), traits plats (alerte), fermés (pause)
            let ew = R * 0.14, eh = R * 0.34
            for sd: CGFloat in [-1, 1] {
                let ex = vcx + sd * R * 0.22
                let eye: Path
                if asleep {
                    eye = Path(roundedRect: CGRect(x: ex - R * 0.09, y: vcy - ew * 0.15, width: R * 0.18, height: ew * 0.3),
                               cornerRadius: ew * 0.15)
                } else if alarm {
                    eye = Path(roundedRect: CGRect(x: ex - R * 0.12, y: vcy - ew * 0.2, width: R * 0.24, height: ew * 0.4),
                               cornerRadius: ew * 0.2)
                } else {
                    eye = Path(roundedRect: CGRect(x: ex - ew / 2, y: vcy - eh / 2, width: ew, height: eh),
                               cornerRadius: ew / 2)
                }
                var glow = face
                glow.addFilter(.blur(radius: R * 0.06))
                glow.opacity = 0.55
                glow.fill(eye, with: .color(OliWidgetColors.eyeLight))
                face.fill(eye, with: .color(OliWidgetColors.eyeLight))
            }

            // Satellite en haut à droite
            let ang: CGFloat = -0.76
            let rad = R * (asleep ? 0.07 : 0.10)
            let px = cx + cos(ang) * R * 1.40, py = cy + sin(ang) * R * 1.40
            let sat = alarm ? OliWidgetColors.down : OliWidgetColors.satellite
            let alpha = asleep ? 0.5 : 1.0
            ctx.fill(Path(ellipseIn: CGRect(x: px - rad * 2.4, y: py - rad * 2.4, width: rad * 4.8, height: rad * 4.8)),
                     with: .radialGradient(Gradient(colors: [sat.opacity(0.35 * alpha), .clear]),
                                           center: CGPoint(x: px, y: py), startRadius: 0, endRadius: rad * 2.4))
            ctx.fill(Path(ellipseIn: CGRect(x: px - rad, y: py - rad, width: rad * 2, height: rad * 2)),
                     with: .color(sat.opacity(alpha)))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(alarm ? "Oli, inquiet" : (asleep ? "Oli, en pause" : "Oli"))
    }
}
