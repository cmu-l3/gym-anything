# stale_pipeline_and_ticket_cleanup

## Overview

**Difficulty**: very_hard
**Occupation**: Sales Operations Manager / Customer Service Manager
**Industry**: IT Consulting / CRM Operations
**Timeout**: 720s | **Max Steps**: 90

An end-of-quarter CRM audit task. The agent must discover and remediate three categories of data quality issues without being told which records are affected: (1) stale deals with past close dates still in active stages, (2) support tickets that were incorrectly closed when they were Critical/Urgent, and (3) a missing account profile. All three require the agent to actively audit the CRM rather than follow a prescribed path.

## Domain Context

Sales Operations Managers and Customer Service Representatives (SOC importance=89, GDP=$1.1B) perform periodic CRM hygiene to ensure pipeline accuracy and SLA compliance. Stale deals inflate pipeline value, misclosed critical tickets violate SLA audit requirements, and incomplete account profiles block marketing segmentation. This task reflects a real end-of-quarter operations audit that any CRM admin would recognize.

## Goal (agent must discover all targets)

Three audit categories — agent must scan the CRM and find records matching each pattern:

1. **Pipeline cleanup**: Find ALL deals where closingdate < today AND stage is NOT Closed Won/Lost → set to Closed Lost, probability=0%

2. **Ticket reclassification**: Find ALL tickets where status='Closed' AND (severity='Critical' OR priority='Urgent') → change status to 'Resolved', prepend '[SLA-AUDIT] Reclassified from Closed to Resolved per Q1 hygiene protocol. ' to the description field

3. **Account update**: Update 'Blackstone Industrial':
   - Industry: 'Industrial Machinery & Equipment'
   - Description: 'Enterprise client specializing in industrial automation and factory systems integration.'

## Injected Errors (Ground Truth)

| Record | Injected Error |
|--------|---------------|
| Nexus SCADA Security Assessment | closingdate=2025-11-30, active stage (Closed Won stage was intact — this is a different deal now at Perception Analysis) |
| Atlas Supply Chain Analytics | closingdate=2025-09-15, active stage |
| Data breach incident response (ticket) | status=Closed, severity=Critical, priority=Urgent |
| Blackstone Industrial (account) | industry='', description='' (cleared) |

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Nexus SCADA → Closed Lost | 10 |
| Nexus SCADA probability = 0% | 7 |
| Atlas Supply Chain → Closed Lost | 11 |
| Atlas Supply Chain probability = 0% | 7 |
| No remaining Closed+Critical/Urgent tickets | 15 |
| SLA-AUDIT marker in ticket description | 12 |
| Description content includes 'Resolved' text | 8 |
| Blackstone Industrial industry set (contains Industrial+Machinery/Equipment) | 15 |
| Blackstone Industrial description set (contains industrial+automation/factory/integration) | 15 |
| **Pass threshold** | **65/100** |

## Verification Strategy

- `export_result.sh` queries: remaining stale deals count, both target deals, remaining Closed+Critical tickets, any ticket with SLA-AUDIT marker, Blackstone account
- Verifier: C1 (35 pts) + C2 (35 pts) + C3 (30 pts)
- The agent gets no record names in the description — must scan the pipeline and ticket queue
- Partial credit: 3 of 4 correct items in C1/C2 = partial; full C3 = 30 pts
- Verifier function: `verify_stale_pipeline_and_ticket_cleanup`

## DB Tables Used

- `vtiger_potential`: closingdate, sales_stage, probability (stale deal check)
- `vtiger_troubletickets`: ticketstatus, ticketseverities, ticketpriorities, description
- `vtiger_account`: accountname, industry, description

## Edge Cases

- "Today's date" is task context date (2026-03-07) — closingdate < '2026-03-07' triggers the stale check
- The ticket description prepend must use exact marker '[SLA-AUDIT]' — verifier checks LIKE '%SLA-AUDIT%'
- Industry field in Vtiger may be a dropdown; agent should find 'Industrial Machinery & Equipment' in the list or type it
- Multiple stale deals may exist (the injected 2 + any pre-existing past-date deals) — agent should close all
