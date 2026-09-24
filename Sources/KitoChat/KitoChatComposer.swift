//
//  KitoChatComposer.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// The message bar: a growing text field, an attach button, and a send button that morphs from a
/// microphone into a paper plane as you type. Hold the microphone to record a voice note — slide
/// left to cancel, slide up to lock and keep recording hands-free.
///
/// Recording needs `NSMicrophoneUsageDescription` in your Info.plist. Without microphone access
/// (or in a simulator with no input) it records a simulated preview unless you turn that off.
///
/// ```swift
/// KitoChatComposer(text: $draft, replyTo: $replyingTo) { kind in
///     send(kind)          // .text("Habari!") or .voice(duration:waveform:url:)
/// }
/// ```
public struct KitoChatComposer: View {
    @Binding private var text: String
    @Binding private var replyTo: KitoChatReply?
    private let placeholder: String
    private let allowsVoice: Bool
    private let simulatesRecordingWhenUnavailable: Bool
    private let tint: Color?
    private let onAttach: (() -> Void)?
    private let onSend: (KitoChatMessage.Kind) -> Void

    @Environment(\.kitoTheme) private var theme
    @Environment(\.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    @State private var recorder = KitoVoiceRecorder()
    @State private var drag: CGSize = .zero
    @State private var isPressing = false
    @State private var pressBegan = Date()
    @State private var pressStartedRecording = false
    @State private var hint: String?
    @State private var hintTask: Task<Void, Never>?
    @State private var sendCount = 0
    @State private var recordCount = 0
    @State private var lockCount = 0
    @State private var cancelCount = 0

    private let cancelDistance: CGFloat = 110
    private let lockDistance: CGFloat = 90

    public init(
        text: Binding<String>,
        replyTo: Binding<KitoChatReply?> = .constant(nil),
        placeholder: String = "Message",
        allowsVoice: Bool = true,
        simulatesRecordingWhenUnavailable: Bool = true,
        tint: Color? = nil,
        onAttach: (() -> Void)? = nil,
        onSend: @escaping (KitoChatMessage.Kind) -> Void
    ) {
        _text = text
        _replyTo = replyTo
        self.placeholder = placeholder
        self.allowsVoice = allowsVoice
        self.simulatesRecordingWhenUnavailable = simulatesRecordingWhenUnavailable
        self.tint = tint
        self.onAttach = onAttach
        self.onSend = onSend
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showsSend: Bool { !trimmed.isEmpty || recorder.phase == .locked || !allowsVoice }
    private var spring: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.36, dampingFraction: 0.72) }

