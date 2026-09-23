//
//  KitoChatModels.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit

// MARK: - User

/// Someone taking part in a conversation.
public struct KitoChatUser: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var avatarURL: URL?
    /// Overrides the avatar gradient and the author-name colour in group chats.
    public var color: Color?
    public var isOnline: Bool

    public init(id: String, name: String, avatarURL: URL? = nil, color: Color? = nil, isOnline: Bool = false) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.color = color
        self.isOnline = isOnline
    }

    /// Up to two initials: "Amani Wanjiru" → "AW", "Baraka" → "B".
    public var initials: String {
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    /// The first word of the name: "Amani Wanjiru" → "Amani".
    public var firstName: String {
        name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
    }

    /// A stable index into a palette of `count` colours, the same on every launch.
    public func paletteIndex(count: Int) -> Int {
        guard count > 0 else { return 0 }
        let hash = id.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
        return Int(hash % UInt64(count))
    }
}

// MARK: - Status

/// Where an outgoing message is on its way to the recipient.
///
/// Statuses only move forward — `sending → sent → delivered → read` — except that a
/// `sending` message can fail and a failed one can be retried (back to `sending`).
public enum KitoChatMessageStatus: String, CaseIterable, Sendable {
    case sending, sent, delivered, read, failed

    private var rank: Int {
        switch self {
        case .sending, .failed: 0
        case .sent: 1
        case .delivered: 2
        case .read: 3
        }
    }

    /// Whether moving from this status to `next` is allowed.
    public func canTransition(to next: KitoChatMessageStatus) -> Bool {
        switch (self, next) {
        case (.sending, .failed), (.failed, .sending): true
        case (.failed, _), (_, .failed): false
        default: next.rank > rank
        }
    }

    /// `next` if the move is allowed, otherwise this status unchanged.
    public func transitioned(to next: KitoChatMessageStatus) -> KitoChatMessageStatus {
        canTransition(to: next) ? next : self
    }

    /// The following step on the happy path, or `nil` once read (or failed).
    public var next: KitoChatMessageStatus? {
        switch self {
        case .sending: .sent
        case .sent: .delivered
        case .delivered: .read
        case .read, .failed: nil
        }
    }

    /// Spoken by VoiceOver: "Sending", "Sent", "Delivered", "Read", "Not delivered".
    public var accessibilityLabel: String {
        switch self {
        case .sending: "Sending"
        case .sent: "Sent"
        case .delivered: "Delivered"
        case .read: "Read"
        case .failed: "Not delivered"
        }
    }
}

// MARK: - Reactions and replies

/// One emoji and everyone who reacted with it.
public struct KitoChatReaction: Identifiable, Hashable, Sendable {
    public var emoji: String
    public var userIDs: [String]

    public var id: String { emoji }
    public var count: Int { userIDs.count }

    public init(_ emoji: String, userIDs: [String]) {
        self.emoji = emoji
        self.userIDs = userIDs
    }

    public func includes(_ userID: String) -> Bool { userIDs.contains(userID) }

    /// The six reactions offered when you long-press a message.
    public static let quickPicks = ["❤️", "😂", "😮", "😢", "🙏", "👍"]
}

/// A quoted message shown above a reply.
public struct KitoChatReply: Hashable, Sendable {
    public var messageID: String
    public var authorName: String
    public var preview: String
    /// An SF Symbol shown before the preview, e.g. `photo` or `waveform`.
    public var symbol: String?

    public init(messageID: String, authorName: String, preview: String, symbol: String? = nil) {
        self.messageID = messageID
        self.authorName = authorName
        self.preview = preview
        self.symbol = symbol
    }

    /// Quotes `message`: its author, a one-line preview and a symbol for photos and voice notes.
    public init(_ message: KitoChatMessage) {
        let preview: String
        let symbol: String?
        switch message.kind {
        case .text(let text), .system(let text):
            preview = KitoChatMessage.singleLine(text)
            symbol = nil
        case .image(let image):
            preview = image.caption.map(KitoChatMessage.singleLine) ?? "Photo"
            symbol = "photo"
        case .voice(let duration, _, _):
            preview = "Voice message (\(KitoChatDateFormat.duration(duration)))"
            symbol = "waveform"
        }
        self.init(messageID: message.id, authorName: message.author.name, preview: preview, symbol: symbol)
    }
}

// MARK: - Image

/// A photo in a message — from a URL or an in-memory image.
public struct KitoChatImage: Equatable, @unchecked Sendable {
    public enum Source: Equatable {
        case url(URL)
        case image(UIImage)
    }

    public var source: Source
    /// Width ÷ height, used to size the bubble before the image loads.
    public var aspectRatio: CGFloat
    public var caption: String?

    public init(url: URL, aspectRatio: CGFloat = 4.0 / 3.0, caption: String? = nil) {
        self.source = .url(url)
        self.aspectRatio = aspectRatio > 0 ? aspectRatio : 1
        self.caption = caption
    }

    public init(_ image: UIImage, caption: String? = nil) {
        self.source = .image(image)
        self.aspectRatio = image.size.height > 0 ? image.size.width / image.size.height : 1
        self.caption = caption
    }
}

// MARK: - Message

