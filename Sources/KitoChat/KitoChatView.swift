//
//  KitoChatView.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit
import Combine
import KitoCore

/// A whole conversation: grouped bubbles under sticky date separators, an "N unread" divider,
/// read receipts, a typing indicator, a scroll-to-bottom button that counts new messages, and the
/// composer. Long-press a bubble to react, reply, copy or delete; swipe it right to reply; tap it
/// to see its time; tap a photo to open it.
///
/// The view edits `messages` itself — sending appends a `.sending` message, reactions and deletes
/// update it — and hands every new message to `onSend` so you can deliver it and move its status on.
///
/// ```swift
/// @State private var messages: [KitoChatMessage] = []
///
/// KitoChatView(messages: $messages, currentUser: me, style: .imessage) { message in
///     Task {
///         try await api.send(message)
///         messages.kitoUpdateStatus(of: message.id, to: .sent)
///     }
/// }
/// ```
public struct KitoChatView: View {
    @Binding private var messages: [KitoChatMessage]
    private let currentUser: KitoChatUser
    private let style: KitoChatBubbleStyle
    private let wallpaper: KitoChatWallpaper
    private let typingUsers: [KitoChatUser]
    private let unreadCount: Int
    private let showsComposer: Bool
    private let placeholder: String
    private let tint: Color?
    private let onAttach: (() -> Void)?
    private let onSend: ((KitoChatMessage) -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var imageNamespace

    @State private var draft = ""
    @State private var replyTo: KitoChatReply?
    @State private var revealedTimeID: String?
    @State private var selectedID: String?
    @State private var expandedImageID: String?
    @State private var highlightedID: String?
    @State private var isAtBottom = true
    @State private var unseenCount = 0
    @State private var longPressCount = 0
    @State private var isKeyboardShown = false

    private static let bottomID = "kito.chat.bottom"

    public init(
        messages: Binding<[KitoChatMessage]>,
        currentUser: KitoChatUser,
        style: KitoChatBubbleStyle = .modern,
        wallpaper: KitoChatWallpaper = .plain,
        typingUsers: [KitoChatUser] = [],
        unreadCount: Int = 0,
        showsComposer: Bool = true,
        placeholder: String = "Message",
        tint: Color? = nil,
        onAttach: (() -> Void)? = nil,
        onSend: ((KitoChatMessage) -> Void)? = nil
    ) {
        _messages = messages
        self.currentUser = currentUser
        self.style = style
        self.wallpaper = wallpaper
        self.typingUsers = typingUsers
        self.unreadCount = unreadCount
        self.showsComposer = showsComposer
        self.placeholder = placeholder
        self.tint = tint
        self.onAttach = onAttach
        self.onSend = onSend
    }

    private var accent: KitoChatAccent { KitoChatAccent(tint: tint, theme: theme, environment: environment) }
    private var isGroup: Bool { KitoChatTimeline.isGroupConversation(messages, currentUserID: currentUser.id) }
    private var insertion: Animation { reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.78) }

