-- APEX Lazarus: development install. Run in SQLcl as the LAZARUS owner on
-- the development instance. LZ_INTAKE, LZ_GUARD, LZ_REPRO, LZ_AGENT and
-- LZ_REVIEW are added here as they are built (see docs/SPEC.md, four-week plan).

whenever sqlerror exit failure rollback

@@01_tables.sql
