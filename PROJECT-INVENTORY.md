# Kunang — what's in the project

Raw material for writing about this later. Facts only, no framing.

Two pieces: an iPad app that runs the community's day, and a Cloudflare Worker
that carries real WhatsApp conversations to and from it.

- **App** — 22 Swift files, ~5,000 lines, zero third-party dependencies
- **Relay** — 7 JavaScript modules + schema + tests, ~1,800 lines, deployed on
  Cloudflare's free tier
- Everything below is built and running, not planned

---

## 1. The problem it addresses

A small volunteer team runs a mental-health helpline in Bali. Messages arrive
faster than the team can triage them by hand, so people wait, get missed, or
have to repeat their story to whoever picks the thread up next.

Kunang does three things about that: it answers immediately, it sorts by need,
and it hands the volunteer enough context to reply without asking again.

---

## 2. iPad app

### Intake

- CSV and TSV import with a hand-written quote-aware parser (no CSV library)
- Header matching is fuzzy and bilingual — `nama`/`name`, `usia`/`age`,
  `lokasi`/`kota`/`city`, `skor`/`score`, `catatan`/`notes` all resolve
- Unrecognised columns aren't discarded; they're passed to the triage model as
  extra context

### On-device triage

- Apple **Foundation Models** framework, running locally on the iPad
- Structured output via `@Generable` / `@Guide` — the model returns a typed
  struct (category, urgency 1–10, one-sentence reason), not text to parse
- Five categories: **Crisis, High Priority, Moderate, Referral Required, Others**
- Triage instructions are editable by the owner, not hardcoded
- Geographic rule overrides the model: anyone outside Bali is filed as
  *Referral Required*, because the community can only meet people in person
- Rule-based fallback (score bands + red-flag keyword matching) keeps import
  working when Apple Intelligence is unavailable
- No client data leaves the device during triage

### Scheduling

- Queue ordered by priority, then urgency, then lowest wellbeing score
- Handlers assigned randomly among the least-loaded, capped at an even split
- A handler can never hold two sessions at the same time
- Owner-editable: opening/closing hours, session length, break between
  sessions, slots per day, weekends on/off
- Live preview of the slots the current settings produce, and a warning when
  more sessions have been asked for than the day can hold
- Editing settings doesn't move existing bookings; a separate rebuild does

### Calendar

- Calendar.app-style Day and Week timeline — hours down the left, sessions
  drawn as blocks at their real time and height
- Overlapping sessions split the column width between them
- Blocks tinted by priority, dimmed with a tick when completed
- Red now-line on today's column, tap a block to open the client

### Client management

- Seven lifecycle states: New, Waiting for appointment, Scheduled, In progress,
  Completed, Referred out, No response
- Sortable table on iPad, list on iPhone, search by name or location
- An **All Clients** view sitting with Overview and Schedule rather than among
  the categories, so the whole community can be sorted by score, handler or
  session time in one place
- Sidebar counts per category, with a marker on anyone still unbooked and
  uncontacted
- Notes are read-only until Edit is tapped, so they can't be changed by accident
- One-tap "Mark session completed", with the finish time stamped

### Two-track chat

- **Demo** — the on-device model drafts an opener and role-plays the client's
  reply, after a randomised pause so it doesn't answer instantly. Nothing
  leaves the iPad.
- **Live** — real messages. Delivery state on every bubble, visually distinct
  from demo, with the relay's automated messages marked so the owner can tell
  what they didn't write.

### Messaging channels

| Channel | Mechanism | Needs |
|---|---|---|
| WhatsApp | `wa.me` deep link, owner confirms in WhatsApp | nothing |
| Relay | Cloud API via the Worker, sends silently | the relay running |

- Phone numbers normalised to E.164 (`+62 813…`, `0813…`, `813…` all resolve)
- Relay mode is the one that matters on iPad: WhatsApp Business doesn't exist
  there, and iOS gives no app permission to send WhatsApp messages silently, so
  the send has to happen server-side
- An iMessage channel was built and then removed — the system compose sheet is
  unavailable on iPad without Text Message Forwarding, which made it a route
  that looked available and usually wasn't

### Inbound routing

- Polls the relay every 10 seconds, every 5 while a Live thread is open, plus
  immediately on app foreground and on opening any chat
- Each message matched by relay client reference, then by phone number
- **A sender nobody recognises becomes a new client** in Others, named from
  their WhatsApp profile — nothing is dropped for not being in the spreadsheet
