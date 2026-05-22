CREATE TABLE IF NOT EXISTS decisions (
    id BIGSERIAL PRIMARY KEY,
    ts TIMESTAMPTZ NOT NULL,
    mode TEXT NOT NULL CHECK (mode IN ('live', 'paper')),
    regime TEXT NOT NULL,
    raw_regime TEXT NOT NULL,
    market_bias TEXT NOT NULL,
    regime_score DOUBLE PRECISION,
    should_rebalance BOOLEAN NOT NULL,
    risk_action TEXT NOT NULL,
    reasons JSONB NOT NULL DEFAULT '[]'::jsonb,
    next_state JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS market_snapshots (
    id BIGSERIAL PRIMARY KEY,
    decision_id BIGINT NOT NULL REFERENCES decisions(id) ON DELETE CASCADE,
    ts TIMESTAMPTZ NOT NULL,
    account JSONB NOT NULL DEFAULT '{}'::jsonb,
    positions JSONB NOT NULL DEFAULT '[]'::jsonb,
    candidates JSONB NOT NULL DEFAULT '[]'::jsonb,
    btc JSONB,
    market_internals JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS planned_orders (
    id BIGSERIAL PRIMARY KEY,
    decision_id BIGINT NOT NULL REFERENCES decisions(id) ON DELETE CASCADE,
    symbol TEXT NOT NULL,
    side TEXT NOT NULL,
    qty NUMERIC,
    type TEXT NOT NULL,
    meta JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS executions (
    id BIGSERIAL PRIMARY KEY,
    decision_id BIGINT NOT NULL REFERENCES decisions(id) ON DELETE CASCADE,
    symbol TEXT NOT NULL,
    side TEXT NOT NULL,
    qty NUMERIC,
    price NUMERIC,
    fee NUMERIC,
    ts TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS trade_results (
    id BIGSERIAL PRIMARY KEY,
    decision_id BIGINT NOT NULL REFERENCES decisions(id) ON DELETE CASCADE,
    symbol TEXT NOT NULL,
    realized_pnl NUMERIC,
    opened_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    status TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_decisions_ts ON decisions (ts DESC);
CREATE INDEX IF NOT EXISTS idx_decisions_mode_ts ON decisions (mode, ts DESC);
CREATE INDEX IF NOT EXISTS idx_market_snapshots_decision_id ON market_snapshots (decision_id);
CREATE INDEX IF NOT EXISTS idx_planned_orders_decision_id ON planned_orders (decision_id);
CREATE INDEX IF NOT EXISTS idx_executions_decision_id ON executions (decision_id);
CREATE INDEX IF NOT EXISTS idx_trade_results_decision_id ON trade_results (decision_id);
