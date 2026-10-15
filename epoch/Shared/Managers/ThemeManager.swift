import Observation
import SwiftUI
import UIKit

/// Paper design tokens defined in DESIGN.md. Own once at the app root and inject into views.
/// Read using `@Environment(ThemeManager.self) private var theme`.
@MainActor
@Observable
final class ThemeManager {
    /// Paper by default. Set `.dark` for Lamplight, or `nil` to follow the system.
    var colorScheme: ColorScheme? = .light
    let colors = Colors()
    let radii = Radii()
    let spacing = Spacing()
    let sizes = Sizes()
    let motion = Motion()

    /// Each token resolves to its Paper value in light mode and its Lamplight value in dark mode.
    struct Colors {
        let paper = Self.color(paper: 0xF4EFE4, lamplight: 0x1C1A17)
        let leaf = Self.color(paper: 0xECE5D6, lamplight: 0x24211D)
        let press = Self.color(paper: 0xE4DBC6, lamplight: 0x2E2A25)
        let rule = Self.color(paper: 0xD6CBB7, lamplight: 0x3A352E)
        /// Decoration only: grabber, ornaments, dotted leaders.
        let grain = Self.color(paper: 0xC9BDA7, lamplight: 0x4A443B)

        let ink = Self.color(paper: 0x29241E, lamplight: 0xE6DED0)
        let inkSoft = Self.color(paper: 0x4F473E, lamplight: 0xC6BDAE)
        /// The floor for readable text.
        let inkMuted = Self.color(paper: 0x6B6155, lamplight: 0xA39886)
        /// Separators and entity underlines; never use for readable text.
        let inkFaint = Self.color(paper: 0x9A8F80, lamplight: 0x6E665A)

        /// The reader's ink: player text, story actions, the primary button, unread dots.
        let quill = Self.color(paper: 0x2E4A6E, lamplight: 0x9DB5D6)
        let rubric = Self.color(paper: 0x9B3A2A, lamplight: 0xD98B78)
        let moss = Self.color(paper: 0x4D6A3F, lamplight: 0x9DB98A)
        let plum = Self.color(paper: 0x6E4A6B, lamplight: 0xC29BBE)
        let ochre = Self.color(paper: 0x85641F, lamplight: 0xD2B270)

        var health: Color { rubric }
        var stamina: Color { inkSoft }
        var xp: Color { quill }

        /// How much the page behind a sheet dims.
        let sheetDimOpacity: Double = 0.16

        private static func color(paper: UInt32, lamplight: UInt32) -> Color {
            Color(uiColor: UIColor { traits in
                uiColor(traits.userInterfaceStyle == .dark ? lamplight : paper)
            })
        }

        private static func uiColor(_ hex: UInt32) -> UIColor {
            UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }

    /// Plates and lists are square-cornered; only sheets and the filled button are rounded.
    struct Radii {
        let sheet: CGFloat = 16

        var sheetTop: UnevenRoundedRectangle {
            UnevenRoundedRectangle(
                topLeadingRadius: sheet,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: sheet,
                style: .continuous
            )
        }

        var capsule: Capsule { Capsule(style: .continuous) }
    }

    struct Spacing {
        let xxs: CGFloat = 4
        let xs: CGFloat = 8
        let sm: CGFloat = 12
        let md: CGFloat = 16
        let lg: CGFloat = 20
        let xl: CGFloat = 24
        let xxl: CGFloat = 32
        let xxxl: CGFloat = 40

        /// Narration and lists.
        let pageMargin: CGFloat = 28
        /// Folio and composer.
        let folioMargin: CGFloat = 20
        let edgeIconMargin: CGFloat = 12
        let passageGap: CGFloat = 22
        let passageToEvents: CGFloat = 10
        let eventGap: CGFloat = 14
        let playerIndent: CGFloat = 22
        let plateBleed: CGFloat = 12
    }

    struct Sizes {
        let minimumTapTarget: CGFloat = 44
        // Visual sizes; interactive views still need a 44 × 44 hit region.
        let icon: CGFloat = 20
        let iconStroke: CGFloat = 1.5
        let sendButton: CGFloat = 32
        let primaryButtonWidth: CGFloat = 180
        let primaryButtonHeight: CGFloat = 50
        let hairline: CGFloat = 1
        let meterFill: CGFloat = 2
        let tabUnderline: CGFloat = 1.5
        let entityUnderlineThickness: CGFloat = 1.5
        let entityUnderlineOffset: CGFloat = 4
        let feedFade: CGFloat = 56
        let storyPlateHeight: CGFloat = 150
        let detailsPlateHeight: CGFloat = 240
        let grabberWidth: CGFloat = 36
        let grabberHeight: CGFloat = 5
    }

