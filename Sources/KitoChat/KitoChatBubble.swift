//
//  KitoChatBubble.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// One message bubble: text, photo, voice note or system note, with its quoted reply and reaction chips.
/// `KitoChatView` lays these out for you; use it directly for custom layouts.
///
/// ```swift
/// KitoChatBubble(message, isOutgoing: true, position: .last, style: .imessage)
/// ```
public struct KitoChatBubble: View {
    private let message: KitoChatMessage
    private let isOutgoing: Bool
    private let position: KitoChatGroupPosition
    private let style: KitoChatBubbleStyle
    private let showsAuthorName: Bool
    private let currentUserID: String?
    private let tint: Color?
    private let onReactionTap: ((String) -> Void)?
    private let onQuoteTap: ((String) -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.self) private var environment

    public init(
        _ message: KitoChatMessage,
        isOutgoing: Bool,
        position: KitoChatGroupPosition = .single,
        style: KitoChatBubbleStyle = .modern,
        showsAuthorName: Bool = false,
        currentUserID: String? = nil,
        tint: Color? = nil,
        onReactionTap: ((String) -> Void)? = nil,
        onQuoteTap: ((String) -> Void)? = nil
    ) {
        self.message = message
        self.isOutgoing = isOutgoing
        self.position = position
        self.style = style
        self.showsAuthorName = showsAuthorName
        self.currentUserID = currentUserID
        self.tint = tint
        self.onReactionTap = onReactionTap
        self.onQuoteTap = onQuoteTap
    }

    public var body: some View {
        let accent = KitoChatAccent(tint: tint, theme: theme, environment: environment)
        let foreground = style.foreground(isOutgoing: isOutgoing, tint: accent.tint, onTint: accent.onTint, theme: theme)
        Group {
            switch message.kind {
            case .system(let text):
                systemNote(text)
            case .text(let text):
                if let count = message.jumboEmojiCount, message.replyTo == nil {
                    Text(text)
                        .font(.system(size: count == 1 ? 56 : 44))
                        .padding(.vertical, theme.spacing.xxs)
                        .accessibilityLabel(text)
                } else {
                    textBubble(text, accent: accent, foreground: foreground)
                }
            case .image(let image):
                imageBubble(image, accent: accent, foreground: foreground)
            case .voice(let duration, let waveform, let url):
                bubbleChrome(accent: accent, foreground: foreground) {
                    KitoVoiceNoteContent(
                        messageID: message.id,
                        duration: duration,
                        waveform: waveform,
                        url: url,
                        isOutgoing: isOutgoing,
                        style: style,
                        accent: accent,
                        foreground: foreground
                    )
                    .padding(.horizontal, theme.spacing.md)
                    .padding(.vertical, theme.spacing.sm)
                }
            }
        }
        .overlay(alignment: isOutgoing ? .bottomLeading : .bottomTrailing) {
            if !message.reactions.isEmpty {
                KitoReactionChips(reactions: message.reactions, currentUserID: currentUserID, tint: accent.tint, onTap: onReactionTap)
                    .offset(x: isOutgoing ? -6 : 6, y: 16)
                    .transition(.scale(scale: 0.4, anchor: .top).combined(with: .opacity))
            }
        }
        .padding(.bottom, message.reactions.isEmpty ? 0 : 18)
    }

    // MARK: Pieces

