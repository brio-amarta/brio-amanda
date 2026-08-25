# Kunang

An iPad/iPhone app for running a community mental health group in Bali.

> **Naming.** The app is **Kunang** everywhere a person sees it — Home Screen,
> sidebar, App Store. The Xcode project, target and scheme are still named
> `Mentalzz`, deliberately: Xcode Cloud workflows reference those by name, and
> renaming them breaks the build pipeline. `CFBundleDisplayName` carries the
> real name instead. The owner drops in a spreadsheet, the on-device model triages everyone, and the app builds a clash-free session schedule.

Built with SwiftUI, SwiftData and Apple's **Foundation Models** framework. Everything runs on device — no client data leaves the iPad.

## Getting started

1. Open `Mentalzz.xcodeproj` and run on an iPad (or iPad simulator).
2. Go to **Handlers** and add the people who run sessions. Nothing schedules until there's at least one.
3. Go to **Upload**, pick `SampleData/sample-clients.csv`, and tap *Triage & build schedule*.

## How it works

**Triage.** Every row from the spreadsheet — including columns Kunang doesn't recognise — is flattened into a prompt, with location appended last, and sent to the on-device model. It returns a category, an urgency (1–10) and a one-line reason. The instructions are editable in Upload → *Triage instructions*.

Anyone outside Bali is filed as **Referral Required** regardless of what the model says, since the community can't see them in person.

If Apple Intelligence isn't available, triage falls back to score-based rules (≤3 Crisis, ≤5 High Priority, ≤7 Moderate, above Others) plus red-flag keyword matching, so import always works.

**Scheduling.** Community hours, session length, break between sessions, slots per day and the weekends toggle are all editable in **Settings**. Out of the box: 08:00–17:00, six back-to-back 90-minute slots (08:00, 09:30, 11:00, 12:30, 14:00, 15:30), weekends skipped.

Settings shows the slots your numbers actually produce as you change them, and warns when you've asked for more sessions than the day can hold — the extras are dropped rather than pushed past closing time. Editing these doesn't move anyone already booked; *Rebuild schedule* does that.

Clients are queued by priority, then urgency, then lowest wellbeing score. Each one gets a handler picked at random from whichever active handlers are currently least loaded, capped at an even split (`ceil(clients ÷ handlers)`), then dropped into that handler's earliest free slot. A handler can never hold two sessions at the same time.

Crisis, High Priority and Moderate get booked. Referral Required and Others get messaged instead.

**Chat.** Every client has two threads, switched with the segmented control at the top of the chat pane.

*Demo* is the original: opening the chat on a client with no history pre-fills the composer with a draft — a warm session invitation, or a soft referral with a nearby-service suggestion for people outside Bali. The owner edits it, sends, and the model writes the client's reply in character after a pause of a few seconds (range editable in Settings). Tap ✨ to redraft. Nothing here leaves the iPad.

*Live* really reaches the person. Pick the channel in Settings → Messaging:

| Channel | What happens | Needs |
|---|---|---|
| WhatsApp | Opens WhatsApp on a `wa.me` link with the text filled in; you tap send there | Nothing |
| iMessage | Opens the system message sheet; iOS reports back whether it sent | A device that can send texts |
| Relay server | POSTs to a server you host, which does the real Cloud API send | Your own relay — see `RELAY.md` |

Live bubbles are green and carry a delivery state. WhatsApp can't tell us whether you actually tapped send, so those messages show *Mark as sent* until you confirm. Replies arrive in WhatsApp, not here — the ✎ button logs what they said so the thread on the iPad matches the real one. With a relay, ↻ pulls new inbound messages instead.

**Before you use Live in production.** WhatsApp's Business Messaging Policy restricts health information, and Meta explicitly disclaims that its Business Services meet the needs of healthcare providers — keep live messages to invitations and times, never triage categories, wellbeing scores or notes. Outside 24 hours of a client's last message WhatsApp only permits pre-approved template messages, so first contact through a relay must use a template. And Meta forbids putting a Cloud API access token in a mobile app, which is why the relay exists at all.

## Spreadsheet format

CSV or TSV. Header names are matched loosely (English and Indonesian aliases both work):

| Column | Aliases |
|---|---|
| Name *(required)* | name, full name, client, nama |
| Age | age, usia, umur |
| Location | location, city, region, lokasi, kota |
| Phone | phone, whatsapp, contact, no hp |
| Mental Health Score | mental health score, score, skor |
| Notes | notes, story, catatan, keterangan |

Any other columns are passed to the triage model as extra context. Score runs 0–10 where 10 is thriving. For `.xlsx` files, export as CSV first.

## Project layout

```
Kunang/
├── KunangApp.swift          App entry, SwiftData container
├── ContentView.swift          RootView — the split-view shell
├── PreviewData.swift          In-memory sample data for Xcode previews
├── Models/
│   ├── Priority.swift         The 5 categories + client status
│   ├── Client.swift           @Model
│   ├── Handler.swift          @Model + derived stats
│   ├── ChatMessage.swift      @Model, demo or live + delivery state
│   ├── CommunitySettings.swift @Model, the one owner-editable row
│   └── BaliRegion.swift       In-Bali matching, referral hints
├── Services/
│   ├── CSVImporter.swift      Quote-aware CSV/TSV parser
│   ├── TriageService.swift    @Generable triage + fallback rules
│   ├── SchedulingService.swift Slot generation and assignment
│   ├── ChatService.swift      Draft openers and client replies
│   └── MessagingService.swift Real sending: wa.me, iMessage, relay
└── Views/
    ├── OverviewView.swift     Home stats + category cards
    ├── UploadView.swift       Spreadsheet import
    ├── CalendarView.swift     Day/Week timeline — the Schedule screen
    ├── ScheduleView.swift     Sortable Table / compact list, per category
    ├── HandlersView.swift     Leaderboard, stats, edit
    ├── SettingsView.swift     Hours, sessions, messaging, delays
    ├── SystemMessageComposer.swift MFMessageComposeViewController wrapper
    └── ClientDetailView.swift Profile + demo/live chat
```

## Notes

- Apple Intelligence must be on for the model features. The app degrades gracefully without it.
- Session links are placeholder strings (`kunang.community/s/…`) — wire them to a real video provider when you have one.
- Client replies in the **Demo** thread are generated fiction. The **Live** thread never invents anything.
- Demo mode keeps the "nothing leaves the iPad" guarantee. Live mode deliberately breaks it — that's the point of it — so ship a privacy policy and accurate App Store privacy labels before publishing with Live enabled.
