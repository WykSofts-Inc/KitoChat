# KitoChat

**[Documentation](https://wyksofts-inc.github.io/KitoChat/documentation/kitochat/)**

A complete chat UI kit for SwiftUI: a conversation view with grouped bubbles, date separators,
read receipts, reactions, swipe-to-reply, voice notes and photos; a composer that records voice
notes; typing indicators; and an inbox. Part of the [Kito](https://github.com/WykSofts-Inc/KitoDevKit) ecosystem.

## A conversation in one view

```swift
import KitoChat

let me = KitoChatUser(id: "wycliff", name: "Wycliff N")
let amani = KitoChatUser(id: "amani", name: "Amani Wanjiru", isOnline: true)

struct ChatScreen: View {
    @State private var messages: [KitoChatMessage] = []
    @State private var typing: [KitoChatUser] = []

    var body: some View {
        VStack(spacing: 0) {
            KitoChatHeader(user: amani, typingUsers: typing, onBack: { dismiss() })
            KitoChatView(messages: $messages, currentUser: me, style: .imessage, typingUsers: typing) { message in
                Task {
                    try await api.send(message)
                    messages.kitoUpdateStatus(of: message.id, to: .sent)
                }
            }
        }
    }
}
```

`KitoChatView` edits `messages` itself: sending appends a `.sending` message, reactions and
deletes update the array, and every new message is handed to `onSend`. Move statuses on as your
backend confirms them — `kitoUpdateStatus(of:to:)` only moves forward
(`sending → sent → delivered → read`, or `sending ⇄ failed`), so late updates can't undo a read.

What you get:

- Consecutive messages from the same person are grouped; only the last one has a tail.
- Sticky date separators ("Today", "Yesterday", "Monday", "Sat 12 Sep") and an "N unread" divider (`unreadCount:`).
- Tap a bubble for its time. Read receipts animate from a clock to one, two and tinted ticks; failed messages offer a retry.
- Long-press a bubble to lift it: react with ❤️😂😮😢🙏👍, or Reply, Copy, Delete.
- Swipe a bubble right to reply; the quote shows above the composer and inside the sent bubble. Tap a quote to jump to it.
- A scroll-to-bottom button that counts messages arriving while you're scrolled up.
- New messages spring in; the view keeps the latest message above the keyboard.
- Group chats (more than one other author) show names and avatars automatically.

## Styles and wallpapers

```swift
KitoChatView(messages: $messages, currentUser: me, style: .glass, wallpaper: .aurora, tint: .orange)
```

Styles: `.modern` (rounded with a soft tail), `.minimal` (flat, tailless), `.glass` (frosted —
made for the `.aurora` wallpaper) and `.imessage` (gradient outgoing bubble, curled tail).
Wallpapers: `.plain`, `.aurora`, `.dots`. `tint` overrides `kitoTheme.colors.primary`; text on it
switches between black and white to stay readable.

## Messages

```swift
KitoChatMessage(author: amani, text: "Tuonane Java saa saba?")
KitoChatMessage(author: me, kind: .image(KitoChatImage(photo, caption: "Diani 🌅")))
KitoChatMessage(author: me, kind: .image(KitoChatImage(url: url, aspectRatio: 4 / 3)))
KitoChatMessage(author: amani, kind: .voice(duration: 14, waveform: samples, url: fileURL))
KitoChatMessage(author: amani, kind: .system("Amani joined"))

var reply = KitoChatMessage(author: me, text: "Perfect", replyTo: KitoChatReply(original))
message.toggleReaction("😂", by: me.id)     // one reaction per person; the same emoji again removes it
```

Text supports inline Markdown and links. One to three emoji on their own are shown large. Voice
notes play with `AVAudioPlayer` when they have a `url` (otherwise playback is simulated, so
previews still play through), with a scrubbable waveform and a 1× / 1.5× / 2× pill. Photos open
full screen with a matched-geometry zoom; drag down to close, pinch or double-tap to zoom.

## Composer

```swift
KitoChatComposer(text: $draft, replyTo: $replyTo, onAttach: { showPicker = true }) { kind in
    send(kind)      // .text("…") or .voice(duration:waveform:url:)
}
```

The field grows to six lines; the microphone morphs into a paper plane when there's text. Hold the
microphone to record — slide left to cancel, slide up to lock and record hands-free, then tap
send. Recording uses `AVAudioRecorder` and needs **`NSMicrophoneUsageDescription`** in your
Info.plist. Without a usable microphone (no usage string, access denied, or a simulator with no
input) the composer records a simulated, clearly labelled "Preview" instead; pass
`simulatesRecordingWhenUnavailable: false` to show a hint instead.

## Presence

```swift
KitoChatTypingIndicator(style: .imessage)
KitoChatStatusTicks(message.status)
KitoChatAvatar(amani, size: 48)            // initials on a stable gradient, or avatarURL; online dot
KitoChatHeader(user: amani, typingUsers: typing, onCall: { … }, onVideo: { … })
```

## Inbox

```swift
KitoChatList(conversations: $conversations, currentUserID: me.id) { conversation in
    open(conversation)
}

// Or your own List:
KitoChatListRow(conversation, currentUserID: me.id)
    .kitoChatSwipeActions(for: conversation,
                          onToggleRead: { … }, onTogglePin: { … },
                          onToggleMute: { … }, onDelete: { … })
```

Rows show the avatar with an online dot, name, last message (with your ticks, or "typing…"), time,
an unread badge, and pinned / muted icons. `KitoChatList` sorts pinned conversations first.

## Logic without UI

```swift
let timeline = KitoChatTimeline(messages: messages, currentUserID: me.id, unreadCount: 3)
timeline.sections           // one per day: title and rows (.message(_, position:) or .unreadDivider)

KitoChatGrouping.positions(for: messages)          // [.first, .middle, .last, .single, …]
KitoChatDateFormat.separatorTitle(for: date)       // "Today", "Yesterday", "Monday", "Sat 12 Sep"
KitoChatDateFormat.listTimestamp(for: date)        // "14:05", "Yesterday", "Mon", "12/09/26"
KitoChatDateFormat.typingText(for: ["Amani", "Baraka"])   // "Amani and Baraka are typing…"
KitoChatWaveform.downsample(samples, to: 40)           // peak bars, normalised to 0…1
```

## Accessibility

Every bubble reads as one element ("Amani Wanjiru: Tuonane Java saa saba?, 14:05") with Reply, React, Copy and
Delete as VoiceOver actions; receipts read "Sent", "Delivered", "Read". Reduce Motion swaps
springs, bouncing dots and lifts for fades. Colours and fonts come from `kitoTheme`, so light and
dark mode follow your theme; bubbles, rows and the composer grow with their text rather than
truncating it.

## Migrating to 0.2

Three public names were renamed so KitoChat can be imported next to KitoLoaders, KitoIslandBar and
KitoMediaPlayer without "ambiguous use" errors:

| 0.1 | 0.2 |
| --- | --- |
| `KitoTypingIndicator` | `KitoChatTypingIndicator` |
| `KitoWaveform` | `KitoChatWaveform` |
| `KitoWaveformView` | `KitoChatWaveformView` |

`KitoChatView`'s `onSend` is now the last parameter with no default, so a trailing closure always
means `onSend` (before, it could bind to `onAttach`). Labelled calls — `onAttach: …, onSend: …` —
and calls with no `onSend` at all compile as before.

## Installation

```swift
.package(url: "https://github.com/WykSofts-Inc/KitoChat.git", from: "0.2.0")
```

## License

MIT — see [LICENSE](LICENSE).
