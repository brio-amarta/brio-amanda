// Kunang relay.
//
// Implements the contract in ../RELAY.md, plus the Meta webhook Kunang cannot
// receive itself. Nothing in the iPad app changes to use this — point
// Settings → Messaging → Relay address at this worker's URL.
//
//   GET  /webhook            Meta's hub.challenge handshake
//   POST /webhook            inbound messages from Meta
//   POST /messages           Kunang sends a message
//   GET  /messages?clientRef=&since=   Kunang pulls what arrived
//   GET  /inbox              every message, known client or not (debugging)
//   GET  /health             is this thing on
//
// The access token lives here and only here. Meta's own guidance is that
// Cloud API tokens are server-side only.

import { verifySignature, sendText, parseInbound } from './whatsapp.js'
import { detectLanguage } from './lang.js'
import { runFlows, normalise } from './flows.js'
import * as store from './store.js'

const DAY = 24 * 60 * 60

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url)
    const path = url.pathname.replace(/\/+$/, '') || '/'

    try {
      if (path === '/health') return json({ ok: true, time: isoSeconds(new Date()) })
      if (path === '/webhook' && request.method === 'GET') return verifyWebhook(url, env)
      if (path === '/webhook' && request.method === 'POST') return receiveWebhook(request, env, ctx)
      if (path === '/messages' && request.method === 'POST') return sendMessage(request, env)
      if (path === '/messages' && request.method === 'GET') return pullMessages(url, env)
      if (path === '/inbox' && request.method === 'GET') return inbox(env)
      if (path === '/queue' && request.method === 'GET') return queue(env)
      return text('Not found', 404)
    } catch (error) {
      console.error('unhandled', error)
      // RELAY.md: non-2xx bodies are shown to the owner verbatim, first 200
      // characters. Make them mean something.
      return text(`Relay error: ${error.message}`, 500)
    }
  },
}

// ── Meta webhook ─────────────────────────────────────────────────────────

/** Meta calls this once when you register the URL. Echo the challenge back. */
function verifyWebhook(url, env) {
  const mode = url.searchParams.get('hub.mode')
  const token = url.searchParams.get('hub.verify_token')
  const challenge = url.searchParams.get('hub.challenge')

  if (mode === 'subscribe' && token && token === env.VERIFY_TOKEN) {
    return new Response(challenge ?? '', { status: 200 })
  }
  return text('Verification failed', 403)
}

async function receiveWebhook(request, env, ctx) {
  // Read the body as text first — the signature covers the raw bytes.
  const raw = await request.text()
  const signature = request.headers.get('x-hub-signature-256')

  const valid = await verifySignature(raw, signature, env.APP_SECRET)
  if (!valid) {
    console.warn('rejected webhook: bad signature')
    return text('Bad signature', 401)
  }

  let payload
  try {
    payload = JSON.parse(raw)
  } catch {
    return text('Bad JSON', 400)
  }

  const messages = parseInbound(payload)

  // Answer Meta immediately; do the work after. Meta retries anything slow,
  // and a retry that re-fires a flow would double-message the client.
  ctx.waitUntil(handleInbound(messages, env))

  return json({ received: messages.length })
}

async function handleInbound(messages, env) {
  for (const message of messages) {
    try {
      const fresh = await store.claimEvent(env.DB, message.id)
      if (!fresh) continue // Meta retry, already handled

      const phone = message.from
      const previous = await store.getContact(env.DB, phone)

      // Once they pick a language at intake, that choice sticks. Before then,
      // follow whatever language this message is in.
      const lang = previous?.language ?? detectLanguage(message.text, 'id')

      const lastInbound = previous?.last_inbound_at ?? 0
      const isNewConversation = message.timestamp - lastInbound > DAY

      const contact = await store.upsertContact(env.DB, phone, {
        profileName: message.profileName,
        lastInboundAt: message.timestamp,
      })

      await store.recordMessage(env.DB, {
        id: message.id,
        phone,
        clientRef: contact.client_ref,
        direction: 'in',
        text: message.text,
        timestamp: message.timestamp,
      })

      const state = await store.getFlowState(env.DB, phone)
      const history = await recentWith(env.DB, phone)
      const historyText = history
        .filter((row) => row.direction === 'in')
        .map((row) => normalise(row.text))
        .join(' ')

      const reply = await runFlows({
        text: message.text,
        normalised: normalise(message.text),
        lang,
        phone,
        firstName: firstName(message.profileName),
        contact,
        state,
        isNewConversation,
        history,
        historyText,
      })

      if (!reply) continue

      // Intake answers, for the volunteer. Stored as an inbound message so it
      // rides the existing GET /messages contract into the Kunang thread —
      // this never goes back over WhatsApp.
      if (reply.summary && env.INTAKE_SUMMARY !== 'off') {
        await store.recordMessage(env.DB, {
          id: `intake-${message.id}`,
          phone,
          clientRef: contact.client_ref,
          direction: 'in',
          text: reply.summary,
          timestamp: message.timestamp + 1,
          auto: true,
        })
      }

      // Persist intake results before sending, so a send failure still leaves
      // the volunteer with the triage.
      const answers = reply.state?.data ?? {}
      if (reply.priority || reply.language || answers.city) {
        await store.upsertContact(env.DB, phone, {
          priority: reply.priority,
          language: reply.language ?? answers.language,
          danger: answers.danger,
          city: answers.city,
          need: answers.need,
          intakeDoneAt: reply.priority ? message.timestamp : undefined,
        })
      }

      if (reply.state) await store.setFlowState(env.DB, phone, reply.state)

      // Inside the 24-hour window by definition — they just messaged us.
      for (const [index, body] of (reply.texts ?? []).entries()) {
        if (!body?.trim()) continue
        const sent = await sendText(env, phone, body)
        if (!sent.ok) {
          console.error(`auto-reply failed for ${phone}: ${sent.error}`)
          break
        }
        await store.recordMessage(env.DB, {
          id: sent.id ?? `auto-${message.id}-${index}`,
          phone,
          clientRef: contact.client_ref,
          direction: 'out',
          text: body,
          timestamp: Math.floor(Date.now() / 1000),
          auto: true,
        })
      }
    } catch (error) {
      console.error('inbound handling failed', message.id, error)
    }
  }
}