    public var body: some View {
        let accent = KitoChatAccent(tint: tint, theme: theme, environment: environment)
        VStack(spacing: theme.spacing.sm) {
            if let hint {
                Text(hint)
                    .font(theme.typography.caption.weight(.medium))
                    .foregroundStyle(theme.colors.onSurface)
                    .padding(.horizontal, theme.spacing.md)
                    .padding(.vertical, theme.spacing.xs + 2)
                    .background(Capsule().fill(.regularMaterial))
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if let replyTo, !recorder.isActive {
                replyPreview(replyTo, accent: accent)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .bottom, spacing: theme.spacing.sm) {
                Group {
                    if recorder.isActive {
                        recordingBar(accent: accent)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    } else {
                        inputRow(accent: accent)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                actionButton(accent: accent)
            }
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.top, theme.spacing.sm)
        .padding(.bottom, theme.spacing.sm)
        .background {
            Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Rectangle().fill(theme.colors.border.opacity(0.6)).frame(height: 0.5) }
        }
        .animation(spring, value: recorder.phase)
        .animation(spring, value: replyTo)
        .animation(spring, value: hint)
        .animation(spring, value: showsSend)
        .onChange(of: replyTo) { _, new in if new != nil { isFocused = true } }
        .sensoryFeedback(.impact(weight: .light), trigger: sendCount)
        .sensoryFeedback(.impact(weight: .medium), trigger: recordCount)
        .sensoryFeedback(.success, trigger: lockCount)
        .sensoryFeedback(.warning, trigger: cancelCount)
    }

    // MARK: Input

    private func inputRow(accent: KitoChatAccent) -> some View {
        HStack(alignment: .bottom, spacing: theme.spacing.sm) {
            if let onAttach {
                Button(action: onAttach) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.colors.onSurface)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(theme.colors.surfaceMuted))
                }
                .buttonStyle(KitoPressableStyle())
                .accessibilityLabel("Attach")
            }
            TextField(placeholder, text: $text, axis: .vertical)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.onSurface)
                .tint(accent.tint)
                .lineLimit(1...6)
                .focused($isFocused)
                .submitLabel(.return)
                .padding(.horizontal, theme.spacing.md + 2)
                .padding(.vertical, 9)
                .frame(minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(theme.colors.surfaceMuted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .strokeBorder(isFocused ? accent.tint.opacity(0.45) : theme.colors.border.opacity(0.7), lineWidth: 1)
                )
                .animation(.easeOut(duration: 0.2), value: isFocused)
        }
    }

    private func replyPreview(_ reply: KitoChatReply, accent: KitoChatAccent) -> some View {
        HStack(spacing: theme.spacing.sm) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent.tint)
            Capsule().fill(accent.tint).frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to \(reply.authorName)")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(accent.tint)
                HStack(spacing: 4) {
                    if let symbol = reply.symbol { Image(systemName: symbol).imageScale(.small) }
                    Text(reply.preview).lineLimit(1)
                }
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.onSurface.opacity(0.7))
            }
            Spacer(minLength: 0)
            Button {
                replyTo = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.colors.onSurface.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(theme.colors.surfaceMuted))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel reply")
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.sm)
        .background(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).fill(theme.colors.surface))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).strokeBorder(theme.colors.border.opacity(0.7), lineWidth: 1))
    }

    // MARK: Recording

    private func recordingBar(accent: KitoChatAccent) -> some View {
        let isLocked = recorder.phase == .locked
        let cancelProgress = min(1, max(0, -drag.width / cancelDistance))
        let recent = Array(recorder.levels.suffix(30))
        let padded = Array(repeating: Float(0.05), count: max(0, 30 - recent.count)) + recent
        return HStack(spacing: theme.spacing.sm) {
            if isLocked {
                Button {
                    cancelRecording()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.colors.danger)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(theme.colors.danger.opacity(0.12)))
                }
                .buttonStyle(KitoPressableStyle())
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Delete recording")
            }
            HStack(spacing: theme.spacing.sm) {
                KitoRecordingDot(color: theme.colors.danger)
                Text(KitoChatDateFormat.duration(recorder.elapsed.rounded(.down)))
                    .font(theme.typography.bodyEmphasized.monospacedDigit())
                    .foregroundStyle(theme.colors.onSurface)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: Int(recorder.elapsed))
                KitoChatWaveformView(samples: padded, progress: 1, activeColor: theme.colors.danger.opacity(0.85), barWidth: 2.5, spacing: 2)
                    .frame(height: 22)
                    .frame(maxWidth: isLocked ? .infinity : 70)
                    .animation(reduceMotion ? nil : .linear(duration: 0.05), value: recorder.levels.count)
                if !isLocked {
                    Spacer(minLength: 0)
                    KitoSlideToCancelLabel(color: theme.colors.onSurface.opacity(0.6), reduceMotion: reduceMotion)
                        .offset(x: max(-cancelDistance, drag.width * 0.5))
                        .opacity(1 - Double(cancelProgress) * 0.9)
                }
                if recorder.isSimulated {
                    Text("Preview")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.colors.onSurface.opacity(0.55))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().strokeBorder(theme.colors.onSurface.opacity(0.25)))
                        .accessibilityLabel("Simulated recording")
                }
            }
            .padding(.horizontal, theme.spacing.md)
            .frame(height: 38)
            .background(Capsule().fill(theme.colors.surfaceMuted))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording, \(KitoChatDateFormat.duration(recorder.elapsed))")
    }

    // MARK: Action button

    private func actionButton(accent: KitoChatAccent) -> some View {
        let isRecording = recorder.phase == .recording
        let lockProgress = min(1, max(0, -drag.height / lockDistance))
        let symbol = showsSend ? "paperplane.fill" : "mic.fill"
        return ZStack {
            if isRecording {
                Circle()
                    .fill(accent.tint.opacity(0.18))
                    .frame(width: 38, height: 38)
                    .scaleEffect(reduceMotion ? 1.7 : 1.6 + CGFloat(recorder.levels.last ?? 0) * 0.7)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: recorder.levels.count)
            }
            Circle()
                .fill(accent.tint)
                .frame(width: 38, height: 38)
                .shadow(color: accent.tint.opacity(isRecording ? 0.45 : 0.2), radius: isRecording ? 12 : 4, y: 2)
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent.onTint)
                .contentTransition(.symbolEffect(.replace.downUp))
                .symbolEffect(.bounce.up, value: sendCount)
        }
        .scaleEffect(isRecording ? 1.45 : 1)
        .offset(x: isRecording ? max(-cancelDistance, min(0, drag.width)) : 0,
                y: isRecording ? max(-lockDistance, min(0, drag.height)) * 0.5 : 0)
        .overlay(alignment: .bottom) {
            if isRecording {
                KitoLockIndicator(progress: lockProgress, tint: accent.tint, reduceMotion: reduceMotion)
                    .offset(y: -72)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 38, height: 38)
        .contentShape(Circle().inset(by: -6))
        .gesture(pressGesture)
        .accessibilityElement()
        .accessibilityLabel(showsSend ? "Send" : "Record voice message")
        .accessibilityHint(showsSend ? "" : "Hold to record, release to send")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if showsSend { send() } else { showHint("Hold to record, release to send") }
        }
        .zIndex(1)
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !isPressing {
                    isPressing = true
                    pressBegan = Date()
                    pressStartedRecording = false
                    if !showsSend { beginRecording() }
                }
                guard recorder.phase == .recording, pressStartedRecording else { return }
                withAnimation(.interactiveSpring) { drag = value.translation }
                if value.translation.width < -cancelDistance {
                    cancelRecording()
                } else if value.translation.height < -lockDistance {
                    recorder.lock()
                    lockCount += 1
                    withAnimation(spring) { drag = .zero }
                }
            }
            .onEnded { value in
                defer {
                    isPressing = false
                    pressStartedRecording = false
                    withAnimation(spring) { drag = .zero }
                }
                if recorder.phase == .recording, pressStartedRecording {
                    if Date().timeIntervalSince(pressBegan) < 0.3 {
                        recorder.cancel()
                        showHint("Hold to record, release to send")
                    } else {
                        sendRecording()
                    }
                } else if !pressStartedRecording, showsSend, abs(value.translation.width) < 30, abs(value.translation.height) < 30 {
                    send()
                }
            }
    }

    private func beginRecording() {
        isFocused = false
        switch recorder.start(simulateWhenUnavailable: simulatesRecordingWhenUnavailable) {
        case .started:
            pressStartedRecording = true
            recordCount += 1
        case .askedPermission:
            showHint("Allow microphone access, then hold to record")
        case .unavailable:
            showHint("Microphone access is off — turn it on in Settings")
        }
    }

    private func cancelRecording() {
        recorder.cancel()
        pressStartedRecording = false
        cancelCount += 1
        withAnimation(spring) { drag = .zero }
    }

    // MARK: Sending

    private func send() {
        if recorder.phase == .locked {
            sendRecording()
            return
        }
        let message = trimmed
        guard !message.isEmpty else { return }
        onSend(.text(message))
        text = ""
        replyTo = nil
        sendCount += 1
    }

    private func sendRecording() {
        guard let recording = recorder.finish() else {
            showHint("Too short — hold a little longer")
            return
        }
        onSend(.voice(duration: recording.duration, waveform: recording.waveform, url: recording.url))
        replyTo = nil
        sendCount += 1
    }

    private func showHint(_ message: String) {
        hintTask?.cancel()
        hint = message
        hintTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            hint = nil
        }
    }
}

