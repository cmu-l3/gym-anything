# oc_tb_contact_trace — TB Contact Tracing

## Overview

**Difficulty**: Very Hard
**Occupation**: Public Health / Infectious Disease Nurse
**Environment**: OpenClinic GA Hospital Information System

A public health contact tracing task. A TB case has been confirmed and three known contacts must be processed through the full intake-plus-testing protocol: registered as patients, given the TB screening lab test (MALAR), and scheduled for follow-up appointments.

## Domain Context

Infectious disease nurses and public health workers perform contact tracing by registering exposed individuals in the hospital system and ordering appropriate screening tests. For TB, the AFB (Acid-Fast Bacilli) smear and culture is the primary screening tool, coded as `MALAR` in OpenClinic's lab system. Each contact requires three separate workflow steps across different system modules.

## Task Setup (Starting State)

None of the three TB contacts exist in the system at task start (`setup_task.sh` removes any prior entries). The agent must register all three from scratch.

| Contact | Gender | DOB | Country |
|---|---|---|---|
| Kofi Asante | Male (M) | 1988-07-22 | GH (Ghana) |
| Rania Aziz | Female (F) | 1975-03-10 | EG (Egypt) |
| Dimitri Papadopoulos | Male (M) | 1962-11-30 | GR (Greece) |

For each contact, the agent must:
1. Register as a new patient (with correct demographics including DOB)
2. Order the `MALAR` lab test (TB AFB smear/culture)
3. Schedule a follow-up appointment

## Expected End State

For each contact:
- Found in `ocadmin_dbo.adminview` with matching firstname, lastname, and DOB
- At least 1 `MALAR` entry in `openclinic_dbo.requestedlabanalyses` for their patient ID
- At least 1 appointment in `openclinic_dbo.oc_planning` for their patient ID

## Scoring

Scoring is per-contact (3 contacts × ~33 pts = 100 pts total):

| Contact | Registered | MALAR Lab | Appointment | Subtotal |
|---|---|---|---|---|
| Kofi Asante | 11 pts | 11 pts | 12 pts | 34 pts |
| Rania Aziz | 11 pts | 11 pts | 11 pts | 33 pts |
| Dimitri Papadopoulos | 11 pts | 11 pts | 11 pts | 33 pts |

Partial credit for registration: if patient is found but DOB is wrong, 5-6 pts awarded instead of 11.
Lab and appointment checks only run if patient ID is found.

**Pass threshold**: 60/100 (at least 2 contacts fully processed)
**Do-nothing state**: 0/100 (none of the contacts exist) → `passed=False`

## Verification Strategy

- `setup_task.sh` removes any prior registrations for the 3 contacts and records start timestamp
- `export_result.sh` queries `ocadmin_dbo.adminview` to find patient IDs by name, then checks lab orders and appointments
- Result written to `/tmp/oc_tb_contact_trace_result.json`
- `verifier.py` copies JSON via `copy_from_env`, evaluates 9 sub-criteria (3 per contact)

## Key Database Tables

- `ocadmin_dbo.adminview` — patient registry (personid, firstname, lastname, dateofbirth, sex)
- `openclinic_dbo.requestedlabanalyses` — lab orders (patientid, analysiscode)
- `openclinic_dbo.oc_planning` — appointments (OC_PLANNING_PATIENTID)

## Why This Is Very Hard

- Agent must complete 9 distinct actions (3 per contact) across multiple modules
- Patient names are non-anglophone (Ghanaian, Egyptian, Greek) — potential spelling/search challenges
- DOB must be entered exactly (format matters for verification)
- Lab code `MALAR` is non-obvious for TB screening — requires domain knowledge (AFB = MALAR in OpenClinic)
- No UI navigation hints or lab code suggestions provided in the description
- 3-patient workload: must stay organized and not conflate patient records
- Pass threshold requires 2/3 contacts fully complete; single-contact completion is insufficient
