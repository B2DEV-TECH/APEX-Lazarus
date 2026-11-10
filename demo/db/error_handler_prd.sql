-- APEX Lazarus demo: error handling function in the production parsing schema.
--
-- The application's error handling function is LZ_CAPTURE.HANDLE, without a
-- schema prefix, so the same APEXlang files work in both environments. Here
-- the name resolves to the Lazarus capture package; in development it
-- resolves to a local package that captures nothing (error_handler_dev.sql).
--
-- Requires: grant execute on lazarus_prd.lz_capture to lz_demo_prd.

create or replace synonym lz_capture for lazarus_prd.lz_capture;
