# Pipeline Discrepancy Audit

## Overview

A CFO at a healthcare IT company discovers that the SuiteCRM opportunity pipeline total is significantly inflated compared to the validated quarterly forecast. The agent must investigate the entire pipeline, identify duplicate entries and inflated amounts, and correct all discrepancies without removing legitimate new business.

## Domain Context

Sales pipeline integrity is critical for accurate revenue forecasting. CRM systems frequently accumulate duplicate records from data imports, partner channel submissions, and legacy system migrations. Finance teams rely on pipeline totals for investor presentations and board reporting.

## Goal

Bring the active opportunity pipeline into alignment with the audited forecast (~$19.74M) by:
- Removing all duplicate opportunity records
- Correcting inflated opportunity amounts to their true values
- Preserving all legitimate opportunities (including recently-added ones)

## Difficulty: Very Hard

The agent must:
- Discover which opportunities are duplicates by comparing names, accounts, and descriptions
- Distinguish duplicates from legitimate similarly-named opportunities
- Identify which amounts are inflated and determine correct values
- Avoid deleting the contamination opportunity (Deloitte - Digital Transformation Advisory)

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 25 | All 4 duplicate opportunities removed |
| C2 | 20 | AT&T opportunity amount corrected to ~$2.1M |
| C3 | 20 | Tesla opportunity amount corrected to ~$3.8M |
| C4 | 20 | Contamination opportunity NOT deleted (gate) |
| C5 | 15 | All original legitimate opportunities preserved |

## Verification Strategy

- C1: Check each injected duplicate ID exists with `deleted=0`
- C2/C3: Query amount fields and compare to expected values (tolerance $100K)
- C4: Gate check - if contamination opp deleted, score capped at 40
- C5: Query all 14 original opportunity names for existence

## Schema Reference

- `opportunities`: id, name, amount, sales_stage, probability, date_closed, account_id, deleted
- `accounts`: id, name (linked via account_id)

## Edge Cases

- "Deloitte - Digital Transformation Advisory" looks like it could be a duplicate but is a legitimate new opportunity
- Duplicate names are slight variations (e.g., "Boeing - Supply Chain Analytics Platform" vs "Boeing - Avionics Test Automation") but tied to the same account