    private func systemNote(_ text: String) -> some View {
        Text(text)
            .font(theme.typography.caption.weight(.medium))
            .foregroundStyle(theme.colors.onSurface.opacity(0.7))
            .multilineTextAlignment(.center)
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.xs + 2)
            .background(Capsule().fill(.thinMaterial))
            .frame(maxWidth: .infinity)
    }

    private func textBubble(_ text: String, accent: KitoChatAccent, foreground: Color) -> some View {
        bubbleChrome(accent: accent, foreground: foreground) {
            Text(Self.attributed(text))
                .font(theme.typography.body)
                .foregroundStyle(foreground)
                .tint(isOutgoing && style != .minimal ? foreground : accent.tint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, theme.spacing.md + 2)
                .padding(.vertical, theme.spacing.sm + 1)
        }
    }

    private func imageBubble(_ image: KitoChatImage, accent: KitoChatAccent, foreground: Color) -> some View {
        let shape = KitoBubbleShape(style: style, isOutgoing: isOutgoing, position: position, showsTail: false)
        return VStack(alignment: .leading, spacing: 0) {
            if showsAuthorName || message.replyTo != nil {
                header(accent: accent, foreground: foreground)
                    .padding(.horizontal, theme.spacing.sm)
                    .padding(.top, theme.spacing.sm)
                    .padding(.bottom, theme.spacing.xs)
            }
            KitoChatImageContent(image: image, messageID: message.id)
                .clipShape(RoundedRectangle(cornerRadius: max(4, style.cornerRadius - 4), style: .continuous))
                .padding(3)
            if let caption = image.caption, !caption.isEmpty {
                Text(Self.attributed(caption))
                    .font(theme.typography.body)
                    .foregroundStyle(foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, theme.spacing.md)
                    .padding(.top, theme.spacing.xs)
                    .padding(.bottom, theme.spacing.sm)
            }
        }
        .frame(width: KitoChatImageContent.width + 6)
        .background(KitoBubbleBackground(style: style, isOutgoing: isOutgoing, position: position, tint: accent.tint, showsTail: false))
        .contentShape(shape)
    }

    private func bubbleChrome<Content: View>(accent: KitoChatAccent, foreground: Color, @ViewBuilder content: () -> Content) -> some View {
        let showsHeader = showsAuthorName || message.replyTo != nil
        return VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                header(accent: accent, foreground: foreground)
                    .padding(.horizontal, theme.spacing.sm)
                    .padding(.top, theme.spacing.sm)
            }
            content()
        }
        .padding(isOutgoing ? .trailing : .leading, style.tail != .none && position.isGroupEnd ? 3 : 0)
        .background(KitoBubbleBackground(style: style, isOutgoing: isOutgoing, position: position, tint: accent.tint))
        .contentShape(KitoBubbleShape(style: style, isOutgoing: isOutgoing, position: position))
    }

    @ViewBuilder
    private func header(accent: KitoChatAccent, foreground: Color) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            if showsAuthorName {
                Text(message.author.name)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(KitoChatPalette.nameColor(for: message.author))
                    .padding(.horizontal, theme.spacing.xs)
            }
            if let reply = message.replyTo {
                KitoQuotedReply(reply: reply, isOutgoing: isOutgoing, style: style, accent: accent, foreground: foreground)
                    .onTapGesture { onQuoteTap?(reply.messageID) }
            }
        }
    }

    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

// MARK: - Quoted reply

/// The quote inside a bubble (and above the composer) that a reply points to.
struct KitoQuotedReply: View {
    let reply: KitoChatReply
    let isOutgoing: Bool
    let style: KitoChatBubbleStyle
    let accent: KitoChatAccent
    let foreground: Color

    @Environment(\.kitoTheme) private var theme

    var body: some View {
        let onFill = isOutgoing && style != .minimal
        HStack(spacing: theme.spacing.sm) {
            Capsule()
                .fill(onFill ? foreground.opacity(0.85) : accent.tint)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(reply.authorName)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(onFill ? foreground : accent.tint)
                HStack(spacing: 4) {
                    if let symbol = reply.symbol {
                        Image(systemName: symbol).imageScale(.small)
                    }
                    Text(reply.preview).lineLimit(2)
                }
                .font(theme.typography.caption)
                .foregroundStyle(onFill ? foreground.opacity(0.8) : theme.colors.onSurface.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, theme.spacing.xs + 2)
        .padding(.leading, theme.spacing.xs + 2)
        .padding(.trailing, theme.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous)
                .fill(onFill ? foreground.opacity(0.14) : accent.tint.opacity(0.10))
        )
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Replying to \(reply.authorName): \(reply.preview)")
    }
}

// MARK: - Reaction chips

