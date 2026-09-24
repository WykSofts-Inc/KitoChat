# ``KitoChat``

A complete chat UI kit for SwiftUI, from the conversation view and composer to typing indicators and an inbox.

## Overview

KitoChat renders a full conversation with ``KitoChatView``: consecutive messages
are grouped, days get sticky date separators, read receipts animate, and bubbles
support reactions, swipe-to-reply, voice notes and photos. The view edits the
`messages` binding itself — sending appends a `.sending` message, reactions and
deletes update the array — and hands every new message to `onSend`.

```swift
import KitoChat

let me = KitoChatUser(id: "wycliff", name: "Wycliff N")
let amani = KitoChatUser(id: "amani", name: "Amani Wanjiru", isOnline: true)

struct ChatScreen: View {
    @State private var messages: [KitoChatMessage] = []

    var body: some View {
        VStack(spacing: 0) {
            KitoChatHeader(user: amani)
            KitoChatView(messages: $messages, currentUser: me, style: .imessage) { message in
                Task {
                    try await api.send(message)
                    messages.kitoUpdateStatus(of: message.id, to: .sent)
                }
            }
        }
    }
}
```

Move statuses on as your backend confirms them with `kitoUpdateStatus(of:to:)`.
It only moves forward along ``KitoChatMessageStatus``, so a late update can't
undo a read. Pick a look with ``KitoChatBubbleStyle`` and ``KitoChatWallpaper``;
colours and fonts come from the Kito theme.

The same pieces are available on their own: ``KitoChatComposer`` records voice
notes and grows with its text, ``KitoChatList`` and ``KitoChatListRow`` build an
inbox, and ``KitoChatTimeline``, ``KitoChatGrouping`` and ``KitoChatDateFormat``
expose the grouping and date logic without any UI. Voice recording needs
`NSMicrophoneUsageDescription` in your `Info.plist`.

## Topics

### Conversation

- ``KitoChatView``
- ``KitoChatBubble``
- ``KitoChatComposer``
- ``KitoChatHeader``

### Models

- ``KitoChatUser``
- ``KitoChatMessage``
- ``KitoChatMessageStatus``
- ``KitoChatReaction``
- ``KitoChatReply``
- ``KitoChatImage``
- ``KitoChatConversation``

### Appearance

- ``KitoChatBubbleStyle``
- ``KitoChatWallpaper``

### Presence

- ``KitoChatTypingIndicator``
- ``KitoChatStatusTicks``
- ``KitoChatAvatar``

### Inbox

- ``KitoChatList``
- ``KitoChatListRow``

### Voice Notes

- ``KitoChatWaveform``
- ``KitoChatWaveformView``
- ``KitoPlaybackSpeed``

### Timeline Logic

- ``KitoChatTimeline``
- ``KitoChatGrouping``
- ``KitoChatGroupPosition``
- ``KitoChatDateFormat``
