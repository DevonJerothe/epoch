import SwiftUI

/// Renders `ErrorManager`'s banner and alert. Apply once at the app root.
private struct ErrorPresentation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let errors: ErrorManager
    let theme: ThemeManager
    let openSettings: () -> Void

    func body(content: Content) -> some View {
        // A stack, not a safe-area inset: a navigation bar ignores the inset and would sit under the banner.
        VStack(spacing: 0) {
            if let banner = errors.banner {
                ErrorBanner(error: banner, theme: theme) {
                    actions(for: banner, ink: theme.colors.quill, dismiss: { errors.dismissBanner() })
                }
                .transition(.opacity)
            }
            content
        }
        .animation(theme.motion.animation(for: .plate, reduceMotion: reduceMotion), value: errors.banner?.id)
        .alert(
            errors.alert?.title ?? "",
            isPresented: Binding(
                get: { errors.alert != nil },
                set: { isPresented in if !isPresented { errors.dismissAlert() } }
            ),
            presenting: errors.alert
        ) { alert in
            actions(for: alert, ink: nil, dismiss: { errors.dismissAlert() })
        } message: { alert in
            Text(alert.message)
        }
    }

    /// `ink` colors the recovery actions in the banner; the system alert styles its own buttons.
    @ViewBuilder
    private func actions(
        for error: PresentedError, ink: Color?, dismiss: @escaping () -> Void
    ) -> some View {
        let recoveryInk = ink ?? theme.colors.inkSoft
        if error.offersSettings {
            Button("Open Settings") {
                dismiss()
                openSettings()
            }
            .foregroundStyle(recoveryInk)
        }
        if error.offersRetry, let retry = error.retry {
            Button("Try Again") {
                dismiss()
                Task { await retry() }
            }
            .foregroundStyle(recoveryInk)
        }
        Button("Dismiss", role: .cancel, action: dismiss)
    }
}

/// A note laid over the top of the page: `leaf` ground, a hairline beneath, no shadow.
/// Only the sign takes `rubric`; recovery actions wait on the reader, so they are quill.
private struct ErrorBanner<Actions: View>: View {
    let error: PresentedError
    let theme: ThemeManager
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.xs) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(theme.colors.rubric)
                    .accessibilityHidden(true)
                Text(error.title)
                    .epochTypography(.ui)
                    .foregroundStyle(theme.colors.ink)
            }
            Text(error.message)
                .epochTypography(.description)
                .foregroundStyle(theme.colors.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: theme.spacing.lg) {
                actions()
            }
            .epochTypography(.ui)
            .foregroundStyle(theme.colors.inkSoft)
            .frame(minHeight: theme.sizes.minimumTapTarget)
        }
        .padding(.horizontal, theme.spacing.folioMargin)
        .padding(.top, theme.spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.leaf)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.colors.rule)
                .frame(height: theme.sizes.hairline)
        }
        .accessibilityElement(children: .contain)
        .task(id: error.id) {
            AccessibilityNotification.Announcement("\(error.title). \(error.message)").post()
        }
    }
}

extension View {
    /// Shows errors reported to `errors`. `openSettings` backs the "Open Settings" recovery.
    func errorPresentation(
        _ errors: ErrorManager, theme: ThemeManager, openSettings: @escaping () -> Void
    ) -> some View {
        modifier(ErrorPresentation(errors: errors, theme: theme, openSettings: openSettings))
    }
}
