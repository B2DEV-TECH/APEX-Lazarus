create or replace package lz_intake
    authid definer
as
    -- APEX Lazarus intake, on the development instance. Pulls new rows from
    -- the production inbox (synonym LZ_PROD_INBOX, through the LZ_PROD link)
    -- and folds them into incidents: one incident per fingerprint, one
    -- context per occurrence.

    -- Pulls every inbox row newer than the last one pulled and commits.
    -- Returns the number of rows pulled.
    function pull return pls_integer;

    -- Clears the raw session-state values of contexts whose retention ended
    -- or whose incident is closed, and commits. The rows are kept with
    -- PURGED_AT set. Returns the number of contexts purged.
    function purge_values return pls_integer;

    -- Normalized error code. ORA_SQLCODE carries the SQLCODE, and
    -- NO_DATA_FOUND arrives as +100, so 100 becomes ORA-01403.
    function error_code (
        p_sqlcode in number
    ) return varchar2;
end lz_intake;
/
