import AppKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "明亮"
        case .dark: return "暗黑"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

enum TerminalPalette {
    static func background(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1)
            : NSColor(srgbRed: 0.98, green: 0.98, blue: 0.97, alpha: 1)
    }

    static func foreground(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1)
            : NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1)
    }
}

enum AppearanceCenter {
    static func apply(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static var isDark: Bool {
        let appearance = NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func resolveIsDark(_ mode: AppearanceMode) -> Bool {
        switch mode {
        case .dark: return true
        case .light: return false
        case .system: return isDark
        }
    }
}
