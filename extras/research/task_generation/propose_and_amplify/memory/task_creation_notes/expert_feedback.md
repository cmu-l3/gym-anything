# Expert Feedback — Task Creation

This file collects notes from **domain experts** who reviewed tasks
produced by the propose-and-amplify pipeline. Each entry is short,
specific, and authoritative.

**You MUST read this file every time you propose new tasks.** The
feedback below supersedes the default task-creation guidance whenever
it applies. If a note applies to the software you are working on,
follow it. If an entry is marked `GLOBAL`, it applies to every
software.

## How to read entries

Each entry has a header like:

```
## <ISO timestamp> — <env or GLOBAL> [— <task name>] — <one-line summary>
```

followed by the expert's note. The note may include:

- A correction to the *kind* of tasks created for this software
  ("for Moodle, prioritize gradebook config tasks over user-management
  tasks; the latter is already covered elsewhere").
- A specific workflow to model ("this software is used by clinical
  data managers; a representative task is reconciling discrepant
  visits across two trial sites").
- A constraint to respect ("don't use synthetic patient data; use the
  Synthea sample dataset already in the env").
- An anti-pattern to avoid for this software ("don't generate tasks
  that just demonstrate a feature — generate workflows a real
  practitioner does in a session").

## How to apply

1. When working on `<env_dir>`, scan this file for entries whose header
   matches `<env_dir>` or `GLOBAL`.
2. Apply matching entries as hard constraints on the tasks you propose.
3. If a note conflicts with the defaults in `task_creation_notes/`,
   follow the expert.
4. When the entry includes a specific task name, treat it as guidance
   for revising or replacing that task in particular.

## Entries

_(appended by the expert console as feedback is submitted)_
