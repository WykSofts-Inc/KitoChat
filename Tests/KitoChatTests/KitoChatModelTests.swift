//
//  KitoChatModelTests.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
@testable import KitoChat

final class KitoChatModelTests: XCTestCase {
    private let me = KitoChatUser(id: "me", name: "Wycliff N")
    private let amani = KitoChatUser(id: "amani", name: "Amani Wanjiru")

    // MARK: User

    func testInitials() {
        XCTAssertEqual(amani.initials, "AW")
        XCTAssertEqual(me.initials, "WN")
        XCTAssertEqual(KitoChatUser(id: "b", name: "baraka").initials, "B")
        XCTAssertEqual(KitoChatUser(id: "x", name: "  ").initials, "?")
        XCTAssertEqual(KitoChatUser(id: "c", name: "Chebet Jepkosgei Rono").initials, "CJ")
    }

    func testFirstName() {
        XCTAssertEqual(amani.firstName, "Amani")
        XCTAssertEqual(KitoChatUser(id: "b", name: "Baraka").firstName, "Baraka")
    }

    func testPaletteIndexIsStableAndInRange() {
        let index = amani.paletteIndex(count: 8)
        XCTAssertEqual(index, amani.paletteIndex(count: 8))
        XCTAssertTrue((0..<8).contains(index))
        XCTAssertEqual(amani.paletteIndex(count: 0), 0)
    }

    // MARK: Status

    func testStatusMovesForwardOnly() {
        XCTAssertTrue(KitoChatMessageStatus.sending.canTransition(to: .sent))
        XCTAssertTrue(KitoChatMessageStatus.sent.canTransition(to: .read))
        XCTAssertFalse(KitoChatMessageStatus.read.canTransition(to: .delivered))
        XCTAssertFalse(KitoChatMessageStatus.delivered.canTransition(to: .delivered))
        XCTAssertFalse(KitoChatMessageStatus.delivered.canTransition(to: .sending))
    }

    func testStatusFailureAndRetry() {
        XCTAssertTrue(KitoChatMessageStatus.sending.canTransition(to: .failed))
        XCTAssertTrue(KitoChatMessageStatus.failed.canTransition(to: .sending))
        XCTAssertFalse(KitoChatMessageStatus.failed.canTransition(to: .read))
        XCTAssertFalse(KitoChatMessageStatus.sent.canTransition(to: .failed))
    }

    func testTransitionedKeepsStatusWhenNotAllowed() {
        XCTAssertEqual(KitoChatMessageStatus.read.transitioned(to: .sent), .read)
        XCTAssertEqual(KitoChatMessageStatus.sent.transitioned(to: .delivered), .delivered)
    }

    func testNextWalksTheHappyPath() {
        var status = KitoChatMessageStatus.sending
        var path = [status]
        while let next = status.next {
            status = next
            path.append(next)
        }
        XCTAssertEqual(path, [.sending, .sent, .delivered, .read])
        XCTAssertNil(KitoChatMessageStatus.failed.next)
    }

    func testUpdateStatusInArray() {
        var messages = [KitoChatMessage(id: "1", author: me, text: "Niko njiani", status: .sending)]
        XCTAssertTrue(messages.kitoUpdateStatus(of: "1", to: .delivered))
        XCTAssertEqual(messages[0].status, .delivered)
        XCTAssertFalse(messages.kitoUpdateStatus(of: "1", to: .sent))
        XCTAssertEqual(messages[0].status, .delivered)
        XCTAssertFalse(messages.kitoUpdateStatus(of: "missing", to: .read))
    }

    // MARK: Reactions

    func testToggleReactionAddsAndRemoves() {
        var message = KitoChatMessage(author: amani, text: "Tuonane Java saa nane")
        message.toggleReaction("❤️", by: "me")
        XCTAssertEqual(message.reactions, [KitoChatReaction("❤️", userIDs: ["me"])])
        message.toggleReaction("❤️", by: "me")
        XCTAssertTrue(message.reactions.isEmpty)
    }

    func testToggleReactionReplacesYourPreviousOne() {
        var message = KitoChatMessage(author: amani, text: "Sawa", reactions: [KitoChatReaction("👍", userIDs: ["baraka", "me"])])
        message.toggleReaction("😂", by: "me")
        XCTAssertEqual(message.reactions.first { $0.emoji == "👍" }?.userIDs, ["baraka"])
        XCTAssertEqual(message.reaction(of: "me"), "😂")
    }

