# Mentalzz

An iPad/iPhone app for running a community mental health group in Bali. The owner drops in a spreadsheet, the on-device model triages everyone, and the app builds a clash-free session schedule.

Built with SwiftUI, SwiftData and Apple's **Foundation Models** framework. Everything runs on device — no client data leaves the iPad.

## Getting started

1. Open `Mentalzz.xcodeproj` and run on an iPad (or iPad simulator).
2. Go to **Handlers** and add the people who run sessions. Nothing schedules until there's at least one.
3. Go to **Upload**, pick `SampleData/sample-clients.csv`, and tap *Triage & build schedule*.

## How it works

**Triage.** Every row from the spreadsheet — including columns Mentalzz doesn't recognise — is flattened into a prompt, with location appended last, and sent to the on-device model. It returns a category, an urgency (1–10) and a one-line reason. The instructions are editable in Upload → *Triage instructions*.

Anyone outside Bali is filed as **Referral Required** regardless of what the model says, since the community can't see them in person.

If Apple Intelligence isn't available, triage falls back to score-based rules (≤3 Crisis, ≤5 High Priority, ≤7 Moderate, above Others) plus red-flag keyword matching, so import always works.

**Scheduling.** Community hours are 08:00–17:00, six 90-minute slots a day: 08:00, 09:30, 11:00, 12:30, 14:00, 15:30. Weekends are skipped by default (toggle in Settings).

Clients are queued by priority, then urgency, then lowest wellbeing score. Each one gets a handler picked at random from whichever active handlers are currently least loaded, capped at an even split (`ceil(clients ÷ handlers)`), then dropped into that handler's earliest free slot. A handler can never hold two sessions at the same time.

Crisis, High Priority and Moderate get booked. Referral Required and Others get messaged instead.

**Chat.** Opening the chat on a client with no history pre-fills the composer with a draft — a warm session invitation, or a soft referral with a nearby-service suggestion for people outside Bali. The owner edits it, sends, and the model writes the client's reply in character. Tap ✨ to redraft.

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
Mentalzz/
├── MentalzzApp.swift          App entry, SwiftData container
├── ContentView.swift          RootView — the split-view shell
├── PreviewData.swift          In-memory sample data for Xcode previews
├── Models/
│   ├── Priority.swift         The 5 categories + client status
│   ├── Client.swift           @Model
│   ├── Handler.swift          @Model + derived stats
│   ├── ChatMessage.swift      @Model
│   └── BaliRegion.swift       In-Bali matching, referral hints
├── Services/
│   ├── CSVImporter.swift      Quote-aware CSV/TSV parser
│   ├── TriageService.swift    @Generable triage + fallback rules
│   ├── SchedulingService.swift Slot generation and assignment
│   └── ChatService.swift      Draft openers and client replies
└── Views/
    ├── OverviewView.swift     Home stats + category cards
    ├── UploadView.swift       Spreadsheet import
    ├── ScheduleView.swift     Sortable Table / compact list
    ├── HandlersView.swift     Leaderboard, stats, edit
    └── ClientDetailView.swift Profile + chat
```

## Notes

- Apple Intelligence must be on for the model features. The app degrades gracefully without it.
- Session links are placeholder strings (`mentalzz.community/s/…`) — wire them to a real video provider when you have one.
- The client replies in chat are generated fiction for demo purposes, not real messages.
