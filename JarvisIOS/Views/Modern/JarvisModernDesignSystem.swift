import SwiftUI

struct JarvisModernTheme {
    static let backgroundTop = Color(red: 0.04, green: 0.06, blue: 0.10)
    static let backgroundBottom = Color(red: 0.08, green: 0.10, blue: 0.16)
    static let backgroundAccent = Color(red: 0.20, green: 0.47, blue: 0.76)
    static let backgroundDepth = Color(red: 0.46, green: 0.73, blue: 0.93)
    static let cardPrimary = Color(red: 0.09, green: 0.12, blue: 0.18).opacity(0.92)
    static let cardSecondary = Color(red: 0.12, green: 0.15, blue: 0.22).opacity(0.84)
    static let cardElevated = Color(red: 0.15, green: 0.19, blue: 0.28).opacity(0.90)
    static let panelGlass = Color.white.opacity(0.06)
    static let panelMuted = Color.white.opacity(0.03)
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.16)
    static let textPrimary = Color(red: 0.95, green: 0.97, blue: 1.00)
    static let textSecondary = Color(red: 0.70, green: 0.76, blue: 0.85)
    static let textTertiary = Color(red: 0.48, green: 0.55, blue: 0.67)
    static let accent = Color(red: 0.39, green: 0.78, blue: 0.99)
    static let accentSoft = Color(red: 0.33, green: 0.56, blue: 0.93)
    static let success = Color(red: 0.34, green: 0.78, blue: 0.54)
    static let warning = Color(red: 0.97, green: 0.72, blue: 0.29)
    static let danger = Color(red: 0.99, green: 0.45, blue: 0.43)
    static let shadow = Color.black.opacity(0.34)
    static let glowPrimary = accent.opacity(0.28)
    static let glowVoice = Color.cyan.opacity(0.24)

    static let screenPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let cardRadius: CGFloat = 28
    static let innerRadius: CGFloat = 20
    static let chipRadius: CGFloat = 18
    static let tabBarRadius: CGFloat = 30
    static let floatingTabBarHeight: CGFloat = 84
    static let assistantAnchorSize: CGFloat = 58
}

struct JarvisModernMotion {
    static let quick = Animation.easeOut(duration: 0.18)
    static let focus = Animation.spring(response: 0.38, dampingFraction: 0.84)
    static let stateChange = Animation.spring(response: 0.42, dampingFraction: 0.88)
    static let surfaceExpand = Animation.spring(response: 0.48, dampingFraction: 0.82)
    static let contentUpdate = Animation.easeInOut(duration: 0.22)
    static let idle = Animation.easeInOut(duration: 1.8).repeatForever(autoreverses: true)
}

struct JarvisModernBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    JarvisModernTheme.backgroundTop,
                    JarvisModernTheme.backgroundBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            AngularGradient(
                colors: [
                    JarvisModernTheme.backgroundAccent.opacity(0.22),
                    .clear,
                    JarvisModernTheme.backgroundDepth.opacity(0.14),
                    .clear,
                    JarvisModernTheme.backgroundAccent.opacity(0.16)
                ],
                center: .topTrailing
            )
            .blur(radius: 60)
        }
        .overlay(
            RadialGradient(
                colors: [JarvisModernTheme.backgroundAccent.opacity(0.28), .clear],
                center: .topTrailing,
                startRadius: 12,
                endRadius: 440
            )
        )
        .overlay(
            RadialGradient(
                colors: [JarvisModernTheme.backgroundDepth.opacity(0.16), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 420
            )
        )
        .overlay(
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.34)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .ignoresSafeArea()
    }
}

