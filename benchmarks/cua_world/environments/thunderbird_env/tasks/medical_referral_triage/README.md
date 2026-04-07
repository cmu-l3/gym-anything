# Task: medical_referral_triage

## Overview

**Difficulty**: very_hard
**Environment**: thunderbird_env
**Occupation**: Practice Manager
**Industry**: Healthcare (Multi-Specialty Outpatient Clinic)

The agent acts as the Practice Manager at Oakwood Medical Group. A week's worth of patient referral emails have accumulated in the shared inbox. Some referrals are time-sensitive (marked [URGENT]) and need priority appointments within 48-72 hours; others are routine follow-up referrals. The agent must organize these by urgency, add the highest-volume referring physician to the address book, and configure a filter for future urgent referrals.

## What the Agent Must Do

1. Create a **Referrals** folder in Local Folders
2. Create **Urgent_Referrals** subfolder — move all 3 [URGENT] emails there
3. Create **Routine_Referrals** subfolder — move all 4 routine referral emails there
4. Add referring cardiologist **Dr. Patricia Nguyen** (p.nguyen@bayviewcardiology.com) to the address book
5. Create a message filter: subject contains **[URGENT]** → route to Urgent_Referrals

## Injected Emails (9 total)

| # | From | Subject | Should Go To |
|---|------|---------|-------------|
| 1 | p.nguyen@bayviewcardiology.com | [URGENT] Cardiac Referral - James Morrison | Urgent_Referrals |
| 2 | dr.patel@emergentneurology.com | [URGENT] Post-TIA Neurology Follow-up - Elena Vasquez | Urgent_Referrals |
| 3 | dr.rodriguez@coastalorthopedics.com | [URGENT] Post-Surgical Wound Concern - Robert Kim | Urgent_Referrals |
| 4 | p.nguyen@bayviewcardiology.com | Routine Cardiology Referral - Margaret Walsh | Routine_Referrals |
| 5 | dr.stevens@pacificorthopedics.com | Orthopedic Referral - Hip Assessment - Frank Torres | Routine_Referrals |
| 6 | dr.kim@dermatologywest.com | Dermatology Referral - Skin Cancer Screening - Thomas Park | Routine_Referrals |
| 7 | dr.williams@bayareaphysicaltherapy.com | PT Referral - Post-Surgical Rehabilitation - David Park | Routine_Referrals |
| 8 | billing@oakwoodmedical.com | March 2025 Insurance Verification Batch | (stay in Inbox) |
| 9 | hr@oakwoodmedical.com | Staff Schedule Update - Week of March 17 | (stay in Inbox) |

## Scoring (100 points total)

| Criterion | Points | Details |
|-----------|--------|---------|
| Referrals folder structure (Referrals.sbd exists) | 10 | Any nested folder named "Referrals" under Local Folders |
| Urgent_Referrals subfolder with ≥3 emails | 25 | Partial credit: ≥2 → 15 pts, ≥1 → 7 pts, folder only → 3 pts |
| Routine_Referrals subfolder with ≥3 emails | 20 | Partial credit: ≥2 → 12 pts, ≥1 → 5 pts, folder only → 2 pts |
| Dr. Patricia Nguyen (p.nguyen@bayviewcardiology.com) in address book | 20 | Full credit requires email match; name only → 12 pts |
| [URGENT] subject routing filter exists | 15 | Filter must reference "urgent" or "[URGENT]" |
| **Total** | **90** | (100 if bonus criteria met) |

**Pass threshold**: 60 points

## Anti-Gaming Measures

- **Wrong-target guard**: If `Referrals.sbd` exists but zero emails are in any subfolder, score is capped at 5.
- **Score cap**: If total emails moved = 0 and computed score ≥ 60, score is reduced to 59.
- **Clean baseline**: `setup_task.sh` removes existing Referrals folder, clears Dr. Nguyen from address book, resets filter rules.

## Accepted Folder Name Variants

- Urgent_Referrals, Urgent-Referrals, UrgentReferrals, Urgent_Cases, Urgent
- Routine_Referrals, Routine-Referrals, RoutineReferrals, Standard_Referrals, Routine

## Files

| File | Description |
|------|-------------|
| `task.json` | Task metadata, hooks, difficulty |
| `setup_task.sh` | Clears state, injects 9 emails, records baseline, starts Thunderbird |
| `export_result.sh` | Kills Thunderbird, checks folder structure, email counts, address book, filter rules |
| `verifier.py` | Scores result JSON on 5 criteria; includes 4 pipeline tests |
| `README.md` | This file |

## Testing

```bash
python3 examples/thunderbird_env/tasks/medical_referral_triage/verifier.py
```
Expected: 4/4 tests passed
