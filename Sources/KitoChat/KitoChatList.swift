//
//  KitoChatList.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

// MARK: - Row

/// An inbox row: avatar with online dot, name, last-message preview (or "typing…"), time, unread
/// badge, and pinned / muted icons.
///
/// ```swift
/// KitoChatListRow(conversation, currentUserID: me.id)
/// ```
public struct KitoChatListRow: View {
    private let conversation: KitoChatConversation
    private let currentUserID: String?
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.self) private var environment

    public init(_ conversation: KitoChatConversation, currentUserID: String? = nil, tint: Color? = nil) {
        self.conversation = conversation
        self.currentUserID = currentUserID
        self.tint = tint
    }

    private var isFromMe: Bool {
        guard let currentUserID, let last = conversation.lastMessage else { return false }
        return last.author.id == currentUserID
    }

    public var body: some View {
        let accent = KitoChatAccent(tint: tint, theme: theme, environment: environment)
        let hasUnread = conversation.unreadCount > 0
        HStack(spacing: theme.spacing.md) {
            KitoChatAvatar(conversation.user, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: theme.spacing.xs) {
                    Text(conversation.displayName)
                        .font(theme.typography.bodyEmphasized.weight(hasUnread ? .bold : .semibold))
                        .foregroundStyle(theme.colors.onSurface)
                        .lineLimit(1)
                    if conversation.isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.colors.onSurface.opacity(0.4))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer(minLength: theme.spacing.sm)
                    if let date = conversation.lastMessage?.date {
                        Text(KitoChatDateFormat.listTimestamp(for: date))
                            .font(theme.typography.caption.weight(hasUnread ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(hasUnread && !conversation.isMuted ? accent.tint : theme.colors.onSurface.opacity(0.5))
                    }
                }
                HStack(alignment: .top, spacing: theme.spacing.xs) {
                    preview(accent: accent)
                    Spacer(minLength: theme.spacing.sm)
                    HStack(spacing: theme.spacing.xs) {
                        if conversation.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 12))
                                .rotationEffect(.degrees(45))
                                .foregroundStyle(theme.colors.onSurface.opacity(0.4))
                                .transition(.scale.combined(with: .opacity))
                        }
                        if hasUnread {
                            Text(conversation.unreadCount > 99 ? "99+" : "\(conversation.unreadCount)")
                                .font(.system(size: 12, weight: .bold).monospacedDigit())
                                .foregroundStyle(conversation.isMuted ? theme.colors.onSurface : accent.onTint)
                                .contentTransition(.numericText(value: Double(conversation.unreadCount)))
                                .padding(.horizontal, 6)
                                .frame(minWidth: 22, minHeight: 22)
                                .background(Capsule().fill(conversation.isMuted ? theme.colors.surfaceMuted : accent.tint))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, theme.spacing.sm)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: conversation)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func preview(accent: KitoChatAccent) -> some View {
        if conversation.isTyping {
            HStack(spacing: 4) {
                Text("typing")
                KitoInlineTypingDots(color: accent.tint)
            }
            .font(theme.typography.label)
            .foregroundStyle(accent.tint)
            .transition(.opacity)
        } else if let last = conversation.lastMessage {
            HStack(spacing: 4) {
                if isFromMe {
                    KitoChatStatusTicks(last.status, tint: accent.tint)
                }
                Text(isFromMe ? "You: \(last.previewText)" : last.previewText)
                    .lineLimit(2)
            }
            .font(theme.typography.label.weight(.regular))
            .foregroundStyle(theme.colors.onSurface.opacity(conversation.unreadCount > 0 ? 0.85 : 0.55))
            .transition(.opacity)
        }
    }

    private var accessibilityLabel: String {
        var parts = [conversation.displayName]
        if conversation.isPinned { parts.append("pinned") }
        if conversation.isMuted { parts.append("muted") }
        if conversation.unreadCount > 0 { parts.append("\(conversation.unreadCount) unread") }
        if conversation.isTyping {
            parts.append("typing")
        } else if let last = conversation.lastMessage {
            parts.append((isFromMe ? "You: " : "") + last.previewText)
            parts.append(KitoChatDateFormat.listTimestamp(for: last.date))
        }
        return parts.joined(separator: ", ")
    }
}

