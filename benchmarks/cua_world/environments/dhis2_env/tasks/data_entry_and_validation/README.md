# Task: data_entry_and_validation

## Overview

This task evaluates an AI agent's ability to perform aggregate data entry in DHIS2 — the most common day-to-day workflow for health facility HMIS officers across Sierra Leone. The task requires selecting the correct dataset and period, entering plausible health data values, running validation, and marking the report complete.

**Difficulty**: Hard
**Timeout**: 720 seconds
**Max Steps**: 90

## Domain Context

In Sierra Leone, every health facility must submit monthly aggregate data reports to DHIS2 by the 5th of the following month. HMIS officers at facilities like Ngelehun CHC navigate to the Data Entry module, select their facility, choose the relevant dataset, and enter counts for all indicators. After entry, they run the built-in validation to catch impossible values (e.g., more deliveries than ANC 4th visits), then mark the form complete to signal it's ready for district review.

This is the highest-volume workflow in Sierra Leone's DHIS2 system — thousands of entries per month across 1,332 org units. The task specifically tests: org unit navigation (facility in district hierarchy), period selection, multi-field data entry, validation tool usage, and form completion.

## Goal

1. **Navigate to Data Entry**: Select Ngelehun CHC (in Bo district)
2. **Select dataset and period**: Choose any available monthly dataset for October 2023
3. **Enter data values**: Enter at least 5 data values with plausible numbers for a small rural facility
4. **Run validation**: Use the validation analysis feature to check data quality
5. **Mark complete**: Click "Complete" to submit the monthly report

## What Makes This Hard

- Data Entry module requires navigating an org unit tree hierarchy (Ngelehun CHC is buried under Bo district)
- Multiple datasets may be available — agent must choose the appropriate monthly one
- Period selection must be exact: October 2023 (not just 2023)
- Data entry fields require plausible values — agent must reason about what's realistic for a small facility
- Validation must be explicitly triggered via the interface (not automatic)
- "Complete" button must be found and clicked (not just saving values)
- Five independent data values must each be individually entered in separate form fields

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| New data values entered for Ngelehun CHC, October 2023 (MANDATORY) | 30 | ≥1 new datavalue in DB after task start for org unit DiszpKrYNg8 |
| At least 5 data values entered | 25 | ≥5 new datavalues for this org unit/period |
| Dataset marked complete | 25 | completedatasetregistration record exists for October 2023 |
| Values are plausible (within realistic range) | 20 | All entered values between 0 and 10,000 |

**Pass threshold**: 60 points
**Mandatory**: At least 1 data value must be entered for Ngelehun CHC in October 2023

## Verification Strategy

1. Query PostgreSQL: `SELECT COUNT(*) FROM datavalue WHERE sourceid = [Ngelehun CHC id] AND periodid = [Oct 2023 period id] AND created > [task_start]`
2. Query `completedatasetregistration` table for Ngelehun CHC and October 2023 period
3. Validate entered values are within plausible range (0–10,000)

## Data Reference

- **Target facility**: Ngelehun CHC, Bo District, Sierra Leone
- **Org unit UID**: DiszpKrYNg8
- **Period**: 202310 (October 2023, monthly period)
- **Available datasets**: Search in Data Entry module — look for Primary Health Care, Child Health, Reproductive Health, or Disease Surveillance datasets
- **Plausible values**: Small rural facility, ~5,000 catchment population. Monthly ANC visits: 30-60, deliveries: 15-30, vaccinations: 30-50, malaria tests: 150-300

## Edge Cases

- If October 2023 data already exists (pre-seeded demo data), verifier detects data ADDED/CHANGED after task start
- Period "202310" may display as "October 2023" in the UI — both refer to the same monthly period
- Agent may choose a dataset that doesn't cover all 5 target indicators — partial credit for ≥1 value
- Validation runner may show zero violations (clean data) — this is still credit for completing the validation step