- Both directions imported, so the volunteer sees the questions as well as the
  answers
- Deduplicated against replays and against messages the app itself sent

---

## 3. Relay (Cloudflare Worker)

Exists because Meta forbids putting a Cloud API access token in a mobile app,
and because receiving messages needs webhooks, which need a public HTTPS
endpoint. Runs on the free tier with a permanent URL and no cold-start sleep.

### Endpoints

| Route | Purpose |
|---|---|
| `GET /webhook` | Meta's verification handshake |
| `POST /webhook` | inbound messages from Meta |
| `POST /messages` | Kunang sends a message |
| `GET /messages` | Kunang pulls one client's thread |
| `GET /inbox` | every message, both directions |
| `GET /queue` | the triaged queue, most urgent first |
| `GET /health` | liveness check |

### Automated intake

Runs the moment someone messages the number, before any human is involved:

```
message received
  → immediate acknowledgement   hours · response time · "not an emergency service"
                                · emergency numbers · self-help resources
  → intake     immediate danger? ──yes──▶ emergency options, stop asking
               city or regency
               preferred language
               what support do you need?
  → tailored waiting message + what to expect
  → one of five priorities, into the human queue
```

- Bilingual Indonesian/English with language detection from the first message
- Every word of copy lives in one config file, separate from the logic
- Danger answer short-circuits the questionnaire and surfaces crisis resources
  immediately rather than continuing to interview someone in trouble
- Writes an intake summary into the app's thread so the volunteer sees the
  city, the stated need and the priority without re-asking

### Storage and safety

- Cloudflare D1 (SQLite) — `contacts`, `messages`, `flow_state`, `seen_events`
- `X-Hub-Signature-256` verification on every webhook Meta sends
- Idempotency table so a redelivered webhook can't double-reply
- Offline test suite that runs with no Meta account and no network

---

## 4. Engineering

- **Swift 5 language mode** with MainActor-by-default isolation and
  member-import-visibility enabled
- **iOS 26**, universal iPhone + iPad
- SwiftUI throughout — UIKit appears only for system colours and opening URLs
- SwiftData with four models; enums stored as raw strings so lightweight
  migrations keep working, and an unknown stored value degrades to a default
  rather than crashing
- `@Observable` services injected through the environment; scheduling logic
  kept as pure functions in a stateless namespace
- Settings migration that retires a dead default phone number on upgrade
- **Xcode Cloud** CI, distribution through TestFlight
- Git pre-commit hook that blocks Xcode silently rewriting the signing identity,
  written after exactly that broke a build
- Documentation: app README, relay contract, relay setup guide, and a
  transcripts file generated from the code so it can't drift from what gets sent

---

## 5. Deliberate constraints

Worth stating plainly, because each cost something:

- **Triage runs on-device.** Slower and less capable than a server model, and
  it needs a fallback for hardware without Apple Intelligence. In exchange, the
  most sensitive step never transmits anything.
- **Demo and Live are separate threads.** A volunteer can never confuse a
  model-generated rehearsal with a message a real person sent.
- **The access token lives on the server only.** Meta's own guidance; it's also
  why the relay exists at all rather than the app calling Meta directly.
- **Live messages carry logistics, not clinical detail.** WhatsApp's business
  policy restricts health information and Meta disclaims suitability for
  healthcare providers, so scores, categories and notes stay on the iPad.
- **Unknown senders become clients rather than being ignored.** Someone in
  distress who wasn't on a spreadsheet is exactly the person who shouldn't fall
  through.
- **Both sides of a conversation are shown, including automated messages.** An
  earlier version imported only the client's replies, which left volunteers
  reading answers like "1" and "2" with the questions invisible. Cheaper to
  store, useless to read.
- **A channel got removed rather than kept for completeness.** iMessage worked
  in principle and almost never in practice on iPad, so it was cut instead of
  left as an option that disappoints.

---

## 6. Known limits

- Free WhatsApp service window ends 1 October 2026; replies become billable
- Meta test numbers reach only 5 verified recipients; production needs Business
  Verification
- The relay has no shared-secret auth yet — anyone with the URL can read
  `/inbox`
- No push notifications; inbound is polled, so "instant" is a few seconds
- Registering a number on the Cloud API takes it out of the normal WhatsApp app,
  and it isn't casually reversible
- No automated test suite on the app side (the relay has one)
