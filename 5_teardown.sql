-- =============================================================================
-- 5_teardown.sql
-- Run on:  SNOWFLAKE   (snow sql -f 5_teardown.sql -c <your-conn>)
--
-- The Snowflake DDL below drops everything Snowflake-side AND drops the
-- Postgres instance. The Postgres-internal cleanup is optional — dropping the
-- instance removes everything inside it — but we include it as a comment for
-- anyone keeping the instance and just resetting the demo objects.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Optional: Postgres-internal cleanup (run via psql if you want to keep
-- DEMO_PG_INSTANCE alive but reset the demo objects).
--
--   SELECT incremental.drop_pipeline('transactions_to_iceberg');
--   DROP TABLE IF EXISTS shop.transactions_iceberg;
--   DROP TABLE IF EXISTS shop.transactions;
--   DROP TABLE IF EXISTS shop.customers;
--   DROP EXTENSION IF EXISTS pg_incremental;
--   DROP EXTENSION IF EXISTS pg_cron;
--   DROP EXTENSION IF EXISTS pg_lake CASCADE;
-- ---------------------------------------------------------------------------

USE ROLE ACCOUNTADMIN;

-- Snowflake side
DROP DATABASE            IF EXISTS PG_SHOP_LIVE;
DROP CATALOG INTEGRATION IF EXISTS pg_shop_catalog;

-- Postgres instance (this is the billable compute — drop it to stop charges)
DROP POSTGRES INSTANCE   IF EXISTS DEMO_PG_INSTANCE;

-- Networking + helper DB
DROP NETWORK POLICY      IF EXISTS pg_demo_netpol;
DROP NETWORK RULE        IF EXISTS PG_LAKE_DEMO.PUBLIC.pg_demo_ingress;
DROP DATABASE            IF EXISTS PG_LAKE_DEMO;
