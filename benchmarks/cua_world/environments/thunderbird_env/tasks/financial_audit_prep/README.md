# Task: financial_audit_prep

## Overview

**Difficulty**: very_hard
**Environment**: thunderbird_env
**Occupation**: Financial Controller / Compliance Officer
**Industry**: Financial Services (Investment Advisory)

The agent acts as Jennifer Reeves, Financial Controller at Meridian Capital Partners, a registered investment advisory firm. The SEC has launched a routine examination (Exam #2024-NY-0847) and FINRA has opened a separate net capital review (Case FR-2024-NY-0312). The inbox contains a backlog of regulatory correspondence that must be organized before the on-site examination visits.

## What the Agent Must Do

1. Create a **Regulatory** folder in Local Folders
2. Create **SEC_Examination** subfolder under Regulatory — move all 4 SEC emails there
3. Create **FINRA_Review** subfolder under Regulatory — move all 3 FINRA emails there
4. Add lead SEC examiner **Jennifer Kowalski** (jkowalski@sec.gov) to the address book
5. Create a message filter routing future **@sec.gov** emails to SEC_Examination
6. Create a message filter routing future **@finra.org** emails to FINRA_Review

## Injected Emails (9 total)

| # | From | Subject | Should Go To |
|---|------|---------|-------------|
| 1 | jkowalski@sec.gov | Examination Notice - SEC Exam #2024-NY-0847 | SEC_Examination |
| 2 | jkowalski@sec.gov | Document Request List No. 1 - Exam #2024-NY-0847 | SEC_Examination |
| 3 | sfletcher@sec.gov | Net Capital Calculations - Supplemental Request | SEC_Examination |
| 4 | jkowalski@sec.gov | On-Site Examination Confirmation - March 18-22, 2024 | SEC_Examination |
| 5 | dcarter@finra.org | FINRA Net Capital Review - Case FR-2024-NY-0312 | FINRA_Review |
| 6 | lhoffman@finra.org | Rule 15c3-1 Compliance Documentation Request | FINRA_Review |
| 7 | dcarter@finra.org | FINRA On-Site Visit Schedule | FINRA_Review |
| 8 | compliance@meridiancp.com | Q4 2023 Annual Compliance Review - Action Items | (stay in Inbox) |
| 9 | cfoteam@meridiancp.com | Monthly Finance Team Standup - March 20 Agenda | (stay in Inbox) |

## Scoring (100 points total)

| Criterion | Points | Details |
|-----------|--------|---------|
| Regulatory folder structure (Regulatory.sbd exists) | 10 | Any nested folder named "Regulatory" under Local Folders |
| SEC_Examination subfolder with ≥4 emails | 25 | Partial credit: ≥2 emails → 13 pts, ≥1 email → 6 pts, folder only → 3 pts |
| FINRA_Review subfolder with ≥3 emails | 20 | Partial credit: ≥2 emails → 12 pts, ≥1 email → 5 pts, folder only → 2 pts |
| Jennifer Kowalski (jkowalski@sec.gov) in address book | 20 | Full credit requires email match; name only → 12 pts |
| @sec.gov routing filter exists | 15 | Filter must reference sec.gov or @sec |
| @finra.org routing filter exists | 10 | Filter must reference finra.org or @finra |
| **Total** | **100** | |

**Pass threshold**: 60 points

## Anti-Gaming Measures

- **Wrong-target guard**: If `Regulatory.sbd` exists but zero emails are in any subfolder, score is capped at 5 (agent made folders but never moved emails).
- **Score cap**: If total emails moved = 0 and computed score ≥ 60, score is reduced to 59.
- **Clean baseline**: `setup_task.sh` removes existing Regulatory folder and clears Jennifer Kowalski from address book before injecting new emails.

## Accepted Folder Name Variants

The export script checks these name variants for tolerance:

- SEC_Examination, SEC-Examination, SECExamination, SEC_Exam, SEC
- FINRA_Review, FINRA-Review, FINRAReview, FINRA_Exam, FINRA

## Files

| File | Description |
|------|-------------|
| `task.json` | Task metadata, hooks, difficulty |
| `setup_task.sh` | Clears state, injects 9 emails, records baseline, starts Thunderbird |
| `export_result.sh` | Kills Thunderbird, checks folder structure and email counts, queries address book and filter rules, writes result JSON |
| `verifier.py` | Scores result JSON on 6 criteria; includes 4 pipeline tests |
| `README.md` | This file |

## Testing

Run verifier pipeline tests:
```bash
python3 examples/thunderbird_env/tasks/financial_audit_prep/verifier.py
```
Expected: 4/4 tests passed
