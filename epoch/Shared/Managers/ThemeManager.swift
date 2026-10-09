import Observation
import SwiftUI

/// Fixed dark theme defined in DESIGN.md. Own once at the app root and inject into views.
/// Read using `@Environment(ThemeManager.self) private var theme`.
@MainActor
@Observable
final class ThemeManager {
    let colorScheme: ColorScheme = .dark
    let colors = Colors()
    let radii = Radii()
    let spacing = Spacing()
    let sizes = Sizes()
    let motion = Motion()

    struct Colors {
        let scrim = Self.color(0x07080A)
        let base = Self.color(0x0E1014)
        let sheet = Self.color(0x13161B)
        let card = Self.color(0x15181D)
        let control = Self.color(0x1A1D23)
        let player = Self.color(0x1B1E24)
        let raised = Self.color(0x20242C)
        let track = Self.color(0x23272F)
        let selected = Self.color(0x2C313B)
        let grabber = Self.color(0x3A404C)

        let textPrimary = Self.color(0xEDE7DB)
        let textSecondary = Self.color(0xCFC8BB)
        let textMuted = Self.color(0x8E887D)
        /// Decoration only; never use for readable labels.
        let textFaint = Self.color(0x6E6A62)

        let amber = Self.color(0xE5A85A)
        let amberLight = Self.color(0xF2C287)
        let onAmber = Self.color(0x1A1206)
        let amberWash = Self.color(0x1E1A14)
        let amberTint = Self.color(0x2A2116)
        let amberSelected = Self.color(0x3A2C17)

        let gain = Self.color(0x7CC4B4)
        let gainTint = Self.color(0x1E2A28)
        let loss = Self.color(0xE07A6E)
        let enemy = Self.color(0xB9665C)
        let condition = Self.color(0x9CC0E8)
        let conditionTint = Self.color(0x161D26)
        let gold = Self.color(0xD9C38A)
        let entityLink = Self.color(0x4F6E67)
        let entityText = Self.color(0xF4E6CB)

        var health: Color { loss }
        var stamina: Color { amber }

        private static func color(_ hex: UInt32) -> Color {
            Color(
                .sRGB,
                red: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255,
                opacity: 1
            )
        }
    }

    struct Radii {
        let sm: CGFloat = 10
        let md: CGFloat = 18
        let lg: CGFloat = 22
        let xl: CGFloat = 28
        let segment: CGFloat = 8
        let bubble: CGFloat = 20
        let bubbleTail: CGFloat = 6

        func rounded(_ radius: CGFloat) -> RoundedRectangle {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
        }

        var playerBubble: UnevenRoundedRectangle {
            UnevenRoundedRectangle(
                topLeadingRadius: bubble,
                bottomLeadingRadius: bubble,
                bottomTrailingRadius: bubbleTail,
                topTrailingRadius: bubble,
                style: .continuous
            )
        }

