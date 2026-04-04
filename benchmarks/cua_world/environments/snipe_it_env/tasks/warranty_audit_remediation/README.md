# Task: warranty_audit_remediation

## Occupation Context
**Role:** IT Compliance Officer
**Industry:** Financial Services

## Task Description
Conduct a quarterly warranty audit in Snipe-IT. The agent must identify all hardware assets with expired warranties (purchase date + warranty months < 2025-03-06), change their status to "Pending", and add a compliance note. Assets that are already retired or marked as lost/stolen must not be modified. Assets with active warranties must not be touched.

## Difficulty: very_hard
- Agent must calculate warranty expiration from purchase_date + warranty_months
- Must navigate across multiple asset pages
- Must discriminate between expired vs active warranties
- Must avoid modifying retired/archived assets
- No UI path provided — goal only

## Verification Criteria (100 points)
1. C1 (30 pts): All 4 expired-warranty injected assets changed to Pending status
2. C2 (20 pts): All 4 expired-warranty assets have "WARRANTY EXPIRED" in notes
3. C3 (20 pts): Active-warranty asset ASSET-W004 not modified
4. C4 (15 pts): No false positives (active-warranty assets left unchanged)
5. C5 (15 pts): Retired asset ASSET-L010 not modified

## Data Seeding
Setup injects 5 new assets with varying warranty periods:
- ASSET-W001: Expired (2022-01-15 + 24m = 2024-01-15)
- ASSET-W002: Expired (2021-06-01 + 36m = 2024-06-01)
- ASSET-W003: Expired (2023-02-20 + 12m = 2024-02-20)
- ASSET-W004: Active  (2024-09-01 + 36m = 2027-09-01)
- ASSET-W005: Expired (2023-03-10 + 18m = 2024-09-10)