struct JarvisModernCard<Content: View>: View {
    let secondary: Bool
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(secondary: Bool = false, padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.secondary = secondary
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: JarvisModernTheme.cardRadius, style: .continuous)
                    .fill(secondary ? JarvisModernTheme.cardSecondary : JarvisModernTheme.cardPrimary)
                    .overlay(
                        RoundedRectangle(cornerRadius: JarvisModernTheme.cardRadius, style: .continuous)
                            .stroke(secondary ? JarvisModernTheme.border : JarvisModernTheme.borderStrong, lineWidth: 1)
                    )
                    .shadow(color: JarvisModernTheme.shadow, radius: 28, x: 0, y: 18)
            )
    }
}

struct JarvisModernSectionHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?
    var trailing: AnyView? = nil

    init(_ title: String, eyebrow: String? = nil, subtitle: String? = nil, trailing: AnyView? = nil) {
        self.title = title
        self.eyebrow = eyebrow
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .foregroundStyle(JarvisModernTheme.accent.opacity(0.88))
                }
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

struct JarvisModernIconBadge: View {
    let systemName: String
    let tint: Color
    let filled: Bool

    init(systemName: String, tint: Color = JarvisModernTheme.accent, filled: Bool = true) {
        self.systemName = systemName
        self.tint = tint
        self.filled = filled
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(filled ? tint.opacity(0.16) : JarvisModernTheme.panelMuted)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(filled ? 0.38 : 0.22), lineWidth: 1)
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 46, height: 46)
    }
}

struct JarvisModernChip: View {
    let title: String
    let icon: String?
    let tint: Color
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(active ? JarvisModernTheme.textPrimary : JarvisModernTheme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(active ? tint.opacity(0.18) : JarvisModernTheme.panelMuted)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(active ? tint.opacity(0.42) : JarvisModernTheme.border, lineWidth: 1)
                )
        )
    }
}

struct JarvisModernPrimaryButtonStyle: ButtonStyle {
    var tint: Color = JarvisModernTheme.accent
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(red: 0.03, green: 0.05, blue: 0.09))
            .padding(.horizontal, compact ? 14 : 16)
            .padding(.vertical, compact ? 10 : 13)
            .background(
                RoundedRectangle(cornerRadius: compact ? 16 : 18, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.78 : 0.96))
                    .shadow(color: tint.opacity(0.28), radius: 12, x: 0, y: 8)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(JarvisModernMotion.quick, value: configuration.isPressed)
    }
}

struct JarvisModernSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(JarvisModernTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(JarvisModernTheme.panelGlass.opacity(configuration.isPressed ? 1.18 : 1.0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(JarvisModernTheme.border, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct JarvisModernInlineStatusRow: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            JarvisModernIconBadge(systemName: icon, tint: tint)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                Text(detail)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(JarvisModernTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

struct JarvisModernFloatingTabBar: View {
    @Binding var selection: JarvisAppTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(JarvisAppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: selection == tab ? .semibold : .regular))
                        Text(tab.title)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == tab ? JarvisModernTheme.accent : JarvisModernTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selection == tab ? JarvisModernTheme.accent.opacity(0.14) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: JarvisModernTheme.tabBarRadius, style: .continuous)
                .fill(JarvisModernTheme.cardPrimary.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: JarvisModernTheme.tabBarRadius, style: .continuous)
                        .stroke(JarvisModernTheme.borderStrong, lineWidth: 1)
                )
                .shadow(color: JarvisModernTheme.shadow, radius: 18, x: 0, y: 8)
        )
        .padding(.horizontal, JarvisModernTheme.screenPadding)
    }
}

struct JarvisModernCapsuleActionStyle: ButtonStyle {
    var tint: Color = JarvisModernTheme.accentSoft
    var emphasized: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(emphasized ? .white : JarvisModernTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(emphasized ? tint.opacity(configuration.isPressed ? 0.78 : 0.94) : JarvisModernTheme.panelGlass.opacity(configuration.isPressed ? 1.14 : 1.0))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(emphasized ? tint.opacity(0.12) : JarvisModernTheme.borderStrong, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(JarvisModernMotion.quick, value: configuration.isPressed)
    }
}
