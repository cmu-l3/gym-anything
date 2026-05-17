# Expert Feedback — Audit Phase

This file collects notes from **domain experts** about what auditors
should look for in specific environments (or globally).

**You MUST read this file every time you audit an environment.** The
guidance below supplements the standard checklist in `audit_prompt.md`.
If an entry applies to the environment you are auditing, treat it as a
hard checklist item.

## How to read entries

Each entry has a header:

```
## <ISO timestamp> — <env or GLOBAL> — <one-line summary>
```

followed by the expert's note. Notes typically tell you:

- A specific failure mode this software is prone to (e.g. "models
  often default to demo data in Odoo HR — verify the database is seeded
  from a real source").
- A check to add to the audit ("confirm the data is a public dataset
  cited in the install script, not synthesized inline").
- A red flag to stop on ("if the install script contains a hardcoded
  Python list of patients, this is FAIL — that is fake data").

## How to apply

1. When auditing `<env_dir>`, scan this file for entries matching
   `<env_dir>` or `GLOBAL`.
2. Apply each matching entry as an additional checklist item.
3. If an entry says "FAIL on X", treat detection of X as a critical
   finding in your audit report, regardless of what `audit_prompt.md`
   says.
4. Cite the entry's timestamp in your audit report so the human reviewer
   can trace the finding.

## Entries

_(appended by the expert console as feedback is submitted)_
