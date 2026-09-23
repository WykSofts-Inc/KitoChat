//
//  KitoChatTimelineTests.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
@testable import KitoChat

final class KitoChatTimelineTests: XCTestCase {
    private let me = KitoChatUser(id: "me", name: "Wycliff N")
    private let amani = KitoChatUser(id: "amani", name: "Amani Wanjiru")
    private let baraka = KitoChatUser(id: "baraka", name: "Baraka Otieno")

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    /// Wednesday 23 September 2026, 12:00 UTC.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12)) ?? .now
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 9, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .now
    }

    private func message(_ id: String, _ author: KitoChatUser, at date: Date, system: Bool = false) -> KitoChatMessage {
        KitoChatMessage(id: id, author: author, date: date, kind: system ? .system("note") : .text(id))
    }

    // MARK: Grouping

    func testSingleMessageIsSingle() {
        let positions = KitoChatGrouping.positions(for: [message("a", amani, at: now)], calendar: calendar)
        XCTAssertEqual(positions, [.single])
    }

    func testConsecutiveMessagesFromSameAuthorGroup() {
        let messages = [
            message("1", amani, at: date(23, 10, 0)),
            message("2", amani, at: date(23, 10, 1)),
            message("3", amani, at: date(23, 10, 2)),
            message("4", me, at: date(23, 10, 3)),
            message("5", me, at: date(23, 10, 4)),
            message("6", amani, at: date(23, 10, 5)),
        ]
        XCTAssertEqual(KitoChatGrouping.positions(for: messages, calendar: calendar), [.first, .middle, .last, .first, .last, .single])
    }

    func testLongGapBreaksAGroup() {
        let messages = [message("1", amani, at: date(23, 10, 0)), message("2", amani, at: date(23, 10, 30))]
        XCTAssertEqual(KitoChatGrouping.positions(for: messages, interval: 300, calendar: calendar), [.single, .single])
        XCTAssertEqual(KitoChatGrouping.positions(for: messages, interval: 3_600, calendar: calendar), [.first, .last])
    }

    func testNewDayBreaksAGroup() {
        let messages = [message("1", amani, at: date(22, 23, 59)), message("2", amani, at: date(23, 0, 1))]
        XCTAssertEqual(KitoChatGrouping.positions(for: messages, calendar: calendar), [.single, .single])
    }

    func testSystemMessagesNeverGroup() {
        let messages = [
            message("1", amani, at: date(23, 10, 0)),
            message("2", amani, at: date(23, 10, 1), system: true),
            message("3", amani, at: date(23, 10, 2)),
        ]
        XCTAssertEqual(KitoChatGrouping.positions(for: messages, calendar: calendar), [.single, .single, .single])
    }

    func testExplicitBreakSplitsAGroup() {
        let messages = [message("1", amani, at: date(23, 10, 0)), message("2", amani, at: date(23, 10, 1)), message("3", amani, at: date(23, 10, 2))]
        XCTAssertEqual(KitoChatGrouping.positions(for: messages, calendar: calendar, breaksBefore: [2]), [.first, .last, .single])
    }

    func testGroupPositionFlags() {
        XCTAssertTrue(KitoChatGroupPosition.single.isGroupStart && KitoChatGroupPosition.single.isGroupEnd)
        XCTAssertTrue(KitoChatGroupPosition.first.isGroupStart && !KitoChatGroupPosition.first.isGroupEnd)
        XCTAssertTrue(!KitoChatGroupPosition.middle.isGroupStart && !KitoChatGroupPosition.middle.isGroupEnd)
        XCTAssertTrue(KitoChatGroupPosition.last.isGroupEnd && !KitoChatGroupPosition.last.isGroupStart)
    }

    // MARK: Date separators

    func testSeparatorTitles() {
        XCTAssertEqual(KitoChatDateFormat.separatorTitle(for: date(23, 8), now: now, calendar: calendar), "Today")
        XCTAssertEqual(KitoChatDateFormat.separatorTitle(for: date(22, 23), now: now, calendar: calendar), "Yesterday")
        XCTAssertEqual(KitoChatDateFormat.separatorTitle(for: date(20, 9), now: now, calendar: calendar), "Sunday")
        XCTAssertEqual(KitoChatDateFormat.separatorTitle(for: date(17, 9), now: now, calendar: calendar), "Thursday")
        XCTAssertEqual(KitoChatDateFormat.separatorTitle(for: date(12, 9), now: now, calendar: calendar), "Sat 12 Sep")
        XCTAssertEqual(KitoChatDateFormat.separatorTitle(for: date(12, 9, year: 2025), now: now, calendar: calendar), "12 Sep 2025")
    }

    func testFutureDateFallsBackToADate() {
        XCTAssertEqual(KitoChatDateFormat.separatorTitle(for: date(25, 9), now: now, calendar: calendar), "Fri 25 Sep")
    }

    func testListTimestamps() {
        XCTAssertEqual(KitoChatDateFormat.listTimestamp(for: date(23, 14, 5), now: now, calendar: calendar), "14:05")
        XCTAssertEqual(KitoChatDateFormat.listTimestamp(for: date(22, 9), now: now, calendar: calendar), "Yesterday")
        XCTAssertEqual(KitoChatDateFormat.listTimestamp(for: date(21, 9), now: now, calendar: calendar), "Mon")
        XCTAssertEqual(KitoChatDateFormat.listTimestamp(for: date(2, 9, month: 8), now: now, calendar: calendar), "02/08/26")
    }

    func testDayKey() {
        XCTAssertEqual(KitoChatDateFormat.dayKey(for: date(3, 22, month: 1), calendar: calendar), "2026-01-03")
    }

    // MARK: Timeline

    func testTimelineSectionsByDay() {
        let messages = [
            message("1", amani, at: date(21, 9)),
            message("2", me, at: date(22, 9)),
            message("3", me, at: date(22, 9, 1)),
            message("4", amani, at: date(23, 9)),
        ]
        let timeline = KitoChatTimeline(messages: messages, currentUserID: "me", now: now, calendar: calendar)
        XCTAssertEqual(timeline.sections.map(\.title), ["Monday", "Yesterday", "Today"])
        XCTAssertEqual(timeline.sections.map(\.id), ["2026-09-21", "2026-09-22", "2026-09-23"])
        XCTAssertEqual(timeline.sections[1].rows, [
            .message(messages[1], position: .first),
            .message(messages[2], position: .last),
        ])
    }

    func testTimelineInsertsUnreadDividerAndBreaksTheGroup() {
        let messages = [
            message("1", amani, at: date(23, 9, 0)),
            message("2", amani, at: date(23, 9, 1)),
            message("3", amani, at: date(23, 9, 2)),
        ]
        let timeline = KitoChatTimeline(messages: messages, currentUserID: "me", unreadCount: 2, now: now, calendar: calendar)
        XCTAssertEqual(timeline.sections.count, 1)
        XCTAssertEqual(timeline.sections[0].rows, [
            .message(messages[0], position: .single),
            .unreadDivider(count: 2),
            .message(messages[1], position: .first),
            .message(messages[2], position: .last),
        ])
        XCTAssertEqual(timeline.sections[0].rows[1].id, KitoChatTimeline.unreadDividerID)
    }

    // MARK: Unread divider

    func testUnreadDividerSkipsYourOwnMessages() {
        let messages = [
            message("1", amani, at: date(23, 9, 0)),
            message("2", amani, at: date(23, 9, 1)),
            message("3", me, at: date(23, 9, 2)),
            message("4", amani, at: date(23, 9, 3)),
        ]
        let divider = KitoChatTimeline.unreadDivider(in: messages, currentUserID: "me", unreadCount: 2)
        XCTAssertEqual(divider?.index, 1)
        XCTAssertEqual(divider?.count, 2)
    }

    func testUnreadDividerWithMoreUnreadThanMessages() {
        let messages = [message("1", me, at: date(23, 9)), message("2", amani, at: date(23, 10)), message("3", amani, at: date(23, 11))]
        let divider = KitoChatTimeline.unreadDivider(in: messages, currentUserID: "me", unreadCount: 10)
        XCTAssertEqual(divider?.index, 1)
        XCTAssertEqual(divider?.count, 2)
    }

    func testNoUnreadDivider() {
        let messages = [message("1", me, at: date(23, 9)), message("2", amani, at: date(23, 10))]
        XCTAssertNil(KitoChatTimeline.unreadDivider(in: messages, currentUserID: "me", unreadCount: 0))
        XCTAssertNil(KitoChatTimeline.unreadDivider(in: [message("1", me, at: now)], currentUserID: "me", unreadCount: 3))
    }

    func testUnreadDividerIgnoresSystemMessages() {
        let messages = [message("1", amani, at: date(23, 9)), message("2", amani, at: date(23, 10), system: true)]
        XCTAssertEqual(KitoChatTimeline.unreadDivider(in: messages, currentUserID: "me", unreadCount: 1)?.index, 0)
    }

    func testGroupConversationDetection() {
        let oneToOne = [message("1", amani, at: now), message("2", me, at: now)]
        XCTAssertFalse(KitoChatTimeline.isGroupConversation(oneToOne, currentUserID: "me"))
        let group = oneToOne + [message("3", baraka, at: now)]
        XCTAssertTrue(KitoChatTimeline.isGroupConversation(group, currentUserID: "me"))
    }

    // MARK: Formatting

    func testDurations() {
        XCTAssertEqual(KitoChatDateFormat.duration(0), "0:00")
        XCTAssertEqual(KitoChatDateFormat.duration(7.4), "0:07")
        XCTAssertEqual(KitoChatDateFormat.duration(83), "1:23")
        XCTAssertEqual(KitoChatDateFormat.duration(3_723), "1:02:03")
        XCTAssertEqual(KitoChatDateFormat.duration(-5), "0:00")
        XCTAssertEqual(KitoChatDateFormat.duration(.infinity), "0:00")
    }

    func testTypingText() {
        XCTAssertEqual(KitoChatDateFormat.typingText(for: []), "")
        XCTAssertEqual(KitoChatDateFormat.typingText(for: ["Amani"]), "Amani is typing…")
        XCTAssertEqual(KitoChatDateFormat.typingText(for: ["Amani", "Baraka"]), "Amani and Baraka are typing…")
        XCTAssertEqual(KitoChatDateFormat.typingText(for: ["Amani", "Baraka", "Chebet"]), "Amani, Baraka and Chebet are typing…")
        XCTAssertEqual(KitoChatDateFormat.typingText(for: ["Amani", "Baraka", "Chebet", "Dan"]), "Amani, Baraka and 2 others are typing…")
    }
}
