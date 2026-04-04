# Stale Pipeline Cleanup

## Overview

A newly appointed VP of Sales at a financial services technology firm must clean up CRM pipeline data quality issues ahead of an investor presentation. Multiple opportunities have internally contradictory data: stale close dates, mismatched probabilities, and impossible Closed Won records.

## Domain Context

Sales pipeline hygiene is essential for accurate forecasting. Standard CRM conventions dictate that each sales stage has a corresponding probability percentage, stale deals should be closed out, and Closed Won deals must have past close dates.

## Goal

Bring every opportunity record into internal consistency:
- Move stale deals (close date >60 days past, still in active stage) to Closed Lost
- Align each opportunity's probability to match its sales stage
- Fix the Closed Won deal that has a future close date
- Do not alter opportunities whose data is already consistent

## Difficulty: Very Hard

The agent must:
- Understand SuiteCRM's stage-to-probability mapping conventions
- Calculate which deals are stale based on close dates vs current date
- Identify probability mismatches across all opportunities
- Recognize the contamination case (GE Aviation with 100% probability at Needs Analysis)

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 25 | Stale deals (ExxonMobil, J&J) moved to Closed Lost |
| C2 | 25 | Probability corrected for NVIDIA, AT&T, Goldman Sachs |
| C3 | 20 | Future Closed Won (Apple ML) date fixed |
| C4 | 15 | GE Aviation probability corrected (100 -> 25) |
| C5 | 15 | Legitimate closed opportunities unchanged (gate) |

## Verification Strategy

- C1: Check sales_stage = 'Closed Lost' for stale deal IDs
- C2: Check probability matches expected value for each stage
- C3: Check Closed Won date is in the past
- C4: Check GE Aviation probability corrected
- C5: Gate - verify 6 legitimate closed deals unchanged; if violated, score capped at 50

## Schema Reference

- `opportunities`: id, name, amount, sales_stage, probability, date_closed, account_id, deleted

## Stage-Probability Mapping

| Stage | Probability |
|-------|-------------|
| Prospecting | 10% |
| Qualification | 20% |
| Needs Analysis | 25% |
| Value Proposition | 30% |
| Id. Decision Makers | 40% |
| Perception Analysis | 50% |
| Proposal/Price Quote | 65% |
| Negotiation/Review | 80% |
| Closed Won | 100% |
| Closed Lost | 0% |
