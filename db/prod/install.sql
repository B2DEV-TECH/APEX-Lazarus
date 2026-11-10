-- APEX Lazarus: production install. Run in SQLcl as the LAZARUS owner.
-- Prompts for the application's parsing schema and the pull account.

whenever sqlerror exit failure rollback

@@01_tables.sql
@@02_lz_capture.pks
@@02_lz_capture.pkb
@@03_purge_job.sql
@@04_grants.sql

show errors package body lz_capture
