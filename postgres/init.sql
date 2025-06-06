CREATE TABLE rate_limit_log (
    id SERIAL PRIMARY KEY,
    ip TEXT,
    count INTEGER,
    timestamp TIMESTAMPTZ DEFAULT NOW()
);
