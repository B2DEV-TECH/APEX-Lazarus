-- APEX Lazarus: production tables, owned by the LAZARUS schema.
--
-- Production holds only these two tables. The application reaches them
-- through LZ_CAPTURE alone; the development instance reads LZ_INBOX through
-- a pull account with SELECT on that table and nothing else.
--
-- Privileges the LAZARUS owner needs: CREATE TABLE, CREATE SEQUENCE (identity
-- columns), CREATE PROCEDURE, CREATE TRIGGER, CREATE JOB, EXECUTE on
-- SYS.DBMS_CRYPTO, and a quota on its default tablespace.

-- One row: the capture switch and the key used to store user names as HMACs.
-- The pull account never gets access to this table.
create table lz_config (
    config_id        number(1)    default 1   not null,
    capture_enabled  varchar2(1)  default 'Y' not null,
    user_hmac_key    raw(32)                  not null,
    constraint lz_config_pk         primary key (config_id),
    constraint lz_config_one_row_ck check (config_id = 1),
    constraint lz_config_enabled_ck check (capture_enabled in ('Y', 'N'))
);

insert into lz_config (config_id, capture_enabled, user_hmac_key)
values (1, 'Y', sys.dbms_crypto.randombytes(32));

commit;

-- One row per captured occurrence. Insert-only for the handler; the purge job
-- (03_purge_job.sql) deletes rows older than 7 days.
-- session_state holds raw item values on purpose: the error classes Lazarus
-- fixes depend on them. They never reach the model unmasked.
create table lz_inbox (
    inbox_id         number generated always as identity,
    captured_at      timestamp with time zone default systimestamp not null,
    app_id           number          not null,
    app_version      varchar2(255),
    page_id          number,
    component_type   varchar2(255),
    component_id     number,
    component_name   varchar2(4000),
    ora_sqlcode      number          not null,
    ora_sqlerrm      varchar2(4000),
    error_statement  clob,
    error_backtrace  clob,
    apex_error_code  varchar2(255),
    -- APEX flags its own wrappers of application errors as internal (for
    -- example "Error processing validation."), so the flags are recorded and
    -- the scope decision is left to LZ_GUARD on the development instance.
    is_internal_error        varchar2(1),
    is_common_runtime_error  varchar2(1),
    app_user_hmac    varchar2(64),
    session_state    clob,
    constraint lz_inbox_pk         primary key (inbox_id),
    constraint lz_inbox_state_json check (session_state is json),
    constraint lz_inbox_internal_ck check (is_internal_error in ('Y', 'N')),
    constraint lz_inbox_common_ck   check (is_common_runtime_error in ('Y', 'N'))
);

-- Rows are never changed after capture.
create or replace trigger lz_inbox_no_update
    before update on lz_inbox
begin
    raise_application_error(-20001, 'LZ_INBOX rows are never updated');
end lz_inbox_no_update;
/
