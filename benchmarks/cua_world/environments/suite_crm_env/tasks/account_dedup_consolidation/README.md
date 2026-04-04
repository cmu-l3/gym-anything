# Account Deduplication and Consolidation

## Overview

A CRM Administrator at an aerospace manufacturing company must clean up duplicate account records introduced by a botched data migration from a legacy ERP system. Duplicate accounts have their own contacts, opportunities, and cases that must be reassigned to the canonical account before the duplicates are deleted.

## Domain Context

Account deduplication is one of the most common and complex CRM maintenance tasks. Data migrations, partner channel imports, and manual entry create duplicate records with slight name variations. Failing to consolidate properly can orphan contacts, lose opportunity history, and fragment case management.

## Goal

- Identify all duplicate account records (name variations of existing accounts)
- Reassign all contacts, opportunities, and cases from duplicates to canonical accounts
- Delete the duplicate account records
- Preserve all genuinely distinct accounts (including similarly-named ones like "Johnson Controls International" vs "Johnson & Johnson")

## Difficulty: Very Hard

The agent must:
- Recognize name variations across 20+ accounts (e.g., "Boeing Co." vs "Boeing Company")
- Determine which is the canonical record vs the duplicate
- Reassign related records across 3 different modules (Contacts, Opportunities, Cases)
- Distinguish "Johnson Controls International" from "Johnson & Johnson" (different companies)

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 20 | Boeing duplicate accounts deleted |
| C2 | 20 | GE duplicate accounts deleted |
| C3 | 20 | Contacts reassigned to canonical accounts |
| C4 | 20 | Opportunities and cases reassigned |
| C5 | 20 | Contamination account preserved + originals intact (gate) |

## Verification Strategy

- C1/C2: Check duplicate account IDs no longer exist with deleted=0
- C3: Check contact account_id matches canonical account
- C4: Check opportunity/case account_id matches canonical account
- C5: Gate - verify Johnson Controls, canonical Boeing/GE, and J&J still exist

## Schema Reference

- `accounts`: id, name, account_type, industry, deleted
- `contacts`: id, first_name, last_name, account_id, deleted
- `opportunities`: id, name, account_id, deleted
- `cases`: id, name, account_id, deleted

## Seeded Duplicates

| Canonical | Duplicate 1 | Duplicate 2 |
|-----------|------------|------------|
| Boeing Company | Boeing Co. | The Boeing Company |
| General Electric Company | GE Company | General Electric Co |
