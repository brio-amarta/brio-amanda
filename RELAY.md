# Relay server contract

Kunang can send real WhatsApp messages through the Meta Cloud API, but the
app never holds a Cloud API access token. Meta's own guidance is that these
tokens are server-side only — anyone who extracts one from a shipped app can
message as your business indefinitely. Receiving messages needs webhooks, which
need a public HTTPS endpoint regardless.

So the app talks to a small server you host. That server holds the token, calls
Meta, receives Meta's webhooks, and exposes the two endpoints below. Point
Settings → Messaging → Relay address at its base URL.

Nothing in the app depends on how you build it. Anything that speaks HTTP and
JSON will do.

## Endpoints

### `POST {base}/messages`

Sends a message.

```json
{
  "to": "628123456789",
  "text": "Hi Kadek, your session is Tuesday at 09:30.",
  "clientRef": "9F2A1C4E-…"
}
```

`to` is digits-only E.164 — no `+`, no spaces. `clientRef` is the client's UUID
inside Kunang; store it so inbound messages can be matched back.

Any 2xx means accepted. The app marks the message **Delivered**. Non-2xx bodies
are shown to the owner verbatim (first 200 characters), so put something useful
there.

### `GET {base}/messages?clientRef=…&since=…`

Returns messages received from that client after `since` (ISO 8601).

```json
[
  { "text": "That works, thank you", "timestamp": "2026-08-22T09:31:04Z" }
]
```

Return `[]` when there's nothing new. The app polls this when the owner taps ↻
in a Live thread; it does not poll on a timer.

## What your server has to handle

**The 24-hour window.** WhatsApp only allows free-form messages within 24 hours
of the client's last message. Outside it, sends must use a template you've had
approved in Meta Business Manager. Your relay should detect this and either
substitute the approved template or return a clear 4xx explaining why it
refused — the owner sees that text.

**Webhooks.** Register your endpoint with Meta, verify the `hub.challenge`
handshake, and validate the `X-Hub-Signature-256` header on every delivery.
Store inbound messages keyed by phone number so `clientRef` lookups resolve.

**Authentication.** The contract above has none. Add a shared secret header or
mTLS before this touches real client data — an open relay is an open SMS gateway.

**Retention.** Client messages passing through your server are health-adjacent
data about identifiable people. Decide how long you keep them and encrypt at
rest.

## Policy limits worth reading before you build this

- WhatsApp's Business Messaging Policy prohibits telemedicine and restricts
  health-related information where regulations limit distributing it to systems
  without heightened safeguards.
- Meta makes no representation that its Business Services meet the needs of
  entities with heightened confidentiality obligations, healthcare included.

Practically: session times, reminders and "are you still coming?" are fine.
Triage categories, wellbeing scores, and intake notes are not — keep those on
the iPad.

Sources: [WhatsApp Business Messaging Policy](https://business.whatsapp.com/policy),
[WhatsApp Business Terms of Service](https://www.whatsapp.com/legal/business-terms),
[Using Authorization Tokens for the WhatsApp Business Platform](https://developers.facebook.com/blog/post/2022/12/05/auth-tokens/)
