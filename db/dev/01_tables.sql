-- APEX Lazarus: development tables, owned by the LAZARUS schema on the
-- development instance. They hold the whole lifecycle of an incident after
-- LZ_INTAKE pulls it from the production inbox.

-- One row per distinct error. The fingerprint is a hash of app, page,
-- component ID and normalized error code. Only one incident per fingerprint
-- can be open; after MERGED, a new occurrence opens a new incident that
-- points to the old one through RECURRENCE_OF.
create table lz_incident (
    incident_id      number generated always as identity,
    fingerprint      varchar2(64)    not null,
    app_id           number          not null,
    app_version      varchar2(255),
    page_id          number,
    component_type   varchar2(255),
    component_id     number,
    component_name   varchar2(4000),
    error_code       varchar2(9)     not null,  -- normalized, e.g. ORA-01403
    error_statement  clob,
    error_backtrace  clob,
    occurrences      number          default 1 not null,
    first_seen       timestamp with time zone not null,
    last_seen        timestamp with time zone not null,
    status           varchar2(20)    default 'NEW' not null,
    recurrence_of    number,
    constraint lz_incident_pk primary key (incident_id),
    constraint lz_incident_status_ck check (status in (
        'NEW', 'REFUSED', 'REPRODUCED', 'PATCHED', 'VALIDATED',
        'IN_REVIEW', 'APPROVED', 'REJECTED', 'FAILED', 'MERGED')),
    constraint lz_incident_recurrence_fk
        foreign key (recurrence_of) references lz_incident (incident_id)
);

create unique index lz_incident_fingerprint_uk on lz_incident (
    case when status <> 'MERGED' then fingerprint end
);

-- One row per occurrence pulled from the inbox. SESSION_STATE holds raw
-- values for reproduction; the purge clears it when the incident closes,
-- and in any case after 14 days, and keeps the row with PURGED_AT set.
create table lz_context (
    context_id       number generated always as identity,
    incident_id      number          not null,
    source_inbox_id  number          not null,
    captured_at      timestamp with time zone not null,
    app_user_hmac    varchar2(64),
    session_state    clob,
    purge_after      timestamp with time zone not null,
    purged_at        timestamp with time zone,
    constraint lz_context_pk         primary key (context_id),
    constraint lz_context_incident_fk
        foreign key (incident_id) references lz_incident (incident_id),
    constraint lz_context_inbox_uk   unique (source_inbox_id),
    constraint lz_context_state_json check (session_state is json)
);

create index lz_context_incident_ix on lz_context (incident_id);

-- One row per repair attempt; at most two per incident. A refusal by
-- LZ_GUARD before the agent runs is recorded as attempt 1 with
-- GUARD_VERDICT = 'REFUSED'.
create table lz_attempt (
    attempt_id       number generated always as identity,
    incident_id      number          not null,
    attempt_no       number(1)       not null,
    guard_verdict    varchar2(10),
    refusal_reason   varchar2(4000),
    repro_result     varchar2(20),
    model            varchar2(255),
    temperature      number,
    tokens_in        number,
    tokens_out       number,
    started_at       timestamp with time zone default systimestamp not null,
    finished_at      timestamp with time zone,
    constraint lz_attempt_pk          primary key (attempt_id),
    constraint lz_attempt_incident_fk
        foreign key (incident_id) references lz_incident (incident_id),
    constraint lz_attempt_no_uk       unique (incident_id, attempt_no),
    constraint lz_attempt_no_ck       check (attempt_no between 1 and 2),
    constraint lz_attempt_verdict_ck  check (guard_verdict in ('IN_SCOPE', 'REFUSED')),
    constraint lz_attempt_repro_ck    check (repro_result in ('REPRODUCED', 'NOT_REPRODUCED', 'ERROR'))
);

-- One row per proposed patch (one per attempt). Each check records PASS or
-- FAIL; the logs and outputs behind them go to EVIDENCE.
create table lz_patch (
    patch_id           number generated always as identity,
    attempt_id         number          not null,
    file_path          varchar2(1000)  not null,
    diff               clob            not null,
    scan_result        varchar2(4),
    validate_result    varchar2(4),
    import_result      varchar2(4),
    rerun_result       varchar2(4),
    regression_result  varchar2(4),
    evidence           clob,
    branch             varchar2(255),
    merge_request_url  varchar2(1000),
    created_at         timestamp with time zone default systimestamp not null,
    constraint lz_patch_pk            primary key (patch_id),
    constraint lz_patch_attempt_fk
        foreign key (attempt_id) references lz_attempt (attempt_id),
    constraint lz_patch_attempt_uk    unique (attempt_id),
    constraint lz_patch_scan_ck       check (scan_result       in ('PASS', 'FAIL')),
    constraint lz_patch_validate_ck   check (validate_result   in ('PASS', 'FAIL')),
    constraint lz_patch_import_ck     check (import_result     in ('PASS', 'FAIL')),
    constraint lz_patch_rerun_ck      check (rerun_result      in ('PASS', 'FAIL')),
    constraint lz_patch_regression_ck check (regression_result in ('PASS', 'FAIL')),
    constraint lz_patch_evidence_json check (evidence is json)
);

-- One row per state transition. Insert-only, enforced by the trigger below.
create table lz_audit (
    audit_id     number generated always as identity,
    incident_id  number          not null,
    from_status  varchar2(20),
    to_status    varchar2(20)    not null,
    actor_type   varchar2(10)    not null,
    actor        varchar2(255),
    changed_at   timestamp with time zone default systimestamp not null,
    note         varchar2(4000),
    constraint lz_audit_pk          primary key (audit_id),
    constraint lz_audit_incident_fk
        foreign key (incident_id) references lz_incident (incident_id),
    constraint lz_audit_actor_ck    check (actor_type in ('AGENT', 'RUNNER', 'PERSON', 'SYSTEM'))
);

create index lz_audit_incident_ix on lz_audit (incident_id);

create or replace trigger lz_audit_insert_only
    before update or delete on lz_audit
begin
    raise_application_error(-20002, 'LZ_AUDIT is insert-only');
end lz_audit_insert_only;
/
