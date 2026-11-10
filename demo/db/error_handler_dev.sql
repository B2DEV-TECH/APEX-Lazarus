-- APEX Lazarus demo: error handling function in the development parsing schema.
--
-- Same name as in production (see error_handler_prd.sql), but nothing is
-- captured: errors raised while Lazarus reproduces or re-runs a page on the
-- development instance must never reach the production inbox.

create or replace package lz_capture
    authid definer
as
    function handle (
        p_error in apex_error.t_error
    ) return apex_error.t_error_result;
end lz_capture;
/

create or replace package body lz_capture
as
    function handle (
        p_error in apex_error.t_error
    ) return apex_error.t_error_result
    is
    begin
        -- The user sees exactly what APEX would show without a handler.
        return apex_error.init_error_result(p_error => p_error);
    end handle;
end lz_capture;
/
