-- APEX Lazarus, week 1: records the hand-made repair of incident 5
-- (ORA-00904 in the Employees region after the email column rename) in the
-- lifecycle tables, so the manual run leaves the same trail the runner will.
-- Run once as LAZARUS_DEV after the steps in docs/WEEK1.md.
--
-- Week 1 has no static scan yet (LZ_GUARD and the scan arrive in weeks 2
-- and 3), so SCAN_RESULT stays null. The regression result is the manual
-- check described in EVIDENCE, not the per-fault oracle of week 3.

set define off
set serveroutput on
whenever sqlerror exit failure rollback

declare
    c_incident_id constant number := 5;
    c_actor       constant varchar2(30) := 'week1-manual';
    v_status      lz_incident.status%type;
    v_attempt_id  lz_attempt.attempt_id%type;
    v_diff        clob;
    v_evidence    clob;

    -- One audit row per transition, in order
    procedure move_to (p_to in varchar2, p_note in varchar2) is
    begin
        insert into lz_audit (incident_id, from_status, to_status, actor_type, actor, note)
        values (c_incident_id, v_status, p_to, 'PERSON', c_actor, p_note);
        update lz_incident set status = p_to where incident_id = c_incident_id;
        v_status := p_to;
    end move_to;
begin
    select i.status into v_status from lz_incident i where i.incident_id = c_incident_id;
    if v_status <> 'NEW' then
        raise_application_error(-20010, 'Incident 5 is ' || v_status || ', expected NEW');
    end if;

    -- The diff is the commit on branch lazarus/incident-5 (git diff week1..lazarus/incident-5).
    -- Each line is a separate literal: SQLcl must not see a line starting with @@.
    v_diff :=    q'~diff --git a/demo/app/pages/p00002-employees.apx b/demo/app/pages/p00002-employees.apx~' || chr(10)
              || q'~index 9b1e015..fe3985a 100644~' || chr(10)
              || q'~--- a/demo/app/pages/p00002-employees.apx~' || chr(10)
              || q'~+++ b/demo/app/pages/p00002-employees.apx~' || chr(10)
              || q'~@@ -30,7 +30,7 @@ page 2 (~' || chr(10)
              || q'~             sqlQuery: ```sql~' || chr(10)
              || q'~ select e.employee_id,~' || chr(10)
              || q'~        e.first_name || ' ' || e.last_name as full_name,~' || chr(10)
              || q'~-       e.email,~' || chr(10)
              || q'~+       e.email_address as email,~' || chr(10)
              || q'~        e.job_title,~' || chr(10)
              || q'~        d.department_name,~' || chr(10)
              || q'~        e.salary,~' || chr(10);

    v_evidence := q'~{
  "mode": "manual",
  "commit": "2d043d3",
  "reproduction": {
    "method": "demo/runbook/repro_region_parse.sql as LZ_DEMO_DEV, application 1420 reset from Git",
    "before": "ORA-00904",
    "after": "PARSE_OK"
  },
  "validate": "apex validate -input demo/app (SQLcl 26.3): no errors",
  "import": {
    "command": "apex import -input demo/app -deployment demo/app/deployments/dev.json -files demo/app/pages/p00002-employees.apx",
    "target": 1420,
    "isolation": "page 1 changed on disk and not listed: its title in 1420 stayed Home"
  },
  "browser": {
    "dev_1420": {"oraInBody": [], "rows": 10, "emptyEmails": 0},
    "prd_1410": {"oraInBody": ["ORA-00904: \"E\".\"EMAIL\": invalid identifier"], "note": "production untouched"}
  },
  "regression": {
    "method": "manual: rendered report against the working version of page 2 (commit 8cea4e9)",
    "expected": {"headings": ["ID", "Name", "Email", "Job", "Department", "Salary"], "rows": 10},
    "actual": {"headings": ["ID", "Name", "Email", "Job", "Department", "Salary"], "rows": 10, "emptyEmails": 0}
  }
}~';

    insert into lz_attempt (incident_id, attempt_no, guard_verdict, repro_result, model, finished_at)
    values (c_incident_id, 1, 'IN_SCOPE', 'REPRODUCED', 'none (manual)', systimestamp)
    returning attempt_id into v_attempt_id;
    move_to('REPRODUCED', 'Region SQL parsed as LZ_DEMO_DEV in 1420: ORA-00904');

    insert into lz_patch (attempt_id, file_path, diff, validate_result, import_result,
                          rerun_result, regression_result, evidence, branch)
    values (v_attempt_id, 'demo/app/pages/p00002-employees.apx', v_diff, 'PASS', 'PASS',
            'PASS', 'PASS', v_evidence, 'lazarus/incident-5');
    move_to('PATCHED', 'Hand-written patch: e.email -> e.email_address as email; validated and imported with -files');
    move_to('VALIDATED', 'Re-run PARSE_OK; dev page renders 10 rows with the same headings; production untouched');

    commit;
    dbms_output.put_line('RECORDED attempt ' || v_attempt_id || ', incident 5 is ' || v_status);
end;
/
