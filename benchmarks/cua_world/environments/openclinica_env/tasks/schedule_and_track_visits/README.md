# Task: schedule_and_track_visits

**Difficulty**: Hard
**Role**: Clinical Research Coordinator
**Environment**: OpenClinica 3.13 Community Edition

## Overview

This task tests the ability of a Clinical Research Coordinator to manage the complete visit scheduling workflow in OpenClinica. The agent must schedule study events for two existing enrolled subjects, enroll a brand-new subject from scratch, and then schedule an event for that newly enrolled subject — all using the OpenClinica GUI.

The task covers two distinct workflows:
1. **Event scheduling for existing subjects** — navigating to a subject's record and adding a scheduled study event with a specific start date and optional location.
2. **New subject enrollment + event scheduling** — using the Add Subject workflow to enroll DM-104 with correct demographic data, then immediately scheduling their first visit.

## Study Context

- **Study**: Phase II Diabetes Trial (`DM-TRIAL-2024`)
- **Pre-existing enrolled subjects**: DM-101 (F, 1968-03-22), DM-102 (M, 1952-11-07), DM-103 (F, 1980-07-14)
- **Event definitions created by setup**: Baseline Assessment (Scheduled, non-repeating), Week 4 Follow-up (Scheduled, repeating)

## Ground Truth / Expected State After Task

| Action | Subject | Event | Date | Notes |
|--------|---------|-------|------|-------|
| Schedule event | DM-101 | Baseline Assessment | 2024-01-15 | Location: Main Clinic |
| Schedule event | DM-102 | Week 4 Follow-up | 2024-03-01 | No location required |
| Enroll new subject | DM-104 | — | enrollment = today | Gender: Male, DOB: 1978-05-23 |
| Schedule event | DM-104 | Baseline Assessment | 2024-01-22 | — |

## Verification Strategy

The verifier checks 4 independent database criteria plus a VLM visual check:

1. **DM-101 Baseline Assessment** (20 pts + 5 bonus): Queries `study_event` joined to `study_subject` for DM-101's study_subject_id and the Baseline Assessment `study_event_definition_id`. Confirms a row exists, then checks `start_date = '2024-01-15'` for the bonus.

2. **DM-102 Week 4 Follow-up** (20 pts + 5 bonus): Same pattern for DM-102 with the Week 4 Follow-up event definition. Bonus for `start_date = '2024-03-01'`.

3. **DM-104 enrollment** (25 pts): Queries `study_subject` for label `DM-104` in the DM Trial. Confirms `subject.gender = 'm'` and `subject.date_of_birth = '1978-05-23'` (reported in feedback, not gated for points).

4. **DM-104 Baseline Assessment** (20 pts + 5 bonus): Confirms a `study_event` row exists for DM-104's `study_subject_id` linked to the Baseline Assessment definition. Bonus for `start_date = '2024-01-22'`.

5. **VLM visual check** (up to 15 pts): End-of-task screenshot is analyzed for OpenClinica UI visibility and presence of scheduling/subject-related content.

6. **Audit log penalty** (-25 pts): If no new audit log entries are detected between setup baseline and export, a penalty is applied to discourage direct DB manipulation instead of GUI use.

**Pass threshold**: 70 / 100 points.

## DB Schema Reference

```sql
-- study_subject: links a subject to a study
study_subject (
    study_subject_id  SERIAL PRIMARY KEY,
    label             VARCHAR,        -- e.g. 'DM-101'
    subject_id        INTEGER REFERENCES subject(subject_id),
    study_id          INTEGER REFERENCES study(study_id),
    status_id         INTEGER,        -- 1=available, 3=removed
    enrollment_date   DATE
)

-- subject: demographic record
subject (
    subject_id        SERIAL PRIMARY KEY,
    date_of_birth     DATE,
    gender            VARCHAR,        -- 'm' or 'f'
    status_id         INTEGER
)

-- study_event_definition: defines visit types for a study
study_event_definition (
    study_event_definition_id  SERIAL PRIMARY KEY,
    study_id                   INTEGER REFERENCES study(study_id),
    name                       VARCHAR,   -- e.g. 'Baseline Assessment'
    description                TEXT,
    repeating                  BOOLEAN,
    type                       VARCHAR,   -- 'Scheduled' or 'Unscheduled'
    status_id                  INTEGER,   -- 1=available, 3=removed
    owner_id                   INTEGER,
    date_created               TIMESTAMP,
    oc_oid                     VARCHAR,
    ordinal                    INTEGER
)

-- study_event: an instance of a scheduled event for a subject
study_event (
    study_event_id             SERIAL PRIMARY KEY,
    study_subject_id           INTEGER REFERENCES study_subject(study_subject_id),
    study_event_definition_id  INTEGER REFERENCES study_event_definition(study_event_definition_id),
    start_date                 DATE,
    status                     VARCHAR,   -- e.g. 'scheduled'
    owner_id                   INTEGER,
    date_created               TIMESTAMP,
    sample_ordinal             INTEGER    -- occurrence index for repeating events
)
```

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task definition: description, difficulty, hooks, metadata, success spec |
| `setup_task.sh` | Pre-task setup: inserts event definitions, cleans up stale data, launches browser, sets audit baseline |
| `export_result.sh` | Post-task export: queries DB for all 4 criteria, writes JSON result file |
| `verifier.py` | Scoring logic: reads result JSON, computes score, applies VLM check and audit penalty |
| `README.md` | This file |
