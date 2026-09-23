//
//  KitoChatBubbleStyle.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

// MARK: - Style

/// How message bubbles look.
public enum KitoChatBubbleStyle: String, CaseIterable, Identifiable, Sendable {
    /// Rounded bubbles with a soft tail; grouped messages tuck their inner corners.
    case modern
    /// Flat, tailless: a tinted wash for you, an outline for them.
    case minimal
    /// Frosted glass with a light-catching edge — best over a wallpaper.
    case glass
    /// A gradient outgoing bubble with the classic curled tail.
    case imessage

    public var id: String { rawValue }

    /// "Modern", "Minimal", "Glass", "iMessage".
    public var title: String {
        switch self {
        case .modern: "Modern"
        case .minimal: "Minimal"
        case .glass: "Glass"
        case .imessage: "iMessage"
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .modern, .glass: 20
        case .minimal: 14
        case .imessage: 18
        }
    }

    var groupedRadius: CGFloat {
        switch self {
        case .modern: 6
        case .minimal: 4
        case .glass: 8
        case .imessage: 18
        }
    }

    var tail: KitoBubbleTail {
        switch self {
        case .modern, .glass: .soft
        case .minimal: .none
        case .imessage: .curled
        }
    }
}

enum KitoBubbleTail {
    case none, soft, curled
}

// MARK: - Shape

/// A bubble outline: per-corner radii for grouping plus an optional tail on the author's side.
struct KitoBubbleShape: Shape {
    var isOutgoing: Bool
    var position: KitoChatGroupPosition
    var radius: CGFloat
    var groupedRadius: CGFloat
    var tail: KitoBubbleTail

    init(style: KitoChatBubbleStyle, isOutgoing: Bool, position: KitoChatGroupPosition, showsTail: Bool = true) {
        self.isOutgoing = isOutgoing
        self.position = position
        self.radius = style.cornerRadius
        self.groupedRadius = style.groupedRadius
        self.tail = showsTail && position.isGroupEnd ? style.tail : .none
    }

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        let grouped = min(groupedRadius, r)
        let sideTop = position.isGroupStart ? r : grouped
        let sideBottom: CGFloat = tail == .none ? (position.isGroupEnd ? r : grouped) : min(4, r)
        let corners = isOutgoing
            ? RectangleCornerRadii(topLeading: r, bottomLeading: r, bottomTrailing: sideBottom, topTrailing: sideTop)
            : RectangleCornerRadii(topLeading: sideTop, bottomLeading: sideBottom, bottomTrailing: r, topTrailing: r)
        let body = UnevenRoundedRectangle(cornerRadii: corners, style: .continuous).path(in: rect)
        guard tail != .none else { return body }
        return body.union(tailPath(in: rect))
    }

    /// Drawn for the right-hand side, mirrored for incoming bubbles.
    private func tailPath(in rect: CGRect) -> Path {
        let edge = isOutgoing ? rect.maxX : rect.minX
        let direction: CGFloat = isOutgoing ? 1 : -1
        func point(_ outward: CGFloat, _ up: CGFloat) -> CGPoint {
            CGPoint(x: edge + outward * direction, y: rect.maxY - up)
        }
        let height = min(tail == .curled ? 22 : 19, rect.height * 0.7)
        var path = Path()
        path.move(to: point(-18, height))
        path.addLine(to: point(0, height))
        switch tail {
        case .curled:
            path.addCurve(to: point(8, 0), control1: point(0, height * 0.4), control2: point(2.5, 1))
            path.addCurve(to: point(-18, 0), control1: point(-1, -1.2), control2: point(-10, -0.4))
        default:
            path.addCurve(to: point(7, 0), control1: point(0, height * 0.35), control2: point(3, 0.5))
            path.addQuadCurve(to: point(-16, 0), control: point(-4, 0))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Background

/// Fills a bubble for a style: solid, washed, frosted or gradient.
struct KitoBubbleBackground: View {
    let style: KitoChatBubbleStyle
    let isOutgoing: Bool
    let position: KitoChatGroupPosition
    let tint: Color
    var showsTail = true

    @Environment(\.kitoTheme) private var theme

    var body: some View {
        let shape = KitoBubbleShape(style: style, isOutgoing: isOutgoing, position: position, showsTail: showsTail)
        switch style {
        case .modern:
            shape.fill(isOutgoing ? AnyShapeStyle(tint) : AnyShapeStyle(theme.colors.surfaceMuted))
        case .minimal:
            if isOutgoing {
                shape.fill(tint.opacity(0.14))
            } else {
                shape.fill(theme.colors.surface).overlay(shape.stroke(theme.colors.border, lineWidth: 1))
            }
        case .glass:
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(tint.opacity(isOutgoing ? 0.72 : 0)))
                .overlay(
                    shape.stroke(
                        LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        case .imessage:
            if isOutgoing {
                shape.fill(tint)
                    .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0), .black.opacity(0.10)], startPoint: .top, endPoint: .bottom)))
            } else {
                shape.fill(theme.colors.surfaceMuted)
            }
        }
    }
}

