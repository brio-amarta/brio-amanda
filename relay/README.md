# Kunang relay

The server side of Live messaging. Holds the WhatsApp Cloud API token,
receives Meta's webhooks, auto-replies, and serves the two endpoints
`../RELAY.md` specifies.

**No app code changes.** Kunang already speaks this contract. You set a URL in
Settings → Messaging and it works.

Runs on Cloudflare Workers + D1 — free tier, permanent HTTPS URL, no cold-start
sleep. That last part matters: Meta gives a webhook a few seconds before it
retries, and hosts that spin down on idle drop the first message of every
conversation.

## What you need from Meta

Everything below is free. You do **not** need to buy a number or migrate an
existing one to test — Meta gives every developer app a test number that can
message up to 5 verified recipients.

1. Go to <https://developers.facebook.com/apps> → **Create app** → type
   **Business** → add the **WhatsApp** product.
2. On **WhatsApp → API Setup**, note:
   - **Phone number ID** (a long number — not the phone number itself)
   - the **temporary access token** (valid 24 hours; fine for testing)
3. On that same page, add **your own WhatsApp number** under *To*. Meta sends a
   code; enter it. Test numbers only reach verified recipients.
4. On **App Settings → Basic**, reveal the **App secret**.
5. Invent a **verify token** — any string, e.g. `kunang-dev-2026`.

> If you later move to a real number: a number registered on the Cloud API can
> no longer be used in the normal WhatsApp or WhatsApp Business app. It is one
> or the other, and the switch is not casually reversible.

## Setup

```bash
cd relay
npm install
npx wrangler login
```

Create the database and paste the id it prints into `wrangler.toml`:

```bash
npx wrangler d1 create kunang-relay
```

Create the tables, locally and remotely:

```bash
npm run db:local
npm run db:remote
```

Put the secrets in `.dev.vars` (gitignored — copy `.dev.vars.example`). Never
commit them, never put them in `wrangler.toml`, never put them in the iOS app.

## Deploy

```bash
npm run deploy
```

Wrangler prints a URL like `https://kunang-relay.<you>.workers.dev`. Register
the secrets against the deployed worker — `.dev.vars` is local only:

```bash
npx wrangler secret put WHATSAPP_TOKEN
npx wrangler secret put PHONE_NUMBER_ID
npx wrangler secret put APP_SECRET
npx wrangler secret put VERIFY_TOKEN
```

Check it: `curl https://kunang-relay.<you>.workers.dev/health`

## Point Meta at it

In the Meta dashboard → **WhatsApp → Configuration → Webhook → Edit**:

- **Callback URL**: `https://kunang-relay.<you>.workers.dev/webhook`
- **Verify token**: whatever you set as `VERIFY_TOKEN`

Click **Verify and save**. Meta calls `GET /webhook` with a challenge; the
worker echoes it back. Then **Manage** → subscribe to the **messages** field.
Nothing arrives until you tick that box.

## Point Kunang at it

On the iPad: **Settings → Messaging** → channel **Relay server** → address
`https://kunang-relay.<you>.workers.dev`

## Test it

1. From your phone, WhatsApp the test number. Within a second or two you get
   the auto-reply — in Indonesian or English, matching what you wrote.
2. `curl https://kunang-relay.<you>.workers.dev/inbox` shows both messages.
3. In Kunang, open a client whose phone number is yours, switch to **Live**,
   send something. It arrives on your phone and comes back marked *Delivered*.
4. Reply from your phone, then tap ↻ in that thread. Your reply appears.

Run the offline tests any time — no Meta account or network needed:

```bash
npm test
```

## Two things to expect

**Inbound only appears when you tap ↻.** `MessagingService.fetchInbound` polls
on demand, not on a timer, and there is no push. The relay has the message the
instant it arrives; Kunang shows it when asked. Making it appear on its own
needs an app-side change.

**Unknown senders are invisible in the app.** Kunang pulls by `clientRef` — a
client's UUID. The relay only learns which phone belongs to which client when
the app first sends to that number, and it backfills earlier messages at that
moment. Someone who messages the number without being in your client list is
stored correctly and shows in `/inbox`, but has no thread to appear in.

## The automated reply

Implements the flowchart. See `TRANSCRIPTS.md` for what each path actually
reads like — generated from the code, so it can't drift from what gets sent.

