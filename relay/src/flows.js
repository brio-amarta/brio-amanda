// Which flow handles an inbound message.
//
// Today there is one: the BISA intake in intake.js, which implements the
// flowchart — automated reply, automated intake, automated waiting message,
// and one of five priorities. Add flows above it to intercept specific
// intents before intake sees them.
//
// A flow is:
//
//   {
//     id: 'unique-name',
//     match: (ctx) => boolean,
//     run:   async (ctx) => Reply | null,
//   }
//
// Reply is `null` (say nothing) or:
//
//   {
//     texts:     string[],   // one WhatsApp message each, sent in order
//     state?:    { flow, step, data },
//     priority?: string,     // one of Kunang's five
//     summary?:  string,     // one line into the Kunang thread, never to WhatsApp
//     language?: 'id'|'en',  // pin the contact's language from here on
//   }
//
// Flows are tried in order; the first match wins.
//
// ── ctx ──────────────────────────────────────────────────────────────────
//   text        what they wrote, verbatim
//   normalised  lowercased, punctuation stripped — for matching
//   lang        'id' | 'en', their stored preference or detected
//   phone       digits-only E.164
//   firstName   WhatsApp profile first name, or null
//   contact     the contacts row
//   state       { flow, step, data } — where this conversation left off
//   isNewConversation  true when their last message was over 24h ago
//   history     last 10 messages, oldest first
//   historyText all of their own words so far, lowercased

import { advance } from './intake.js'

const intake = {
  id: 'intake',
  match: () => true,
  run: async (ctx) => advance(ctx),
}

/** Ordered. First match wins. Put narrower flows above `intake`. */
const FLOWS = [intake]

export async function runFlows(ctx) {
  for (const flow of FLOWS) {
    let matched = false
    try {
      matched = flow.match(ctx)
    } catch (error) {
      console.error(`flow ${flow.id} match threw`, error)
      continue
    }
    if (!matched) continue

    try {
      const reply = await flow.run(ctx)
      if (!reply) return null
      return { ...reply, flowId: flow.id }
    } catch (error) {
      // A broken flow must not swallow the message. It is already stored and
      // the volunteer will still see it in Kunang.
      console.error(`flow ${flow.id} run threw`, error)
      return null
    }
  }
  return null
}

/** Strips punctuation and case so `match` can compare against plain words. */
export function normalise(text) {
  return String(text ?? '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s']/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}