    public var body: some View {
        let timeline = KitoChatTimeline(messages: messages, currentUserID: currentUser.id, unreadCount: unreadCount)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(timeline.sections) { section in
                        Section {
                            ForEach(section.rows) { row in
                                rowView(row, proxy: proxy).id(row.id)
                            }
                        } header: {
                            dateSeparator(section.title)
                        }
                    }
                    if !typingUsers.isEmpty {
                        typingRow
                            .id("kito.chat.typing")
                            .transition(.scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity))
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                        .onAppear {
                            if !isAtBottom { isAtBottom = true }
                            if unseenCount != 0 { unseenCount = 0 }
                        }
                        .onDisappear { if isAtBottom { isAtBottom = false } }
                }
                .padding(.horizontal, theme.spacing.md)
                .padding(.bottom, theme.spacing.sm)
                .animation(insertion, value: messages)
                .animation(insertion, value: typingUsers.map(\.id))
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .background(KitoChatWallpaperView(wallpaper: wallpaper, tint: accent.tint))
            .overlay(alignment: .bottomTrailing) { scrollButton(proxy: proxy) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsComposer {
                    KitoChatComposer(text: $draft, replyTo: $replyTo, placeholder: placeholder, tint: tint, onAttach: onAttach) { kind in
                        send(kind)
                    }
                }
            }
            .overlayPreferenceValue(KitoSelectedBubbleKey.self) { anchor in
                GeometryReader { geometry in
                    if let anchor, let message = selectedMessage, let position = position(of: message, in: timeline) {
                        let isOutgoing = message.author.id == currentUser.id
                        KitoReactionOverlay(
                            rect: geometry[anchor],
                            container: geometry.size,
                            isOutgoing: isOutgoing,
                            canCopy: message.copyableText != nil,
                            selectedEmoji: message.reaction(of: currentUser.id),
                            tint: accent.tint,
                            bubble: bubble(for: message, position: position, proxy: proxy),
                            onReact: { emoji in react(emoji, to: message.id) },
                            onReply: { reply(to: message) },
                            onCopy: { UIPasteboard.general.string = message.copyableText },
                            onDelete: { delete(message.id) },
                            onDismiss: { selectedID = nil }
                        )
                    }
                }
            }
            .overlay { imageViewer }
            .environment(\.kitoChatImageViewer, KitoChatImageViewerContext(namespace: imageNamespace, expandedID: expandedImageID) { id in
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { expandedImageID = id }
            })
            .onChange(of: messages.last?.id) { old, new in
                handleNewLastMessage(old: old, new: new, proxy: proxy)
            }
            .onChange(of: typingUsers.isEmpty) { _, isEmpty in
                guard !isEmpty, isAtBottom else { return }
                withAnimation(insertion) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                guard !isKeyboardShown else { return }
                isKeyboardShown = true
                if isAtBottom { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardShown = false
            }
            .task { await jumpToUnread(proxy: proxy) }
            .sensoryFeedback(.impact(weight: .medium), trigger: longPressCount)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func rowView(_ row: KitoChatTimeline.Row, proxy: ScrollViewProxy) -> some View {
        switch row {
        case .unreadDivider(let count):
            unreadDivider(count)
        case .message(let message, let position):
            let isOutgoing = message.author.id == currentUser.id
            KitoMessageRow(
                message: message,
                position: position,
                isOutgoing: isOutgoing,
                showsAvatar: isGroup && !isOutgoing,
                isTimeRevealed: revealedTimeID == message.id,
                isSelected: selectedID == message.id,
                isHighlighted: highlightedID == message.id,
                tint: accent.tint,
                bubble: bubble(for: message, position: position, proxy: proxy),
                onTap: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        revealedTimeID = revealedTimeID == message.id ? nil : message.id
                    }
                },
                onLongPress: {
                    guard !message.isSystem else { return }
                    longPressCount += 1
                    selectedID = message.id
                },
                onReply: { reply(to: message) },
                onRetry: { retry(message.id) },
                accessibilityActions: .init(
                    react: { react(KitoChatReaction.quickPicks[0], to: message.id) },
                    reply: { reply(to: message) },
                    copy: message.copyableText.map { text in { UIPasteboard.general.string = text } },
                    delete: { delete(message.id) }
                )
            )
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .scale(scale: 0.6, anchor: isOutgoing ? .bottomTrailing : .bottomLeading)
                            .combined(with: .offset(y: 24))
                            .combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    )
            )
        }
    }

    private func bubble(for message: KitoChatMessage, position: KitoChatGroupPosition, proxy: ScrollViewProxy) -> KitoChatBubble {
        let isOutgoing = message.author.id == currentUser.id
        return KitoChatBubble(
            message,
            isOutgoing: isOutgoing,
            position: position,
            style: style,
            showsAuthorName: isGroup && !isOutgoing && position.isGroupStart,
            currentUserID: currentUser.id,
            tint: tint,
            onReactionTap: { emoji in react(emoji, to: message.id) },
            onQuoteTap: { id in jump(to: id, proxy: proxy) }
        )
    }

    private var typingRow: some View {
        HStack(alignment: .bottom, spacing: theme.spacing.sm - 2) {
            if isGroup, let first = typingUsers.first {
                KitoChatAvatar(first, size: 28, showsOnlineStatus: false)
            }
            KitoTypingIndicator(style: style)
            Spacer(minLength: 0)
        }
        .padding(.top, theme.spacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KitoChatDateFormat.typingText(for: typingUsers.map(\.firstName)))
    }

    private func dateSeparator(_ title: String) -> some View {
        Text(title)
            .font(theme.typography.caption.weight(.semibold))
            .foregroundStyle(theme.colors.onSurface.opacity(0.7))
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.xs + 1)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(theme.colors.border.opacity(0.4), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.spacing.sm)
            .accessibilityAddTraits(.isHeader)
    }

    private func unreadDivider(_ count: Int) -> some View {
        HStack(spacing: theme.spacing.sm) {
            Rectangle().fill(accent.tint.opacity(0.35)).frame(height: 1)
            Text(count == 1 ? "1 unread message" : "\(count) unread messages")
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(accent.tint)
                .fixedSize()
            Rectangle().fill(accent.tint.opacity(0.35)).frame(height: 1)
        }
        .padding(.vertical, theme.spacing.md)
        .accessibilityElement(children: .combine)
    }

    // MARK: Floating pieces

    @ViewBuilder
    private func scrollButton(proxy: ScrollViewProxy) -> some View {
        if !isAtBottom {
            Button {
                withAnimation(insertion) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.colors.onSurface)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.regularMaterial))
                    .overlay(Circle().strokeBorder(theme.colors.border.opacity(0.5), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                    .symbolEffect(.bounce.down, value: unseenCount)
                    .overlay(alignment: .top) {
                        if unseenCount > 0 {
                            Text(unseenCount > 99 ? "99+" : "\(unseenCount)")
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(accent.onTint)
                                .contentTransition(.numericText(value: Double(unseenCount)))
                                .padding(.horizontal, 6)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(Capsule().fill(accent.tint))
                                .offset(y: -10)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
            }
            .buttonStyle(KitoPressableStyle())
            .padding(.trailing, theme.spacing.lg)
            .padding(.bottom, theme.spacing.md)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: unseenCount)
            .accessibilityLabel(unseenCount > 0 ? "Scroll to latest, \(unseenCount) new" : "Scroll to latest")
        }
    }

    @ViewBuilder
    private var imageViewer: some View {
        if let id = expandedImageID, let message = messages.first(where: { $0.id == id }), case .image(let image) = message.kind {
            KitoImageViewer(image: image, messageID: id, namespace: imageNamespace) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { expandedImageID = nil }
            }
            .zIndex(2)
        }
    }

    // MARK: Actions

    private var selectedMessage: KitoChatMessage? {
        selectedID.flatMap { id in messages.first { $0.id == id } }
    }

    private func position(of message: KitoChatMessage, in timeline: KitoChatTimeline) -> KitoChatGroupPosition? {
        for section in timeline.sections {
            for row in section.rows {
                if case .message(let candidate, let position) = row, candidate.id == message.id { return position }
            }
        }
        return nil
    }

    private func send(_ kind: KitoChatMessage.Kind) {
        let message = KitoChatMessage(author: currentUser, kind: kind, status: .sending, replyTo: replyTo)
        withAnimation(insertion) { messages.append(message) }
        onSend?(message)
    }

    private func retry(_ id: String) {
        guard messages.kitoUpdateStatus(of: id, to: .sending), let message = messages.first(where: { $0.id == id }) else { return }
        onSend?(message)
    }

    private func react(_ emoji: String, to id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            messages[index].toggleReaction(emoji, by: currentUser.id)
            selectedID = nil
        }
    }

    private func reply(to message: KitoChatMessage) {
        selectedID = nil
        withAnimation(insertion) { replyTo = KitoChatReply(message) }
    }

    private func delete(_ id: String) {
        withAnimation(insertion) {
            messages.removeAll { $0.id == id }
            selectedID = nil
            if replyTo?.messageID == id { replyTo = nil }
        }
    }

    private func jump(to id: String, proxy: ScrollViewProxy) {
        guard messages.contains(where: { $0.id == id }) else { return }
        withAnimation(insertion) { proxy.scrollTo(id, anchor: .center) }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeOut(duration: 0.2)) { highlightedID = id }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.6)) { if highlightedID == id { highlightedID = nil } }
        }
    }

    private func handleNewLastMessage(old: String?, new: String?, proxy: ScrollViewProxy) {
        guard let new, new != old, let last = messages.last, last.id == new else { return }
        if let old, !messages.contains(where: { $0.id == old }) { return }
        if last.author.id == currentUser.id || isAtBottom {
            withAnimation(insertion) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        } else if !last.isSystem {
            unseenCount += 1
        }
    }

    private func jumpToUnread(proxy: ScrollViewProxy) async {
        guard let divider = KitoChatTimeline.unreadDivider(in: messages, currentUserID: currentUser.id, unreadCount: unreadCount) else { return }
        try? await Task.sleep(for: .milliseconds(120))
        proxy.scrollTo(KitoChatTimeline.unreadDividerID, anchor: .top)
        try? await Task.sleep(for: .milliseconds(250))
        if !isAtBottom { unseenCount = divider.count }
    }
}

