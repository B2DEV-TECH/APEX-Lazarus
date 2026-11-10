# APEX Lazarus

APEX Lazarus turns an Oracle APEX runtime error into a validated, human-approved APEXlang merge request. It never changes production on its own.

When a page raises a database error in production, Lazarus records the incident. On a development instance, it reproduces the failure and asks a model for a fix limited to one APEXlang page file. It then validates the file, imports it with SQLcl file-level import and checks that the error is gone without hiding it. A person reviews the evidence in an APEX Human Task and approves it, which opens a merge request. Production changes only when that merge request is merged and deployed through the team's normal pipeline.

The project is built around limits. Lazarus refuses incidents it cannot reproduce, fixes that need more than one page file, and changes outside a small set of allowed properties, and it records the reason each time.

## Status

Early work. This repository holds the MVP specification and the first database objects. None of it has been run on an APEX instance yet. The four-week plan and its exit checks are in [`docs/SPEC.md`](docs/SPEC.md).

## Scope of the MVP

- Oracle APEX 26.2 and SQLcl 26.2, one application exported as APEXlang.
- Three error classes whose fix lives in a page definition:
  - ORA-01403 and ORA-01422 in processes and computations;
  - ORA-00904 in region sources after a column rename;
  - ORA-06502 in validations and computations.
- A seeded fault set (15 in-scope faults and 5 decoys that must be refused) and a benchmark script that publishes fixes, failures, refusals and wrong fixes.

## Layout

| Path | Contents |
|---|---|
| `docs/SPEC.md` | MVP specification: architecture, data model, guardrails, benchmark, plan |
| `db/prod/` | Objects installed in production: `LZ_CONFIG`, `LZ_INBOX`, the `LZ_CAPTURE` error handler, inbox retention job, grants |
| `db/dev/` | Objects installed on the development instance: incident, context, attempt, patch and audit tables |

The demo application, the runner, the fault set and the benchmark are added as they are built.

## Install (development only, for now)

Run in SQLcl as the LAZARUS owner:

```
@db/prod/install.sql   -- on the instance that plays production
@db/dev/install.sql    -- on the development instance
```

## License

[Universal Permissive License (UPL), Version 1.0](LICENSE).

APEX Lazarus is independent community work. It is not an Oracle product and is not endorsed by Oracle.
