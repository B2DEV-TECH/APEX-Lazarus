create or replace package lz_capture
    authid definer
as
    -- APEX Lazarus capture: the only Lazarus code that runs in production.
    -- It records database errors raised by application components in
    -- LZ_INBOX and never changes what the user sees.

    -- Error handling function for an application that has none.
    -- Shared Components > Application Definition > Error Handling:
    --   lazarus.lz_capture.handle
    function handle (
        p_error in apex_error.t_error
    ) return apex_error.t_error_result;

    -- For an application that already has an error handling function:
    -- add one call to this procedure inside it. It records the error,
    -- never raises, and returns nothing to the handler.
    procedure log_incident (
        p_error in apex_error.t_error
    );
end lz_capture;
/
