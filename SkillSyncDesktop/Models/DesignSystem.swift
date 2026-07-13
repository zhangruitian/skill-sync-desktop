import SwiftUI

// MARK: - Design System (Terminal Catalyst / Professional Utility)

/// Centralized design tokens from the Stitch "Skill Script Studio" system.
/// Targets a dark-mode-first macOS developer tool aesthetic.
enum DesignSystem {
    // MARK: - Colors (Surface hierarchy)

    struct Colors {
        /// Main app background — deepest level
        static let background        = Color(hex: "#10131b")
        /// Sidebar, glass panels
        static let surface           = Color(hex: "#181c23")
        /// Hover/active states
        static let surfaceHigh       = Color(hex: "#272a32")
        /// Containers elevated above background
        static let surfaceContainer  = Color(hex: "#1c2028")
        /// Highest elevation
        static let surfaceHighest   = Color(hex: "#31353d")

        /// Primary action color (Sapphire Blue)
        static let primary           = Color(hex: "#adc6ff")
        /// Primary container for selected states
        static let primaryContainer  = Color(hex: "#4b8eff")

        /// Success / Synced status
        static let statusSynced      = Color(hex: "#34C759")
        /// Warning / Stale status
        static let statusStale       = Color(hex: "#FF9F0A")
        /// Error / Outdated
        static let statusError       = Color(hex: "#ffb4ab")

        /// Text colors
        static let textPrimary       = Color(hex: "#e0e2ed")
        static let textSecondary     = Color(hex: "#A1A1A1")
        static let textOnPrimary     = Color(hex: "#002e69")

        /// Borders & separators
        static let borderSubtle      = Color(hex: "#3F3F3F")
        static let outline           = Color(hex: "#8b90a0")
        static let outlineVariant    = Color(hex: "#414755")

        /// Accent
        static let actionPrimary     = Color(hex: "#007AFF")
    }

    // MARK: - Typography

    struct Typography {
        /// Sidebar section headers, table headers
        static let labelCaps: Font = .system(size: 11, weight: .bold, design: .default)
        /// Body text
        static let bodyMD: Font     = .system(size: 13, weight: .regular, design: .default)
        /// Secondary text
        static let bodySM: Font     = .system(size: 12, weight: .regular, design: .default)
        /// Code: paths, skill names, timestamps
        /// Ideally JetBrains Mono — falls back to system monospaced if not installed.
        static let codeSM: Font     = .system(size: 12, weight: .regular, design: .monospaced)
        /// Section headings
        static let headlineMD: Font = .system(size: 16, weight: .semibold, design: .default)
        /// Page titles
        static let headlineLG: Font = .system(size: 20, weight: .semibold, design: .default)
    }

    // MARK: - Shapes

    struct Shapes {
        /// Default small UI element radius
        static let small: CGFloat  = 2
        /// Card/container radius
        static let medium: CGFloat = 6
        /// Larger container radius
        static let large: CGFloat  = 8
        /// Fully round
        static let full: CGFloat   = 9999
    }

    // MARK: - Spacing & Layout

    struct Layout {
        static let sidebarWidth: CGFloat = 240
        static let edgeMargin: CGFloat   = 24
        static let gutter: CGFloat       = 16
        static let stackSM: CGFloat      = 8
        static let componentPadding: CGFloat = 12
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        if hex.count == 6 {
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        } else {
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }

    /// Get the hex string for this color (approximate)
    func hexString() -> String {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return "#000000"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
