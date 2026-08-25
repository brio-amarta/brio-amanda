// The intake state machine, priority rules, and the safety net that runs
// before any of it.
//
// Shape of the conversation:
//
//   message received
//     → greeting (hours, response time, "not an emergency service", emergency
//       options, self-help link)
//     → Q1 immediate danger?  ── yes ──▶ emergency options, STOP. No queue
//     → Q2 city or regency          form. Marked Crisis.
//     → Q3 preferred language
//     → Q4 what support do you need?
//     → waiting message, tailored to the answers
//     → priority assigned, human queue
//
// At every step, before the step runs, the person's free text is checked for
// crisis language. Someone in real distress will not reliably answer "1".

import * as copy from './config.js'
import { say } from './lang.js'

export const STEPS = ['danger', 'city', 'language', 'need', 'queued', 'escalated']

// ── The five priorities, matching Kunang's Priority.swift ────────────────

export const PRIORITY = {
  crisis: 'Crisis',
  high: 'High Priority',
  moderate: 'Moderate',
  referral: 'Referral Required',
  others: 'Others',
}

// ── Safety net ───────────────────────────────────────────────────────────

// Phrases, not single words, so "I want to die" trips it but "dying to see
// you" does not. It will still over-trigger sometimes — on someone asking
// about a friend, or quoting. That is the right direction to be wrong in:
// showing crisis resources to someone who doesn't need them costs little,
// missing someone who does costs everything.
const CRISIS_PHRASES = [
  // Indonesian
  'bunuh diri', 'mengakhiri hidup', 'akhiri hidup', 'ingin mati', 'pengen mati',
  'mau mati', 'pingin mati', 'tidak mau hidup', 'gak mau hidup', 'ga mau hidup',
  'menyakiti diri', 'melukai diri', 'nyakitin diri', 'sayat', 'menyayat',
  'overdosis', 'gantung diri', 'lompat dari', 'tidak sanggup lagi',
  'gak sanggup lagi', 'sudah menyerah', 'lebih baik aku mati',
  'tidak ada gunanya hidup', 'percuma hidup',
  // English
  'kill myself', 'killing myself', 'end my life', 'ending my life',
  'want to die', 'wanna die', 'better off dead', 'take my own life',
  'hurt myself', 'harm myself', 'self harm', 'cut myself', 'cutting myself',
  'overdose', 'hang myself', 'jump off', "can't go on", 'cant go on',
  'no reason to live', 'nothing to live for', 'suicidal',
]

/**
 * True when the text carries crisis language, whatever step we're on.
 * @param {string} normalised  lowercased, punctuation-stripped
 */
export function mentionsCrisis(normalised) {
  return CRISIS_PHRASES.some((phrase) => normalised.includes(phrase))
}

// ── Answer parsing ───────────────────────────────────────────────────────

/**
 * Reads a numbered answer, and also accepts the obvious words. People reply
 * "ya" or "yes" as often as "1".
 *
 * @param {string} normalised
 * @param {number} max  how many options the question offered
 * @param {Object<string, number>} words  word → option number
 * @returns {number|null}
 */
export function parseChoice(normalised, max, words = {}) {
  const trimmed = normalised.trim()
  if (!trimmed) return null

  const digit = trimmed.match(/^(\d+)\b/)
  if (digit) {
    const n = Number(digit[1])
    if (n >= 1 && n <= max) return n
  }

  for (const [word, n] of Object.entries(words)) {
    if (trimmed === word || trimmed.startsWith(word + ' ')) return n
  }
  return null
}

const DANGER_WORDS = {
  ya: 1, iya: 1, yes: 1, yep: 1, 'ya benar': 1,
  tidak: 2, no: 2, nggak: 2, gak: 2, ga: 2, enggak: 2, nope: 2,
  'tidak yakin': 3, 'gak yakin': 3, 'not sure': 3, unsure: 3, 'ga tau': 3,
  'tidak tahu': 3, 'gak tau': 3, maybe: 3, mungkin: 3,
}

const LANGUAGE_WORDS = {
  indonesia: 1, indonesian: 1, bahasa: 1, id: 1, 'bahasa indonesia': 1,
  english: 2, inggris: 2, en: 2, eng: 2,
}

export const DANGER_ANSWERS = { 1: 'yes', 2: 'no', 3: 'not sure' }

export const NEED_ANSWERS = {
  1: 'someone to talk to',
  2: 'anxiety/panic',
  3: 'addiction',
  4: 'self-harm or suicidal thoughts',
  5: 'referral to professional help',
  6: 'other',
}

// ── Bali ─────────────────────────────────────────────────────────────────

