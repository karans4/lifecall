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
  urgency         TEXT,                        -- playbook tier name (Hot/Warm/Cold)
  playbook_id     TEXT,
  created_at      TEXT NOT NULL
);

-- Billing: one row per account (Apple sub), synced from Stripe webhooks.
CREATE TABLE IF NOT EXISTS subscriptions (
  owner                TEXT PRIMARY KEY,        -- Apple user id (sub)
  stripe_customer_id   TEXT,
  stripe_subscription_id TEXT,
  tier                 TEXT,                    -- legacy (subscription); credits model below
  status               TEXT,
  current_period_end   TEXT,
  credits_cents        INTEGER NOT NULL DEFAULT 0,  -- prepaid balance; each call debits CALL_COST_CENTS
  updated_at           TEXT NOT NULL
);

-- Owner-authored playbooks (the in-app editor syncs JSON here). Each owner has
-- one active playbook that drives live calls + the post-call pipeline.
CREATE TABLE IF NOT EXISTS playbooks (
  id          TEXT NOT NULL,
  owner       TEXT NOT NULL,
  json        TEXT NOT NULL,                   -- the full Playbook as JSON
  active      INTEGER NOT NULL DEFAULT 0,
  updated_at  TEXT NOT NULL,
  PRIMARY KEY (owner, id)
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
