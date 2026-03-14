import SwiftUI
import AppKit

// MARK: - Apple-Native Design System

enum JarvisColors {
    // Semantic colors that adapt to light/dark mode
    static let background = Color(nsColor: .windowBackgroundColor)
    static let secondaryBackground = Color(nsColor: .controlBackgroundColor)
    static let tertiaryBackground = Color(nsColor: .underPageBackgroundColor)
    static let quaternaryBackground = Color(nsColor: .quaternaryLabelColor).opacity(0.08)
    
    static let label = Color(nsColor: .labelColor)
    static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
    static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)
    
    static let separator = Color(nsColor: .separatorColor)
    static let grid = Color(nsColor: .gridColor)
    
    // Accent follows system
    static let accent = Color.accentColor
}

enum JarvisLayout {
    // Apple HIG compliant spacing
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 20
    static let xxLarge: CGFloat = 24
    
    // Hit targets
    static let minHitTarget: CGFloat = 44
    static let minButtonHeight: CGFloat = 28
    
    // Corners - continuous for modern feel
    static let cornerSmall: CGFloat = 6
    static let cornerMedium: CGFloat = 10
    static let cornerLarge: CGFloat = 14
}

// MARK: - Native Button Styles

struct JarvisPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: JarvisLayout.minButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: JarvisLayout.cornerSmall, style: .continuous)
                    .fill(JarvisColors.accent)
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .contentShape(Rectangle())
    }
}

struct JarvisSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: JarvisLayout.minButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: JarvisLayout.cornerSmall, style: .continuous)
                    .fill(JarvisColors.secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: JarvisLayout.cornerSmall, style: .continuous)
                    .stroke(JarvisColors.separator, lineWidth: 0.5)
            )
            .foregroundStyle(JarvisColors.label)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .contentShape(Rectangle())
    }
}

struct JarvisToolbarButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: JarvisLayout.cornerSmall, style: .continuous)
                    .fill(configuration.isPressed ? JarvisColors.quaternaryBackground : Color.clear)
            )
            .foregroundStyle(JarvisColors.secondaryLabel)
            .contentShape(Rectangle())
    }
}

// MARK: - Native Card/Panel

struct JarvisPanel<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        content
            .padding(JarvisLayout.large)
            .background(
                RoundedRectangle(cornerRadius: JarvisLayout.cornerMedium, style: .continuous)
                    .fill(JarvisColors.secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: JarvisLayout.cornerMedium, style: .continuous)
                    .stroke(JarvisColors.separator, lineWidth: 0.5)
            )
    }
}

// MARK: - Section Header

struct JarvisSectionHeader: View {
    let title: String
    var subtitle: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: JarvisLayout.xSmall) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(JarvisColors.label)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(JarvisColors.secondaryLabel)
            }
        }
    }
}

// MARK: - Search Field

struct JarvisSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var onSubmit: (() -> Void)?
    
    var body: some View {
        HStack(spacing: JarvisLayout.small) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(JarvisColors.tertiaryLabel)
            
            TextField(placeholder, text: $text)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .onSubmit {
                    onSubmit?()
                }
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(JarvisColors.tertiaryLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, JarvisLayout.medium)
        .padding(.vertical, JarvisLayout.small)
        .background(
            RoundedRectangle(cornerRadius: JarvisLayout.cornerSmall, style: .continuous)
                .fill(JarvisColors.tertiaryBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: JarvisLayout.cornerSmall, style: .continuous)
                .stroke(JarvisColors.separator, lineWidth: 0.5)
        )
    }
}

// MARK: - Sidebar Item

struct JarvisSidebarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: JarvisLayout.small) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22, alignment: .center)
                
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                
                Spacer()
            }
            .padding(.horizontal, JarvisLayout.small)
            .padding(.vertical, JarvisLayout.small)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: JarvisLayout.cornerSmall, style: .continuous)
                .fill(isSelected ? JarvisColors.accent.opacity(0.15) : Color.clear)
        )
        .foregroundStyle(isSelected ? JarvisColors.accent : JarvisColors.label)
    }
}

// MARK: - Status Badge

struct JarvisStatusBadge: View {
    let text: String
    var style: Style = .default
    
    enum Style {
        case `default`
        case success
        case warning
        case error
        
        var color: Color {
            switch self {
            case .default: return JarvisColors.secondaryLabel
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(style.color.opacity(0.12))
            )
            .foregroundStyle(style.color)
    }
}

// MARK: - Divider

struct JarvisDivider: View {
    var body: some View {
        Rectangle()
            .fill(JarvisColors.separator)
            .frame(height: 0.5)
    }
}