// Mirrors BaliRegion.keywords in the app. If that list changes, change this
// one too — the relay and the iPad disagreeing about who is in Bali would be
// a quiet, confusing bug.
const BALI_KEYWORDS = [
  'bali', 'denpasar', 'badung', 'gianyar', 'tabanan', 'buleleng',
  'klungkung', 'karangasem', 'bangli', 'jembrana',
  'kuta', 'legian', 'seminyak', 'canggu', 'kerobokan', 'jimbaran',
  'nusa dua', 'uluwatu', 'pecatu', 'sanur', 'ubud', 'tegallalang',
  'singaraja', 'lovina', 'amed', 'candidasa', 'negara', 'semarapura',
  'mengwi', 'sukawati', 'payangan', 'tampaksiring', 'bedugul',
  'nusa penida', 'nusa lembongan', 'gilimanuk', 'kintamani', 'seririt',
]

export function isInBali(location) {
  const needle = String(location ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
  if (!needle.trim()) return false
  return BALI_KEYWORDS.some((keyword) => needle.includes(keyword))
}

// ── Priority ─────────────────────────────────────────────────────────────

/**
 * Assigns one of Kunang's five priorities from the intake answers.
 *
 * Note where this deliberately differs from the app: Kunang files anyone
 * outside Bali as Referral Required regardless of what triage says. Here that
 * rule does not override Crisis. Someone in Sumatra who is suicidal is still
 * a crisis; the emergency resources they were sent work anywhere.
 *
 * @param {{danger: string, need: string, city: string, crisisLanguage: boolean}} answers
 */
export function assignPriority(answers) {
  const { danger, need, city, crisisLanguage } = answers

  if (danger === 'yes' || crisisLanguage || need === 'self-harm or suicidal thoughts') {
    return PRIORITY.crisis
  }

  const outsideBali = city ? !isInBali(city) : false
  if (outsideBali) return PRIORITY.referral
  if (need === 'referral to professional help') return PRIORITY.referral

  if (danger === 'not sure') return PRIORITY.high
  if (need === 'anxiety/panic' || need === 'addiction') return PRIORITY.high
  if (need === 'someone to talk to') return PRIORITY.moderate
  if (need === 'other') return PRIORITY.others

  return PRIORITY.moderate
}

// ── Waiting message ──────────────────────────────────────────────────────

/**
 * Builds the tailored waiting message. Resources are chosen by what they
 * asked for, so nobody gets a wall of text about addiction when they asked
 * about panic.
 */
export function waitingMessage({ need, city, lang, mentionedSomeoneElse }) {
  const parts = [say(copy.WAITING_INTRO, lang)]

  if (need === 'anxiety/panic') parts.push(say(copy.RESOURCE_GROUNDING, lang))
  if (need === 'self-harm or suicidal thoughts') parts.push(say(copy.RESOURCE_SAFETY_PLAN, lang))
  if (need === 'addiction') parts.push(say(copy.RESOURCE_RECOVERY, lang))
  if (mentionedSomeoneElse) parts.push(say(copy.RESOURCE_SUPPORT_FRIEND, lang))

  if (city) {
    parts.push(
      isInBali(city)
        ? say(copy.RESOURCE_REFERRAL_BALI, lang)
        : say(copy.RESOURCE_REFERRAL_OUTSIDE, lang)
    )
  }

  parts.push(say(copy.WAITING_CLOSE, lang))
  return parts.join('\n\n')
}

const OTHER_PERSON = [
  'teman', 'temanku', 'sahabat', 'pacar', 'adik', 'kakak', 'anak', 'ibu',
  'bapak', 'saudara', 'istri', 'suami', 'keluarga',
  'friend', 'my friend', 'partner', 'brother', 'sister', 'daughter', 'son',
  'mother', 'father', 'wife', 'husband', 'someone i',
]

/** True when they seem to be asking on behalf of another person. */
export function mentionsSomeoneElse(normalised) {
  return OTHER_PERSON.some((word) => normalised.includes(word))
}

// ── The machine ──────────────────────────────────────────────────────────

/**
 * Advances one step. Pure — no database, no network. Returns the messages to
 * send and the state to store, so this is trivial to test.
 *
 * @returns {{texts: string[], state: object, priority?: string, summary?: string}|null}
 */
export function advance(ctx) {
  const { normalised, lang, state } = ctx
  const data = state.data ?? {}
  const step = state.step

  // ── Safety net, before anything else ──────────────────────────────────
  // Applies at every step except when they are already escalated (we do not
  // repeat the emergency card at them over and over).
  if (step !== 'escalated' && mentionsCrisis(normalised)) {
    const answers = { ...data, danger: data.danger ?? 'unknown', crisisLanguage: true }
    return {
      texts: [say(copy.IN_DANGER, lang)],
      state: { flow: 'intake', step: 'escalated', data: answers },
      priority: PRIORITY.crisis,
      summary: summarise({ ...answers, priority: PRIORITY.crisis, trigger: 'crisis language' }),
    }
  }

  // ── Already handled ───────────────────────────────────────────────────
  if (step === 'escalated') return null

  if (step === 'queued') {
    // Only reassure once per new conversation, so we never talk over a
    // volunteer who has picked the thread up.
    if (!ctx.isNewConversation) return null
    return { texts: [say(copy.ALREADY_QUEUED, lang)], state }
  }

  // ── Start ─────────────────────────────────────────────────────────────
  if (!step) {
    return {
      texts: [say(copy.GREETING, lang)(ctx.firstName), say(copy.ASK_DANGER, lang)],
      state: { flow: 'intake', step: 'danger', data: {} },
    }
  }

  // ── Q1 immediate danger ───────────────────────────────────────────────
  if (step === 'danger') {
    const choice = parseChoice(normalised, 3, DANGER_WORDS)
    if (!choice) return retry(ctx, copy.ASK_DANGER)

    const danger = DANGER_ANSWERS[choice]
    const next = { ...data, danger }

    if (danger === 'yes') {
      const priority = PRIORITY.crisis
      return {
        texts: [say(copy.IN_DANGER, lang)],
        state: { flow: 'intake', step: 'escalated', data: next },
        priority,
        summary: summarise({ ...next, priority, trigger: 'answered yes to immediate danger' }),
      }
    }

    const texts = []
    if (danger === 'not sure') texts.push(say(copy.UNSURE_DANGER, lang))
    texts.push(say(copy.ASK_CITY, lang))
    return { texts, state: { flow: 'intake', step: 'city', data: next } }
  }

  // ── Q2 city or regency ────────────────────────────────────────────────
  if (step === 'city') {
    const city = ctx.text.trim().slice(0, 80)
    if (!city) return retry(ctx, copy.ASK_CITY)
    return {
      texts: [say(copy.ASK_LANGUAGE, lang)],
      state: { flow: 'intake', step: 'language', data: { ...data, city } },
    }
  }

  // ── Q3 preferred language ─────────────────────────────────────────────
  if (step === 'language') {
    const choice = parseChoice(normalised, 2, LANGUAGE_WORDS)
    if (!choice) return retry(ctx, copy.ASK_LANGUAGE)

    const preferred = choice === 2 ? 'en' : 'id'
    const next = { ...data, language: preferred }
    return {
      texts: [say(copy.ASK_NEED, preferred)],
      state: { flow: 'intake', step: 'need', data: next },
      language: preferred, // from here on, reply in what they chose
    }
  }

  // ── Q4 what support do you need ───────────────────────────────────────
  if (step === 'need') {
    const choice = parseChoice(normalised, 6)
    if (!choice) return retry(ctx, copy.ASK_NEED)

    const need = NEED_ANSWERS[choice]
    const answers = { ...data, need }
    const replyLang = data.language ?? lang
    const priority = assignPriority({ ...answers, crisisLanguage: false })

    const texts = []
    // Chose self-harm or suicidal thoughts, but said they are not in
    // immediate danger. Not an emergency — but they should still have the
    // 24-hour number in hand before they wait a day or two for us.
    if (need === 'self-harm or suicidal thoughts') {
      texts.push(say(copy.RESOURCE_SAFETY_PLAN, replyLang))
    }
    texts.push(
      waitingMessage({
        need,
        city: answers.city,
        lang: replyLang,
        mentionedSomeoneElse: mentionsSomeoneElse(ctx.historyText ?? ''),
      })
    )

    return {
      texts,
      state: { flow: 'intake', step: 'queued', data: answers },
      priority,
      summary: summarise({ ...answers, priority }),
    }
  }

  return null
}

function retry(ctx, question) {
  return {
    texts: [say(copy.DIDNT_UNDERSTAND, ctx.lang), say(question, ctx.lang)],
    state: ctx.state,
  }
}

/**
 * One line the volunteer can read at a glance. Goes into the Kunang thread,
 * never over WhatsApp.
 */
export function summarise(answers) {
  const bits = [`Priority: ${answers.priority}`]
  if (answers.danger) bits.push(`danger: ${answers.danger}`)
  if (answers.city) bits.push(`city: ${answers.city}${isInBali(answers.city) ? ' (Bali)' : ' (outside Bali)'}`)
  if (answers.language) bits.push(`language: ${answers.language}`)
  if (answers.need) bits.push(`need: ${answers.need}`)
  if (answers.trigger) bits.push(`triggered by: ${answers.trigger}`)
  return `[Intake] ${bits.join(' — ')}`
}
