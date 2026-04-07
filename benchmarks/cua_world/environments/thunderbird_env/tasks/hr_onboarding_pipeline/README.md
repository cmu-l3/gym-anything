# Task: hr_onboarding_pipeline

## Overview

**Difficulty**: very_hard
**Environment**: thunderbird_env
**Occupation**: HR Manager
**Industry**: Technology (Software Company)

The agent acts as the HR Manager at TechVenture Corp. Q1 2025 hiring has concluded and three new employees (Alex Johnson, Sarah Kim, Robert Chen) are starting Monday. The inbox has a mix of new hire paperwork follow-up emails and IT provisioning requests. The agent must organize the inbox by onboarding type, add the IT Director to the address book, and compose a draft confirmation email to the IT Director.

## What the Agent Must Do

1. Create an **Onboarding_Q1** folder in Local Folders
2. Create **Documents_Pending** subfolder — move all 3 outstanding-paperwork emails there
3. Create **IT_Requests** subfolder — move all 4 IT provisioning emails there
4. Add IT Director **Marcus Thompson** (m.thompson@techventure-it.com) to the address book
5. Compose a **draft reply** to Marcus Thompson's Q1 batch email confirming new hire start details (Johnson, Kim, Chen start Monday) — save as draft, do not send

## Injected Emails (9 total)

| # | From | Subject | Should Go To |
|---|------|---------|-------------|
| 1 | alex.johnson@gmail.com | Onboarding Documents - Alex Johnson (missing items) | Documents_Pending |
| 2 | sarah.kim.newhire@protonmail.com | Missing Onboarding Forms - Sarah Kim | Documents_Pending |
| 3 | recruiter@talentbridge.com | New Placement - Robert Chen - Documents Required | Documents_Pending |
| 4 | m.thompson@techventure-it.com | IT Setup Request - Alex Johnson - Equipment Assignment | IT_Requests |
| 5 | m.thompson@techventure-it.com | IT Setup - Sarah Kim - MacBook + Security Badge | IT_Requests |
| 6 | helpdesk@techventure-it.com | New Employee Account Creation - Robert Chen | IT_Requests |
| 7 | m.thompson@techventure-it.com | Q1 2025 New Hire Batch - VPN Access and Security Training | IT_Requests |
| 8 | payroll@techventure.com | Q1 2025 Payroll Processing Cutoff Reminder | (stay in Inbox) |
| 9 | benefits@techventure.com | Open Enrollment Reminder - Benefits Window Closing | (stay in Inbox) |

## Scoring (100 points total)

| Criterion | Points | Details |
|-----------|--------|---------|
| Onboarding_Q1 folder structure (*.sbd exists) | 10 | Any variant folder name accepted |
| Documents_Pending subfolder with ≥3 emails | 20 | Partial credit: ≥2 → 13 pts, ≥1 → 6 pts, folder only → 3 pts |
| IT_Requests subfolder with ≥4 emails | 25 | Partial credit: ≥2 → 13 pts, ≥1 → 6 pts, folder only → 3 pts |
| Marcus Thompson (m.thompson@techventure-it.com) in address book | 20 | Full credit requires email match; name only → 12 pts |
| Draft reply to Marcus Thompson with new-hire keywords | 25 | Partial credit: draft found but missing keywords → 15 pts |
| **Total** | **100** | |

**Pass threshold**: 60 points

## Anti-Gaming Measures

- **Wrong-target guard**: If `Onboarding_Q1.sbd` exists but zero emails in any subfolder, score capped at 5.
- **Score cap**: If total emails moved = 0 and computed score ≥ 60, score reduced to 59.
- **Clean baseline**: `setup_task.sh` removes existing Onboarding_Q1 folder, clears Marcus Thompson from address book, removes any pre-existing drafts to m.thompson@techventure-it.com.

## Accepted Folder Name Variants

- Parent: Onboarding_Q1, Onboarding-Q1, OnboardingQ1, Onboarding_2025, Onboarding
- Subfolder 1: Documents_Pending, Documents-Pending, DocumentsPending, Pending_Docs, Outstanding_Documents, Docs_Pending
- Subfolder 2: IT_Requests, IT-Requests, ITRequests, IT_Setup, IT_Provisioning

## Files

| File | Description |
|------|-------------|
| `task.json` | Task metadata, hooks, difficulty |
| `setup_task.sh` | Clears state, injects 9 emails, records baseline, starts Thunderbird |
| `export_result.sh` | Kills Thunderbird, checks folder structure, email counts, address book, Drafts mbox |
| `verifier.py` | Scores result JSON on 5 criteria; includes 4 pipeline tests |
| `README.md` | This file |

## Testing

```bash
python3 examples/thunderbird_env/tasks/hr_onboarding_pipeline/verifier.py
```
Expected: 4/4 tests passed
