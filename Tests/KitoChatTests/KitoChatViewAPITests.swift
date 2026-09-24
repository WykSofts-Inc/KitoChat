//
//  KitoChatViewAPITests.swift
//  KitoChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
import SwiftUI
@testable import KitoChat

/// These mostly check that the call shapes compile: a trailing closure must bind to `onSend`.
@MainActor
final class KitoChatViewAPITests: XCTestCase {
    private let me = KitoChatUser(id: "me", name: "Wycliff N")

    func testTrailingClosureIsOnSend() {
        var sent: [String] = []
        _ = KitoChatView(messages: .constant([]), currentUser: me) { message in sent.append(message.id) }
        _ = KitoChatView(messages: .constant([]), currentUser: me, onAttach: {}) { message in sent.append(message.id) }
        XCTAssertTrue(sent.isEmpty)
    }

    func testLabelledAndClosureFreeFormsStillCompile() {
        _ = KitoChatView(messages: .constant([]), currentUser: me)
        _ = KitoChatView(messages: .constant([]), currentUser: me, onAttach: {})
        _ = KitoChatView(messages: .constant([]), currentUser: me, onAttach: {}, onSend: { _ in })
        _ = KitoChatView(messages: .constant([]), currentUser: me, onSend: nil)
    }

    func testRenamedPresenceViews() {
        _ = KitoChatTypingIndicator(style: .imessage)
        _ = KitoChatWaveformView(samples: KitoChatWaveform.placeholder(count: 8))
    }
}
