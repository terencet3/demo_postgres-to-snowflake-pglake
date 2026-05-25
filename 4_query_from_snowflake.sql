-- =============================================================================
-- 4_query_from_snowflake.sql
-- Run on:  SNOWFLAKE   (snow sql -f 4_query_from_snowflake.sql -c <your-conn>)
-- Time:    < 1 minute total. THE HEADLINE: two statements replace a CDC project.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- =============================================================================
-- Statement 1 of 2: catalog integration to the Postgres-managed Iceberg catalog.
-- VENDED_CREDENTIALS = Snowflake fetches the storage creds for you.
-- No S3, no IAM, no trust policy, no external volume.
-- =============================================================================
CREATE OR REPLACE CATALOG INTEGRATION pg_shop_catalog
  CATALOG_SOURCE = SNOWFLAKE_POSTGRES
  TABLE_FORMAT   = ICEBERG
  REST_CONFIG = (
    POSTGRES_INSTANCE      = 'DEMO_PG_INSTANCE'
    CATALOG_NAME           = 'postgres'
    ACCESS_DELEGATION_MODE = VENDED_CREDENTIALS
  )
  REFRESH_INTERVAL_SECONDS = 60
  ENABLED = TRUE;

-- =============================================================================
-- Statement 2 of 2: catalog-linked database. Snowflake AUTO-DISCOVERS every
-- Iceberg table in every Postgres schema. New tables show up without per-table
-- DDL. This is the part that replaces a multi-week CDC project.
-- =============================================================================
CREATE OR REPLACE DATABASE PG_SHOP_LIVE
  LINKED_CATALOG = (
    CATALOG = pg_shop_catalog,
    ALLOWED_WRITE_OPERATIONS = NONE
  );

USE DATABASE PG_SHOP_LIVE;
USE SCHEMA "shop";

-- Confirm auto-discovery (no DDL was added on this side for the tables).
SHOW ICEBERG TABLES IN SCHEMA PG_SHOP_LIVE."shop";

-- Force a refresh so we see the latest backfill snapshot. Auto-refresh polls
-- every REFRESH_INTERVAL_SECONDS on the catalog integration.
ALTER ICEBERG TABLE "transactions_iceberg" REFRESH;
ALTER ICEBERG TABLE "customers"            REFRESH;

-- NOTE: PG-discovered Iceberg tables preserve their lowercase identifiers.
-- From Snowflake we double-quote them: "shop"."orders", "customer_id", etc.

-- =============================================================================
-- Analytics on PG-sourced data, no ETL involved.
-- =============================================================================

-- 1. Row count from Snowflake (should match the heap row count from step 3).
SELECT COUNT(*) AS rows_in_snowflake FROM "transactions_iceberg";

-- 2. Daily volume on the brownfield data.
SELECT
    "txn_ts"::DATE                       AS txn_date,
    COUNT(*)                             AS txns,
    SUM("amount_usd")::NUMBER(14,2)      AS gross_usd
FROM "transactions_iceberg"
GROUP BY 1
ORDER BY txn_date DESC
LIMIT 14;

-- 3. Top merchants by gross volume.
SELECT
    "merchant",
    COUNT(*)                             AS txns,
    SUM("amount_usd")::NUMBER(14,2)      AS gross_usd
FROM "transactions_iceberg"
GROUP BY 1
ORDER BY gross_usd DESC
LIMIT 10;

-- 4. Customer LTV joining two PG-sourced Iceberg tables natively in Snowflake.
SELECT
    c."country",
    c."name"                          AS customer_name,
    COUNT(t."txn_id")                 AS num_txns,
    SUM(t."amount_usd")::NUMBER(14,2) AS lifetime_txn_usd
FROM "customers" c
JOIN "transactions_iceberg" t ON c."customer_id" = t."customer_id"
WHERE t."status" = 'POSTED'
GROUP BY 1, 2
ORDER BY lifetime_txn_usd DESC;

-- =============================================================================
-- THE WOW MOMENT (optional, run only after seeing the analytics above)
-- Back in psql, run:
--    INSERT INTO shop.transactions VALUES
--      (9000001, 1, 'Apple', 'Electronics', 1999.00, 'USD', 'USA', now(), 'POSTED'),
--      (9000002, 4, 'Costco','Groceries',    899.00, 'USD', 'USA', now(), 'POSTED'),
--      (9000003, 7, 'IKEA',  'Home',         499.00, 'USD', 'USA', now(), 'POSTED');
--
-- Then come back here and re-run:
--    ALTER ICEBERG TABLE "transactions_iceberg" REFRESH;
--    SELECT * FROM "transactions_iceberg" ORDER BY "txn_ts" DESC LIMIT 5;
-- =============================================================================
