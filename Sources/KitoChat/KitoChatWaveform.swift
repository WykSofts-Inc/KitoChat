//
//  KitoChatWaveform.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

// MARK: - Maths

/// Waveform maths for voice notes: downsampling to bars, metering and demo shapes.
public enum KitoChatWaveform {
    /// Buckets `samples` into exactly `count` bars, each the peak magnitude of its bucket,
    /// scaled so the loudest bar is 1. Fewer samples than bars are stretched.
    public static func downsample(_ samples: [Float], to count: Int) -> [Float] {
        guard count > 0, !samples.isEmpty else { return [] }
        let n = samples.count
        let bars = (0..<count).map { bar -> Float in
            let start = bar * n / count
            let end = max(start + 1, (bar + 1) * n / count)
            return samples[start..<min(end, n)].reduce(0) { max($0, abs($1).isFinite ? abs($1) : 0) }
        }
        return normalized(bars)
    }

    /// Scales `samples` so the loudest is 1. Silence stays silent.
    public static func normalized(_ samples: [Float]) -> [Float] {
        let magnitudes = samples.map { $0.isFinite ? abs($0) : 0 }
        guard let peak = magnitudes.max(), peak > 0 else { return magnitudes.map { _ in 0 } }
        return magnitudes.map { $0 / peak }
    }

    /// Maps an `AVAudioRecorder` power reading (dBFS, ≤ 0) to 0…1, treating `floor` and below as silence.
    public static func level(fromDecibels decibels: Float, floor: Float = -50) -> Float {
        guard decibels.isFinite, floor < 0 else { return 0 }
        return min(1, max(0, (decibels - floor) / -floor))
    }

    /// A natural-looking waveform for previews and simulated recordings. The same seed gives the same shape.
    public static func placeholder(count: Int = 40, seed: UInt64 = 1) -> [Float] {
        guard count > 0 else { return [] }
        let fallback: UInt64 = 0x9E37_79B9_7F4A_7C15
        var state = seed == 0 ? fallback : seed
        var smooth: Float = 0.5
        return (0..<count).map { index in
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            let random = Float(state % 10_000) / 10_000
            smooth = smooth * 0.45 + random * 0.55
            let position = Float(index) / Float(max(1, count - 1))
            let envelope = 0.55 + 0.45 * sin(position * .pi)
            return min(1, max(0.08, smooth * envelope + 0.06))
        }
    }
}

// MARK: - Playback speed

/// Voice-note playback speed, cycled by tapping the speed pill.
public enum KitoPlaybackSpeed: Float, CaseIterable, Sendable {
    case normal = 1
    case fast = 1.5
    case fastest = 2

    /// 1× → 1.5× → 2× → 1×.
    public var next: KitoPlaybackSpeed {
        switch self {
        case .normal: .fast
        case .fast: .fastest
        case .fastest: .normal
        }
    }

    /// "1×", "1.5×", "2×".
    public var label: String {
        switch self {
        case .normal: "1×"
        case .fast: "1.5×"
        case .fastest: "2×"
        }
    }
}

// MARK: - Swipe to reply

/// The rubber-banded offset and threshold for swiping a message to reply.
enum KitoSwipeReply {
    static let limit: CGFloat = 96
    static let threshold: CGFloat = 60

    /// Follows the finger at first, then resists; never goes left of zero or past `limit`.
    static func offset(for translation: CGFloat) -> CGFloat {
        guard translation > 0, translation.isFinite else { return 0 }
        return limit * (1 - exp(-translation / limit))
    }

    /// 0…1 as the offset approaches the threshold.
    static func progress(for offset: CGFloat) -> CGFloat {
        min(1, max(0, offset / threshold))
    }
}

// MARK: - View

/// Waveform bars with a playback progress fill. Drag across it to scrub when `onScrub` is set.
///
/// ```swift
/// KitoChatWaveformView(samples: KitoChatWaveform.placeholder(count: 32), progress: 0.4)
/// ```
public struct KitoChatWaveformView: View {
    private let samples: [Float]
    private let progress: Double
    private let activeColor: Color?
    private let inactiveColor: Color?
    private let barWidth: CGFloat
    private let spacing: CGFloat
    private let onScrub: ((Double) -> Void)?

    @Environment(\.kitoTheme) private var theme

    public init(
        samples: [Float],
        progress: Double = 0,
        activeColor: Color? = nil,
        inactiveColor: Color? = nil,
        barWidth: CGFloat = 3,
        spacing: CGFloat = 2,
        onScrub: ((Double) -> Void)? = nil
    ) {
        self.samples = samples
        self.progress = progress
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.barWidth = barWidth
        self.spacing = spacing
        self.onScrub = onScrub
    }

    public var body: some View {
        let active = activeColor ?? theme.colors.primary
        let inactive = inactiveColor ?? theme.colors.onSurface.opacity(0.25)
        GeometryReader { proxy in
            let count = CGFloat(max(1, samples.count))
            let fitted = max(1, min(barWidth, (proxy.size.width - spacing * (count - 1)) / count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                    let played = samples.isEmpty ? false : Double(index) / Double(samples.count) < progress
                    Capsule()
                        .fill(played ? active : inactive)
                        .frame(width: fitted, height: max(fitted, proxy.size.height * CGFloat(max(0.12, min(1, sample)))))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(scrub(width: proxy.size.width), including: onScrub == nil ? .none : .all)
        }
        .animation(.easeOut(duration: 0.12), value: progress)
        .accessibilityHidden(true)
    }

    private func scrub(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0 else { return }
                onScrub?(min(1, max(0, value.location.x / width)))
            }
    }
}
