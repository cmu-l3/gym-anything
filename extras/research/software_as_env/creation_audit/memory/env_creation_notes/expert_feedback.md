# Expert Feedback — Environment Creation

This file collects notes from **domain experts** who reviewed the
environments produced by this pipeline. Each entry is short, specific,
and authoritative — it represents a correction or guidance that the
domain expert wanted incorporated.

**You MUST read this file every time you create or modify an
environment.** The feedback below supersedes default behavior whenever
it applies. If a note applies to the software you are working on, follow
it. If an entry is marked `GLOBAL`, it applies to every environment.

## How to read entries

Each entry has a header like:

```
## <ISO timestamp> — <env or GLOBAL> — <one-line summary>
```

followed by the expert's note. The note may include:

- A correction to follow ("use real, not demo, data").
- A specific data source the expert recommends.
- A constraint to respect ("never use the LibreOffice GUI for this
  workflow; the task is about the desktop calendar").
- Instructions to add or remove items from the audit checklist.

## How to apply

1. When starting work on `<env_dir>`, scan this file for entries whose
   header matches `<env_dir>` or `GLOBAL`.
2. If found, treat the note as a hard requirement for this environment.
3. If the note conflicts with a default in `prompt.md`, follow the
   expert. They have more domain context than the prompt does.
4. If the note references a checklist change, also reflect it in your
   audit work for this env.

## Entries

_(appended by the expert console as feedback is submitted)_
