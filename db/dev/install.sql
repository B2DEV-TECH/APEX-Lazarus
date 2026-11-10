-- APEX Lazarus: development install. Run in SQLcl as the LAZARUS owner on
-- the development instance, with pull_password, prod_connect and prod_schema
-- defined and verify off (see 02_prod_link.sql). LZ_GUARD, LZ_REPRO, LZ_AGENT and
-- LZ_REVIEW are added here as they are built (see docs/SPEC.md, four-week plan).

whenever sqlerror exit failure rollback

@@01_tables.sql
@@02_prod_link.sql
@@03_lz_intake.pks
@@03_lz_intake.pkb

show errors package body lz_intake
