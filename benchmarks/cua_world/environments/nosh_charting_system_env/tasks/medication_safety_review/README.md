# medication_safety_review

## Overview

A medication safety review task using the **contamination-injection** design pattern. Setup seeds three medications into the patient's chart — one medically necessary anticoagulant (Warfarin) and two contraindicated drugs (Aspirin, Ibuprofen). The agent must identify which medications are dangerous in combination with Warfarin, discontinue them without touching the Warfarin, order monitoring labs, and document the review.

**Difficulty**: Very Hard
**Patient**: Cordie King (PID 13, DOB: 1995-03-11, Female)
**Occupation Context**: Clinical Pharmacist performing medication safety audit and drug interaction remediation

## Goal

Review and correct the medication list for Cordie King:
1. Identify and discontinue Aspirin 325mg (antiplatelet — bleeding risk with Warfarin)
2. Identify and discontinue Ibuprofen 600mg (NSAID — bleeding risk with Warfarin)
3. Retain Warfarin 5mg as active (medically necessary anticoagulant)
4. Order INR (International Normalized Ratio) lab for anticoagulation monitoring
5. Create an encounter documenting the medication safety review

## Seeded State (Contamination-Injection Pattern)

setup_task.sh seeds three active medications for pid=13:
| Medication | Dosage | Status | Agent Action Required |
|-----------|--------|--------|----------------------|
| Warfarin | 5mg daily | Active | **Keep active** (anticoagulant) |
| Aspirin | 325mg daily | Active | **Discontinue** (antiplatelet + Warfarin = bleeding risk) |
| Ibuprofen | 600mg TID | Active | **Discontinue** (NSAID + Warfarin = bleeding risk) |

## Success Criteria

| Criterion | Points | Verification |
|-----------|--------|--------------|
| Aspirin discontinued | 25 | `rx_list` Aspirin with rxl_date_inactive set |
| Ibuprofen discontinued | 25 | `rx_list` Ibuprofen with rxl_date_inactive set |
| Warfarin still active (anti-gaming) | 30 | `rx_list` Warfarin with rxl_date_inactive NULL |
| INR lab ordered | 10 | `orders.orders_labs` LIKE '%INR%' or '%PROTHROMBIN%' |
| Encounter created | 10 | `encounters` COUNT > 0 for pid=13 |
| **Total** | **100** | **Pass threshold: 75** |

## Anti-Gaming Analysis

The Warfarin retention criterion (30 pts) is designed to prevent gaming by mass-discontinuation:

| Scenario | Score | Passed? |
|----------|-------|---------|
| **Do-nothing** (all seeded meds active, no labs/encounter) | 30 | No (< 75) |
| **Mass-discontinue all** (including Warfarin) + INR + encounter | 70 | No (< 75) |
| **Correct** (discontinue Aspirin + Ibuprofen, keep Warfarin) + INR + encounter | 100 | Yes |
| **Partial** (only Aspirin discontinued, Warfarin kept, no labs) | 55 | No (< 75) |

## Verification Strategy

- **Baseline Recording**: setup_task.sh records Warfarin rxl_id and initial rx count to `/tmp/msr_*.txt`
- **Discontinuation check**: rxl_date_inactive IS NOT NULL AND != '' AND != '0000-00-00'
- **Active check**: rxl_date_inactive IS NULL OR = '' OR = '0000-00-00'
- **INR flexibility**: Matches '%INR%', '%PROTHROMBIN%', '%PT %', '% PT%', '%COAG%'

## Do-Nothing Test

Initial state: Warfarin active (30 pts from Warfarin-still-active criterion), no labs, no encounters.
Do-nothing score: 30/100 -> passed=False (threshold 75)

## Schema Reference

- `rx_list`: pid, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_date_active, rxl_date_inactive
- `orders`: pid, orders_labs (text)
- `encounters`: pid, eid

## Edge Cases

- Agent must NOT discontinue Warfarin — the task description explicitly states this
- Agent may need to create an encounter before ordering INR lab (NOSH requires active encounter session)
- Discontinuation in NOSH sets rxl_date_inactive to current date
- Some agents may attempt to "replace" medications rather than discontinue — the verifier checks for discontinuation specifically
