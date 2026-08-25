// Thin wrapper over D1. Kept separate so flows never write SQL.

const now = () => Math.floor(Date.now() / 1000)

export async function getContact(db, phone) {
  return db.prepare('SELECT * FROM contacts WHERE phone = ?').bind(phone).first()
}

export async function upsertContact(db, phone, fields = {}) {
  const existing = await getContact(db, phone)
  const merged = {
    client_ref: fields.clientRef ?? existing?.client_ref ?? null,
    profile_name: fields.profileName ?? existing?.profile_name ?? null,
    language: fields.language ?? existing?.language ?? null,
    last_inbound_at: fields.lastInboundAt ?? existing?.last_inbound_at ?? null,
    priority: fields.priority ?? existing?.priority ?? null,
    danger: fields.danger ?? existing?.danger ?? null,
    city: fields.city ?? existing?.city ?? null,
    need: fields.need ?? existing?.need ?? null,
    intake_done_at: fields.intakeDoneAt ?? existing?.intake_done_at ?? null,
  }

  await db
    .prepare(
      `INSERT INTO contacts
         (phone, client_ref, profile_name, language, last_inbound_at,
          priority, danger, city, need, intake_done_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(phone) DO UPDATE SET
         client_ref = excluded.client_ref,
         profile_name = excluded.profile_name,
         language = excluded.language,
         last_inbound_at = excluded.last_inbound_at,
         priority = excluded.priority,
         danger = excluded.danger,
         city = excluded.city,
         need = excluded.need,
         intake_done_at = excluded.intake_done_at,
         updated_at = excluded.updated_at`
    )
    .bind(
      phone,
      merged.client_ref,
      merged.profile_name,
      merged.language,
      merged.last_inbound_at,
      merged.priority,
      merged.danger,
      merged.city,
      merged.need,
      merged.intake_done_at,
      now()
    )
    .run()

  return { phone, ...merged }
}

/** Rank order matching Priority.rank in the app, so /queue sorts the same way. */
const PRIORITY_RANK = {
  Crisis: 0,
  'High Priority': 1,
  Moderate: 2,
  'Referral Required': 3,
  Others: 4,
}

/** Everyone who has finished intake, most urgent first. */
export async function queue(db) {
  const { results } = await db
    .prepare(
      `SELECT * FROM contacts WHERE priority IS NOT NULL ORDER BY intake_done_at DESC LIMIT 200`
    )
    .all()

  return (results ?? []).sort((a, b) => {
    const rank = (PRIORITY_RANK[a.priority] ?? 9) - (PRIORITY_RANK[b.priority] ?? 9)
    return rank !== 0 ? rank : (a.intake_done_at ?? 0) - (b.intake_done_at ?? 0)
  })
}

export async function recordMessage(db, { id, phone, clientRef, direction, text, timestamp, auto = false }) {
  await db
    .prepare(
      `INSERT OR IGNORE INTO messages (id, phone, client_ref, direction, text, timestamp, auto, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
    )
    .bind(id, phone, clientRef ?? null, direction, text, timestamp ?? now(), auto ? 1 : 0, now())
    .run()
}

/**
 * Backfills client_ref on messages we stored before the app told us who this
 * number belongs to. Without this, everything received before the first
 * outbound send would be invisible to Kunang forever.
 */
export async function linkClientRef(db, phone, clientRef) {
  await db
    .prepare('UPDATE messages SET client_ref = ? WHERE phone = ? AND client_ref IS NULL')
    .bind(clientRef, phone)
    .run()
}

export async function inboundSince(db, clientRef, sinceEpoch) {
  const { results } = await db
    .prepare(
      `SELECT text, timestamp FROM messages
       WHERE client_ref = ? AND direction = 'in' AND timestamp > ?
       ORDER BY timestamp ASC
       LIMIT 200`
    )
    .bind(clientRef, sinceEpoch)
    .all()
  return results ?? []
}

/** Everything, known client or not. Used by the /inbox debug view. */
export async function recentMessages(db, limit = 100) {
  const { results } = await db
    .prepare(
      `SELECT m.*, c.profile_name FROM messages m
       LEFT JOIN contacts c ON c.phone = m.phone
       ORDER BY m.timestamp DESC LIMIT ?`
    )
    .bind(limit)
    .all()
  return results ?? []
}

export async function getFlowState(db, phone) {
  const row = await db.prepare('SELECT * FROM flow_state WHERE phone = ?').bind(phone).first()
  if (!row) return { flow: null, step: null, data: {} }
  let data = {}
  try {
    data = row.data ? JSON.parse(row.data) : {}
  } catch {
    data = {}
  }
  return { flow: row.flow, step: row.step, data }
}

export async function setFlowState(db, phone, state) {
  await db
    .prepare(
      `INSERT INTO flow_state (phone, flow, step, data, updated_at)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(phone) DO UPDATE SET
         flow = excluded.flow, step = excluded.step,
         data = excluded.data, updated_at = excluded.updated_at`
    )
    .bind(phone, state.flow ?? null, state.step ?? null, JSON.stringify(state.data ?? {}), now())
    .run()
}

/** True the first time this event id is seen. Meta retries webhooks. */
export async function claimEvent(db, id) {
  const result = await db
    .prepare('INSERT OR IGNORE INTO seen_events (id, created_at) VALUES (?, ?)')
    .bind(id, now())
    .run()
  return (result.meta?.changes ?? 0) > 0
}
