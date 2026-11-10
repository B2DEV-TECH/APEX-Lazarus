create or replace package body lz_intake
as
    -- Raw values are kept at most this long after capture.
    c_retention constant interval day to second := interval '14' day;

    function error_code (
        p_sqlcode in number
    ) return varchar2
    is
    begin
        if p_sqlcode = 100 then
            return 'ORA-01403';
        end if;

        return 'ORA-' || to_char(abs(p_sqlcode), 'fm00000');
    end error_code;

    -- Hash of app, page, component and normalized error code. 500
    -- occurrences of one bug produce one fingerprint.
    function fingerprint (
        p_app_id         in number,
        p_page_id        in number,
        p_component_type in varchar2,
        p_component_id   in number,
        p_error_code     in varchar2
    ) return varchar2
    is
        v_hash varchar2(64);
    begin
        select lower(rawtohex(standard_hash(
                   p_app_id || '|' || p_page_id || '|' || p_component_type || '|'
                   || p_component_id || '|' || p_error_code, 'SHA256')))
          into v_hash
          from dual;

        return v_hash;
    end fingerprint;

    procedure audit (
        p_incident_id in number,
        p_from_status in varchar2,
        p_to_status   in varchar2,
        p_note        in varchar2
    )
    is
    begin
        insert into lz_audit (incident_id, from_status, to_status, actor_type, actor, note)
        values (p_incident_id, p_from_status, p_to_status, 'SYSTEM', 'LZ_INTAKE', p_note);
    end audit;

    function pull return pls_integer
    is
        v_last_inbox_id number;
        v_pulled        pls_integer := 0;
        v_error_code    lz_incident.error_code%type;
        v_fingerprint   lz_incident.fingerprint%type;
        v_incident_id   lz_incident.incident_id%type;
        v_merged_id     lz_incident.incident_id%type;
    begin
        select nvl(max(source_inbox_id), 0)
          into v_last_inbox_id
          from lz_context;

        for r_inbox in (
            select i.inbox_id, i.captured_at, i.app_id, i.app_version, i.page_id,
                   i.component_type, i.component_id, i.component_name, i.ora_sqlcode,
                   i.error_statement, i.error_backtrace, i.app_user_hmac, i.session_state
              from lz_prod_inbox i
             where i.inbox_id > v_last_inbox_id
             order by i.inbox_id
        ) loop
            v_error_code  := error_code(r_inbox.ora_sqlcode);
            v_fingerprint := fingerprint(r_inbox.app_id, r_inbox.page_id, r_inbox.component_type,
                                         r_inbox.component_id, v_error_code);

            -- At most one incident per fingerprint is open (not MERGED).
            begin
                select incident_id
                  into v_incident_id
                  from lz_incident
                 where fingerprint = v_fingerprint
                   and status <> 'MERGED';

                update lz_incident
                   set occurrences = occurrences + 1,
                       last_seen   = greatest(last_seen, r_inbox.captured_at)
                 where incident_id = v_incident_id;
            exception
                when no_data_found then
                    -- A new incident; after a merge it is a recurrence.
                    select max(incident_id)
                      into v_merged_id
                      from lz_incident
                     where fingerprint = v_fingerprint
                       and status = 'MERGED';

                    insert into lz_incident (
                        fingerprint, app_id, app_version, page_id, component_type, component_id,
                        component_name, error_code, error_statement, error_backtrace,
                        first_seen, last_seen, recurrence_of
                    ) values (
                        v_fingerprint, r_inbox.app_id, r_inbox.app_version, r_inbox.page_id,
                        r_inbox.component_type, r_inbox.component_id, r_inbox.component_name,
                        v_error_code, r_inbox.error_statement, r_inbox.error_backtrace,
                        r_inbox.captured_at, r_inbox.captured_at, v_merged_id
                    )
                    returning incident_id into v_incident_id;

                    audit(v_incident_id, null, 'NEW', 'inbox ' || r_inbox.inbox_id
                          || case when v_merged_id is not null
                                  then ', recurrence of incident ' || v_merged_id end);
            end;

            insert into lz_context (
                incident_id, source_inbox_id, captured_at, app_user_hmac, session_state, purge_after
            ) values (
                v_incident_id, r_inbox.inbox_id, r_inbox.captured_at, r_inbox.app_user_hmac,
                r_inbox.session_state, r_inbox.captured_at + c_retention
            );

            v_pulled := v_pulled + 1;
        end loop;

        commit;
        return v_pulled;
    end pull;

    function purge_values return pls_integer
    is
        v_purged pls_integer;
    begin
        update lz_context c
           set c.session_state = null,
               c.purged_at     = systimestamp
         where c.purged_at is null
           and (   c.purge_after <= systimestamp
                or exists (select 1
                             from lz_incident i
                            where i.incident_id = c.incident_id
                              and i.status in ('REFUSED', 'REJECTED', 'FAILED', 'MERGED')));

        v_purged := sql%rowcount;
        commit;
        return v_purged;
    end purge_values;
end lz_intake;
/
