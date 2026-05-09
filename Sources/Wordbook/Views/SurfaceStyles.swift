import SwiftUI

enum AppTheme {
    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 10
        static let row: CGFloat = 10
        static let large: CGFloat = 14
        static let panel: CGFloat = 14
        static let prominent: CGFloat = 16
    }

    enum Space {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 20
        static let page: CGFloat = 24
        static let section: CGFloat = 20
        static let cardPadding: CGFloat = 16
        static let rowHorizontal: CGFloat = 12
        static let rowVertical: CGFloat = 8
    }

    enum Stroke {
        static let hairline: CGFloat = 1
        static let subtle: Double = 0.08
        static let standard: Double = 0.12
        static let active: Double = 0.22
    }

    enum Shadow {
        static let cardOpacity: Double = 0.032
        static let cardRadius: CGFloat = 8
        static let cardY: CGFloat = 3
    }

    enum Size {
        static let compactRowHeight: CGFloat = 50
        static let sidebarRowHeight: CGFloat = 48
        static let metricCardHeight: CGFloat = 118
        static let sectionCardMinHeight: CGFloat = 246
        static let statusDot: CGFloat = 8
    }
}

struct SurfaceCardModifier: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.Radius.panel
    var material: Material = .regularMaterial
    var strokeOpacity: Double = AppTheme.Stroke.standard
    var shadowOpacity: Double = AppTheme.Shadow.cardOpacity
    var shadowRadius: CGFloat = AppTheme.Shadow.cardRadius
    var shadowY: CGFloat = AppTheme.Shadow.cardY
    var accent: Color?

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: isDark
                                        ? [Color.white.opacity(0.035), Color.white.opacity(0.008)]
                                        : [Color.white.opacity(0.14), Color.white.opacity(0.025)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                accent?.opacity(AppTheme.Stroke.active) ?? Color.primary.opacity(strokeOpacity),
                                lineWidth: AppTheme.Stroke.hairline
                            )
                    }
                    .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
            }
    }
}

struct InsetPillModifier: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.Radius.medium
    var tint: Color = .secondary
    var isActive = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isActive ? tint.opacity(0.14) : Color.secondary.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                isActive ? tint.opacity(AppTheme.Stroke.active) : Color.primary.opacity(AppTheme.Stroke.subtle),
                                lineWidth: AppTheme.Stroke.hairline
                            )
                    }
                    .shadow(color: .black.opacity(isActive ? 0.025 : 0.012), radius: isActive ? 4 : 2, x: 0, y: isActive ? 2 : 1)
            }
    }
}

/// 标签自动补全建议条：输入逗号分隔标签时显示匹配建议。
struct TagSuggestionBar: View {
    let tagsField: String
    let allTags: [String]
    let onSelect: (String) -> Void

    var body: some View {
        let input = tagsField.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? ""
        if input.isEmpty { EmptyView() }
        let suggestions = allTags.filter { $0.localizedCaseInsensitiveContains(input) && !tagsField.contains($0) }.prefix(6)
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { tag in
                        Button {
                            onSelect(tag)
                        } label: {
                            Text(tag)
                                .font(.callout)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

extension View {
    func surfaceCard(
        cornerRadius: CGFloat = AppTheme.Radius.panel,
        material: Material = .regularMaterial,
        strokeOpacity: Double = AppTheme.Stroke.standard,
        shadowOpacity: Double = AppTheme.Shadow.cardOpacity,
        shadowRadius: CGFloat = AppTheme.Shadow.cardRadius,
        shadowY: CGFloat = AppTheme.Shadow.cardY,
        accent: Color? = nil
    ) -> some View {
        modifier(
            SurfaceCardModifier(
                cornerRadius: cornerRadius,
                material: material,
                strokeOpacity: strokeOpacity,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY,
                accent: accent
            )
        )
    }

    func insetPill(cornerRadius: CGFloat = AppTheme.Radius.medium, tint: Color = .secondary, isActive: Bool = false) -> some View {
        modifier(InsetPillModifier(cornerRadius: cornerRadius, tint: tint, isActive: isActive))
    }

    func insetRowBackground(isActive: Bool = false, tint: Color = .accentColor) -> some View {
        background {
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .fill(isActive ? tint.opacity(0.12) : Color.secondary.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                        .strokeBorder(
                            isActive ? tint.opacity(AppTheme.Stroke.active) : Color.primary.opacity(0.04),
                            lineWidth: AppTheme.Stroke.hairline
                        )
                }
        }
    }
}
