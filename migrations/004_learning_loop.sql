CREATE TABLE IF NOT EXISTS learning_runs (
    id BIGSERIAL PRIMARY KEY,
    ts TIMESTAMPTZ NOT NULL DEFAULT now(),
    trigger TEXT NOT NULL,
    window_size INTEGER NOT NULL,
    mode TEXT,
    evaluation_id BIGINT REFERENCES evaluations(id) ON DELETE SET NULL,
    apply_result JSONB NOT NULL DEFAULT '{}'::jsonb,
    stage_before TEXT NOT NULL DEFAULT 'BABY',
    stage_after TEXT NOT NULL DEFAULT 'BABY',
    promoted BOOLEAN NOT NULL DEFAULT FALSE,
    status TEXT NOT NULL,
    error TEXT,
    metrics JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS learning_stage (
    id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
    current_stage TEXT NOT NULL DEFAULT 'BABY' CHECK (current_stage IN ('BABY', 'JUNIOR', 'PRO')),
    promoted_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO learning_stage (id, current_stage)
VALUES (TRUE, 'BABY')
ON CONFLICT (id) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_learning_runs_ts ON learning_runs (ts DESC);
CREATE INDEX IF NOT EXISTS idx_learning_runs_status ON learning_runs (status, ts DESC);
