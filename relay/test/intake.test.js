// Walks the intake flowchart end to end, plus the paths that matter most
// when they go wrong: immediate danger, crisis language at any step, and
// priority assignment.

import { test } from 'node:test'
import assert from 'node:assert/strict'

import { advance, assignPriority, isInBali, mentionsCrisis, parseChoice, PRIORITY } from '../src/intake.js'
import { normalise } from '../src/flows.js'
import { EMERGENCY } from '../src/config.js'

/** Feeds one message into the machine. */
function send(text, state = { flow: null, step: null, data: {} }, extra = {}) {
  return advance({
    text,
    normalised: normalise(text),
    lang: extra.lang ?? 'id',
    state,
    firstName: extra.firstName ?? null,
    isNewConversation: extra.isNewConversation ?? false,
    historyText: extra.historyText ?? '',
  })
}

test('first message gets expectations then the danger question', () => {
  const reply = send('halo', undefined, { firstName: 'Kadek' })

  assert.equal(reply.texts.length, 2)
  const [greeting, question] = reply.texts

  // Everything the flowchart requires in the automated reply.
  assert.match(greeting, /24 jam/)
  assert.match(greeting, /1–2 hari/)
  assert.match(greeting, /bukan layanan darurat/)
  assert.match(greeting, /119/)
  assert.match(greeting, new RegExp(EMERGENCY.lisa.id.replace(/\+/g, '\\+')))
  assert.match(greeting, /bisahelpline\.org\/resources/)
  assert.match(greeting, /Kadek/)

  assert.match(question, /bahaya langsung/)
  assert.equal(reply.state.step, 'danger')
})

test('answering YES to danger stops intake and escalates', () => {
  const state = { flow: 'intake', step: 'danger', data: {} }
  const reply = send('1', state)

  assert.equal(reply.state.step, 'escalated')
  assert.equal(reply.priority, PRIORITY.crisis)
  assert.equal(reply.texts.length, 1)

  // No further questions.
  assert.doesNotMatch(reply.texts[0], /kota atau kabupaten/)
  // Emergency options, and means-restriction advice.
  assert.match(reply.texts[0], /119/)
  assert.match(reply.texts[0], /IGD/)
  assert.match(reply.texts[0], /titipkan/)

  // And nothing more is said afterwards.
  assert.equal(send('halo?', reply.state), null)
})

test('"ya" works as well as "1"', () => {
  const state = { flow: 'intake', step: 'danger', data: {} }
  assert.equal(send('ya', state).state.step, 'escalated')
  assert.equal(send('Tidak', state).state.step, 'city')
  assert.equal(send('not sure', state, { lang: 'en' }).state.step, 'city')
})

test('"not sure" carries a safety note and raises priority', () => {
  const state = { flow: 'intake', step: 'danger', data: {} }
  const reply = send('3', state)

  assert.equal(reply.state.data.danger, 'not sure')
  assert.match(reply.texts[0], /119/)
  assert.equal(
    assignPriority({ danger: 'not sure', need: 'someone to talk to', city: 'Denpasar' }),
    PRIORITY.high
  )
})

test('full happy path: greeting to queued', () => {
  let reply = send('halo', undefined)
  assert.equal(reply.state.step, 'danger')

  reply = send('2', reply.state) // no danger
  assert.equal(reply.state.step, 'city')

  reply = send('Denpasar', reply.state)
  assert.equal(reply.state.step, 'language')
  assert.equal(reply.state.data.city, 'Denpasar')

  reply = send('1', reply.state) // Bahasa Indonesia
  assert.equal(reply.state.step, 'need')
  assert.equal(reply.language, 'id')

  reply = send('2', reply.state) // anxiety/panic
  assert.equal(reply.state.step, 'queued')
  assert.equal(reply.priority, PRIORITY.high)

  const waiting = reply.texts.join('\n')
  assert.match(waiting, /Tarik napas/)              // grounding steps
  assert.match(waiting, /tidak harus menghadapi ini sendirian/) // not a rejection
  assert.match(waiting, /bisahelpline\.org\/services/)          // local referral
  assert.match(reply.summary, /Priority: High Priority/)
  assert.match(reply.summary, /Denpasar \(Bali\)/)

  // Queued and quiet — a volunteer owns the thread now.
  assert.equal(send('masih nunggu nih', reply.state), null)
})