    func testToggleReactionJoinsExistingEmoji() {
        var message = KitoChatMessage(author: amani, text: "Karibu", reactions: [KitoChatReaction("🙏", userIDs: ["baraka"])])
        message.toggleReaction("🙏", by: "me")
        XCTAssertEqual(message.reactions.count, 1)
        XCTAssertEqual(message.reactions[0].count, 2)
        XCTAssertTrue(message.reactions[0].includes("me"))
    }

    // MARK: Previews and replies

    func testPreviewText() {
        XCTAssertEqual(KitoChatMessage(author: me, text: "Habari\nya asubuhi").previewText, "Habari ya asubuhi")
        XCTAssertEqual(KitoChatMessage(author: me, kind: .voice(duration: 12.2, waveform: [])).previewText, "🎤 Voice message · 0:12")
        let photo = KitoChatImage(url: URL(fileURLWithPath: "/tmp/a.jpg"))
        XCTAssertEqual(KitoChatMessage(author: me, kind: .image(photo)).previewText, "📷 Photo")
        let captioned = KitoChatImage(url: URL(fileURLWithPath: "/tmp/a.jpg"), caption: "Diani sunset")
        XCTAssertEqual(KitoChatMessage(author: me, kind: .image(captioned)).previewText, "📷 Diani sunset")
    }

    func testReplyFromMessage() {
        let voice = KitoChatMessage(id: "v", author: amani, kind: .voice(duration: 65, waveform: []))
        let reply = KitoChatReply(voice)
        XCTAssertEqual(reply.messageID, "v")
        XCTAssertEqual(reply.authorName, "Amani Wanjiru")
        XCTAssertEqual(reply.preview, "Voice message (1:05)")
        XCTAssertEqual(reply.symbol, "waveform")
        XCTAssertNil(KitoChatReply(KitoChatMessage(author: amani, text: "Poa")).symbol)
    }

    func testCopyableText() {
        XCTAssertEqual(KitoChatMessage(author: me, text: "Asante").copyableText, "Asante")
        XCTAssertNil(KitoChatMessage(author: me, kind: .voice(duration: 3, waveform: [])).copyableText)
    }

    func testJumboEmoji() {
        XCTAssertEqual(KitoChatMessage(author: me, text: "🔥").jumboEmojiCount, 1)
        XCTAssertEqual(KitoChatMessage(author: me, text: " 😂🙏 ").jumboEmojiCount, 2)
        XCTAssertEqual(KitoChatMessage(author: me, text: "👍🏾").jumboEmojiCount, 1)
        XCTAssertNil(KitoChatMessage(author: me, text: "😂 sawa").jumboEmojiCount)
        XCTAssertNil(KitoChatMessage(author: me, text: "😂😂😂😂").jumboEmojiCount)
        XCTAssertNil(KitoChatMessage(author: me, text: "1").jumboEmojiCount)
    }

    func testImageAspectRatioGuardsAgainstZero() {
        XCTAssertEqual(KitoChatImage(url: URL(fileURLWithPath: "/a"), aspectRatio: 0).aspectRatio, 1)
    }

    // MARK: Conversations

    func testConversationsSortPinnedThenRecent() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = KitoChatConversation(id: "old", user: amani, lastMessage: KitoChatMessage(author: amani, text: "a", date: now.addingTimeInterval(-500)))
        let recent = KitoChatConversation(id: "recent", user: amani, lastMessage: KitoChatMessage(author: amani, text: "b", date: now))
        let pinned = KitoChatConversation(id: "pinned", user: amani, lastMessage: KitoChatMessage(author: amani, text: "c", date: now.addingTimeInterval(-9_000)), isPinned: true)
        let empty = KitoChatConversation(id: "empty", user: amani)
        XCTAssertEqual(KitoChatConversation.sorted([old, empty, recent, pinned]).map(\.id), ["pinned", "recent", "old", "empty"])
    }

    func testDisplayNamePrefersTitle() {
        XCTAssertEqual(KitoChatConversation(user: amani, title: "Safari Crew").displayName, "Safari Crew")
        XCTAssertEqual(KitoChatConversation(user: amani).displayName, "Amani Wanjiru")
    }
}