struct KitoReactionChips: View {
    let reactions: [KitoChatReaction]
    let currentUserID: String?
    let tint: Color
    let onTap: ((String) -> Void)?

    @Environment(\.kitoTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(reactions) { reaction in
                let mine = currentUserID.map(reaction.includes) ?? false
                Button {
                    onTap?(reaction.emoji)
                } label: {
                    HStack(spacing: 3) {
                        Text(reaction.emoji).font(.system(size: 14))
                        if reaction.count > 1 {
                            Text("\(reaction.count)")
                                .font(theme.typography.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(mine ? tint : theme.colors.onSurface.opacity(0.75))
                                .contentTransition(.numericText(value: Double(reaction.count)))
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(mine ? AnyShapeStyle(tint.opacity(0.16)) : AnyShapeStyle(theme.colors.surface)))
                    .background(Capsule().fill(theme.colors.surface))
                    .overlay(Capsule().strokeBorder(mine ? tint.opacity(0.6) : theme.colors.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .disabled(onTap == nil)
                .transition(.scale(scale: 0.3).combined(with: .opacity))
                .accessibilityLabel("\(reaction.emoji) \(reaction.count)")
                .accessibilityAddTraits(mine ? .isSelected : [])
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: reactions)
    }
}

// MARK: - Image

/// Shares the full-screen viewer and its matched-geometry namespace with image bubbles.
struct KitoChatImageViewerContext {
    let namespace: Namespace.ID
    let expandedID: String?
    let open: (String) -> Void
}

private struct KitoChatImageViewerKey: EnvironmentKey {
    static let defaultValue: KitoChatImageViewerContext? = nil
}

extension EnvironmentValues {
    var kitoChatImageViewer: KitoChatImageViewerContext? {
        get { self[KitoChatImageViewerKey.self] }
        set { self[KitoChatImageViewerKey.self] = newValue }
    }
}

/// Draws a `KitoChatImage` from either source, with a soft placeholder while a URL loads.
struct KitoChatImageView: View {
    let image: KitoChatImage
    var contentMode: ContentMode = .fill

    @Environment(\.kitoTheme) private var theme

    var body: some View {
        switch image.source {
        case .image(let uiImage):
            Image(uiImage: uiImage).resizable().aspectRatio(contentMode: contentMode)
        case .url(let url):
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let loaded):
                    loaded.resizable().aspectRatio(contentMode: contentMode).transition(.opacity)
                case .failure:
                    ZStack {
                        theme.colors.surfaceMuted
                        Image(systemName: "photo").font(.title2).foregroundStyle(theme.colors.onSurface.opacity(0.4))
                    }
                default:
                    ZStack {
                        theme.colors.surfaceMuted
                        ProgressView()
                    }
                }
            }
        }
    }
}

/// The photo inside a bubble. Tap to open it full screen.
struct KitoChatImageContent: View {
    static let width: CGFloat = 236

    let image: KitoChatImage
    let messageID: String

    @Environment(\.kitoChatImageViewer) private var viewer
    @State private var isPresentingLocally = false

    var body: some View {
        let height = min(320, max(140, Self.width / max(0.2, image.aspectRatio)))
        ZStack {
            if viewer?.expandedID != messageID {
                matched(KitoChatImageView(image: image))
            }
        }
        .frame(width: Self.width, height: height)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            if let viewer { viewer.open(messageID) } else { isPresentingLocally = true }
        }
        .fullScreenCover(isPresented: $isPresentingLocally) {
            KitoImageViewer(image: image, messageID: messageID, namespace: nil) { isPresentingLocally = false }
        }
        .accessibilityElement()
        .accessibilityLabel(image.caption.map { "Photo: \($0)" } ?? "Photo")
        .accessibilityAddTraits([.isImage, .isButton])
        .accessibilityHint("Opens the photo full screen")
    }

    @ViewBuilder
    private func matched<V: View>(_ view: V) -> some View {
        if let namespace = viewer?.namespace {
            view.matchedGeometryEffect(id: messageID, in: namespace)
        } else {
            view
        }
    }
}
