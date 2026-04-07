# comprehensive_chronic_disease_visit

## Overview

A quarterly diabetes management visit requiring the provider to complete four distinct clinical workflows in a single encounter: create an encounter, order labs, place a specialty referral, and add a medication.

**Difficulty**: Very Hard
**Patient**: Kelle Crist (PID 9, DOB: 2002-10-18, Female)
**Occupation Context**: Family Medicine Physician performing routine chronic disease management

## Goal

Complete a comprehensive quarterly diabetes visit for Kelle Crist by:
1. Creating a new office visit encounter
2. Ordering HbA1c and CMP laboratory tests
3. Placing an Endocrinology referral for uncontrolled T2DM
4. Adding Metformin 500mg to the active medication list

## Success Criteria

| Criterion | Points | Verification |
|-----------|--------|--------------|
| Encounter created for pid=9 | 20 | `encounters` table COUNT > baseline |
| HbA1c lab ordered | 20 | `orders.orders_labs` LIKE '%A1C%' for pid=9 |
| CMP lab ordered | 15 | `orders.orders_labs` LIKE '%CMP%' or '%METABOLIC%' for pid=9 |
| Endocrinology referral placed | 25 | `orders.orders_referrals` LIKE '%ENDO%' for pid=9 |
| Metformin added as active medication | 20 | `rx_list` with Metformin active for pid=9 |
| **Total** | **100** | **Pass threshold: 70** |

## Verification Strategy

- **Baseline Recording**: setup_task.sh records initial encounter/order/rx counts to `/tmp/ccdv_init_*.txt`
- **Export**: export_result.sh queries MariaDB for all criteria, writes `/tmp/comprehensive_chronic_disease_visit_result.json`
- **Verifier**: Reads JSON via `copy_from_env`, applies multi-criterion scoring
- **Wrong-target rejection**: All DB queries filter by pid=9; actions on other patients yield score=0

## Do-Nothing Test

Initial state: no encounters, orders, or Metformin for pid=9 (all cleaned by setup).
Do-nothing score: 0/100 -> passed=False

## Schema Reference

- `encounters`: pid, eid (auto-increment), encounter_date
- `orders`: pid, orders_labs (text), orders_referrals (text)
- `rx_list`: pid, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_date_inactive

## Edge Cases

- Agent may type "Hemoglobin A1c" or "HbA1c" or "A1C" — export uses broad LIKE patterns
- Agent may type "Comprehensive Metabolic Panel" or "CMP" — both accepted
- NOSH requires active encounter session before ordering labs (Session::get('eid'))
- Metformin must remain active (rxl_date_inactive IS NULL or empty)
