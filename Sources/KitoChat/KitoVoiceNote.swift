//
//  KitoVoiceNote.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import AVFoundation
import KitoCore

// MARK: - Player

/// Plays a voice note with `AVAudioPlayer` when there's a file, otherwise simulates progress
/// so a waveform still plays through in previews.
@MainActor
@Observable
final class KitoVoicePlayer {
    private(set) var progress: Double = 0
    private(set) var isPlaying = false
    private(set) var speed: KitoPlaybackSpeed = .normal

    let duration: TimeInterval
    private let url: URL?
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    init(url: URL?, duration: TimeInterval) {
        self.url = url
        self.duration = max(0.1, duration)
    }

    var elapsed: TimeInterval { progress * duration }

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        if player == nil, let url {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try? AVAudioPlayer(contentsOf: url)
            player?.enableRate = true
            player?.prepareToPlay()
        }
        if progress >= 1 { progress = 0 }
        if let player {
            player.currentTime = progress * player.duration
            player.rate = speed.rawValue
            player.play()
        }
        isPlaying = true
        startTicking()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.cancel()
    }

    func stop() {
        pause()
        player?.stop()
        player = nil
    }

    func seek(to fraction: Double) {
        progress = min(1, max(0, fraction))
        if let player { player.currentTime = progress * player.duration }
    }

    func cycleSpeed() {
        speed = speed.next
        player?.rate = speed.rawValue
    }

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            let step: Double = 1.0 / 30.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(step))
                guard let self, self.isPlaying else { return }
                self.tick(step)
            }
        }
    }

    private func tick(_ step: Double) {
        if let player {
            guard player.duration > 0 else { return finish() }
            progress = min(1, player.currentTime / player.duration)
            if !player.isPlaying { finish() }
        } else {
            progress = min(1, progress + step * Double(speed.rawValue) / duration)
            if progress >= 1 { finish() }
        }
    }

    private func finish() {
        isPlaying = false
        ticker?.cancel()
        progress = 0
    }
}

// MARK: - Bubble content

/// Play/pause, a scrubbable waveform, the time and a 1×/1.5×/2× pill.
struct KitoVoiceNoteContent: View {
    let messageID: String
    let isOutgoing: Bool
    let style: KitoChatBubbleStyle
    let accent: KitoChatAccent
    let foreground: Color
    private let bars: [Float]

    @State private var player: KitoVoicePlayer
    @Environment(\.kitoTheme) private var theme

    init(messageID: String, duration: TimeInterval, waveform: [Float], url: URL?, isOutgoing: Bool, style: KitoChatBubbleStyle, accent: KitoChatAccent, foreground: Color) {
        self.messageID = messageID
        self.isOutgoing = isOutgoing
        self.style = style
        self.accent = accent
        self.foreground = foreground
        let seed = messageID.unicodeScalars.reduce(UInt64(7)) { ($0 &* 31) &+ UInt64($1.value) }
        self.bars = KitoChatWaveform.downsample(waveform.isEmpty ? KitoChatWaveform.placeholder(count: 32, seed: seed) : waveform, to: 32)
        _player = State(initialValue: KitoVoicePlayer(url: url, duration: duration))
    }

    var body: some View {
        let onFill = isOutgoing && style != .minimal
        let buttonFill = onFill ? foreground : accent.tint
        let buttonGlyph = onFill ? accent.tint : accent.onTint
        HStack(spacing: theme.spacing.sm + 2) {
            Button(action: player.toggle) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(buttonGlyph)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(buttonFill))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: player.isPlaying)
            .accessibilityLabel(player.isPlaying ? "Pause voice message" : "Play voice message")

            VStack(alignment: .leading, spacing: 4) {
                KitoChatWaveformView(
                    samples: bars,
                    progress: player.progress,
                    activeColor: onFill ? foreground : accent.tint,
                    inactiveColor: (onFill ? foreground : theme.colors.onSurface).opacity(0.3),
                    barWidth: 3,
                    spacing: 2,
                    onScrub: { player.seek(to: $0) }
                )
                .frame(width: 128, height: 26)
                .accessibilityHidden(true)

                Text(KitoChatDateFormat.duration(player.isPlaying || player.progress > 0 ? player.elapsed : player.duration))
                    .font(theme.typography.caption.monospacedDigit())
                    .foregroundStyle(foreground.opacity(0.75))
                    .contentTransition(.numericText())
            }

            Button(action: player.cycleSpeed) {
                Text(player.speed.label)
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(onFill ? foreground : theme.colors.onSurface)
                    .contentTransition(.numericText())
                    .frame(minWidth: 34)
                    .padding(.vertical, 5)
                    .background(Capsule().fill((onFill ? foreground : theme.colors.onSurface).opacity(0.14)))
            }
            .buttonStyle(.plain)
            .animation(.snappy, value: player.speed)
            .accessibilityLabel("Playback speed \(player.speed.label)")
            .accessibilityHint("Changes the playback speed")
        }
        .onDisappear { player.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice message, \(KitoChatDateFormat.duration(player.duration))")
        .accessibilityValue(player.isPlaying ? "Playing, \(Int(player.progress * 100)) percent" : "")
    }
}