        var sheetTop: UnevenRoundedRectangle {
            UnevenRoundedRectangle(
                topLeadingRadius: xl,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: xl,
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

        let cardMargin: CGFloat = 16
        let headerMargin: CGFloat = 20
        let narrationMargin: CGFloat = 22
        let passageGap: CGFloat = 18
        let passageToEvents: CGFloat = 10
        let cardGap: CGFloat = 18
        let sectionGap: CGFloat = 28
        let cardPadding: CGFloat = 16
        let generousCardPadding: CGFloat = 18
        let eventGap: CGFloat = 14
        let illustrationBleed: CGFloat = 12
        let segmentInset: CGFloat = 2
    }

    struct Sizes {
        let minimumTapTarget: CGFloat = 44
        let buttonHeight: CGFloat = 50
        let composerHeight: CGFloat = 44
        let bagButton: CGFloat = 44
        // Visual sizes; interactive views still need a 44 × 44 hit region.
        let chipHeight: CGFloat = 36
        let sendButton: CGFloat = 36
        let closeButton: CGFloat = 32
        let segmentHeight: CGFloat = 32
        let rollButton: CGFloat = 108
        let navigationAvatar: CGFloat = 30
        let cardAvatar: CGFloat = 34
        let sheetAvatar: CGFloat = 64
        let navigationIcon: CGFloat = 22
        let inlineIcon: CGFloat = 18
        let eventIcon: CGFloat = 13
        let progressHeight: CGFloat = 4
        let sheetProgressHeight: CGFloat = 6
        let storyIllustrationHeight: CGFloat = 184
        let feedIllustrationHeight: CGFloat = 210
        let feedIllustrationHorizontalInset: CGFloat = 12
        let grabberWidth: CGFloat = 36
        let grabberHeight: CGFloat = 5
        let playerMessageMaxWidth: CGFloat = 270
        let entityUnderlineThickness: CGFloat = 1.5
        let entityUnderlineOffset: CGFloat = 4
    }

    enum TextStyle: CaseIterable {
        case largeTitle, storyTitle, itemTitle, narration, description, caption
        case headline, navigationTitle, uiBody, eventLine, eyebrow, chip, textButton

        var font: Font {
            switch self {
            case .largeTitle: .largeTitle.bold()
            case .storyTitle: .custom("Literata-Regular", size: 23, relativeTo: .title2).weight(.semibold)
            case .itemTitle: .custom("Literata-Regular", size: 19, relativeTo: .title3).weight(.semibold)
            case .narration: .custom("Literata-Regular", size: 18, relativeTo: .body)
            case .description: .custom("Literata-Regular", size: 15, relativeTo: .subheadline)
            case .caption: .custom("Literata-Italic", size: 13, relativeTo: .footnote)
            case .headline: .headline.weight(.semibold)
            case .navigationTitle: .headline.scaled(by: 16.0 / 17.0).weight(.semibold)
            case .uiBody: .subheadline
            case .eventLine: .footnote.monospacedDigit()
            case .eyebrow: .caption.weight(.semibold)
            case .chip: .subheadline.scaled(by: 14.0 / 15.0)
            case .textButton: .subheadline.weight(.semibold)
            }
        }

        fileprivate var relativeTo: Font.TextStyle {
            switch self {
            case .largeTitle: .largeTitle
            case .storyTitle: .title2
            case .itemTitle: .title3
            case .narration: .body
            case .description, .uiBody, .chip, .textButton: .subheadline
            case .caption, .eventLine: .footnote
            case .headline, .navigationTitle: .headline
            case .eyebrow: .caption
            }
        }

        // Approximate leading for Literata; SwiftUI includes the font's natural leading.
        fileprivate var lineSpacing: CGFloat {
            switch self {
            case .storyTitle, .itemTitle, .caption: 5
            case .narration: 12
            case .description: 7
            default: 0
            }
        }

        fileprivate var tracking: CGFloat {
            switch self {
            case .largeTitle: -0.34
            case .eyebrow: 0.72
            default: 0
            }
        }
    }

    struct Motion {
        let eventDelay: TimeInterval = 0.2
        let vitalsDuration: TimeInterval = 0.4
        let illustrationDuration: TimeInterval = 0.3
        let rollDuration: TimeInterval = 0.6

        /// Use with an opacity transition instead of counting/tumbling when Reduce Motion is on.
        func animation(for moment: Moment, reduceMotion: Bool) -> Animation {
            if reduceMotion {
                return .easeInOut(duration: illustrationDuration)
            }
            switch moment {
            case .vitals: return .easeInOut(duration: vitalsDuration)
            case .illustration: return .easeInOut(duration: illustrationDuration)
            case .roll: return .easeInOut(duration: rollDuration)
            }
        }

        enum Moment {
            case vitals, illustration, roll
        }
    }
}

private struct EpochTypographyModifier: ViewModifier {
    let style: ThemeManager.TextStyle
    @ScaledMetric private var lineSpacing: CGFloat
    @ScaledMetric private var tracking: CGFloat

    init(style: ThemeManager.TextStyle) {
        self.style = style
        _lineSpacing = ScaledMetric(wrappedValue: style.lineSpacing, relativeTo: style.relativeTo)
        _tracking = ScaledMetric(wrappedValue: style.tracking, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content
            .font(style.font)
            .lineSpacing(lineSpacing)
            .tracking(tracking)
            .textCase(style == .eyebrow ? .uppercase : nil)
    }
}

extension View {
    /// Applies font, Dynamic Type leading/tracking, and uppercase section labels together.
    func epochTypography(_ style: ThemeManager.TextStyle) -> some View {
        modifier(EpochTypographyModifier(style: style))
    }
}