test('language choice switches the reply, and sticks', () => {
  const state = { flow: 'intake', step: 'language', data: { danger: 'no', city: 'Ubud' } }
  const reply = send('2', state) // English

  assert.equal(reply.language, 'en')
  assert.match(reply.texts[0], /What support do you need today/)
})

test('crisis language escalates at any step, whatever the question was', () => {
  const midway = { flow: 'intake', step: 'city', data: { danger: 'no' } }
  const reply = send('sebenarnya aku ingin mati saja', midway)

  assert.equal(reply.state.step, 'escalated')
  assert.equal(reply.priority, PRIORITY.crisis)
  assert.match(reply.summary, /crisis language/)
})

test('crisis phrases in English are caught too', () => {
  assert.equal(mentionsCrisis(normalise("I can't go on anymore")), true)
  assert.equal(mentionsCrisis(normalise('I want to kill myself')), true)
  assert.equal(mentionsCrisis(normalise('aku mau bunuh diri')), true)
  assert.equal(mentionsCrisis(normalise('mau makan siang')), false)
  assert.equal(mentionsCrisis(normalise('I am dying to see the ocean')), false)
})

test('self-harm option is Crisis even when they said no immediate danger', () => {
  const state = {
    flow: 'intake',
    step: 'need',
    data: { danger: 'no', city: 'Denpasar', language: 'id' },
  }
  const reply = send('4', state)

  assert.equal(reply.priority, PRIORITY.crisis)
  assert.match(reply.texts.join('\n'), new RegExp(EMERGENCY.lisa.id.replace(/\+/g, '\\+')))
  assert.match(reply.texts.join('\n'), /3 tanda/) // safety-plan starter
})

test('outside Bali becomes Referral Required, but never overrides Crisis', () => {
  assert.equal(
    assignPriority({ danger: 'no', need: 'someone to talk to', city: 'Surabaya' }),
    PRIORITY.referral
  )
  assert.equal(
    assignPriority({ danger: 'yes', need: 'someone to talk to', city: 'Surabaya' }),
    PRIORITY.crisis
  )
})

test('priority covers all five buckets', () => {
  const base = { city: 'Denpasar', danger: 'no' }
  assert.equal(assignPriority({ ...base, need: 'self-harm or suicidal thoughts' }), PRIORITY.crisis)
  assert.equal(assignPriority({ ...base, need: 'addiction' }), PRIORITY.high)
  assert.equal(assignPriority({ ...base, need: 'someone to talk to' }), PRIORITY.moderate)
  assert.equal(assignPriority({ ...base, need: 'referral to professional help' }), PRIORITY.referral)
  assert.equal(assignPriority({ ...base, need: 'other' }), PRIORITY.others)
})

test('unparseable answers re-ask instead of guessing', () => {
  const state = { flow: 'intake', step: 'danger', data: {} }
  const reply = send('hmm gimana ya', state)

  assert.equal(reply.state.step, 'danger') // did not advance
  assert.match(reply.texts[0], /belum menangkap/)
  assert.match(reply.texts[1], /bahaya langsung/)
})

test('someone asking on behalf of a friend gets the supporting-a-friend guide', () => {
  const state = {
    flow: 'intake',
    step: 'need',
    data: { danger: 'no', city: 'Ubud', language: 'id' },
  }
  const reply = send('1', state, { historyText: 'aku khawatir sama temanku' })
  assert.match(reply.texts.join('\n'), /mendampingi orang lain/)
})

test('a queued person who returns days later is reassured, not re-interrogated', () => {
  const state = { flow: 'intake', step: 'queued', data: { danger: 'no' } }
  assert.equal(send('halo lagi', state), null)

  const reply = send('halo lagi', state, { isNewConversation: true })
  assert.match(reply.texts[0], /masih menyimpan permintaanmu/)
  assert.equal(reply.state.step, 'queued')
})

test('Bali detection matches the app list', () => {
  assert.equal(isInBali('Denpasar'), true)
  assert.equal(isInBali('nusa penida'), true)
  assert.equal(isInBali('Ubud, Gianyar'), true)
  assert.equal(isInBali('Surabaya'), false)
  assert.equal(isInBali(''), false)
})

test('parseChoice ignores out-of-range numbers', () => {
  assert.equal(parseChoice('7', 6), null)
  assert.equal(parseChoice('0', 6), null)
  assert.equal(parseChoice('3 tolong', 6), 3)
})
