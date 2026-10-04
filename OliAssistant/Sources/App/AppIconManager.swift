import AppKit

/// The four Oli icons from the chara design sheet. The choice is stored in UserDefaults and
/// re-applied at launch: on the bundle (Finder) via NSWorkspace, and on the running app.
enum AppIconVariant: String, CaseIterable {
    case glow, dark, light, outline

    var assetName: String {
        switch self {
        case .glow:    return "OliIconGlow"
        case .dark:    return "OliIconDark"
        case .light:   return "OliIconLight"
        case .outline: return "OliIconOutline"
        }
    }
    var title: String {
        switch self {
        case .glow:    return "Lumineuse"
        case .dark:    return "Sombre"
        case .light:   return "Claire"
        case .outline: return "Contour"
        }
    }
}

@MainActor
enum AppIconManager {
    private static let key = "appIconVariant"

    static var current: AppIconVariant {
        AppIconVariant(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .glow
    }

    /// Applies the stored choice (call once at launch).
    static func applyStored() { apply(current, persist: false) }

    static func apply(_ v: AppIconVariant, persist: Bool = true) {
        if persist { UserDefaults.standard.set(v.rawValue, forKey: key) }
        guard let image = NSImage(named: v.assetName) else { return }
        NSApp.applicationIconImage = image
        // Finder icon of the .app: a custom icon on the bundle, nothing inside the bundle is rewritten.
        let path = Bundle.main.bundlePath
        if v == .glow {
            NSWorkspace.shared.setIcon(nil, forFile: path, options: [])   // back to the bundled AppIcon
        } else {
            NSWorkspace.shared.setIcon(image, forFile: path, options: [])
        }
        NotificationCenter.default.post(name: .appIconChanged, object: v)
    }
}

extension Notification.Name {
    static let appIconChanged = Notification.Name("oli.appIconChanged")
}
