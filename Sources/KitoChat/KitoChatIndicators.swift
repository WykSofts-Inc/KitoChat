//
//  KitoChatIndicators.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

// MARK: - Typing indicator

/// Three bouncing dots in an incoming bubble.
///
/// ```swift
/// if isTyping { KitoTypingIndicator(style: .imessage) }
/// ```
public struct KitoTypingIndicator: View {
    private let style: KitoChatBubbleStyle
    private let dotColor: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(style: KitoChatBubbleStyle = .modern, dotColor: Color? = nil) {
        self.style = style
        self.dotColor = dotColor
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = max(0, sin(time * 2 * .pi / 1.1 - Double(index) * 0.75))
                    Circle()
                        .fill(dotColor ?? theme.colors.onSurface.opacity(0.55))
                        .frame(width: 8, height: 8)
                        .offset(y: reduceMotion ? 0 : -5 * wave)
                        .opacity(0.45 + 0.55 * wave)
                        .scaleEffect(reduceMotion ? 1 : 0.9 + 0.15 * wave)
                }
            }
            .padding(.horizontal, theme.spacing.md + 2)
            .padding(.vertical, theme.spacing.md)
            .padding(.leading, style.tail != .none ? 3 : 0)
            .background(KitoBubbleBackground(style: style, isOutgoing: false, position: .single, tint: theme.colors.primary))
        }
        .accessibilityElement()
        .accessibilityLabel("Typing")
    }
}

// MARK: - Status ticks

/// A clock while sending, one tick when sent, two when delivered, two tinted when read, and a red
/// badge when it failed — each change animates.
public struct KitoChatStatusTicks: View {
    private let status: KitoChatMessageStatus
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ status: KitoChatMessageStatus, tint: Color? = nil) {
        self.status = status
        self.tint = tint
    }

    public var body: some View {
        let readColor = tint ?? theme.colors.primary
        let delivered = status == .delivered || status == .read
        ZStack {
            switch status {
            case .sending:
                Image(systemName: "clock")
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(theme.colors.danger)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            case .sent, .delivered, .read:
                ZStack(alignment: .leading) {
                    Image(systemName: "checkmark")
                    if delivered {
                        Image(systemName: "checkmark")
                            .offset(x: 5)
                            .transition(.asymmetric(insertion: .scale(scale: 0.2, anchor: .leading).combined(with: .opacity), removal: .opacity))
                    }
                }
                .frame(width: 18, alignment: .leading)
                .foregroundStyle(status == .read ? readColor : theme.colors.onSurface.opacity(0.45))
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(theme.colors.onSurface.opacity(0.45))
        .frame(height: 14)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.55), value: status)
        .accessibilityElement()
        .accessibilityLabel(status.accessibilityLabel)
    }
}

// MARK: - Avatar

/// A round avatar — the photo if there's a URL, otherwise initials on a gradient — with a
/// pulsing green dot when the person is online.
public struct KitoChatAvatar: View {
    private let user: KitoChatUser
    private let size: CGFloat
    private let showsOnlineStatus: Bool

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ user: KitoChatUser, size: CGFloat = 40, showsOnlineStatus: Bool = true) {
        self.user = user
        self.size = size
        self.showsOnlineStatus = showsOnlineStatus
    }

    public var body: some View {
        let colors = KitoChatPalette.colors(for: user)
        ZStack {
            Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(user.initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
            if let url = user.avatarURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill().transition(.opacity)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            if showsOnlineStatus && user.isOnline {
                KitoOnlineDot(size: max(8, size * 0.28), ring: theme.colors.background, color: theme.colors.success, reduceMotion: reduceMotion)
                    .offset(x: size * 0.02, y: size * 0.02)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: user.isOnline)
        .accessibilityElement()
        .accessibilityLabel(user.isOnline && showsOnlineStatus ? "\(user.name), online" : user.name)
    }
}

private struct KitoOnlineDot: View {
    let size: CGFloat
    let ring: Color
    let color: Color
    let reduceMotion: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(color.opacity(0.45))
                    .scaleEffect(pulse ? 1.9 : 1)
                    .opacity(pulse ? 0 : 0.8)
            }
            Circle().fill(color).overlay(Circle().stroke(ring, lineWidth: max(1.5, size * 0.2)))
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

// MARK: - Header

/// The bar above a conversation: back, avatar, name and a subtitle that switches to
/// "Amani is typing…" while someone types.
///
/// ```swift
/// KitoChatHeader(user: amani, typingUsers: typing, onBack: { dismiss() }, onCall: { … })
/// ```
public struct KitoChatHeader: View {
    private let user: KitoChatUser
    private let title: String?
    private let typingUsers: [KitoChatUser]
    private let subtitle: String?
    private let tint: Color?
    private let onBack: (() -> Void)?
    private let onCall: (() -> Void)?
    private let onVideo: (() -> Void)?

    @Environment(\.kitoTheme) private var theme

    public init(
        user: KitoChatUser,
        title: String? = nil,
        typingUsers: [KitoChatUser] = [],
        subtitle: String? = nil,
        tint: Color? = nil,
        onBack: (() -> Void)? = nil,
        onCall: (() -> Void)? = nil,
        onVideo: (() -> Void)? = nil
    ) {
        self.user = user
        self.title = title
        self.typingUsers = typingUsers
        self.subtitle = subtitle
        self.tint = tint
        self.onBack = onBack
        self.onCall = onCall
        self.onVideo = onVideo
    }

    private var resolvedSubtitle: (text: String, isTyping: Bool)? {
        if !typingUsers.isEmpty {
            return (KitoChatDateFormat.typingText(for: typingUsers.map(\.firstName)), true)
        }
        if let subtitle { return (subtitle, false) }
        return user.isOnline ? ("Online", false) : nil
    }

    public var body: some View {
        let accent = tint ?? theme.colors.primary
        HStack(spacing: theme.spacing.sm + 2) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.colors.onSurface)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(KitoPressableStyle())
                .accessibilityLabel("Back")
            }
            KitoChatAvatar(user, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(title ?? user.name)
                    .font(theme.typography.bodyEmphasized.weight(.semibold))
                    .foregroundStyle(theme.colors.onSurface)
                    .lineLimit(1)
                if let resolvedSubtitle {
                    Text(resolvedSubtitle.text)
                        .font(theme.typography.caption.weight(resolvedSubtitle.isTyping ? .semibold : .regular))
                        .foregroundStyle(resolvedSubtitle.isTyping ? accent : theme.colors.onSurface.opacity(0.6))
                        .lineLimit(1)
                        .id(resolvedSubtitle.text)
                        .transition(.push(from: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: resolvedSubtitle?.text)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if let onVideo { circleButton("video.fill", label: "Video call", action: onVideo) }
            if let onCall { circleButton("phone.fill", label: "Call", action: onCall) }
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.sm)
        .background {
            Rectangle().fill(.bar).ignoresSafeArea(edges: .top)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.border.opacity(0.6)).frame(height: 0.5) }
        }
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.onSurface)
                .frame(width: 38, height: 38)
                .background(Circle().fill(theme.colors.surfaceMuted))
        }
        .buttonStyle(KitoPressableStyle())
        .accessibilityLabel(label)
    }
}
