# Task: study_closeout

**Difficulty**: Very Hard
**Role**: Senior Clinical Data Manager
**Environment**: OpenClinica 3.13 Community Edition

## Overview

This task simulates the complete end-of-study administrative closeout workflow that a Senior Clinical Data Manager performs when one or more clinical trials reach their conclusion. The agent must independently discover and execute five distinct administrative actions across two separate studies, with no UI navigation hints provided.

The task is classified as "very hard" because:
- The task description states only the goal, not how to achieve it (no menu path hints)
- The agent must navigate between two different studies and know how to switch the active study context in OpenClinica
- The agent must locate and use features that are not centrally located: event definition management (Study Setup menu), subject status changes (Subject record), study status transitions (Update Study or Administration menu), and data export (Tasks → Extract Data)
- The correct status transition workflow for AP Pilot requires understanding that Completed → Locked (or Completed → Frozen → Locked) are the valid paths — the agent cannot simply jump to Locked from Available
- There are five independent subtasks that each touch different parts of the OpenClinica application

## Professional Context

In a real clinical trial setting, a Senior CDM closing out a study must:
1. **Amend the event schedule**: Protocol amendments that add final safety visits must be reflected as new event definitions before data entry closes.
2. **Handle subject withdrawals**: Subjects who discontinue must be administratively marked so they are excluded from per-protocol analyses.
3. **Freeze the study**: Freezing signals that data entry is complete but queries (data discrepancies) may still be resolved. The study is locked only after all queries are closed.
4. **Lock a completed study**: Once a study is archived and regulatory binders are filed, the study is locked to prevent any further data modifications.
5. **Export the dataset**: A final data export provides the archival copy of the database for regulatory submission or sponsor handoff.

## Studies Involved

| Identifier | Study Name | Starting Status | Target Status |
|---|---|---|---|
| DM-TRIAL-2024 | Phase II Diabetes Trial | Available (1) | Frozen (5) |
| AP-PILOT-2022 | Asthma Prevention Pilot | Completed (4) | Locked (6) |

## Five Subtasks

| # | Action | Study | Points |
|---|---|---|---|
| 1 | Add "End of Study Assessment" event definition (Unscheduled, non-repeating) | DM-TRIAL-2024 | 20 |
| 2 | Change DM-103's enrollment status to discontinued/withdrawn | DM-TRIAL-2024 | 20 |
| 3 | Change study status from Available to Frozen | DM-TRIAL-2024 | 20 |
| 4 | Change study status from Completed to Locked | AP-PILOT-2022 | 20 |
| 5 | Export study data to Desktop or Downloads (any format) | Either study | 20 |

## Verification Strategy

The verifier reads `/tmp/study_closeout_result.json` written by `export_result.sh` and checks five independent database/filesystem criteria:

1. **Event definition exists** (20 pts): Queries `study_event_definition` for a row in DM Trial whose `name` matches a broad pattern: `end+assess`, `end+study`, or `final+assess`. Also checks `status_id != 3` (not removed). The event type (Unscheduled) and repeating=false are reported as informational feedback but are not gated criteria.

2. **DM-103 status changed** (20 pts): Queries `study_subject.status_id` for subject `DM-103` in DM Trial. Any value other than 1 (active) earns full credit — 2 (completed), 3 (discontinued), and 4 (removed) are all accepted.

3. **DM Trial status changed** (20 pts): Queries `study.status_id` for DM-TRIAL-2024. Any value other than 1 (Available) earns full credit. Status 5 (Frozen) matches the task recommendation; 6 (Locked) and 4 (Completed) are also accepted.

4. **AP Pilot status Frozen or Locked** (20 pts): Queries `study.status_id` for AP-PILOT-2022. Status must be 5 (Frozen) or 6 (Locked). The starting status was 4 (Completed), so that value earns zero points. Status 6 (Locked) is the target described in the task.

5. **Export file exists** (20 pts): Uses `find` to locate any `.xml`, `.zip`, `.xls`, `.xlsx`, `.csv`, or `.ods` file in `/home/ga/Desktop` or `/home/ga/Downloads` that is newer than the `/tmp/task_start_timestamp` file created during setup.

6. **VLM visual check** (up to 10 pts bonus): The end-of-task screenshot is analyzed for evidence of OpenClinica administrative activity (study settings, export pages, subject management).

7. **Audit log penalty** (-20 pts): If no new audit log entries are detected between setup baseline and export, a penalty is applied to discourage direct database manipulation in lieu of GUI interaction.

**Pass threshold**: 70 / 100 points (plus up to 10 VLM bonus).

## DB Schema Reference

```sql
-- study: top-level study record
study (
    study_id            SERIAL PRIMARY KEY,
    unique_identifier   VARCHAR,   -- e.g. 'DM-TRIAL-2024'
    name                VARCHAR,
    status_id           INTEGER    -- 1=Available, 2=Design, 4=Completed, 5=Frozen, 6=Locked
)

-- study_event_definition: defines visit/event types for a study
study_event_definition (
    study_event_definition_id  SERIAL PRIMARY KEY,
    study_id                   INTEGER REFERENCES study(study_id),
    name                       VARCHAR,    -- e.g. 'End of Study Assessment'
    description                TEXT,
    repeating                  BOOLEAN,    -- false = non-repeating
    type                       VARCHAR,    -- 'Scheduled' | 'Unscheduled' | 'Common'
    status_id                  INTEGER,    -- 1=available, 3=removed
    owner_id                   INTEGER,
    date_created               TIMESTAMP,
    oc_oid                     VARCHAR,
    ordinal                    INTEGER
)

-- study_subject: links a subject enrollment to a study
study_subject (
    study_subject_id   SERIAL PRIMARY KEY,
    label              VARCHAR,    -- e.g. 'DM-103'
    subject_id         INTEGER REFERENCES subject(subject_id),
    study_id           INTEGER REFERENCES study(study_id),
    status_id          INTEGER,    -- 1=active, 2=completed, 3=discontinued, 4=removed
    enrollment_date    DATE
)
```

## Files

| File | Purpose |
|---|---|
| `task.json` | Task definition: description, difficulty, hooks, metadata, success spec |
| `setup_task.sh` | Pre-task setup: verifies/resets study states, cleans stale event defs, clears export files, launches browser, sets audit baseline |
| `export_result.sh` | Post-task export: queries DB for all 5 criteria and filesystem for export file, writes JSON result |
| `verifier.py` | Scoring logic: reads result JSON, evaluates 5 criteria, applies VLM check and audit penalty |
| `README.md` | This file |
