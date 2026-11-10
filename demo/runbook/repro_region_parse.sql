-- APEX Lazarus, week 1 manual reproduction of an ORA-00904 in a region source.
-- Run as the development application's parsing schema. The region's SQL is
-- read from the APEX dictionary of the development application and parsed
-- with DBMS_SQL: an invalid identifier fails at parse time, nothing runs.
--
--   &app_id       development application ID
--   &page_id      page of the failing region
--   &region_name  region name from the incident (component_name)

set serveroutput on
declare
    v_sql    clob;
    v_cursor integer;
begin
    select r.region_source
      into v_sql
      from apex_application_page_regions r
     where r.application_id = &app_id
       and r.page_id        = &page_id
       and r.region_name    = '&region_name';

    v_cursor := dbms_sql.open_cursor;
    begin
        dbms_sql.parse(v_cursor, v_sql, dbms_sql.native);
        dbms_output.put_line('REPRO_RESULT=PARSE_OK');
    exception
        when others then
            -- The reproduction result is the error itself: it is reported,
            -- the cursor is closed, and the block ends normally.
            dbms_output.put_line('REPRO_RESULT=' || sqlerrm);
    end;
    dbms_sql.close_cursor(v_cursor);
end;
/
