-- =============================================================================
-- 1_provision_postgres.sql
-- Run on:  SNOWFLAKE   (snow sql -f 1_provision_postgres.sql -c <your-conn>)
-- Time:    ~3-5 minutes for the instance to reach READY state.
-- =============================================================================
-- BEFORE RUNNING: replace the IP below with your laptop's public IP.
--   Get it with:   curl -s https://api.ipify.org
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- 1. Helper database to hold the network rule (any DB works; we keep it isolated).
CREATE DATABASE IF NOT EXISTS PG_LAKE_DEMO;
USE DATABASE PG_LAKE_DEMO;
USE SCHEMA   PUBLIC;

-- 2. Network rule with POSTGRES_INGRESS mode.
--    Snowflake Postgres instances IGNORE ALLOWED_IP_LIST on a network policy;
--    they only honor ALLOWED_NETWORK_RULE_LIST with rules in this mode.
CREATE OR REPLACE NETWORK RULE pg_demo_ingress
  TYPE       = IPV4
  MODE       = POSTGRES_INGRESS
  VALUE_LIST = ('REPLACE_WITH_YOUR_IP/32')        -- <<< edit me
  COMMENT    = 'Ingress rule for the pg_lake demo instance';

-- 3. Network policy that wraps the rule.
CREATE OR REPLACE NETWORK POLICY pg_demo_netpol
  ALLOWED_NETWORK_RULE_LIST = ('PG_LAKE_DEMO.PUBLIC.PG_DEMO_INGRESS')
  COMMENT = 'Network policy for DEMO_PG_INSTANCE';

-- 4. Postgres instance. STANDARD_M is the smallest pg_lake-eligible tier.
--    BURSTABLE tiers do NOT support pg_lake.
CREATE POSTGRES INSTANCE DEMO_PG_INSTANCE
  COMPUTE_FAMILY           = 'STANDARD_M'
  STORAGE_SIZE_GB          = 50
  AUTHENTICATION_AUTHORITY = POSTGRES
  POSTGRES_VERSION         = 17
  HIGH_AVAILABILITY        = FALSE
  NETWORK_POLICY           = 'PG_DEMO_NETPOL'
  COMMENT                  = 'pg_lake demo - ephemeral, drop with 5_teardown.sql';

-- The output of CREATE POSTGRES INSTANCE returns:
--   status, host, access_roles, default_database
-- The access_roles JSON contains the snowflake_admin user + password.
-- !!! COPY THE PASSWORD NOW. It cannot be retrieved later. !!!
--
-- Wait for state = READY (~3-5 min):
--   DESC POSTGRES INSTANCE DEMO_PG_INSTANCE;
