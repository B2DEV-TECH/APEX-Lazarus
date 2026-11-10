create or replace package body lz_capture
as
    -- Longest text stored in a VARCHAR2(4000) column of LZ_INBOX.
    c_max_text constant pls_integer := 4000;

    -- User name as an HMAC-SHA256 with the key kept in LZ_CONFIG.
    -- A plain hash of a user name can be reversed by trying known names;
    -- without the key, the HMAC cannot.
    function user_hmac (
        p_user in varchar2,
        p_key  in raw
    ) return varchar2
    is
    begin
        if p_user is null then
            return null;
        end if;

        return rawtohex(
                   sys.dbms_crypto.mac(
                       src => utl_i18n.string_to_raw(p_user, 'AL32UTF8'),
                       typ => sys.dbms_crypto.hmac_sh256,
                       key => p_key));
    end user_hmac;

    -- Page items of the failing page with their current session-state values,
    -- as a JSON object. Values are raw on purpose (see LZ_INBOX).
    -- To confirm in week 1: the APEX dictionary views return the running
    -- application's items when queried from this definer-rights package.
    function session_state_json (
        p_app_id  in number,
        p_page_id in number
    ) return clob
    is
        v_state json_object_t := json_object_t();
    begin
        for r_item in (
            select i.item_name
              from apex_application_page_items i
             where i.application_id = p_app_id
               and i.page_id        = p_page_id
        ) loop
            v_state.put(r_item.item_name,
                        apex_util.get_session_state(r_item.item_name));
        end loop;

        return v_state.to_clob;
    end session_state_json;

    -- The application's Version attribute, used to match the incident with
    -- the APEXlang files in Git.
    function app_version (
        p_app_id in number
    ) return varchar2
    is
        v_version apex_applications.version%type;
    begin
        select a.version
          into v_version
          from apex_applications a
         where a.application_id = p_app_id;

        return v_version;
    exception
        when no_data_found then
            -- Not fatal: the incident is still recorded, and LZ_GUARD
            -- refuses it later because its version cannot be matched.
            return null;
    end app_version;

    procedure log_incident (
        p_error in apex_error.t_error
    )
    is
        pragma autonomous_transaction;

        v_enabled lz_config.capture_enabled%type;
        v_key     lz_config.user_hmac_key%type;
        v_app_id  number := apex_application.g_flow_id;
        v_page_id number := apex_application.g_flow_step_id;
    begin
        -- Only database errors raised by application components are
        -- candidates. APEX internal errors are out of scope.
        if p_error.ora_sqlcode is null or p_error.is_internal_error then
            return;
        end if;

        select c.capture_enabled, c.user_hmac_key
          into v_enabled, v_key
          from lz_config c
         where c.config_id = 1;

        -- Capture switch: operators turn capture off with one update.
        if v_enabled <> 'Y' then
            return;
        end if;

        insert into lz_inbox (
            app_id,
            app_version,
            page_id,
            component_type,
            component_id,
            component_name,
            ora_sqlcode,
            ora_sqlerrm,
            error_statement,
            error_backtrace,
            apex_error_code,
            app_user_hmac,
            session_state
        ) values (
            v_app_id,
            app_version(v_app_id),
            v_page_id,
            p_error.component.type,
            p_error.component.id,
            substr(p_error.component.name, 1, c_max_text),
            p_error.ora_sqlcode,
            substr(p_error.ora_sqlerrm, 1, c_max_text),
            p_error.error_statement,
            p_error.error_backtrace,
            p_error.apex_error_code,
            user_hmac(v('APP_USER'), v_key),
            session_state_json(v_app_id, v_page_id)
        );

        commit;
    exception
        when others then
            -- Capture must never change what the user sees, so this error is
            -- not raised again. It is written to the APEX debug log instead.
            rollback;
            apex_debug.error('APEX Lazarus: capture failed: %s', sqlerrm);
    end log_incident;

    function handle (
        p_error in apex_error.t_error
    ) return apex_error.t_error_result
    is
        v_result apex_error.t_error_result;
    begin
        v_result := apex_error.init_error_result(p_error => p_error);

        log_incident(p_error);  -- never raises

        -- The user sees exactly what they would see without Lazarus.
        return v_result;
    end handle;
end lz_capture;
/
