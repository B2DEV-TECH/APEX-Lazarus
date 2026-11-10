# APEX Lazarus

APEX Lazarus turns an Oracle APEX runtime error into a validated, human-approved APEXlang merge request. It never changes production on its own.

When a page raises a database error in production, Lazarus records the incident. On a development instance, it reproduces the failure and asks a model for a fix limited to one APEXlang page file. It then validates the file, imports it with SQLcl file-level import and checks that the error is gone without hiding it. A person reviews the evidence in an APEX Human Task and approves it, which opens a merge request. Production changes only when that merge request is merged and deployed through the team's normal pipeline.

The project is built around limits. Lazarus refuses incidents it cannot reproduce, fixes that need more than one page file, and changes outside a small set of allowed properties, and it records the reason each time.

## Status

Week 1 of four is done. On a local Oracle Database Free with APEX 26.2, a seeded ORA-00904 went through the whole mechanical path by hand: capture in production, intake on development, reproduction, a one-line APEXlang patch, file-level import into the development application, and a clean re-run. Production was not touched. There is no agent yet. The evidence is in [`docs/WEEK1.md`](docs/WEEK1.md); the plan and its exit checks are in [`docs/SPEC.md`](docs/SPEC.md).

## Scope of the MVP

- Oracle APEX 26.2 and SQLcl 26.3 (the first SQLcl with `apex import -files`), one application exported as APEXlang.
- Three error classes whose fix lives in a page definition:
  - ORA-01403 and ORA-01422 in processes and computations;
  - ORA-00904 in region sources after a column rename;
  - ORA-06502 in validations and computations.
- A seeded fault set (15 in-scope faults and 5 decoys that must be refused) and a benchmark script that publishes fixes, failures, refusals and wrong fixes.

## Layout

| Path | Contents |
|---|---|
| `docs/SPEC.md` | MVP specification: architecture, data model, guardrails, benchmark, plan |
| `docs/WEEK1.md` | Week 1 results: what ran, what came back, what is not covered yet |
| `db/prod/` | Objects installed in production: `LZ_CONFIG`, `LZ_INBOX`, the `LZ_CAPTURE` error handler, inbox retention job, grants |
| `db/dev/` | Objects installed on the development instance: incident, context, attempt, patch and audit tables, the link to the inbox, `LZ_INTAKE` |
| `demo/app/` | Demo application in APEXlang, with deployment files for production (1410) and development (1420) |
| `demo/db/` | Demo tables and the per-environment error handler binding |
| `demo/faults/` | Seeded faults (week 1: the email column rename) |
| `demo/runbook/` | Week 1 manual steps: region reproduction and the lifecycle record for incident 5 |
| `scripts/` | Local lab setup and teardown, SQLcl wrapper, browser probe |

The runner, the remaining packages, the full fault set and the benchmark are added as they are built.

## Local lab

The lab runs both environments on one Oracle Database Free with APEX 26.2, as two workspaces. `scripts/setup-local.ps1` creates the users and workspaces and keeps the generated passwords in the ignored `.local/oracle.json`; `scripts/lz-sql.ps1` runs SQLcl as one of those accounts without putting a password on a command line. The install sequence is in [Running it again](docs/WEEK1.md#running-it-again).

In another setup, run in SQLcl as the LAZARUS owner:

```
@db/prod/install.sql   -- on the instance that plays production
@db/dev/install.sql    -- on the development instance
```

## License

[Universal Permissive License (UPL), Version 1.0](LICENSE).

APEX Lazarus is independent community work. It is not an Oracle product and is not endorsed by Oracle.
