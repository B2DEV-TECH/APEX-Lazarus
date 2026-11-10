-- APEX Lazarus: retention of raw values in production.
-- LZ_INBOX rows are deleted 7 days after capture. Rows the development
-- instance has not pulled by then are lost, which is accepted: an error that
-- keeps happening produces new rows.

begin
    dbms_scheduler.create_job(
        job_name        => 'LZ_INBOX_PURGE',
        job_type        => 'PLSQL_BLOCK',
        job_action      => q'[
            begin
                delete from lz_inbox
                 where captured_at < systimestamp - interval '7' day;
                commit;
            end;]',
        repeat_interval => 'FREQ=DAILY;BYHOUR=3;BYMINUTE=0',
        enabled         => true,
        comments        => 'APEX Lazarus: keep raw session state in production at most 7 days');
end;
/
