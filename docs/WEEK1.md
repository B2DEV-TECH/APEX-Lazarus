# Week 1 results

2026-11-10 · local lab · exit check **passed**

Week 1 asked whether the mechanical loop works by hand before any agent is written: capture in production, intake on development, reproduction, a one-file APEXlang patch, file-level import into the development application, and a re-run. It does. A hand-written patch fixed a seeded ORA-00904 through the full path, and production was never written to.

This page records what was run, what came back, and what week 1 did not cover.

## Lab

| Item | Version or value |
|---|---|
| Database | Oracle AI Database 26ai Free 23.26.3, one pluggable database (`FREEPDB1`) |
| APEX | 26.2.0, served by ORDS at `http://localhost:8080/ords` |
| SQLcl | 26.3.0 (`apex import -files` is not in SQLcl 26.2.2) |
| Browser checks | Playwright driving Microsoft Edge (`scripts/browser-probe.cjs`) |

Both environments share one APEX instance as two workspaces. The spec's default of two pluggable databases was not needed: the import target question (below) was answered on one instance.

| Workspace | Plays | Parsing schema | Lazarus schema | Application ID |
|---|---|---|---|---|
| `LZ_PRD` | production | `LZ_DEMO_PRD` | `LAZARUS_PRD` | 1410 |
| `LZ_DEV` | development | `LZ_DEMO_DEV` | `LAZARUS_DEV` | 1420 |

`LZ_PULL` is the only account that crosses zones. It has `SELECT` on `LAZARUS_PRD.LZ_INBOX` and nothing else. `LAZARUS_DEV` reads the inbox through a database link that connects as `LZ_PULL` (a loopback link on this single-host lab) and a synonym, `LZ_PROD_INBOX`.

The application calls `lz_capture.handle` without a schema prefix. In `LZ_DEMO_PRD` that name is a synonym for `LAZARUS_PRD.LZ_CAPTURE`; in `LZ_DEMO_DEV` it is a local package that does nothing, so errors raised while testing in development never reach the production inbox. The same APEXlang source runs in both workspaces.

## The four week 1 questions

### 1. The `-files` syntax

SQLcl 26.3 documents and accepts:

```
apex import -input demo/app -deployment demo/app/deployments/dev.json -files demo/app/pages/p00002-employees.apx
```

- `-deployment` selects a JSON file that sets the workspace, application ID and parsing schema, so one source tree imports as 1410 or 1420. `-id` overrides the application ID as well.
- Isolation holds. Page 1's title was changed on disk and the file was left out of `-files`; after the import, page 1 in 1420 still had its old title, and page 2 had the new region source.
- SQLcl 26.2.2 does not have `-files`. Its help lists the other options but not this one.

### 2. Reset, then import

A full import of Git HEAD into 1420 (`apex import -input demo/app -deployment demo/app/deployments/dev.json`), followed by a file-level import of one page, works in that order. This is the patch path's step 1 and step 4.

### 3. `APEX_HUMAN_TASK` in 26.2

The package is present in APEX 26.2 (public synonym `APEX_HUMAN_TASK`). No task definition was created in week 1.

### 4. Handler coverage

A probe page (page 90) raises each in-scope error. All of them reached `lz_capture.handle` with `component` filled.

| Error | Raised in | `component.type` | `is_internal_error` | `apex_error_code` |
|---|---|---|---|---|
| ORA-01403 | page process | `APEX_APPLICATION_PAGE_PROCESS` | N | none |
| ORA-01422 | page process | `APEX_APPLICATION_PAGE_PROCESS` | N | none |
| ORA-06502 | computation | `APEX_APPLICATION_PAGES` | **Y** | `APEX.COMPUTATION.UNHANDLED_ERROR` |
| ORA-06502 | validation | `APEX_APPLICATION_PAGE_VAL` | **Y** | `APEX.VALIDATION.UNHANDLED_ERROR` |
| ORA-00904 | region rendering | `APEX_APPLICATION_PAGE_REGIONS` | N | none |

Two results change the spec:

- APEX marks an unhandled error inside a computation or a validation as internal, although the error comes from the page's own code. The first version of the capture filter skipped internal errors and lost both ORA-06502 cases. Capture now keeps every error that has an `ora_sqlcode` and stores both flags; scope is decided later by `LZ_GUARD`.
- For a computation, `component` is the page, not the computation. Reproduction must find the failing computation another way, for example from the error statement or by trying the page's computations in order.

`ora_sqlcode` arrives as `100` for NO_DATA_FOUND, as expected; the intake maps it to `ORA-01403`.

## Exit check: incident 5

The fault is `demo/faults/f00904-rename-email.sql`, which renames `LZ_EMPLOYEES.EMAIL` to `EMAIL_ADDRESS`. It ran in both parsing schemas, as a scripted deployment would.

