import SwiftUI

// MARK: - Briques d'interface communes

struct Card<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(tint.map { $0.opacity(0.10) } ?? Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.map { $0.opacity(0.35) } ?? Palette.hair, lineWidth: 1))
    }
}

struct Tag: View {
    let text: String
    var tint: Color = Palette.sand
    var body: some View {
        Text(text)
            .font(Typo.text(10.5, .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(Capsule().fill(tint.opacity(0.14)))
            .lineLimit(1)
    }
}

struct Dot: View {
    let color: Color
    var size: CGFloat = 7
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

/// A clickable row: dot / icon, title, detail, accessory.
struct Row<Accessory: View>: View {
    var color: Color = Palette.sand
    var icon: String? = nil
    let title: String
    var detail: String = ""
    var strong = false
    var action: (() -> Void)? = nil
    @ViewBuilder var accessory: Accessory
    @State private var hover = false

    var body: some View {
        HStack(spacing: 9) {
            if let icon {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(color).frame(width: 16)
            } else {
                Dot(color: color)
            }
            Text(title)
                .font(Typo.text(12.5, strong ? .bold : .semibold))
                .foregroundStyle(strong ? color : Palette.cream)
                .lineLimit(1)
                .layoutPriority(1)
            Text(detail)
                .font(Typo.text(11.5))
                .foregroundStyle(Palette.sand)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            accessory
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(hover && action != nil ? Palette.raised : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { action?() }
    }
}

extension Row where Accessory == EmptyView {
    init(color: Color = Palette.sand, icon: String? = nil, title: String, detail: String = "", strong: Bool = false,
         action: (() -> Void)? = nil) {
        self.init(color: color, icon: icon, title: title, detail: detail, strong: strong, action: action) { EmptyView() }
    }
}

struct ActionButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = Palette.tomate
    var filled = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 10.5, weight: .bold)) }
                Text(title).font(Typo.text(11.5, .bold))
            }
            .foregroundStyle(filled ? Palette.night : tint)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Capsule().fill(filled ? tint.opacity(hover ? 0.85 : 1) : tint.opacity(hover ? 0.2 : 0.12)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct EmptyNote: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.dust)
            Text(text).font(Typo.text(12.5)).foregroundStyle(Palette.sand).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

/// Thin progress bar.
struct Progress: View {
    let value: Double
    var tint: Color = Palette.tomate
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.raised)
                Capsule().fill(tint).frame(width: max(4, g.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 5)
    }
}

func openURL(_ s: String?) {
    guard let s, !s.isEmpty, let u = URL(string: s.hasPrefix("http") ? s : "https://" + s) else { return }
    NSWorkspace.shared.open(u)
}