    enum TextStyle: CaseIterable {
        case display, title, narration, player, description, caption
        case eyebrow, event, ui

        private static let serif = "Newsreader"
        private static let serifItalic = "Newsreader16pt-Italic"

        /// `player` text is also set in `quill`; apply the color at the call site.
        var font: Font {
            switch self {
            case .display: .custom(Self.serif, size: 38, relativeTo: .largeTitle).weight(.medium)
            case .title: .custom(Self.serif, size: 25, relativeTo: .title2).weight(.medium)
            case .narration: .custom(Self.serif, size: 18, relativeTo: .body)
            case .player: .custom(Self.serifItalic, size: 17, relativeTo: .body)
            case .description: .custom(Self.serif, size: 15.5, relativeTo: .subheadline)
            case .caption: .custom(Self.serifItalic, size: 12.5, relativeTo: .footnote)
            case .eyebrow: .caption2.scaled(by: 10.5 / 11).weight(.semibold)
            case .event: .caption2.weight(.medium).monospacedDigit()
            case .ui: .subheadline.weight(.medium).monospacedDigit()
            }
        }

        fileprivate var relativeTo: Font.TextStyle {
            switch self {
            case .display: .largeTitle
            case .title: .title2
            case .narration, .player: .body
            case .description, .ui: .subheadline
            case .caption: .footnote
            case .eyebrow, .event: .caption2
            }
        }

        /// Base point size and font name, used to turn the target leading into line spacing.
        fileprivate var metrics: (name: String, size: CGFloat, leading: CGFloat)? {
            switch self {
            case .display: (Self.serif, 38, 42)
            case .title: (Self.serif, 25, 30)
            case .narration: (Self.serif, 18, 29)
            case .player: (Self.serifItalic, 17, 26)
            case .description: (Self.serif, 15.5, 23)
            case .caption: (Self.serifItalic, 12.5, 18)
            case .eyebrow, .event, .ui: nil
            }
        }

        fileprivate var tracking: CGFloat {
            switch self {
            case .eyebrow: 10.5 * 0.14
            case .event: 11 * 0.08
            default: 0
            }
        }

        fileprivate var isUppercased: Bool {
            self == .eyebrow || self == .event
        }
    }

    struct Motion {
        let eventDelay: TimeInterval = 0.2
        let vitalsDuration: TimeInterval = 0.4
        let plateDuration: TimeInterval = 0.3
        let rollDuration: TimeInterval = 0.6

        /// Use with an opacity transition instead of counting/tumbling when Reduce Motion is on.
        func animation(for moment: Moment, reduceMotion: Bool) -> Animation {
            if reduceMotion {
                return .easeInOut(duration: plateDuration)
            }
            switch moment {
            case .vitals: return .easeInOut(duration: vitalsDuration)
            case .plate: return .easeInOut(duration: plateDuration)
            case .roll: return .easeInOut(duration: rollDuration)
            }
        }

        enum Moment {
            case vitals, plate, roll
        }
    }
}

private struct EpochTypographyModifier: ViewModifier {
    let style: ThemeManager.TextStyle
    @ScaledMetric private var size: CGFloat
    @ScaledMetric private var leading: CGFloat
    @ScaledMetric private var tracking: CGFloat

    init(style: ThemeManager.TextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.metrics?.size ?? 0, relativeTo: style.relativeTo)
        _leading = ScaledMetric(wrappedValue: style.metrics?.leading ?? 0, relativeTo: style.relativeTo)
        _tracking = ScaledMetric(wrappedValue: style.tracking, relativeTo: style.relativeTo)
    }

    /// SwiftUI adds line spacing on top of the font's natural line height, so subtract it.
    private var lineSpacing: CGFloat {
        guard let name = style.metrics?.name, let font = UIFont(name: name, size: size) else { return 0 }
        return max(0, leading - font.lineHeight)
    }

    func body(content: Content) -> some View {
        content
            .font(style.font)
            .lineSpacing(lineSpacing)
            .tracking(tracking)
            .textCase(style.isUppercased ? .uppercase : nil)
    }
}

extension View {
    /// Applies font, Dynamic Type leading/tracking, and uppercase labels together.
    func epochTypography(_ style: ThemeManager.TextStyle) -> some View {
        modifier(EpochTypographyModifier(style: style))
    }
}
