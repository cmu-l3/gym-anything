# pipeline_audit_and_correction

## Overview

**Difficulty**: very_hard
**Occupation**: Sales Manager
**Industry**: IT Consulting / CRM
**Timeout**: 600s | **Max Steps**: 80

A quarterly pipeline audit task for a Sales Manager at Meridian Technology Partners. The agent must discover and fix all CRM data quality issues without being told which records are wrong — mimicking a real end-of-quarter data cleanup before a board review.

## Domain Context

Sales Managers (SOC importance=82, GDP=$301M) routinely audit their CRM pipeline for data integrity before financial reporting. Common issues include probability scores that don't match the sales stage, deals with past close dates that were never closed out, and amounts that need updating after contract revisions. These tasks require scanning all records and applying domain knowledge (stage → probability mappings) rather than being told which records to fix.

## Goal

Fix all data quality issues in the Vtiger CRM deal pipeline:

1. **Probability-stage inconsistencies**: Any deal whose probability falls outside the expected range for its stage must be corrected. Stage-to-probability mappings: Closed Won=100%, Closed Lost=0%, Negotiation/Review=70–90%, Proposal/Price Quote=40–70%, Needs Analysis=20–50%, Perception Analysis=10–30%, Qualification=20–40%, Value Proposition=30–60%.

2. **Stale deals**: Any deal with a past close date AND active stage → move to Closed Lost / probability=0%.

3. **Specific update**: Set 'Horizon 5G Network Planning' amount to $320,000.

## Injected Errors (Ground Truth)

| Deal | Injected Error |
|------|---------------|
| Nexus SCADA Security Assessment | stage=Closed Won, probability=65 (must be 100) |
| GreenLeaf IoT Factory Monitoring | stage=Needs Analysis, probability=88 (must be 20-50) |
| Atlas Supply Chain Analytics | closingdate=2025-06-30, stage=Perception Analysis (stale) |
| Catalyst LIMS Implementation | closingdate=2025-09-15, stage=Needs Analysis (stale) |

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Nexus SCADA: probability corrected to 100% | 25 |
| GreenLeaf: probability corrected to ≤50% | 20 |
| Atlas Supply Chain: Closed Lost, probability=0 | 25 |
| Catalyst LIMS: Closed Lost, probability=0 | 10 |
| Horizon 5G: amount=$320,000 | 20 |
| **Pass threshold** | **65/100** |

## Verification Strategy

- `export_result.sh` queries all 5 target deals directly by name
- `verifier.py` checks each deal independently with partial scoring
- All 4 injected errors must be discovered by the agent — no targets named in description
- Verifier function: `verify_pipeline_audit_and_correction`

## DB Tables Used

- `vtiger_potential`: `potentialname`, `sales_stage`, `probability`, `amount`, `closingdate`
- `vtiger_crmentity`: `deleted` flag (to confirm records aren't deleted)

## Edge Cases

- Agent may navigate to different deal views (list, kanban, filter)
- Stale deals check: `closingdate < current_date` AND stage NOT IN ('Closed Won','Closed Lost')
- Probability fields are stored as strings in MariaDB — cast appropriately in queries
- Agent may fix only some errors (partial credit by criterion)
