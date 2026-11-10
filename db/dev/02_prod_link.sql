-- APEX Lazarus: the development instance's only path into production.
-- The link connects as the pull account, which has SELECT on LZ_INBOX and
-- nothing else. Run as the LAZARUS owner on the development instance, with
-- verify off so the substituted password is not echoed:
--
--   &pull_password  the pull account's password
--   &prod_connect   production connect string, e.g. //host:1521/service
--   &prod_schema    the Lazarus schema in production (owner of LZ_INBOX)

create database link lz_prod
    connect to lz_pull identified by "&pull_password"
    using '&prod_connect';

-- LZ_INTAKE reads the inbox through this name only.
create or replace synonym lz_prod_inbox for &prod_schema..lz_inbox@lz_prod;
