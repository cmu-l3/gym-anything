# client_onboarding_full_setup

## Overview

**Difficulty**: hard
**Occupation**: Sales Representative / Account Manager
**Industry**: IT Consulting / Defense Aerospace CRM
**Timeout**: 720s | **Max Steps**: 90

A new enterprise client (ClearSky Aerospace Technologies) has signed a contract. The agent must complete the full CRM onboarding workflow: create the organization, create two contacts linked to it, create the deal, and schedule the kickoff meeting. Four independent subtasks across four CRM modules.

## Domain Context

Sales Representatives (SOC importance=77, GDP=$277M) handle new client onboarding by creating all relevant records in the CRM. A full onboarding requires: (1) creating the org account, (2) adding decision-maker contacts linked to that org, (3) opening the initial deal opportunity, and (4) scheduling the kickoff call. This is a realistic 4-step onboarding workflow that requires all modules of the CRM.

## Goal

Four sequential subtasks (each independent for scoring):

1. **Create Organization**: ClearSky Aerospace Technologies — Dulles VA, 900 employees, $180M revenue, aerospace industry, phone 703-555-2000, website clearsky-aero.com

2. **Create Two Contacts** linked to ClearSky:
   - Harrison Yates (VP of Technology): harrison.yates@clearsky-aero.com, 703-555-2001
   - Priya Natarajan (Director of IT Security): priya.natarajan@clearsky-aero.com, 703-555-2002

3. **Create Deal** linked to ClearSky:
   - Name: 'ClearSky Zero-Trust Security Implementation'
   - Amount: $425,000, Stage: Needs Analysis, Probability: 40%, Close: 2026-10-31

4. **Schedule Kickoff Meeting**:
   - Subject: 'ClearSky Aerospace - Onboarding Kickoff'
   - Date: 2026-03-20, Start: 10:00, End: 11:00, Status: Planned

## Setup State

The setup script cleans up any pre-existing ClearSky records (org, contacts, deal, events) and records baseline counts. The agent starts at the Organizations list.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Organization created (name exists) | 5 |
| Org: phone set | 4 |
| Org: website set (contains clearsky/aerospace) | 4 |
| Org: employees ~900 | 4 |
| Org: city=Dulles or state=VA | 4 |
| Org: revenue ~$180M | 4 |
| Harrison Yates created + email + phone + title + linked | 12 |
| Priya Natarajan created + email + phone + title + linked | 13 |
| Deal created (name exists) | 5 |
| Deal: amount=$425K | 8 |
| Deal: stage=Needs Analysis | 7 |
| Deal: probability=40% | 5 |
| Deal: closedate=2026-10-31 | 5 |
| Meeting created (ClearSky in subject) | 5 |
| Meeting: date=2026-03-20 | 6 |
| Meeting: start=10:00 | 5 |
| Meeting: type=Meeting | 4 |
| **Pass threshold** | **70/100** |

## Verification Strategy

- `export_result.sh` queries org by name, contacts by firstname+lastname, deal by name, event by subject LIKE
- Contact-org linkage verified via `vtiger_contactdetails.account_id`
- Partial credit per subtask — an agent that completes 3 of 4 subtasks can pass
- Verifier function: `verify_client_onboarding_full_setup`

## DB Tables Used

- `vtiger_account` + `vtiger_accountbillads`: org name, phone, website, employees, revenue, city, state
- `vtiger_contactdetails`: firstname, lastname, email, phone, title, account_id (linkage)
- `vtiger_potential`: potentialname, amount, sales_stage, probability, closingdate
- `vtiger_activity`: subject, activitytype, date_start, time_start

## Edge Cases

- Contact linkage requires the contact's `account_id` to point to ClearSky's `accountid` — agent must link during contact creation or edit afterward
- Deal amount $425,000 may be entered as 425000 or 425,000 — strip commas in export
- Meeting subject check is loose (LIKE '%ClearSky%Kickoff%' OR '%ClearSky%Onboarding%') to allow minor agent variation
