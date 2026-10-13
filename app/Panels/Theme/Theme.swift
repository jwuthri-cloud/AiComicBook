import SwiftUI
import UIKit

/// Calm, mid-contrast palette: warm paper by day, soft slate by night (never pure white or black).
enum Theme {
    static let background = Color(light: 0xF3EFE8, dark: 0x1B1F27)
    static let surface = Color(light: 0xFBF9F5, dark: 0x242A34)
    static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x2C3340)
    static let sunken = Color(light: 0xE9E4DA, dark: 0x161A21)
    static let paper = Color(light: 0xFAF6EE, dark: 0x22262E)
    static let ink = Color(light: 0x23262D, dark: 0xECE8E0)
    static let inkSecondary = Color(light: 0x5F6370, dark: 0xA6ABB7)
    static let inkTertiary = Color(light: 0x8E919B, dark: 0x767C89)
    static let hairline = Color(light: 0x23262D, dark: 0xFFFFFF).opacity(0.09)
    static let accent = Color(light: 0x0E7C89, dark: 0x52C8D4)
    /// Text on a filled tint: white on the deeper daytime tints, slate on the lighter night tints.
    static let onTint = Color(light: 0xFFFFFF, dark: 0x14171D)

    static func tint(_ name: String) -> Color {
        switch name {
        case "teal": Color(light: 0x0E7C89, dark: 0x52C8D4)
        case "violet": Color(light: 0x6F55B8, dark: 0xB39CF0)
        case "amber": Color(light: 0xA86B12, dark: 0xF0BC55)
        case "lime": Color(light: 0x4F7D1C, dark: 0xA9D35A)
        case "coral": Color(light: 0xB9533A, dark: 0xF2937A)
        default: accent
        }
    }

    static func symbol(_ name: String) -> String {
        switch name {
        case "flask": "flask"
        case "shield": "checkmark.shield"
        case "brain": "brain.head.profile"
        case "algorithm": "point.3.connected.trianglepath.dotted"
        case "branch": "arrow.triangle.branch"
        default: "book.closed"
        }
    }

    static func categoryTint(_ category: String) -> Color {
        switch category {
        case "AI Safety": tint("violet")
        case "Interpretability": tint("teal")
        case "Research Methods": tint("coral")
        case "Machine Learning", "LLMs": tint("amber")
        case "Algorithms", "Data Structures": tint("lime")
        case "Git": tint("coral")
        default: accent
        }
    }
}

extension Font {
    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Reusable styling

struct CardStyle: ViewModifier {
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }
}

extension View {
    func card(radius: CGFloat = 20) -> some View { modifier(CardStyle(radius: radius)) }
}

/// Small rounded label, e.g. a category or "4 pages".
struct Pill: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.rounded(.caption, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.13), in: Capsule())
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var tint: Color = Theme.accent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.serif(.title2, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.rounded(.subheadline))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    return s >= 60 ? "\(s / 60)m \(s % 60)s" : "\(s)s"
}