// MARK: - Recording pieces

private struct KitoRecordingDot: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dot = Circle().fill(color).frame(width: 10, height: 10)
        Group {
            if reduceMotion {
                dot
            } else {
                dot.phaseAnimator([1.0, 0.25]) { dot, phase in
                    dot.opacity(phase)
                } animation: { _ in .easeInOut(duration: 0.6) }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct KitoSlideToCancelLabel: View {
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        let label = HStack(spacing: 2) {
            Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
            Text("Slide to cancel").font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(color)
        Group {
            if reduceMotion {
                label
            } else {
                label.phaseAnimator([0.0, -6.0]) { label, phase in
                    label.offset(x: phase)
                } animation: { _ in .easeInOut(duration: 0.7) }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityLabel("Slide left to cancel")
    }
}

private struct KitoLockIndicator: View {
    let progress: CGFloat
    let tint: Color
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: progress >= 1 ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 14, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .offset(y: progress * 6)
            let chevron = Image(systemName: "chevron.up")
                .font(.system(size: 11, weight: .bold))
                .opacity(1 - Double(progress))
            if reduceMotion {
                chevron
            } else {
                chevron.phaseAnimator([0.0, -4.0]) { chevron, phase in
                    chevron.offset(y: phase)
                } animation: { _ in .easeInOut(duration: 0.5) }
            }
        }
        .foregroundStyle(progress >= 1 ? tint : .secondary)
        .frame(width: 36, height: 76 - progress * 20)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityLabel("Slide up to lock recording")
    }
}

/// Shrinks slightly while pressed.
struct KitoPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
