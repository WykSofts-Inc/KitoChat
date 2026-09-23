//
//  KitoChatOverlays.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

// MARK: - Selected bubble anchor

struct KitoSelectedBubbleKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Reactions and actions

/// The long-press layer: the bubble lifted above a blurred conversation, an emoji bar above it and
/// Reply / Copy / Delete below. Everything shifts to stay on screen.
struct KitoReactionOverlay<Bubble: View>: View {
    let rect: CGRect
    let container: CGSize
    let isOutgoing: Bool
    let canCopy: Bool
    let selectedEmoji: String?
    let tint: Color
    let bubble: Bubble
    let onReact: (String) -> Void
    let onReply: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    private let barHeight: CGFloat = 52
    private let rowHeight: CGFloat = 46
    private let gap: CGFloat = 10
    private let menuWidth: CGFloat = 210
    private var barWidth: CGFloat { CGFloat(KitoChatReaction.quickPicks.count) * 42 + 12 }
    private var menuHeight: CGFloat { rowHeight * (canCopy ? 3 : 2) }

    private var shift: CGFloat {
        let margin: CGFloat = 12
        let top = rect.minY - barHeight - gap
        let bottom = rect.maxY + gap + menuHeight
        var shift: CGFloat = 0
        if bottom > container.height - margin { shift = container.height - margin - bottom }
        if top + shift < margin { shift = margin - top }
        return shift
    }

    var body: some View {
        let lifted = isShown ? shift : 0
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.12))
                .opacity(isShown ? 1 : 0)
                .ignoresSafeArea()
                .onTapGesture { close(then: onDismiss) }
                .accessibilityLabel("Close")
                .accessibilityAddTraits(.isButton)

            bubble
                .frame(width: rect.width, height: rect.height)
                .scaleEffect(isShown && !reduceMotion ? 1.04 : 1, anchor: isOutgoing ? .trailing : .leading)
                .shadow(color: .black.opacity(isShown ? 0.18 : 0), radius: 18, y: 8)
                .position(x: rect.midX, y: rect.midY + lifted)
                .allowsHitTesting(false)

            emojiBar
                .position(x: clampedX(width: barWidth), y: rect.minY + lifted - gap - barHeight / 2)

            menu
                .position(x: clampedX(width: menuWidth), y: rect.maxY + lifted + gap + menuHeight / 2)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.74)) { isShown = true }
        }
        .accessibilityAction(.escape) { close(then: onDismiss) }
    }

    private func clampedX(width: CGFloat) -> CGFloat {
        let margin: CGFloat = 8
        let preferred = isOutgoing ? rect.maxX - width / 2 : rect.minX + width / 2
        return min(max(preferred, width / 2 + margin), container.width - width / 2 - margin)
    }

    private var emojiBar: some View {
        HStack(spacing: 2) {
            ForEach(Array(KitoChatReaction.quickPicks.enumerated()), id: \.offset) { index, emoji in
                Button {
                    close { onReact(emoji) }
                } label: {
                    Text(emoji)
                        .font(.system(size: 27))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(selectedEmoji == emoji ? tint.opacity(0.22) : .clear))
                }
                .buttonStyle(KitoEmojiButtonStyle())
                .scaleEffect(isShown ? 1 : 0.2)
                .opacity(isShown ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.55).delay(Double(index) * 0.035), value: isShown)
                .accessibilityLabel("React with \(emoji)")
                .accessibilityAddTraits(selectedEmoji == emoji ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .frame(height: barHeight)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .scaleEffect(isShown ? 1 : 0.6, anchor: isOutgoing ? .bottomTrailing : .bottomLeading)
        .opacity(isShown ? 1 : 0)
    }

    private var menu: some View {
        VStack(spacing: 0) {
            menuRow("Reply", symbol: "arrowshape.turn.up.left", color: theme.colors.onSurface) { close(then: onReply) }
            if canCopy {
                Divider()
                menuRow("Copy", symbol: "doc.on.doc", color: theme.colors.onSurface) { close(then: onCopy) }
            }
            Divider()
            menuRow("Delete", symbol: "trash", color: theme.colors.danger) { close(then: onDelete) }
        }
        .frame(width: menuWidth)
        .background(RoundedRectangle(cornerRadius: theme.radii.xl - 4, style: .continuous).fill(.regularMaterial))
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.xl - 4, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .scaleEffect(isShown ? 1 : 0.5, anchor: isOutgoing ? .topTrailing : .topLeading)
        .opacity(isShown ? 1 : 0)
    }

    private func menuRow(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(theme.typography.body)
                Spacer()
                Image(systemName: symbol).font(.system(size: 16, weight: .medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, theme.spacing.lg)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(KitoMenuRowStyle())
    }

    private func close(then action: @escaping () -> Void) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.24)) { isShown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            action()
        }
    }
}

private struct KitoEmojiButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.35 : 1)
            .offset(y: configuration.isPressed ? -6 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

private struct KitoMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
    }
}

// MARK: - Image viewer

/// A photo full screen: drag down to close, pinch to zoom, double-tap to zoom in and out.
struct KitoImageViewer: View {
    let image: KitoChatImage
    let messageID: String
    let namespace: Namespace.ID?
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var isChromeVisible = false

    var body: some View {
        let dismissProgress = min(1, abs(dragOffset.height) / 300)
        ZStack {
            Color.black
                .opacity(1 - dismissProgress * 0.8)
                .ignoresSafeArea()
            matched(KitoChatImageView(image: image, contentMode: .fit))
                .aspectRatio(image.aspectRatio, contentMode: .fit)
                .scaleEffect(zoom * (1 - dismissProgress * 0.25))
                .offset(dragOffset)
                .gesture(dragToClose)
                .simultaneousGesture(pinch)
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        zoom = zoom > 1 ? 1 : 2.2
                        committedZoom = zoom
                    }
                }
                .accessibilityLabel(image.caption.map { "Photo: \($0)" } ?? "Photo")
                .accessibilityAddTraits(.isImage)
        }
        .overlay(alignment: .topLeading) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.ultraThinMaterial))
                    .environment(\.colorScheme, .dark)
            }
            .buttonStyle(KitoPressableStyle())
            .padding(16)
            .opacity(isChromeVisible ? 1 - dismissProgress : 0)
            .accessibilityLabel("Close photo")
        }
        .overlay(alignment: .bottom) {
            if let caption = image.caption, !caption.isEmpty {
                Text(caption)
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
                    .opacity(isChromeVisible ? 1 - dismissProgress : 0)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.25).delay(0.15)) { isChromeVisible = true } }
        .accessibilityAction(.escape, onClose)
        .statusBarHidden()
    }

    private var dragToClose: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoom <= 1 else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard zoom <= 1 else { return }
                if abs(value.translation.height) > 120 || abs(value.predictedEndTranslation.height) > 400 {
                    onClose()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dragOffset = .zero }
                }
            }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in zoom = min(4, max(1, committedZoom * value.magnification)) }
            .onEnded { _ in
                committedZoom = zoom
                if zoom < 1.05 { withAnimation(.spring) { zoom = 1; committedZoom = 1 } }
            }
    }

    @ViewBuilder
    private func matched<V: View>(_ view: V) -> some View {
        if let namespace {
            view.matchedGeometryEffect(id: messageID, in: namespace)
        } else {
            view
        }
    }
}
