//
//  KitoChatTimeline.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

// MARK: - Grouping

/// Where a message sits in a run of consecutive messages from the same person.
/// Only the last one (or a `single`) gets a tail.
public enum KitoChatGroupPosition: Sendable, Equatable {
    case single, first, middle, last

    public var isGroupStart: Bool { self == .single || self == .first }
    public var isGroupEnd: Bool { self == .single || self == .last }
}

/// Groups consecutive messages from the same author.
public enum KitoChatGrouping {
    /// A run breaks on a new author, a system message, a new day, or a gap longer than `interval`.
    /// `breaksBefore` holds extra indices a run must break before (the unread divider, for instance).
    public static func positions(
        for messages: [KitoChatMessage],
        interval: TimeInterval = 300,
        calendar: Calendar = .current,
        breaksBefore: Set<Int> = []
    ) -> [KitoChatGroupPosition] {
        let joins = messages.indices.map { index in
            index > 0 && !breaksBefore.contains(index)
                && continues(messages[index - 1], with: messages[index], interval: interval, calendar: calendar)
        }
        return messages.indices.map { index in
            let joinsPrevious = joins[index]
            let joinsNext = index + 1 < messages.count && joins[index + 1]
            switch (joinsPrevious, joinsNext) {
            case (false, false): return .single
            case (false, true): return .first
            case (true, true): return .middle
            case (true, false): return .last
            }
        }
    }

    static func continues(_ previous: KitoChatMessage, with message: KitoChatMessage, interval: TimeInterval, calendar: Calendar) -> Bool {
        previous.author.id == message.author.id
            && !previous.isSystem && !message.isSystem
            && calendar.isDate(previous.date, inSameDayAs: message.date)
            && abs(message.date.timeIntervalSince(previous.date)) <= interval
    }
}

// MARK: - Timeline

/// Messages laid out for display: one section per day with its separator title, grouped
/// positions, and an "N unread" divider. Messages are expected in chronological order.
public struct KitoChatTimeline: Equatable {
    public struct Section: Identifiable, Equatable {
        /// The day, as `yyyy-MM-dd`.
        public let id: String
        /// "Today", "Yesterday", "Monday" or a date.
        public let title: String
        public var rows: [Row]
    }

    public enum Row: Identifiable, Equatable {
        case message(KitoChatMessage, position: KitoChatGroupPosition)
        case unreadDivider(count: Int)

        public var id: String {
            switch self {
            case .message(let message, _): message.id
            case .unreadDivider: KitoChatTimeline.unreadDividerID
            }
        }
    }

    /// The scroll id of the unread divider.
    public static let unreadDividerID = "kito.chat.unread"

    public var sections: [Section]

    public init(
        messages: [KitoChatMessage],
        currentUserID: String,
        unreadCount: Int = 0,
        now: Date = .now,
        calendar: Calendar = .current,
        groupingInterval: TimeInterval = 300
    ) {
        let divider = Self.unreadDivider(in: messages, currentUserID: currentUserID, unreadCount: unreadCount)
        let positions = KitoChatGrouping.positions(
            for: messages,
            interval: groupingInterval,
            calendar: calendar,
            breaksBefore: divider.map { [$0.index] } ?? []
        )
        var sections: [Section] = []
        for (index, message) in messages.enumerated() {
            let key = KitoChatDateFormat.dayKey(for: message.date, calendar: calendar)
            if sections.last?.id != key {
                let title = KitoChatDateFormat.separatorTitle(for: message.date, now: now, calendar: calendar)
                sections.append(Section(id: key, title: title, rows: []))
            }
            if let divider, divider.index == index {
                sections[sections.count - 1].rows.append(.unreadDivider(count: divider.count))
            }
            sections[sections.count - 1].rows.append(.message(message, position: positions[index]))
        }
        self.sections = sections
    }

    /// Where the "N unread" divider goes: before the `unreadCount`-th incoming message from the end
    /// (or the earliest incoming one, if there are fewer), and how many incoming messages follow it.
    public static func unreadDivider(in messages: [KitoChatMessage], currentUserID: String, unreadCount: Int) -> (index: Int, count: Int)? {
        guard unreadCount > 0 else { return nil }
        var counted = 0
        var index: Int?
        for candidate in messages.indices.reversed() {
            let message = messages[candidate]
            guard message.author.id != currentUserID, !message.isSystem else { continue }
            counted += 1
            index = candidate
            if counted == unreadCount { break }
        }
        return index.map { ($0, counted) }
    }

    /// True when more than one other person has written — show names and avatars.
    public static func isGroupConversation(_ messages: [KitoChatMessage], currentUserID: String) -> Bool {
        Set(messages.lazy.filter { !$0.isSystem && $0.author.id != currentUserID }.map(\.author.id)).count > 1
    }
}

// MARK: - Formatting

/// Dates, durations and typing text as a chat shows them.
public enum KitoChatDateFormat {
    /// "Today", "Yesterday", a weekday within the last week ("Monday"), "Sat 12 Sep" this year,
    /// otherwise "12 Sep 2025".
    public static func separatorTitle(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        switch daysAgo(date, now: now, calendar: calendar) {
        case 0: return "Today"
        case 1: return "Yesterday"
        case .some(let days) where days > 1 && days < 7:
            return format(date, template: "EEEE", calendar: calendar)
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return format(date, template: sameYear ? "EEE d MMM" : "d MMM yyyy", calendar: calendar)
        }
    }

    /// The time in a chat list: "14:05" today, "Yesterday", "Mon" this week, otherwise a short date.
    public static func listTimestamp(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        switch daysAgo(date, now: now, calendar: calendar) {
        case 0: return time(date, calendar: calendar)
        case 1: return "Yesterday"
        case .some(let days) where days > 1 && days < 7:
            return format(date, template: "EEE", calendar: calendar)
        default:
            return format(date, template: "ddMMyy", calendar: calendar)
        }
    }

    /// The time of day in the calendar's locale: "14:05" or "2:05 PM".
    public static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = formatter(calendar: calendar)
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// "0:07", "1:23", "1:02:03".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded())) : 0
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// "Amani is typing…", "Amani and Baraka are typing…", "Amani, Baraka and Chebet are typing…",
    /// "Amani, Baraka and 2 others are typing…".
    public static func typingText(for names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return "\(names[0]) is typing…"
        case 2: return "\(names[0]) and \(names[1]) are typing…"
        case 3: return "\(names[0]), \(names[1]) and \(names[2]) are typing…"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) others are typing…"
        }
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func daysAgo(_ date: Date, now: Date, calendar: Calendar) -> Int? {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day
    }

    private static func format(_ date: Date, template: String, calendar: Calendar) -> String {
        let formatter = formatter(calendar: calendar)
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private static func formatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        return formatter
    }
}
