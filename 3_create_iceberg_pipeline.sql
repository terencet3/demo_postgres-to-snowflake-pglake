-- =============================================================================
-- 3_create_iceberg_pipeline.sql
-- Run on:  POSTGRES (psql)
-- Time:    < 30 seconds. The "ONE pipeline = backfill + ongoing sync" headline.
-- =============================================================================

\timing on
SET client_min_messages TO WARNING;
SET search_path TO shop, public;

-- pg_cron schedules SQL inside Postgres; pg_incremental builds exactly-once
-- pipelines on top of pg_cron with built-in fencing for in-flight writes.
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_incremental;

-- =============================================================================
-- Iceberg "shadow" of the heap table. Same columns, USING iceberg.
-- Snowflake-managed storage. No S3, no IAM, no external volume.
-- =============================================================================
DROP TABLE IF EXISTS shop.transactions_iceberg;
CREATE TABLE shop.transactions_iceberg (
    txn_id      BIGINT,
    customer_id INT,
    merchant    TEXT,
    category    TEXT,
    amount_usd  NUMERIC(10,2),
    currency    TEXT,
    country     TEXT,
    txn_ts      TIMESTAMPTZ,
    status      TEXT
) USING iceberg;

-- =============================================================================
-- ONE pipeline declaration that does BOTH:
--   1. backfill the entire history (start_time -> now())
--   2. keep syncing new rows on every tick (1-minute cadence)
--
-- Key knobs:
--   time_interval     - window size. Smaller = fresher; larger = fewer files.
--   source_table_name - the EXACTLY-ONCE guard. Pipeline waits for in-flight
--                       transactions before closing each window.
--   start_time        - earliest watermark in the source. Triggers the backfill.
-- =============================================================================
SELECT incremental.create_time_interval_pipeline(
    pipeline_name      := 'transactions_to_iceberg',
    time_interval      := '1 minute',
    source_table_name  := 'shop.transactions',
    start_time         := (SELECT MIN(txn_ts) FROM shop.transactions),
    command            := $$
        INSERT INTO shop.transactions_iceberg
            (txn_id, customer_id, merchant, category, amount_usd,
             currency, country, txn_ts, status)
        SELECT  txn_id, customer_id, merchant, category, amount_usd,
                currency, country, txn_ts, status
        FROM    shop.transactions
        WHERE   txn_ts >= $1 AND txn_ts < $2
    $$
);

-- =============================================================================
-- Receipts: pipeline definition + heap vs iceberg row counts.
-- The first call backfills the full history immediately (all 1M rows in one
-- shot); after that the cron job ticks every minute.
-- =============================================================================
SELECT p.pipeline_name, p.source_relation, t.time_interval, t.last_processed_time
FROM   incremental.pipelines               p
JOIN   incremental.time_interval_pipelines t USING (pipeline_name)
WHERE  p.pipeline_name = 'transactions_to_iceberg';

SELECT
    (SELECT COUNT(*) FROM shop.transactions)         AS heap_rows,
    (SELECT COUNT(*) FROM shop.transactions_iceberg) AS iceberg_rows;