// MARK: - Row

/// One message in the list: avatar, bubble, time and receipts, with tap, long-press and swipe.
struct KitoMessageRow: View {
    struct AccessibilityActions {
        let react: () -> Void
        let reply: () -> Void
        let copy: (() -> Void)?
        let delete: () -> Void
    }

    let message: KitoChatMessage
    let position: KitoChatGroupPosition
    let isOutgoing: Bool
    let showsAvatar: Bool
    let isTimeRevealed: Bool
    let isSelected: Bool
    let isHighlighted: Bool
    let tint: Color
    let bubble: KitoChatBubble
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onReply: () -> Void
    let onRetry: () -> Void
    let accessibilityActions: AccessibilityActions

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swipe: CGFloat = 0
    @State private var isSwiping = false
    @State private var passedThreshold = false

    private let avatarSize: CGFloat = 28

    var body: some View {
        if message.isSystem {
            bubble
                .padding(.vertical, theme.spacing.sm)
                .accessibilityElement(children: .combine)
        } else {
            content
        }
    }

    private var content: some View {
        let showsFooter = isTimeRevealed || message.status == .failed || (isOutgoing && position.isGroupEnd)
        let progress = KitoSwipeReply.progress(for: swipe)
        return VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 3) {
            ZStack(alignment: .leading) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(passedThreshold ? tint : theme.colors.onSurface.opacity(0.6))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(theme.colors.surfaceMuted))
                    .scaleEffect(0.4 + 0.6 * progress)
                    .opacity(Double(progress))
                    .offset(x: min(swipe, KitoSwipeReply.threshold) / 2 - 18)
                    .symbolEffect(.bounce, value: passedThreshold)
                    .accessibilityHidden(true)

