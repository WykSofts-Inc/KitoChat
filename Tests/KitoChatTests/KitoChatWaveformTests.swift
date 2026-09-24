//
//  KitoChatWaveformTests.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
@testable import KitoChat

final class KitoChatWaveformTests: XCTestCase {
    func testDownsampleReturnsExactlyTheBarCount() {
        let samples = (0..<1_000).map { Float(sin(Double($0) / 20)) }
        XCTAssertEqual(KitoChatWaveform.downsample(samples, to: 40).count, 40)
        XCTAssertEqual(KitoChatWaveform.downsample(samples, to: 7).count, 7)
    }

    func testDownsampleKeepsPeaksAndNormalises() {
        let samples: [Float] = [0.1, 0.2, 0.5, 0.1, 0.25, 0.05]
        XCTAssertEqual(KitoChatWaveform.downsample(samples, to: 3), [0.4, 1, 0.5])
    }

    func testDownsampleUsesMagnitudes() {
        XCTAssertEqual(KitoChatWaveform.downsample([-0.8, 0.2, 0.4, -0.2], to: 2), [1, 0.5])
    }

    func testDownsampleStretchesShortInput() {
        let bars = KitoChatWaveform.downsample([0.5, 1], to: 4)
        XCTAssertEqual(bars, [0.5, 0.5, 1, 1])
    }

    func testDownsampleEdgeCases() {
        XCTAssertEqual(KitoChatWaveform.downsample([], to: 10), [])
        XCTAssertEqual(KitoChatWaveform.downsample([0.3], to: 0), [])
        XCTAssertEqual(KitoChatWaveform.downsample([0, 0, 0], to: 3), [0, 0, 0])
        XCTAssertEqual(KitoChatWaveform.downsample([.nan, 0.5], to: 2), [0, 1])
    }

    func testNormalized() {
        XCTAssertEqual(KitoChatWaveform.normalized([0.25, 0.5]), [0.5, 1])
        XCTAssertEqual(KitoChatWaveform.normalized([]), [])
    }

    func testLevelFromDecibels() {
        XCTAssertEqual(KitoChatWaveform.level(fromDecibels: 0), 1)
        XCTAssertEqual(KitoChatWaveform.level(fromDecibels: -25), 0.5, accuracy: 0.0001)
        XCTAssertEqual(KitoChatWaveform.level(fromDecibels: -80), 0)
        XCTAssertEqual(KitoChatWaveform.level(fromDecibels: 6), 1)
        XCTAssertEqual(KitoChatWaveform.level(fromDecibels: -.infinity), 0)
        XCTAssertEqual(KitoChatWaveform.level(fromDecibels: -30, floor: -60), 0.5, accuracy: 0.0001)
    }

    func testPlaceholderIsDeterministicAndInRange() {
        let a = KitoChatWaveform.placeholder(count: 32, seed: 42)
        XCTAssertEqual(a, KitoChatWaveform.placeholder(count: 32, seed: 42))
        XCTAssertNotEqual(a, KitoChatWaveform.placeholder(count: 32, seed: 43))
        XCTAssertEqual(a.count, 32)
        XCTAssertTrue(a.allSatisfy { (0...1).contains($0) })
        XCTAssertEqual(KitoChatWaveform.placeholder(count: 0), [])
        XCTAssertEqual(KitoChatWaveform.placeholder(count: 5, seed: 0).count, 5)
    }

    func testPlaybackSpeedCycles() {
        XCTAssertEqual(KitoPlaybackSpeed.normal.next, .fast)
        XCTAssertEqual(KitoPlaybackSpeed.fast.next, .fastest)
        XCTAssertEqual(KitoPlaybackSpeed.fastest.next, .normal)
        XCTAssertEqual(KitoPlaybackSpeed.allCases.map(\.label), ["1×", "1.5×", "2×"])
        XCTAssertEqual(KitoPlaybackSpeed.fast.rawValue, 1.5)
    }

    func testSwipeReplyRubberBand() {
        XCTAssertEqual(KitoSwipeReply.offset(for: -40), 0)
        XCTAssertEqual(KitoSwipeReply.offset(for: 0), 0)
        let small = KitoSwipeReply.offset(for: 10)
        XCTAssertEqual(small, 10, accuracy: 1)
        XCTAssertLessThan(KitoSwipeReply.offset(for: 1_000), KitoSwipeReply.limit)
        XCTAssertLessThan(KitoSwipeReply.offset(for: 100), KitoSwipeReply.offset(for: 200))
        XCTAssertGreaterThanOrEqual(KitoSwipeReply.offset(for: 140), KitoSwipeReply.threshold)
    }

    func testSwipeReplyProgress() {
        XCTAssertEqual(KitoSwipeReply.progress(for: 0), 0)
        XCTAssertEqual(KitoSwipeReply.progress(for: KitoSwipeReply.threshold / 2), 0.5, accuracy: 0.0001)
        XCTAssertEqual(KitoSwipeReply.progress(for: 500), 1)
    }

    @MainActor
    func testRecorderFinishWithoutStartingReturnsNil() {
        let recorder = KitoVoiceRecorder()
        XCTAssertNil(recorder.finish())
        XCTAssertEqual(recorder.phase, .idle)
    }

    @MainActor
    func testSimulatedPlayerCyclesSpeedAndSeeks() {
        let player = KitoVoicePlayer(url: nil, duration: 10)
        player.cycleSpeed()
        XCTAssertEqual(player.speed, .fast)
        player.seek(to: 1.4)
        XCTAssertEqual(player.progress, 1)
        player.seek(to: 0.25)
        XCTAssertEqual(player.elapsed, 2.5, accuracy: 0.0001)
    }
}
