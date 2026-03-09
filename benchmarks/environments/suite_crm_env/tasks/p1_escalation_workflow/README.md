# P1 Escalation Workflow

## Overview

A Support Director at a telecommunications company must bring all support cases into compliance with escalation policy after the escalation manager left without documenting case status. Policy mandates P1 classification for large-impact outages, escalation review notes on aging P1 cases, and ownership assignment for all P1 cases.

## Domain Context

Support case escalation workflows are critical in telecommunications where outages affect thousands of customers. P1 cases represent the highest severity and require specific handling: timely triage, ownership assignment, and documented escalation reviews for aging cases.

## Goal

Review all cases in SuiteCRM and enforce company policy:
1. Any case affecting >500 users/endpoints must be P1 (High) priority
2. Every P1 case open >7 days needs '[ESCALATION REVIEW]' note in description
3. Every P1 case with status 'Open_New' must become 'Open_Assigned'
4. Do not escalate cases that don't meet the impact threshold

## Difficulty: Very Hard

The agent must:
- Read case descriptions to assess user impact (not explicitly stated as counts)
- Identify underclassified P2 cases that should be P1 based on impact analysis
- Calculate case age from date_entered fields
- Add structured escalation notes to aging P1 cases
- Distinguish high-impact cases from low-impact ones (contamination: Adobe PDF issue)

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 25 | Underclassified cases upgraded to P1 (Walmart, Cisco) |
| C2 | 25 | Stale P1 cases have '[ESCALATION REVIEW]' note |
| C3 | 20 | All P1 Open_New cases changed to Open_Assigned |
| C4 | 15 | Contamination P2 case NOT upgraded (gate) |
| C5 | 15 | No legitimate case data corrupted |

## Verification Strategy

- C1: Check priority='P1' for Walmart and Cisco case IDs
- C2: Check description contains '[ESCALATION REVIEW]' for all stale P1 IDs
- C3: Count remaining P1 Open_New cases (should be 0)
- C4: Gate - if Adobe contamination case upgraded, score capped at 50
- C5: Verify 3 specific closed cases remain unchanged

## Schema Reference

- `cases`: id, name, status, priority, type, description, account_id, date_entered, deleted
- `accounts`: id, name (linked via account_id)

## Seeded Cases

| Case | Priority | Status | Age | Issue |
|------|----------|--------|-----|-------|
| AT&T data center outage | P1 | Open_New | 14 days | Stale, needs review |
| Goldman Sachs system failure | P1 | Open_New | 10 days | Stale, needs review |
| Tesla production halt | P1 | Open_Assigned | 8 days | Stale, needs review |
| Cisco 650 locations offline | P2 | Open_New | New | Underclassified |
| Walmart report timeout (2100 users) | P2 | Open_New | Existing | Underclassified |
| Adobe PDF font issue (3 users) | P2 | Open_Assigned | New | Contamination |