                HStack(alignment: .bottom, spacing: theme.spacing.sm - 2) {
                    if isOutgoing { Spacer(minLength: 52) }
                    if showsAvatar {
                        Group {
                            if position.isGroupEnd {
                                KitoChatAvatar(message.author, size: avatarSize, showsOnlineStatus: false)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: avatarSize, height: avatarSize)
                    }
                    bubble
                        .anchorPreference(key: KitoSelectedBubbleKey.self, value: .bounds) { isSelected ? $0 : nil }
                        .opacity(isSelected ? 0 : 1)
                        .onTapGesture(perform: onTap)
                        .onLongPressGesture(minimumDuration: 0.32, perform: onLongPress)
                        .accessibilityElement(children: accessibilityChildren)
                        .accessibilityLabel(accessibilityLabel)
                        .accessibilityValue(isOutgoing ? message.status.accessibilityLabel : "")
                        .accessibilityHint("Actions available")
                        .accessibilityAction(named: "Reply", accessibilityActions.reply)
                        .accessibilityAction(named: "React with a heart", accessibilityActions.react)
                        .modifier(KitoOptionalAccessibilityAction(name: "Copy", action: accessibilityActions.copy))
                        .accessibilityAction(named: "Delete", accessibilityActions.delete)
                    if !isOutgoing { Spacer(minLength: 52) }
                }
                .offset(x: swipe)
            }
            .simultaneousGesture(swipeGesture)

            if showsFooter {
                footer
                    .padding(.leading, showsAvatar ? avatarSize + theme.spacing.sm - 2 : 0)
                    .padding(.horizontal, theme.spacing.xs)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, position.isGroupStart ? theme.spacing.sm : 2)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
                .fill(tint.opacity(isHighlighted ? 0.14 : 0))
                .padding(.horizontal, -theme.spacing.sm)
        )
        .sensoryFeedback(.impact(weight: .light), trigger: passedThreshold) { _, new in new }
    }

    private var footer: some View {
        HStack(spacing: theme.spacing.xs) {
            if isTimeRevealed {
                Text(KitoChatDateFormat.time(message.date))
                    .font(theme.typography.caption.monospacedDigit())
                    .foregroundStyle(theme.colors.onSurface.opacity(0.5))
            }
            if isOutgoing {
                if message.status == .failed {
                    Button(action: onRetry) {
                        HStack(spacing: 3) {
                            Text("Not delivered · Tap to retry")
                            Image(systemName: "arrow.clockwise")
                        }
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.danger)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Not delivered. Retry")
                }
                KitoChatStatusTicks(message.status, tint: tint)
            }
        }
    }

    private var accessibilityChildren: AccessibilityChildBehavior {
        if case .voice = message.kind { return .contain }
        return .combine
    }

    private var accessibilityLabel: String {
        let who = isOutgoing ? "You" : message.author.name
        let time = KitoChatDateFormat.time(message.date)
        let reactions = message.reactions.map { "\($0.emoji) \($0.count)" }.joined(separator: ", ")
        var label = "\(who): \(message.previewText), \(time)"
        if let reply = message.replyTo { label += ", replying to \(reply.authorName)" }
        if !reactions.isEmpty { label += ", reactions \(reactions)" }
        return label
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                let dx = value.translation.width, dy = value.translation.height
                if !isSwiping {
                    guard dx > 0, abs(dx) > abs(dy) * 1.6 else { return }
                    isSwiping = true
                }
                swipe = KitoSwipeReply.offset(for: dx)
                let passed = swipe >= KitoSwipeReply.threshold
                if passed != passedThreshold { passedThreshold = passed }
            }
            .onEnded { _ in
                if passedThreshold { onReply() }
                isSwiping = false
                passedThreshold = false
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.7)) { swipe = 0 }
            }
    }
}

private struct KitoOptionalAccessibilityAction: ViewModifier {
    let name: String
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.accessibilityAction(named: name, action)
        } else {
            content
        }
    }
}
