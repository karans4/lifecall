-- LifeCall D1 schema. Leads are owner-scoped by the Apple user id (sub).
CREATE TABLE IF NOT EXISTS leads (
  id              TEXT PRIMARY KEY,            -- uuid
  owner           TEXT NOT NULL,               -- Apple user id of the agent who owns this lead
  name            TEXT,
  age             INTEGER,
  coverage_type   TEXT,
  coverage_amount TEXT,
  monthly_budget  TEXT,
  outcome         TEXT,
  email           TEXT,
  phone           TEXT,
  callback_at     TEXT,                        -- ISO 8601
  callback_status TEXT DEFAULT 'pending',
  transcript      TEXT,
  summary         TEXT,
  fact_find       TEXT,                        -- JSON blob
  created_at      TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_leads_owner       ON leads(owner, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_leads_callback    ON leads(owner, callback_at);

-- Consent ledger for outbound dialing (TCPA). A number must be present and
-- consented before it can be dialed. No self-expanding history rule.
CREATE TABLE IF NOT EXISTS consents (
  owner       TEXT NOT NULL,
  phone       TEXT NOT NULL,                   -- E.164
  granted_at  TEXT NOT NULL,
  source      TEXT,                            -- how consent was captured
  PRIMARY KEY (owner, phone)
);
