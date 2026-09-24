//
//  KitoVoiceRecorder.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation
import AVFoundation

/// A finished voice recording.
struct KitoVoiceRecording: Equatable {
    let duration: TimeInterval
    let waveform: [Float]
    let url: URL?
}

/// Records a voice note with `AVAudioRecorder` and live metering. When the microphone can't be
/// used — no `NSMicrophoneUsageDescription`, access denied, or no input (some simulators) — it can
/// simulate a recording instead so the composer still works in previews.
@MainActor
@Observable
final class KitoVoiceRecorder {
    enum Phase: Equatable { case idle, recording, locked }

    enum StartResult: Equatable {
        case started
        /// The system permission prompt was shown; try again once answered.
        case askedPermission
        case unavailable
    }

    private(set) var phase: Phase = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels: [Float] = []
    private(set) var isSimulated = false

    /// Recordings shorter than this are discarded.
    static let minimumDuration: TimeInterval = 0.6

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var startDate = Date()
    private var ticker: Task<Void, Never>?

    var isActive: Bool { phase != .idle }

    static var hasUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
    }

    func start(simulateWhenUnavailable: Bool) -> StartResult {
        guard phase == .idle else { return .started }
        if Self.hasUsageDescription {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                if startMicrophone() { return begin(simulated: false) }
            case .undetermined:
                Task { _ = await AVAudioApplication.requestRecordPermission() }
                return .askedPermission
            default:
                break
            }
        }
        return simulateWhenUnavailable ? begin(simulated: true) : .unavailable
    }

    func lock() {
        guard phase == .recording else { return }
        phase = .locked
    }

    /// Stops and returns the recording, or `nil` if it was too short.
    func finish() -> KitoVoiceRecording? {
        guard phase != .idle else { return nil }
        let duration = elapsed
        let url = isSimulated ? nil : fileURL
        let waveform = KitoChatWaveform.downsample(levels, to: 40)
        tearDown()
        guard duration >= Self.minimumDuration else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        return KitoVoiceRecording(duration: duration, waveform: waveform, url: url)
    }

    func cancel() {
        guard phase != .idle else { return }
        let url = fileURL
        tearDown()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: Private

    private func startMicrophone() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            return false
        }
        guard session.isInputAvailable else { return false }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kito-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        recorder.isMeteringEnabled = true
        guard recorder.record() else { return false }
        self.recorder = recorder
        self.fileURL = url
        return true
    }

    private func begin(simulated: Bool) -> StartResult {
        isSimulated = simulated
        phase = .recording
        elapsed = 0
        levels = []
        startDate = Date()
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.phase != .idle else { return }
                self.sample()
            }
        }
        return .started
    }

    private func sample() {
        elapsed = Date().timeIntervalSince(startDate)
        let level: Float
        if let recorder {
            recorder.updateMeters()
            level = KitoChatWaveform.level(fromDecibels: recorder.averagePower(forChannel: 0))
        } else {
            let t = Float(elapsed)
            let speech = abs(sin(t * 3.1) * sin(t * 7.3 + 1.2))
            level = min(1, 0.12 + 0.7 * speech + Float.random(in: 0...0.15))
        }
        levels.append(level)
        if levels.count > 4_000 { levels.removeFirst(levels.count - 4_000) }
    }

    private func tearDown() {
        ticker?.cancel()
        ticker = nil
        recorder?.stop()
        recorder = nil
        fileURL = nil
        phase = .idle
        elapsed = 0
        levels = []
        if !isSimulated {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        isSimulated = false
    }
}
