CREATE TABLE IF NOT EXISTS bot_params (
    id BIGSERIAL PRIMARY KEY,
    version INTEGER NOT NULL UNIQUE,
    params JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    active BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_bot_params_one_active
    ON bot_params (active)
    WHERE active;

CREATE INDEX IF NOT EXISTS idx_bot_params_created_at ON bot_params (created_at DESC);
