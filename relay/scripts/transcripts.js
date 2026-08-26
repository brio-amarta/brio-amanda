// Regenerates TRANSCRIPTS.md by actually running the intake state machine.
//
// The file used to be written by hand, which meant it drifted: it was still
// quoting the LISA helpline months after that number came out of config.js.
// Now every quoted line is whatever `advance()` really returns, so the
// transcripts cannot claim something the bot doesn't say.
//
//     npm run transcripts
//
// Run it after editing src/config.js and commit the result.

import { writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

import { advance } from '../src/intake.js'
import { normalise } from '../src/flows.js'
import { detectLanguage } from '../src/lang.js'

const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'TRANSCRIPTS.md')

/**
 * Plays one conversation through the real state machine.
 * @param {{title: string, note: string, firstName: string|null, turns: string[]}} scenario
 */
function play({ title, note, firstName, turns }) {
  const lines = [`## ${title}`, '', note, '']

  let state = { flow: null, step: null, data: {} }
  let pinned = null
  let summary = null
  let priority = null

  for (const text of turns) {
    lines.push(`**Them:** ${text}`, '')

    const reply = advance({
      text,
      normalised: normalise(text),
      lang: pinned ?? detectLanguage(text),
      state,
      firstName,
      isNewConversation: false,
      historyText: turns.join(' ').toLowerCase(),
    })

    if (!reply) {
      lines.push('*(no automated reply — a volunteer owns the thread)*', '')
      continue
    }

    for (const out of reply.texts) {
      lines.push('**BISA:**', '')
      lines.push(...out.split('\n').map((l) => (l ? `> ${l}` : '>')))
      lines.push('')
    }

    if (reply.language) pinned = reply.language
    if (reply.state) state = reply.state
    if (reply.priority) priority = reply.priority
    if (reply.summary) summary = reply.summary
  }

  if (summary) {
    lines.push(
      `**Into Kunang** (never sent over WhatsApp):`,
      '',
      '```',
      summary,
      '```',
      ''
    )
  }
  if (priority) lines.push(`**Priority:** ${priority}`, '')

  return lines.join('\n')
}

const SCENARIOS = [
  {
    title: 'Path A — no immediate danger, anxiety, in Bali',
    note: 'The ordinary case. Language first, then everything in Indonesian.',
    firstName: 'Kadek',
    turns: ['Halo', '1', '2', 'Denpasar', '2'],
  },
  {
    title: 'Path B — English speaker, referral, outside Bali',
    note: 'Choosing English at Q1 switches every later message, including the out-of-Bali referral.',
    firstName: 'Sarah',
    turns: ['Hello', '2', '2', 'Surabaya', '5'],
  },
  {
    title: 'Path C — immediate danger',
    note: 'Answering yes stops the intake. No city question, no need question, no queue form.',
    firstName: 'Wayan',
    turns: ['Halo', '1', '1'],
  },
  {
    title: 'Path D — crisis language before the language question',
    note:
      'The safety net runs before every step, including Q1. Someone opening with distress is ' +
      'never asked to pick from a menu first — the language is detected from their words instead.',
    firstName: null,
    turns: ['aku ingin mati saja'],
  },
  {
    title: 'Path E — self-harm need, but not in immediate danger',
    note: 'Not an emergency, so intake continues — but the safety-plan starter goes out anyway.',
    firstName: 'Putu',
    turns: ['Halo', '1', '2', 'Ubud', '4'],
  },
  {
    title: 'Path F — an answer we could not read',
    note: 'Anything unparseable re-asks rather than guessing. At Q1 the re-ask is bilingual too.',
    firstName: null,
    turns: ['Halo', 'apa ya', '1', 'hmm gimana'],
  },
]

const header = `# Automated reply — sample transcripts

**Generated file — do not edit by hand.** Run \`npm run transcripts\` after
changing \`src/config.js\`; every line below is produced by running the real
state machine in \`src/intake.js\`, so it cannot drift from what actually gets
sent.

The language question comes first and on its own. Every message after it is in
whichever language the person chose.

`

writeFileSync(OUT, header + SCENARIOS.map(play).join('\n---\n\n') + '\n')
console.log(`wrote ${OUT}`)
