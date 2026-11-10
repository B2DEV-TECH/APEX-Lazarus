-- APEX Lazarus: grants in production. Run as the LAZARUS owner.
--
--   &parsing_schema  the application's parsing schema
--   &pull_user       the account the development instance uses to pull the inbox
--
-- The pull account gets SELECT on LZ_INBOX only: no access to LZ_CONFIG
-- (which holds the HMAC key) and nothing else in production.

grant execute on lz_capture to &parsing_schema;
grant select  on lz_inbox   to &pull_user;
