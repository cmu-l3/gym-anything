# lost_deal_reactivation_and_contact_fix

## Overview

**Difficulty**: hard
**Occupation**: Sales Manager
**Industry**: IT Consulting / Industrial CRM
**Timeout**: 600s | **Max Steps**: 75

A deal reactivation and contact data remediation task. The IronShield Network Hardening deal was accidentally marked Closed Lost, two key contacts are missing critical fields, and a follow-up call must be scheduled. Three independent subtasks across three CRM modules.

## Domain Context

Sales Managers (SOC importance=82, GDP=$301M) handle deal reactivation when a deal is incorrectly closed — typically caused by data entry error or premature stage progression. This requires: updating the deal stage back to active, correcting the amount and close date, fixing incomplete contact records that block outreach campaigns, and scheduling the follow-up call. All three are standard CRM remediation workflows that real sales teams perform weekly.

## Goal

Three subtasks (targeted — the description names the exact records to fix):

1. **Reactivate deal** 'IronShield Network Hardening':
   - Stage → Value Proposition
   - Probability → 55%
   - Close Date → 2026-08-31
   - Amount → $198,500

2. **Fix contact records**:
   - Victoria Blackwell: add email victoria.blackwell@blackstone-industrial.com, title = Director of IT Security
   - Thomas Park: add phone +1-312-555-0847, title = VP of Operations

3. **Schedule follow-up call**:
   - Subject: 'Blackstone Industrial IronShield Reactivation Call'
   - Type: Call, Date: 2026-03-18, Start: 14:00, End: 15:00, Status: Planned

## Setup Corruption

The setup script injects the following state before the agent starts:
- IronShield deal: stage=Closed Lost, probability=0, amount=$175,000, closedate=2025-12-31
- Victoria Blackwell: email='' (cleared), title='' (cleared)
- Thomas Park: phone='' (cleared), title='' (cleared)
- Any pre-existing IronShield reactivation call events are deleted

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Deal stage = Value Proposition | 12 |
| Deal probability = 55% | 10 |
| Deal amount = $198,500 | 10 |
| Deal closedate = 2026-08-31 | 8 |
| Victoria Blackwell email set (correct domain) | 9 |
| Victoria Blackwell title = Director of IT Security | 6 |
| Thomas Park phone set (+1-312-555-0847) | 9 |
| Thomas Park title = VP of Operations | 6 |
| Call event found (IronShield in subject) | 8 |
| Call date = 2026-03-18 | 8 |
| Call start = 14:00 | 7 |
| Call type = Call | 7 |
| **Pass threshold** | **65/100** |

## Verification Strategy

- `export_result.sh` queries deal by name, contacts by firstname+lastname, call by subject LIKE
- Partial credit per subtask — passing at 65 means completing any 2 of 3 subtasks fully
- Phone normalization: strip non-digits for comparison (13125550847)
- Verifier function: `verify_lost_deal_reactivation_and_contact_fix`

## DB Tables Used

- `vtiger_potential`: potentialname, sales_stage, probability, amount, closingdate
- `vtiger_contactdetails`: firstname, lastname, email, phone, title
- `vtiger_activity`: subject, activitytype, date_start, time_start, time_end, status

## Edge Cases

- Deal amount $198,500 — check within ±$500 tolerance
- Phone may be entered in various formats (+1-312-555-0847 or 312-555-0847); normalize to digits
- Call event query uses LIKE '%IronShield%Reactivation%' OR '%Blackstone%IronShield%'
- Agent may need to know that Vtiger has separate fields for work phone/mobile phone — either is acceptable