| Step | What ran | Result |
|---|---|---|
| Break | Open Employees (page 2) in 1410 | `ORA-00904: "E"."EMAIL": invalid identifier` on the page |
| Capture | `lz_capture.handle` | Rows in `LZ_INBOX` with component `Employees` and the user name as an HMAC. Page 2 has no items, so the session state is `{}`; the page 90 rows carry values, such as `{"P90_TEXT":"abc","P90_CODE":null}` |
| Intake | `lz_intake.pull` as `LAZARUS_DEV` | Incident 5, status `NEW`, one incident for every occurrence (3 by the end of the day) |
| Reset | Full import of HEAD into 1420 | `Import successful.` |
| Reproduce | `demo/runbook/repro_region_parse.sql` as `LZ_DEMO_DEV` (region SQL parsed with `DBMS_SQL`) | `REPRO_RESULT=ORA-00904` |
| Patch | Branch `lazarus/incident-5`, one line in `p00002-employees.apx`: `e.email,` becomes `e.email_address as email,` | Report column `EMAIL` keeps its name and heading |
| Validate | `apex validate -input demo/app` (offline) | No errors |
| Import | The `-files` command above | `Import successful.` |
| Re-run | Same reproduction script | `REPRO_RESULT=PARSE_OK` |
| Regression | Page 2 in 1420 through the browser, against the working version (commit `8cea4e9`) | Headings ID, Name, Email, Job, Department, Salary; 10 rows; no empty email |
| Production | Page 2 in 1410 | Still raises ORA-00904. Nothing was written to production. |
| Record | `demo/runbook/week1_incident5_record.sql` | `LZ_ATTEMPT` 1, `LZ_PATCH` 1, and `LZ_AUDIT` rows `NEW` → `REPRODUCED` → `PATCHED` → `VALIDATED`, actor type `PERSON` |

The patch branch is not merged. In the design, merging it is the deployment gate, and that decision belongs to a person.

## Other findings

- **REST-enabled schema not needed here.** The file-level import worked with `LZ_DEMO_DEV` not REST-enabled (`USER_ORDS_SCHEMAS` is empty), over a direct SQLcl connection. The spec had listed REST enablement as a prerequisite.
- **Line endings.** APEXlang files must use LF. A CRLF file fails validation with `token recognition error at: '\r\n'`. `.gitattributes` pins `*.apx` and the deployment JSON files to LF.
- **Application IDs 3000 to 8999 are reserved.** The import refuses them as invalid; the lab uses 1410 and 1420.
- **`apex import` exit status.** A failed import in SQLcl does not make the session exit with an error. The runner has to read the output or check the APEX dictionary after each import.
- **Item references in APEXlang.** Properties that point to a component take `@name` (`associatedItem: @P3_SALARY`). Properties that take an item name take the plain name (`itemName: P90_CODE`). The validator accepts `@P90_CODE` in the second case, but at runtime APEX then looks for an item literally named `@P90_CODE` (ERR-1002).
- **Mapping production to development.** Region IDs differ between 1410 and 1420 after import, and the demo regions have no static ID, so week 1 matched by page and region name. The fault set should give every component a static ID.
- **`last_updated_on` is empty after an APEXlang import**, so it cannot show which pages an import changed. The isolation test used page titles instead.
- **APEX views outside a session.** Run as a schema that is not a workspace schema and outside an APEX session, the `APEX_APPLICATION_*` views return no rows. `LZ_CAPTURE` reads them inside the user's session, where they work.

## Not covered in week 1

- `LZ_REPRO`, `LZ_GUARD`, the runner and the data reset do not exist yet. Reproduction used a runbook script, and only for a region source. Reproducing processes, computations and validations with `APEX_SESSION` and `APEX_EXEC` is week 2 work.
- The regression check was manual: headings and row count on the rendered page. The per-fault oracle is week 3 work.
- `SCAN_RESULT` is empty in `LZ_PATCH`: there is no static scan yet.
- No Human Task, no pushed branch, no merge request.
- Incidents 1 to 4 (the page 90 probes) stay `NEW`. They exist to show the handler reaches each class.
- The two-database topology was not tested.

## Running it again

From the repository root, in Windows PowerShell, with Oracle Database Free, APEX 26.2, ORDS and SQLcl 26.3 installed:

```powershell
./scripts/setup-local.ps1          # users, workspaces, .local/oracle.json (refuses to overwrite it)
$s = './scripts/lz-sql.ps1'
& $s -Account LZ_DEMO_PRD -Command '@demo/db/demo_tables.sql'
& $s -Account LZ_DEMO_DEV -Command '@demo/db/demo_tables.sql'
& $s -Account LAZARUS_PRD -Command "set verify off`ndefine parsing_schema = LZ_DEMO_PRD`ndefine pull_user = LZ_PULL`n@db/prod/install.sql"
& $s -Account LAZARUS_DEV -Command "set verify off`ndefine pull_password = {{secret:LZ_PULL}}`ndefine prod_connect = //localhost:1521/FREEPDB1`ndefine prod_schema = LAZARUS_PRD`n@db/dev/install.sql"
& $s -Account LZ_DEMO_PRD -File demo/db/error_handler_prd.sql
& $s -Account LZ_DEMO_DEV -File demo/db/error_handler_dev.sql
& $s -Account LZ_DEMO_PRD -Command 'apex import -input demo/app'
& $s -Account LZ_DEMO_DEV -Command 'apex import -input demo/app -deployment demo/app/deployments/dev.json'
```

`lz-sql.ps1` reads passwords from `.local/oracle.json`, passes them to SQLcl through standard input, and masks them in the output. Then follow the exit check table: apply the fault in both parsing schemas, open page 2 in `LZ_PRD` (`node scripts/browser-probe.cjs prd employees`), pull, reset, reproduce, patch, validate, import, re-run. `scripts/teardown-local.ps1` removes the lab.