/// One message in a conversation.
public struct KitoChatMessage: Identifiable, Equatable, Sendable {
    /// What the message carries.
    public enum Kind: Equatable, Sendable {
        case text(String)
        case image(KitoChatImage)
        /// A voice note: its length, loudness samples (0…1) for the waveform, and the recording if you have it.
        case voice(duration: TimeInterval, waveform: [Float], url: URL? = nil)
        /// A centred note such as "Amani joined the group".
        case system(String)
    }

    public let id: String
    public var author: KitoChatUser
    public var date: Date
    public var kind: Kind
    public var status: KitoChatMessageStatus
    public var reactions: [KitoChatReaction]
    public var replyTo: KitoChatReply?

    public init(
        id: String = UUID().uuidString,
        author: KitoChatUser,
        date: Date = .now,
        kind: Kind,
        status: KitoChatMessageStatus = .sent,
        reactions: [KitoChatReaction] = [],
        replyTo: KitoChatReply? = nil
    ) {
        self.id = id
        self.author = author
        self.date = date
        self.kind = kind
        self.status = status
        self.reactions = reactions
        self.replyTo = replyTo
    }

    /// A text message.
    public init(
        id: String = UUID().uuidString,
        author: KitoChatUser,
        text: String,
        date: Date = .now,
        status: KitoChatMessageStatus = .sent,
        reactions: [KitoChatReaction] = [],
        replyTo: KitoChatReply? = nil
    ) {
        self.init(id: id, author: author, date: date, kind: .text(text), status: status, reactions: reactions, replyTo: replyTo)
    }

    public var isSystem: Bool {
        if case .system = kind { return true }
        return false
    }

    /// The text you'd copy: the message text, the photo caption or the system note.
    public var copyableText: String? {
        switch kind {
        case .text(let text), .system(let text): text
        case .image(let image): image.caption
        case .voice: nil
        }
    }

    /// A one-line summary for chat lists and notifications: "📷 Photo", "🎤 Voice message · 0:12".
    public var previewText: String {
        switch kind {
        case .text(let text), .system(let text):
            Self.singleLine(text)
        case .image(let image):
            "📷 " + (image.caption.map(Self.singleLine) ?? "Photo")
        case .voice(let duration, _, _):
            "🎤 Voice message · " + KitoChatDateFormat.duration(duration)
        }
    }

    /// How many emoji a text message holds when it holds nothing else (1…3), so it can be shown large.
    public var jumboEmojiCount: Int? {
        guard case .text(let text) = kind else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 3, trimmed.allSatisfy(\.isKitoEmoji) else { return nil }
        return trimmed.count
    }

    /// Adds `emoji` from `userID`, replacing that person's previous reaction; the same emoji again removes it.
    public mutating func toggleReaction(_ emoji: String, by userID: String) {
        let hadSame = reactions.first { $0.emoji == emoji }?.includes(userID) ?? false
        for index in reactions.indices {
            reactions[index].userIDs.removeAll { $0 == userID }
        }
        if !hadSame {
            if let index = reactions.firstIndex(where: { $0.emoji == emoji }) {
                reactions[index].userIDs.append(userID)
            } else {
                reactions.append(KitoChatReaction(emoji, userIDs: [userID]))
            }
        }
        reactions.removeAll { $0.userIDs.isEmpty }
    }

    /// The emoji `userID` reacted with, if any.
    public func reaction(of userID: String) -> String? {
        reactions.first { $0.includes(userID) }?.emoji
    }

    static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

extension Character {
    var isKitoEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation || (unicodeScalars.count > 1 && first.properties.isEmoji)
    }
}

// MARK: - Arrays of messages

public extension Array where Element == KitoChatMessage {
    /// Moves the message with `id` to `status`, if that transition is allowed. Returns whether it changed.
    @discardableResult
    mutating func kitoUpdateStatus(of id: KitoChatMessage.ID, to status: KitoChatMessageStatus) -> Bool {
        guard let index = firstIndex(where: { $0.id == id }), self[index].status.canTransition(to: status) else { return false }
        self[index].status = status
        return true
    }
}

// MARK: - Conversation

/// One row of an inbox.
public struct KitoChatConversation: Identifiable, Equatable, Sendable {
    public let id: String
    /// The other person (or the group, with a group avatar colour).
    public var user: KitoChatUser
    /// Shown instead of `user.name` — for groups.
    public var title: String?
    public var lastMessage: KitoChatMessage?
    public var unreadCount: Int
    public var isPinned: Bool
    public var isMuted: Bool
    public var isTyping: Bool

    public init(
        id: String = UUID().uuidString,
        user: KitoChatUser,
        title: String? = nil,
        lastMessage: KitoChatMessage? = nil,
        unreadCount: Int = 0,
        isPinned: Bool = false,
        isMuted: Bool = false,
        isTyping: Bool = false
    ) {
        self.id = id
        self.user = user
        self.title = title
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.isPinned = isPinned
        self.isMuted = isMuted
        self.isTyping = isTyping
    }

    public var displayName: String { title ?? user.name }

    /// Pinned first, then the most recent message first.
    public static func sorted(_ conversations: [KitoChatConversation]) -> [KitoChatConversation] {
        conversations.enumerated().sorted { lhs, rhs in
            if lhs.element.isPinned != rhs.element.isPinned { return lhs.element.isPinned }
            let l = lhs.element.lastMessage?.date ?? .distantPast
            let r = rhs.element.lastMessage?.date ?? .distantPast
            return l == r ? lhs.offset < rhs.offset : l > r
        }
        .map(\.element)
    }
}
