-- =============================================================================
-- 2_seed_postgres.sql
-- Run on:  POSTGRES (psql)
--   PGPASSWORD='<from step 1 output>' \
--     psql "host=<host-from-step-1> port=5432 dbname=postgres \
--           user=snowflake_admin sslmode=require" \
--     -f 2_seed_postgres.sql
-- Time:    ~10-30 seconds for the 1M-row seed on STANDARD_M.
-- =============================================================================

\timing on
SET client_min_messages TO WARNING;

-- pg_lake gives us CREATE TABLE ... USING iceberg in Postgres.
CREATE EXTENSION IF NOT EXISTS pg_lake CASCADE;

-- App schema for the OLTP store.
CREATE SCHEMA IF NOT EXISTS shop;
SET search_path TO shop, public;

-- =============================================================================
-- Customer dimension. Small, lives directly in Iceberg from day one (greenfield
-- pattern). Snowflake will read this through vended creds, no S3 needed.
-- =============================================================================
DROP TABLE IF EXISTS shop.customers;
CREATE TABLE shop.customers (
    customer_id   INT,
    name          TEXT,
    email         TEXT,
    signup_date   DATE,
    country       TEXT
) USING iceberg;

INSERT INTO shop.customers (customer_id, name, email, signup_date, country) VALUES
  (1,  'Ava Patel',    'ava@example.com',    '2025-01-12', 'USA'),
  (2,  'Liam Chen',    'liam@example.com',   '2025-02-03', 'Canada'),
  (3,  'Noah Garcia',  'noah@example.com',   '2025-02-19', 'USA'),
  (4,  'Olivia Kim',   'olivia@example.com', '2025-03-05', 'Singapore'),
  (5,  'Mia Schmidt',  'mia@example.com',    '2025-03-21', 'Germany'),
  (6,  'Ethan Brown',  'ethan@example.com',  '2025-04-02', 'USA'),
  (7,  'Sofia Rossi',  'sofia@example.com',  '2025-04-18', 'Italy'),
  (8,  'Lucas Silva',  'lucas@example.com',  '2025-05-04', 'Brazil'),
  (9,  'Emma Dubois',  'emma@example.com',   '2025-05-22', 'France'),
  (10, 'Aiden Tanaka', 'aiden@example.com',  '2025-06-09', 'Japan');

-- =============================================================================
-- Transactions HEAP table. This is the brownfield reality: a normal Postgres
-- table that your application already writes to. Pretend it has 100M rows;
-- we seed 1M for demo speed.
-- =============================================================================
DROP TABLE IF EXISTS shop.transactions;
CREATE TABLE shop.transactions (
    txn_id      BIGINT        NOT NULL,
    customer_id INT           NOT NULL,
    merchant    TEXT          NOT NULL,
    category    TEXT          NOT NULL,
    amount_usd  NUMERIC(10,2) NOT NULL,
    currency    TEXT          NOT NULL,
    country     TEXT          NOT NULL,
    txn_ts      TIMESTAMPTZ   NOT NULL,
    status      TEXT          NOT NULL
);

-- BRIN index on the watermark column. BRIN is ideal for append-mostly tables
-- with naturally ordered timestamps: tiny on disk and very fast for the range
-- scans that pg_incremental's time-interval pipeline performs each tick.
CREATE INDEX idx_transactions_txn_ts ON shop.transactions USING brin (txn_ts);

-- 1,000,000 rows spread across the last 365 days.
INSERT INTO shop.transactions (
    txn_id, customer_id, merchant, category, amount_usd,
    currency, country, txn_ts, status
)
SELECT
    g::BIGINT                                                                     AS txn_id,
    ((random()*9)::INT + 1)                                                       AS customer_id,
    (ARRAY['Amazon','Walmart','Target','Costco','Apple','Google','Netflix','Uber',
           'DoorDash','Spotify','Starbucks','Whole Foods','Best Buy','Home Depot',
           'Nike','Adidas','IKEA','Sephora','REI','Zara'])
        [1 + (random()*19)::INT]                                                  AS merchant,
    (ARRAY['Groceries','Electronics','Apparel','Travel','Entertainment',
           'Dining','Subscriptions','Home'])
        [1 + (random()*7)::INT]                                                   AS category,
    (random()*490 + 10)::NUMERIC(10,2)                                            AS amount_usd,
    (CASE WHEN random()<0.95 THEN 'USD'
          ELSE (ARRAY['EUR','GBP','JPY','CAD'])[1 + (random()*3)::INT] END)       AS currency,
    (ARRAY['USA','Canada','Singapore','Germany','Italy','Brazil','France','Japan'])
        [1 + (random()*7)::INT]                                                   AS country,
    now() - (random() * 365 * INTERVAL '1 day')                                   AS txn_ts,
    (CASE WHEN random()<0.97 THEN 'POSTED'
          WHEN random()<0.99 THEN 'PENDING'
          ELSE 'REVERSED' END)                                                    AS status
FROM generate_series(1, 1000000) AS g;

ANALYZE shop.transactions;

-- Receipts
SELECT
    COUNT(*)                                                       AS total_rows,
    MIN(txn_ts)::DATE                                              AS earliest,
    MAX(txn_ts)::DATE                                              AS latest,
    pg_size_pretty(pg_total_relation_size('shop.transactions'))    AS size_on_disk
FROM shop.transactions;
