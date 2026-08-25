// Everything that talks to Meta's Cloud API, plus the signature check that
// proves an inbound request really came from Meta.

/**
 * Verifies the X-Hub-Signature-256 header against the raw request body.
 * Meta signs with the app secret; anyone who can POST to a public URL can
 * forge a webhook otherwise.
 *
 * @param {string} rawBody   the body exactly as received, before JSON.parse
 * @param {string|null} header  value of X-Hub-Signature-256, "sha256=<hex>"
 * @param {string} appSecret
 */
export async function verifySignature(rawBody, header, appSecret) {
  if (!header || !appSecret) return false
  const [scheme, signature] = header.split('=')
  if (scheme !== 'sha256' || !signature) return false

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(appSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  )
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody))
  const expected = [...new Uint8Array(mac)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')

  return timingSafeEqual(expected, signature.toLowerCase())
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

/**
 * Sends a free-form text message. Only legal inside the 24-hour window —
 * the caller is responsible for checking that first.
 *
 * @returns {Promise<{ok: boolean, status: number, id?: string, error?: string}>}
 */
export async function sendText(env, to, text) {
  const version = env.GRAPH_API_VERSION || 'v21.0'
  const url = `https://graph.facebook.com/${version}/${env.PHONE_NUMBER_ID}/messages`

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.WHATSAPP_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      recipient_type: 'individual',
      to,
      type: 'text',
      text: { preview_url: false, body: text },
    }),
  })

  const body = await response.json().catch(() => ({}))

  if (!response.ok) {
    const detail = body?.error?.message || JSON.stringify(body).slice(0, 200)
    return { ok: false, status: response.status, error: detail }
  }

  return { ok: true, status: response.status, id: body?.messages?.[0]?.id }
}

/**
 * Sends a pre-approved template. Required for first contact and for anything
 * outside the 24-hour window.
 *
 * @param {string} name      template name as approved in Business Manager
 * @param {string} lang      template language code, e.g. 'id' or 'en_US'
 * @param {string[]} params  body variables, in order
 */
export async function sendTemplate(env, to, name, lang, params = []) {
  const version = env.GRAPH_API_VERSION || 'v21.0'
  const url = `https://graph.facebook.com/${version}/${env.PHONE_NUMBER_ID}/messages`

  const components = params.length
    ? [{ type: 'body', parameters: params.map((text) => ({ type: 'text', text })) }]
    : []

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.WHATSAPP_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to,
      type: 'template',
      template: { name, language: { code: lang }, components },
    }),
  })

  const body = await response.json().catch(() => ({}))
  if (!response.ok) {
    const detail = body?.error?.message || JSON.stringify(body).slice(0, 200)
    return { ok: false, status: response.status, error: detail }
  }
  return { ok: true, status: response.status, id: body?.messages?.[0]?.id }
}

/**
 * Pulls the text messages out of a webhook payload. Meta nests them four
 * levels deep and batches multiple entries per delivery.
 *
 * @returns {Array<{id: string, from: string, text: string, timestamp: number, profileName: string|null}>}
 */
export function parseInbound(payload) {
  const out = []

  for (const entry of payload?.entry ?? []) {
    for (const change of entry?.changes ?? []) {
      const value = change?.value
      if (!value?.messages) continue

      const names = new Map(
        (value.contacts ?? []).map((c) => [c.wa_id, c.profile?.name ?? null])
      )

      for (const message of value.messages) {
        // Ignore stickers, images, audio for now — flows are text-driven.
        if (message.type !== 'text') continue
        out.push({
          id: message.id,
          from: message.from,
          text: message.text?.body ?? '',
          timestamp: Number(message.timestamp) || Math.floor(Date.now() / 1000),
          profileName: names.get(message.from) ?? null,
        })
      }
    }
  }

  return out
}
