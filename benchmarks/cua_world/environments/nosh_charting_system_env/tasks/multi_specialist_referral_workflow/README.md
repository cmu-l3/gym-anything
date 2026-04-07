# multi_specialist_referral_workflow

## Overview

A complex multi-specialty coordination visit requiring the physician to chain five distinct clinical workflows: create an encounter, order two labs, place two specialty referrals, and send an internal message to a colleague. This is the most feature-diverse task in the suite, spanning encounters, lab orders, referrals, and messaging.

**Difficulty**: Very Hard
**Patient**: Malka Hartmann (PID 12, DOB: 1994-11-26, Female)
**Occupation Context**: Family Medicine Physician coordinating multi-specialty workup for complex presentation

## Goal

Coordinate multi-specialty care for Malka Hartmann (fatigue, weight gain, palpitations):
1. Create a new office visit encounter
2. Order TSH (Thyroid Stimulating Hormone) lab
3. Order CBC (Complete Blood Count) lab
4. Place Endocrinology referral for possible hypothyroidism
5. Place Cardiology referral for palpitations
6. Send internal message to Dr. Emily Brooks requesting cardiology consult

## Success Criteria

| Criterion | Points | Verification |
|-----------|--------|--------------|
| Encounter created for pid=12 | 15 | `encounters` COUNT > 0 |
| TSH lab ordered | 20 | `orders.orders_labs` LIKE '%TSH%' for pid=12 |
| CBC lab ordered | 15 | `orders.orders_labs` LIKE '%CBC%' for pid=12 |
| Endocrinology referral placed | 20 | `orders.orders_referrals` LIKE '%ENDO%' for pid=12 |
| Cardiology referral placed | 20 | `orders.orders_referrals` LIKE '%CARDIO%' for pid=12 |
| Message sent to Dr. Brooks | 10 | `messaging` from user_id=2 with subject matching 'Hartmann' or 'Cardiology' |
| **Total** | **100** | **Pass threshold: 70** |

## Verification Strategy

- **Baseline Recording**: setup_task.sh cleans encounters, orders, and matching messages for pid=12; records initial counts
- **Dr. Brooks user**: setup_task.sh ensures dr_brooks user (id=3, group_id=2) exists for messaging dropdown
- **Message verification**: Checks messaging table for message_from=2 (demo_provider) with subject matching expected keywords, sent to user_id=3
- **Lab order flexibility**: TSH matches '%TSH%' or '%THYROID STIMULATING%'; CBC matches '%CBC%' or '%COMPLETE BLOOD%'

## Do-Nothing Test

Initial state: no encounters, orders, or relevant messages for pid=12.
Do-nothing score: 0/100 -> passed=False

## Prerequisites

- Dr. Emily Brooks (user id=3) must exist as a group_id=2 provider for the messaging dropdown
- NOSH requires active encounter session (Session::get('eid')) before ordering labs
- Labs and referrals are placed within the encounter context

## Schema Reference

- `encounters`: pid, eid
- `orders`: pid, orders_labs (text), orders_referrals (text)
- `messaging`: message_from (user_id), message_to (user_id), subject, body
- `users`: id=2 (demo_provider), id=3 (dr_brooks)

## Edge Cases

- NOSH messaging dropdown only shows group_id=2 providers (not admin group_id=1)
- Agent must navigate to Messages section separately from patient chart for messaging
- Labs require active encounter; referrals may or may not require active encounter
- Multiple referrals may be stored as separate rows or combined text in orders_referrals