async function recentWith(db, phone) {
  const { results } = await db
    .prepare(
      `SELECT direction, text, timestamp FROM messages
       WHERE phone = ? ORDER BY timestamp DESC LIMIT 10`
    )
    .bind(phone)
    .all()
  return (results ?? []).reverse()
}

// ── Contract: POST /messages ─────────────────────────────────────────────

async function sendMessage(request, env) {
  const guard = checkAppSecret(request, env)
  if (guard) return guard

  let body
  try {
    body = await request.json()
  } catch {
    return text('Body must be JSON', 400)
  }

  const to = String(body?.to ?? '').replace(/\D/g, '')
  const messageText = String(body?.text ?? '')
  const clientRef = body?.clientRef ? String(body.clientRef) : null

  if (!to) return text('Missing "to" — expected digits-only E.164, no +', 400)
  if (!messageText.trim()) return text('Missing "text"', 400)

  // Learn who this number is, and backfill anything received before we knew.
  if (clientRef) {
    await store.upsertContact(env.DB, to, { clientRef })
    await store.linkClientRef(env.DB, to, clientRef)
  }

  // The 24-hour window. Outside it Meta only accepts pre-approved templates,
  // so refuse clearly rather than letting the Cloud API return something
  // cryptic. RELAY.md: the owner sees this text.
  const contact = await store.getContact(env.DB, to)
  const last = contact?.last_inbound_at ?? 0
  const age = Math.floor(Date.now() / 1000) - last

  if (!last || age > DAY) {
    const reason = last
      ? `Their last message was ${Math.floor(age / 3600)} hours ago.`
      : 'They have never messaged this number.'
    return text(
      `Outside WhatsApp's 24-hour window. ${reason} Free-form messages are only allowed within 24 hours of their last message — first contact needs a template approved in Meta Business Manager. Nothing was sent.`,
      409
    )
  }

  const sent = await sendText(env, to, messageText)
  if (!sent.ok) {
    return text(`WhatsApp refused the message: ${sent.error}`, 502)
  }

  await store.recordMessage(env.DB, {
    id: sent.id ?? `out-${crypto.randomUUID()}`,
    phone: to,
    clientRef,
    direction: 'out',
    text: messageText,
    timestamp: Math.floor(Date.now() / 1000),
  })

  return json({ ok: true, id: sent.id })
}

// ── Contract: GET /messages?clientRef=…&since=… ──────────────────────────

async function pullMessages(url, env) {
  const clientRef = url.searchParams.get('clientRef')
  const since = url.searchParams.get('since')

  if (!clientRef) return json([])

  const sinceEpoch = since ? Math.floor(Date.parse(since) / 1000) : 0
  const rows = await store.inboundSince(
    env.DB,
    clientRef,
    Number.isFinite(sinceEpoch) ? sinceEpoch : 0
  )

  // Kunang parses with ISO8601DateFormatter at its default settings, which
  // rejects fractional seconds. toISOString() would emit ".000Z" and every
  // timestamp would silently fall back to "now". Second precision only.
  return json(
    rows.map((row) => ({
      text: row.text,
      timestamp: isoSeconds(new Date(row.timestamp * 1000)),
    }))
  )
}

// ── Debugging ────────────────────────────────────────────────────────────

/**
 * Everything the relay has, including messages from numbers that are not
 * Kunang clients — those have no clientRef, so the app cannot show them.
 */
async function inbox(env) {
  const rows = await store.recentMessages(env.DB, 100)
  return json(
    rows.map((row) => ({
      phone: row.phone,
      name: row.profile_name,
      clientRef: row.client_ref,
      visibleInKunang: Boolean(row.client_ref),
      direction: row.direction,
      auto: Boolean(row.auto),
      text: row.text,
      timestamp: isoSeconds(new Date(row.timestamp * 1000)),
    }))
  )
}

/**
 * The triaged queue, most urgent first — the last box on the flowchart.
 * Kunang cannot show this without app changes, so it lives here.
 */
async function queue(env) {
  const rows = await store.queue(env.DB)
  return json(
    rows.map((row) => ({
      phone: row.phone,
      name: row.profile_name,
      priority: row.priority,
      danger: row.danger,
      city: row.city,
      need: row.need,
      language: row.language,
      clientRef: row.client_ref,
      visibleInKunang: Boolean(row.client_ref),
      intakeDoneAt: row.intake_done_at ? isoSeconds(new Date(row.intake_done_at * 1000)) : null,
    }))
  )
}

// ── Helpers ──────────────────────────────────────────────────────────────

function firstName(full) {
  if (!full) return null
  return String(full).trim().split(/\s+/)[0]
}

/**
 * Optional shared secret. Kunang sends no auth header today, so this is off
 * unless APP_SHARED_SECRET is set. RELAY.md is right that an open relay is an
 * open SMS gateway — set it before this touches real client data.
 */
function checkAppSecret(request, env) {
  if (!env.APP_SHARED_SECRET) return null
  if (request.headers.get('x-relay-secret') === env.APP_SHARED_SECRET) return null
  return text('Relay rejected the request: missing or wrong X-Relay-Secret.', 401)
}

function isoSeconds(date) {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z')
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function text(message, status = 200) {
  return new Response(message, {
    status,
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  })
}
