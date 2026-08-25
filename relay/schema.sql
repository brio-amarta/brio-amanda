-- Kunang relay storage.
--
-- Inbound messages are keyed by phone number, because that is all Meta gives
-- us. The link to a Kunang client UUID is learned the first time the app sends
-- to that number (RELAY.md: "clientRef is the client's UUID inside Kunang;
-- store it so inbound messages can be matched back").

CREATE TABLE IF NOT EXISTS contacts (
  phone           TEXT PRIMARY KEY,   -- digits-only E.164, no '+'
  client_ref      TEXT,               -- Kunang client UUID, NULL until first send
  profile_name    TEXT,               -- WhatsApp display name, if Meta sends it
  language        TEXT,               -- 'id' | 'en', chosen at intake or detected
  last_inbound_at INTEGER,            -- epoch seconds; drives the 24-hour window
  -- Intake answers. Health-adjacent: these stay between the relay and the
  -- iPad and are never sent back over WhatsApp.
  priority        TEXT,               -- one of Kunang's five
  danger          TEXT,               -- 'yes' | 'no' | 'not sure'
  city            TEXT,
  need            TEXT,
  intake_done_at  INTEGER,
  updated_at      INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_contacts_priority ON contacts (priority);

CREATE TABLE IF NOT EXISTS messages (
  id          TEXT PRIMARY KEY,       -- Meta wamid, or generated for outbound
  phone       TEXT NOT NULL,
  client_ref  TEXT,                   -- denormalised at write time; may be NULL
  direction   TEXT NOT NULL,          -- 'in' | 'out'
  text        TEXT NOT NULL,
  timestamp   INTEGER NOT NULL,       -- epoch seconds
  auto        INTEGER NOT NULL DEFAULT 0,  -- 1 when written by a flow, not a human
  created_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_messages_client
  ON messages (client_ref, timestamp);

CREATE INDEX IF NOT EXISTS idx_messages_phone
  ON messages (phone, timestamp);

-- Where each conversation is inside a flow. Sam's flows land here later.
CREATE TABLE IF NOT EXISTS flow_state (
  phone      TEXT PRIMARY KEY,
  flow       TEXT,                    -- flow id, NULL when idle
  step       TEXT,                    -- step id within the flow
  data       TEXT,                    -- JSON blob the flow owns
  updated_at INTEGER NOT NULL
);

-- Webhook de-duplication. Meta retries; retries must not re-fire a flow.
CREATE TABLE IF NOT EXISTS seen_events (
  id         TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL
);
