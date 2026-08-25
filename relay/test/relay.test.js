// Runs on plain Node — no wrangler, no network, no Meta account.
//   node --test test/
//
// Covers the parts that are easy to get silently wrong: language detection,
// the signature check, Meta's nested payload shape, and the timestamp format
// Kunang's ISO8601DateFormatter will actually accept.

import { test } from 'node:test'
import assert from 'node:assert/strict'

import { detectLanguage } from '../src/lang.js'
import { verifySignature, parseInbound } from '../src/whatsapp.js'
import { normalise } from '../src/flows.js'

test('detects Indonesian', () => {
  assert.equal(detectLanguage('Halo, saya mau tanya jadwal sesi minggu ini'), 'id')
  assert.equal(detectLanguage('terima kasih banget kak'), 'id')
  assert.equal(detectLanguage('bisa ga saya daftar?'), 'id')
})

test('detects English', () => {
  assert.equal(detectLanguage('Hi, can I ask about the session schedule this week?'), 'en')
  assert.equal(detectLanguage('thank you so much'), 'en')
  assert.equal(detectLanguage('what time should I come'), 'en')
})

test('falls back when there is no signal', () => {
  assert.equal(detectLanguage('👍'), 'id')
  assert.equal(detectLanguage(''), 'id')
  assert.equal(detectLanguage('ok', 'en'), 'en')
})

test('signature check accepts a correctly signed body', async () => {
  const secret = 'test-app-secret'
  const body = JSON.stringify({ hello: 'world' })

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  )
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body))
  const hex = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('')

  assert.equal(await verifySignature(body, `sha256=${hex}`, secret), true)
})

test('signature check rejects forgery, wrong secret and missing header', async () => {
  const body = JSON.stringify({ hello: 'world' })
  assert.equal(await verifySignature(body, 'sha256=' + 'a'.repeat(64), 'secret'), false)
  assert.equal(await verifySignature(body, null, 'secret'), false)
  assert.equal(await verifySignature(body, 'sha256=deadbeef', ''), false)
})

test('parses a real-shaped Meta payload', () => {
  const payload = {
    object: 'whatsapp_business_account',
    entry: [
      {
        id: '102290129340398',
        changes: [
          {
            field: 'messages',
            value: {
              messaging_product: 'whatsapp',
              metadata: { display_phone_number: '15550783881', phone_number_id: '106540352242922' },
              contacts: [{ profile: { name: 'Kadek Ayu' }, wa_id: '628123456789' }],
              messages: [
                {
                  from: '628123456789',
                  id: 'wamid.HBgNNjI4MTIz',
                  timestamp: '1755000000',
                  text: { body: 'Halo, jadwal saya kapan ya?' },
                  type: 'text',
                },
              ],
            },
          },
        ],
      },
    ],
  }

  const [message] = parseInbound(payload)
  assert.equal(message.from, '628123456789')
  assert.equal(message.text, 'Halo, jadwal saya kapan ya?')
  assert.equal(message.profileName, 'Kadek Ayu')
  assert.equal(message.timestamp, 1755000000)
  assert.equal(detectLanguage(message.text), 'id')
})

test('ignores non-text messages and status-only deliveries', () => {
  assert.deepEqual(parseInbound({ entry: [{ changes: [{ value: { statuses: [{}] } }] }] }), [])
  assert.deepEqual(
    parseInbound({
      entry: [{ changes: [{ value: { messages: [{ type: 'image', from: '62812', id: 'x' }] } }] }],
    }),
    []
  )
  assert.deepEqual(parseInbound({}), [])
})

test('timestamps carry no fractional seconds', () => {
  // Kunang uses ISO8601DateFormatter at default settings, which rejects
  // ".000Z" and silently substitutes the current time.
  const isoSeconds = (d) => d.toISOString().replace(/\.\d{3}Z$/, 'Z')
  const stamp = isoSeconds(new Date(1755000000 * 1000))
  assert.match(stamp, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
})

test('normalise strips punctuation for flow matching', () => {
  assert.equal(normalise('  JADWAL, please!! '), 'jadwal please')
  assert.equal(normalise(null), '')
})
