CREATE TABLE IF NOT EXISTS evaluations (
    id BIGSERIAL PRIMARY KEY,
    ts TIMESTAMPTZ NOT NULL DEFAULT now(),
    window_size INTEGER NOT NULL,
    summary TEXT NOT NULL DEFAULT '',
    findings JSONB NOT NULL DEFAULT '[]'::jsonb,
    param_suggestions JSONB NOT NULL DEFAULT '[]'::jsonb,
    pine_suggestions JSONB NOT NULL DEFAULT '[]'::jsonb,
    stage_eval JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw JSONB NOT NULL DEFAULT '{}'::jsonb,
    applied BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_evaluations_ts ON evaluations (ts DESC);
CREATE INDEX IF NOT EXISTS idx_evaluations_applied ON evaluations (applied, ts DESC);