// MARK: - Colours

extension KitoChatBubbleStyle {
    /// The text colour inside a bubble.
    func foreground(isOutgoing: Bool, tint: Color, onTint: Color, theme: KitoTheme) -> Color {
        guard isOutgoing else { return theme.colors.onSurface }
        switch self {
        case .minimal: return theme.colors.onSurface
        case .modern, .glass, .imessage: return onTint
        }
    }
}

extension Color {
    /// Black or white, whichever reads better on this colour in `environment`.
    func kitoContrasting(in environment: EnvironmentValues) -> Color {
        let resolved = resolve(in: environment)
        let luminance = 0.2126 * resolved.linearRed + 0.7152 * resolved.linearGreen + 0.0722 * resolved.linearBlue
        return luminance > 0.36 ? .black : .white
    }
}

/// The accent a view should use and the colour to put on it.
struct KitoChatAccent {
    let tint: Color
    let onTint: Color

    init(tint: Color?, theme: KitoTheme, environment: EnvironmentValues) {
        if let tint {
            self.tint = tint
            self.onTint = tint.kitoContrasting(in: environment)
        } else {
            self.tint = theme.colors.primary
            self.onTint = theme.colors.onPrimary
        }
    }
}

/// A stable pair of colours for a user's avatar and name.
enum KitoChatPalette {
    static let gradients: [[Color]] = [
        [Color(red: 1.00, green: 0.55, blue: 0.35), Color(red: 0.93, green: 0.27, blue: 0.47)],
        [Color(red: 0.25, green: 0.78, blue: 0.75), Color(red: 0.15, green: 0.47, blue: 0.87)],
        [Color(red: 0.62, green: 0.45, blue: 1.00), Color(red: 0.35, green: 0.27, blue: 0.85)],
        [Color(red: 0.45, green: 0.85, blue: 0.45), Color(red: 0.13, green: 0.60, blue: 0.47)],
        [Color(red: 1.00, green: 0.78, blue: 0.30), Color(red: 0.96, green: 0.49, blue: 0.16)],
        [Color(red: 0.98, green: 0.45, blue: 0.62), Color(red: 0.69, green: 0.28, blue: 0.85)],
        [Color(red: 0.40, green: 0.72, blue: 1.00), Color(red: 0.22, green: 0.38, blue: 0.93)],
        [Color(red: 0.80, green: 0.60, blue: 0.45), Color(red: 0.55, green: 0.35, blue: 0.25)],
    ]

    static func colors(for user: KitoChatUser) -> [Color] {
        if let color = user.color { return [color.opacity(0.75), color] }
        return gradients[user.paletteIndex(count: gradients.count)]
    }

    static func nameColor(for user: KitoChatUser) -> Color {
        colors(for: user).last ?? .accentColor
    }
}

// MARK: - Wallpaper

/// What sits behind the conversation.
public enum KitoChatWallpaper: String, CaseIterable, Identifiable, Sendable {
    /// The theme background.
    case plain
    /// Soft drifting colour blobs from the tint — made for `.glass` bubbles.
    case aurora
    /// A faint dot grid.
    case dots

    public var id: String { rawValue }
}

struct KitoChatWallpaperView: View {
    let wallpaper: KitoChatWallpaper
    let tint: Color

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            theme.colors.background
            switch wallpaper {
            case .plain:
                EmptyView()
            case .aurora:
                GeometryReader { proxy in
                    let size = proxy.size
                    ZStack {
                        blob(tint.opacity(0.55), diameter: size.width * 0.9)
                            .offset(x: drift ? -size.width * 0.25 : -size.width * 0.05, y: -size.height * 0.28)
                        blob(Color(red: 1.0, green: 0.55, blue: 0.4).opacity(0.40), diameter: size.width * 0.8)
                            .offset(x: drift ? size.width * 0.3 : size.width * 0.15, y: drift ? size.height * 0.05 : size.height * 0.15)
                        blob(Color(red: 0.55, green: 0.4, blue: 1.0).opacity(0.40), diameter: size.width)
                            .offset(x: drift ? -size.width * 0.1 : -size.width * 0.3, y: size.height * 0.38)
                    }
                    .frame(width: size.width, height: size.height)
                }
                .blur(radius: 60)
            case .dots:
                Canvas { context, size in
                    let step: CGFloat = 18
                    var y: CGFloat = step / 2
                    var row = 0
                    while y < size.height {
                        var x: CGFloat = row.isMultiple(of: 2) ? step / 2 : step
                        while x < size.width {
                            context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(theme.colors.onBackground.opacity(0.10)))
                            x += step
                        }
                        y += step
                        row += 1
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard wallpaper == .aurora, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color, diameter: CGFloat) -> some View {
        Circle().fill(color).frame(width: diameter, height: diameter)
    }
}
