# Cross-Module Integrity Audit

## Overview

A Data Governance Manager at a management consulting firm must investigate and correct cross-module data integrity violations in SuiteCRM uncovered by a security audit. Issues span account type classifications, orphaned contacts, and misattributed contact-account relationships.

## Domain Context

CRM data integrity across modules is essential for regulatory reporting and client communications. Account types must reflect business relationships (Customer = has won business), contacts must link to existing accounts, and contact email domains should match their assigned account.

## Goal

Audit and fix all integrity violations:
1. Account types that contradict opportunity history (Customer type without Closed Won deals, or non-Customer type with Closed Won deals)
2. Contacts linked to non-existent or deleted accounts (orphans)
3. Contacts whose email domain contradicts their account assignment
4. Preserve Partner/Competitor account types that accurately reflect real-world relationships

## Difficulty: Very Hard

The agent must:
- Cross-reference account types against opportunity stages across modules
- Identify orphaned contacts by checking if their account_id references a valid account
- Use email domain, job title, and description as context clues for correct account assignment
- Understand that Partner (Adobe) and Competitor (Salesforce) types are intentional regardless of opportunity history

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 20 | Apple type corrected to Customer (has Closed Won deal) |
| C2 | 20 | Meta and ExxonMobil types corrected from Customer |
| C3 | 20 | Orphan contacts reassigned to correct accounts |
| C4 | 20 | James Chen reassigned back to Apple |
| C5 | 20 | Adobe Partner and Salesforce Competitor types preserved (gate) |

## Verification Strategy

- C1: Check Apple account_type = 'Customer'
- C2: Check Meta and ExxonMobil account_type != 'Customer'
- C3: Check orphan contact account_ids match expected accounts (Alphabet, Amazon)
- C4: Check James Chen's account_id matches Apple
- C5: Gate - if Adobe or Salesforce types changed, score capped at 50

## Schema Reference

- `accounts`: id, name, account_type, deleted
- `contacts`: id, first_name, last_name, email1, account_id, description, deleted
- `opportunities`: id, name, sales_stage, account_id, deleted

## Seeded Violations

| Entity | Issue | Expected Fix |
|--------|-------|-------------|
| Apple Inc. | Type='Prospect' but has Closed Won opp | Change to Customer |
| Meta Platforms Inc. | Type='Customer' but no Closed Won opp | Change to non-Customer |
| ExxonMobil Corporation | Type='Customer' but no Closed Won opp | Change to non-Customer |
| Victor Huang | account_id = fake UUID, email @abc.xyz | Reassign to Alphabet Inc. |
| Laura Fischer | Account soft-deleted, email @amazon.com | Reassign to Amazon.com Inc. |
| James Chen | Moved from Apple to Microsoft | Reassign back to Apple |
| Adobe Inc. | Type='Partner' | Do NOT change |
| Salesforce Inc. | Type='Competitor' | Do NOT change |
