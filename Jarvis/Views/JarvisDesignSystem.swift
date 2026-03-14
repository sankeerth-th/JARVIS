import SwiftUI
import AppKit

enum JarvisSpacing {
    static let xSmall: CGFloat = 6
    static let small: CGFloat = 10
    static let medium: CGFloat = 14
    static let large: CGFloat = 20
}

enum JarvisRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
}

enum JarvisTypography {
    case title
    case section
    case body
    case caption
    case mono

    var font: Font {
        switch self {
        case .title:
            return .system(size: 19, weight: .semibold)
        case .section:
            return .subheadline.weight(.semibold)
        case .body:
            return .body
        case .caption:
            return .caption
        case .mono:
            return .system(.body, design: .monospaced)
        }
    }
}

enum JarvisBorderStrength {
    case subtle
    case `default`
    case emphasis
}

enum JarvisPalette {
    static let window = Color(nsColor: NSColor.windowBackgroundColor).opacity(0.96)
    static let panel = Color.white.opacity(0.035)
    static let panelMuted = Color.white.opacity(0.02)
    static let border = Color.white.opacity(0.12)
    static let borderStrong = Color.white.opacity(0.18)
    static let accent = Color.blue.opacity(0.26)
    static let accentBorder = Color.blue.opacity(0.48)
    static let warning = Color.orange.opacity(0.16)
    static let warningBorder = Color.orange.opacity(0.42)
    static let danger = Color.red.opacity(0.16)
    static let dangerBorder = Color.red.opacity(0.40)

    static func borderColor(_ strength: JarvisBorderStrength = .default) -> Color {
        switch strength {
        case .subtle:
            return Color.white.opacity(0.08)
        case .default:
            return border
        case .emphasis:
            return borderStrong
        }
    }
}

enum JarvisButtonTone {
    case primary
    case secondary
    case danger
    case tertiary
    case text

    var fill: Color {
        switch self {
        case .primary:
            return JarvisPalette.accent
        case .secondary:
            return Color.white.opacity(0.08)
        case .danger:
            return JarvisPalette.danger
        case .tertiary, .text:
            return Color.clear
        }
    }

    var border: Color {
        switch self {
        case .primary:
            return JarvisPalette.accentBorder
        case .secondary:
            return JarvisPalette.borderColor(.default)
        case .danger:
            return JarvisPalette.dangerBorder
        case .tertiary:
            return JarvisPalette.borderColor(.default)
        case .text:
            return Color.clear
        }
    }
}

struct JarvisButtonStyle: ButtonStyle {
    let tone: JarvisButtonTone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .background(tone.fill, in: RoundedRectangle(cornerRadius: JarvisRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: JarvisRadius.small, style: .continuous)
                    .stroke(tone.border.opacity(configuration.isPressed ? 0.85 : 1), lineWidth: tone == .text ? 0 : 1)
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .accessibilityAddTraits(.isButton)
    }
}

struct JarvisSidebarTabStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: JarvisRadius.small, style: .continuous)
                    .fill(selected ? JarvisPalette.accent : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: JarvisRadius.small, style: .continuous)
                    .stroke(selected ? JarvisPalette.accentBorder : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct JarvisCardModifier: ViewModifier {
    let fill: Color
    let border: Color
    let radius: CGFloat
    let shadowOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 10, x: 0, y: 6)
    }
}

enum JarvisStatusTone {
    case info
    case warning
    case error
    case success

    var icon: String {
        switch self {
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        case .success:
            return "checkmark.circle"
        }
    }

    var fill: Color {
        switch self {
        case .info:
            return JarvisPalette.panelMuted
        case .warning:
            return JarvisPalette.warning
        case .error:
            return JarvisPalette.danger
        case .success:
            return Color.green.opacity(0.12)
        }
    }

    var border: Color {
        switch self {
        case .info:
            return JarvisPalette.borderColor(.default)
        case .warning:
            return JarvisPalette.warningBorder
        case .error:
            return JarvisPalette.dangerBorder
        case .success:
            return Color.green.opacity(0.42)
        }
    }
}

struct JarvisStatusRow: View {
    let tone: JarvisStatusTone
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tone.icon)
                .foregroundStyle(.secondary)
            Text(message)
                .font(JarvisTypography.caption.font)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(JarvisButtonStyle(tone: .secondary))
            }
        }
        .padding(10)
        .jarvisCard(fill: tone.fill, border: tone.border, shadowOpacity: 0.02)
    }
}

struct JarvisPermissionRow: View {
    let title: String
    let subtitle: String
    let status: String
    let isGranted: Bool
    let primaryActionTitle: String
    let primaryAction: () -> Void
    let secondaryActionTitle: String
    let secondaryAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: JarvisSpacing.small) {
            Image(systemName: isGranted ? "checkmark.shield" : "shield")
                .foregroundStyle(isGranted ? Color.green : Color.orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(isGranted ? Color.green : .secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                Button(primaryActionTitle, action: primaryAction)
                    .buttonStyle(JarvisButtonStyle(tone: .primary))
                Button(secondaryActionTitle, action: secondaryAction)
                    .buttonStyle(JarvisButtonStyle(tone: .tertiary))
            }
        }
        .padding(10)
        .jarvisCard(fill: JarvisPalette.panel, border: JarvisPalette.borderColor(.default), shadowOpacity: 0.02)
    }
}

struct JarvisResultRow: View {
    let title: String
    let subtitle: String
    let metadata: String
    var snippet: String? = nil
    var trailing: (() -> AnyView)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Text(metadata)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .lineLimit(2)
            }
            if let trailing {
                trailing()
            }
        }
        .padding(10)
        .jarvisCard(fill: JarvisPalette.panel, border: JarvisPalette.borderColor(.default), shadowOpacity: 0.02)
    }
}

struct JarvisEmptyStateRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .jarvisCard(fill: JarvisPalette.panelMuted, border: JarvisPalette.borderColor(.default), shadowOpacity: 0.02)
    }
}

struct JarvisLoadingRow: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .jarvisCard(fill: JarvisPalette.panelMuted, border: JarvisPalette.borderColor(.default), shadowOpacity: 0.02)
    }
}

extension View {
    func jarvisCard(fill: Color = JarvisPalette.panel,
                    border: Color = JarvisPalette.borderColor(.default),
                    radius: CGFloat = JarvisRadius.medium,
                    shadowOpacity: Double = 0.12) -> some View {
        modifier(JarvisCardModifier(fill: fill, border: border, radius: radius, shadowOpacity: shadowOpacity))
    }

    func jarvisInputContainer(focused: Bool = false) -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: JarvisRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: JarvisRadius.small, style: .continuous)
                    .stroke(focused ? JarvisPalette.accentBorder : JarvisPalette.borderColor(.default), lineWidth: focused ? 1.5 : 1)
            )
    }
}

struct JarvisSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(JarvisTypography.section.font)
            if let subtitle {
                Text(subtitle)
                    .font(JarvisTypography.caption.font)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct JarvisStatusBadge: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(JarvisTypography.caption.font)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.16), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.42), lineWidth: 1)
            )
    }
}