private struct KitoInlineTypingDots: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = max(0, sin(time * 2 * .pi / 1.1 - Double(index) * 0.75))
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                        .offset(y: reduceMotion ? 0 : -2.5 * wave)
                        .opacity(0.4 + 0.6 * wave)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Swipe actions

public extension View {
    /// Inbox swipe actions for a row inside a `List`: swipe right for read/unread and pin, left for
    /// mute and delete. Leave a handler `nil` to hide its button.
    func kitoChatSwipeActions(
        for conversation: KitoChatConversation,
        onToggleRead: (() -> Void)? = nil,
        onTogglePin: (() -> Void)? = nil,
        onToggleMute: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        modifier(KitoChatSwipeActions(conversation: conversation, onToggleRead: onToggleRead, onTogglePin: onTogglePin, onToggleMute: onToggleMute, onDelete: onDelete))
    }
}

private struct KitoChatSwipeActions: ViewModifier {
    let conversation: KitoChatConversation
    let onToggleRead: (() -> Void)?
    let onTogglePin: (() -> Void)?
    let onToggleMute: (() -> Void)?
    let onDelete: (() -> Void)?

    @Environment(\.kitoTheme) private var theme

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let onToggleRead {
                    Button(action: onToggleRead) {
                        Label(conversation.unreadCount > 0 ? "Read" : "Unread",
                              systemImage: conversation.unreadCount > 0 ? "envelope.open.fill" : "envelope.badge.fill")
                    }
                    .tint(theme.colors.primary)
                }
                if let onTogglePin {
                    Button(action: onTogglePin) {
                        Label(conversation.isPinned ? "Unpin" : "Pin", systemImage: conversation.isPinned ? "pin.slash.fill" : "pin.fill")
                    }
                    .tint(theme.colors.warning)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash.fill")
                    }
                    .tint(theme.colors.danger)
                }
                if let onToggleMute {
                    Button(action: onToggleMute) {
                        Label(conversation.isMuted ? "Unmute" : "Mute", systemImage: conversation.isMuted ? "bell.fill" : "bell.slash.fill")
                    }
                    .tint(theme.colors.secondary)
                }
            }
    }
}

// MARK: - List

/// A ready-made inbox: pinned conversations first, swipe to read, pin, mute or delete, and rows
/// that animate as conversations change.
///
/// ```swift
/// KitoChatList(conversations: $conversations, currentUserID: me.id) { conversation in
///     path.append(conversation)
/// }
/// ```
public struct KitoChatList: View {
    @Binding private var conversations: [KitoChatConversation]
    private let currentUserID: String?
    private let tint: Color?
    private let onSelect: (KitoChatConversation) -> Void

    @Environment(\.kitoTheme) private var theme

    public init(
        conversations: Binding<[KitoChatConversation]>,
        currentUserID: String? = nil,
        tint: Color? = nil,
        onSelect: @escaping (KitoChatConversation) -> Void = { _ in }
    ) {
        _conversations = conversations
        self.currentUserID = currentUserID
        self.tint = tint
        self.onSelect = onSelect
    }

    public var body: some View {
        List {
            ForEach(KitoChatConversation.sorted(conversations)) { conversation in
                Button {
                    onSelect(conversation)
                } label: {
                    KitoChatListRow(conversation, currentUserID: currentUserID, tint: tint)
                }
                .buttonStyle(.plain)
                .listRowBackground(theme.colors.background)
                .listRowSeparatorTint(theme.colors.border.opacity(0.6))
                .alignmentGuide(.listRowSeparatorLeading) { _ in 66 }
                .kitoChatSwipeActions(
                    for: conversation,
                    onToggleRead: { update(conversation.id) { $0.unreadCount = $0.unreadCount > 0 ? 0 : 1 } },
                    onTogglePin: { update(conversation.id) { $0.isPinned.toggle() } },
                    onToggleMute: { update(conversation.id) { $0.isMuted.toggle() } },
                    onDelete: { withAnimation(.spring) { conversations.removeAll { $0.id == conversation.id } } }
                )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.colors.background)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: conversations)
    }

    private func update(_ id: String, _ change: (inout KitoChatConversation) -> Void) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { change(&conversations[index]) }
    }
}