```
message received
  → stored, appears in Kunang on ↻
  → automated reply    hours · response time · "not an emergency service"
                       · emergency options · self-help link
  → automated intake   immediate danger? ──yes──▶ emergency options, STOP
                       city or regency              no queue form, Crisis
                       preferred language
                       what support do you need?
  → waiting message    tailored to the answers, plus "what to expect"
  → one of five priorities, into the human queue
```

**Every word lives in `src/config.js`.** Hours, response time, resource links,
and both language versions of every message. Edit that file; the logic in
`src/intake.js` doesn't move. Run `npm test` afterwards — the tests assert that
the required elements are still present in the greeting.

**Answering "yes" to immediate danger ends the intake.** No city question, no
language question. They get 119, the nearest IGD, LISA's 24-hour line, a
suggestion to have someone stay with them, and means-restriction advice — then
the bot goes silent. Nobody in danger should have to fill in a form.

**Crisis language escalates at any step.** Someone in real distress won't
reliably answer "1". If any message contains crisis phrasing — in Indonesian or
English — the intake stops and the same emergency response fires. This
over-triggers sometimes, on people asking about a friend. That's the right
direction to be wrong in.

**Answers are accepted as numbers or words.** "ya", "tidak", "not sure",
"english" all work. Anything unparseable re-asks rather than guessing.

**Language sticks once chosen.** Before intake, each reply matches the language
of that message. After Q3, the stored preference wins.

### The five priorities

Same names as `Priority.swift`, so the queue sorts the way the app does.

| | |
|---|---|
| **Crisis** | immediate danger, crisis language, or chose self-harm/suicidal thoughts |
| **High Priority** | "not sure" about danger, anxiety/panic, or addiction |
| **Moderate** | someone to talk to |
| **Referral Required** | outside Bali, or asked for a professional referral |
| **Others** | other |

One deliberate difference from the app: Kunang files anyone outside Bali as
Referral Required regardless of triage. Here that rule does **not** override
Crisis. Someone suicidal in Surabaya is still a crisis, and the emergency
resources they were sent work anywhere.

### Where the intake answers show up

Kunang has no UI for them, so the relay writes a one-line summary into the
thread as if it were an inbound message:

```
[Intake] Priority: High Priority — danger: no — city: Denpasar (Bali) — language: id — need: anxiety/panic
```

It rides the existing `GET /messages` contract, so it appears in the Live
thread with zero app changes. It is **never** sent over WhatsApp. Set
`INTAKE_SUMMARY=off` to disable it and read `GET /queue` instead.

### Adding more flows

`src/flows.js`. A flow is `{ id, match, run }`, tried in order, first match
wins. Put narrower flows **above** `intake` to intercept specific intents.
`run` returns `{ texts, state, priority, summary, language }` or `null` for
silence. Webhook parsing, de-duplication, storage, sending and the 24-hour
window are handled around it.

## Endpoints

| | |
|---|---|
| `GET /health` | liveness |
| `GET /webhook` | Meta's `hub.challenge` handshake |
| `POST /webhook` | inbound from Meta; `X-Hub-Signature-256` verified |
| `POST /messages` | Kunang sends — see `../RELAY.md` |
| `GET /messages?clientRef=&since=` | Kunang pulls |
| `GET /inbox` | every message, including unknown senders (debugging) |
| `GET /queue` | everyone who finished intake, most urgent first |

## Before this touches real client data

- **Authentication.** `POST /messages` is open unless you set
  `APP_SHARED_SECRET`. Kunang sends no auth header today, so switching it on
  needs a matching app change. An open relay is an open SMS gateway — do not
  leave a production URL unprotected.
- **`/inbox` and `/queue` are unauthenticated** and dump message contents and
  triage answers. They are debugging aids. Protect or delete both routes
  before production.
- **Re-verify the crisis numbers before every deploy.** `src/config.js` has
  them in one block with the date they were last checked. A dead crisis number
  is worse than no number.
- **Retention.** Messages passing through here are health-adjacent data about
  identifiable people. Decide how long you keep them.
- **Content.** WhatsApp's Business Messaging Policy restricts health
  information, and Meta disclaims that its Business Services meet the needs of
  healthcare providers. Session times, reminders and "are you still coming?"
  are fine. Triage categories, wellbeing scores and intake notes are not —
  those stay on the iPad.
