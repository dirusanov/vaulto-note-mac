import AppKit
import SwiftUI

/// Port of the shared Vaulto palette (vaulto_note_mobile/src/theme/colors.ts).
/// Each colour resolves to its light or dark value with the system appearance.
enum VaultoColor {
    static let background = dynamic(0xF8F9FA, 0x0F1113)
    static let backgroundSecondary = dynamic(0xE9ECEF, 0x1F2329)
    static let surface = dynamic(0xFFFFFF, 0x181B1F)
    static let surfaceElevated = dynamic(0xFFFFFF, 0x252A30)
    static let primary = dynamic(0x0066FF, 0x3D8BFF)
    static let primaryHover = dynamic(0x0052CC, 0x66A3FF)
    static let primaryLight = dynamic(0x0066FF, 0x3D8BFF, alpha: (0.12, 0.18))
    static let text = dynamic(0x1A1A1A, 0xECEEF1)
    static let textSecondary = dynamic(0x6C757D, 0xA1A8B1)
    static let textTertiary = dynamic(0xADB5BD, 0x737B85)
    static let border = dynamic(0xDEE2E6, 0x2B3036)
    static let error = dynamic(0xDC3545, 0xF26B78)
    static let success = dynamic(0x10B981, 0x34D399)
    static let warning = dynamic(0xF59E0B, 0xFBBF24)
    static let warningLight = dynamic(0xF59E0B, 0xFBBF24, alpha: (0.10, 0.14))
    static let onPrimary = Color.white

    private static func dynamic(_ light: UInt32, _ dark: UInt32, alpha: (CGFloat, CGFloat) = (1, 1)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? alpha.1 : alpha.0)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// `card` style from the mobile Settings screen: flat surface, 16 pt radius, hairline border.
struct VaultoCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(VaultoColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(VaultoColor.border, lineWidth: 1))
    }
}

extension View {
    func vaultoCard() -> some View { modifier(VaultoCard()) }
}

struct VaultoPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(VaultoColor.onPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(configuration.isPressed ? VaultoColor.primaryHover : VaultoColor.primary)
            )
    }
}

enum VaultoFont {
    static let h2 = Font.system(size: 24, weight: .semibold)
    static let sectionTitle = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 14)
    static let notePreview = Font.system(size: 14)
    static let caption = Font.system(size: 12)
    static let captionBold = Font.system(size: 12, weight: .semibold)
}
