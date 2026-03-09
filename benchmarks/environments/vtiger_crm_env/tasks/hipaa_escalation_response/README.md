# hipaa_escalation_response

## Overview

**Difficulty**: hard
**Occupation**: Customer Service Manager / Compliance Officer
**Industry**: IT Consulting / Healthcare CRM
**Timeout**: 540s | **Max Steps**: 70

A compliance emergency response task. A HIPAA audit finding has been miscategorized as low-priority. The agent must escalate the ticket, update the associated deal to reflect the compliance impact, and schedule an emergency remediation meeting.

## Domain Context

Customer Service Representatives (SOC importance=89, GDP=$1.1B) handle escalation of critical support tickets. In healthcare IT, HIPAA compliance issues must be escalated immediately to Critical/Urgent status and tracked through the CRM deal pipeline. This task tests the agent's ability to execute three correlated subtasks across three different CRM modules (Tickets, Deals, Calendar) without being given UI navigation paths.

## Goal

Three independent subtasks, all required:

1. **Ticket escalation**: Find ticket 'HIPAA audit finding - unencrypted backups' and update:
   - Priority → Urgent
   - Severity → Critical
   - Status → In Progress

2. **Deal update**: Find deal 'Pinnacle EHR Security Upgrade' and update:
   - Sales Stage → Negotiation/Review
   - Probability → 75%
   - Close Date → 2026-05-31

3. **Emergency meeting**: Create a Meeting event:
   - Subject: 'HIPAA Emergency Remediation - Pinnacle Healthcare'
   - Date: 2026-03-15, Start: 09:00, End: 11:00
   - Status: Planned, Location: Video Conference - Zoom

## Setup Corruption

The setup script deliberately miscategorizes these records before the agent starts:
- Ticket is set to Normal priority / Minor severity / Open status
- Deal is downgraded to Qualification stage, probability=30, closedate=2026-07-30
- Any pre-existing HIPAA emergency events are deleted

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Ticket priority=Urgent | 12 |
| Ticket severity=Critical | 12 |
| Ticket status=In Progress | 11 |
| Deal stage=Negotiation/Review | 12 |
| Deal probability=75 | 12 |
| Deal closedate=2026-05-31 | 11 |
| Meeting found (HIPAA+Pinnacle in subject) | 10 |
| Meeting date=2026-03-15 | 8 |
| Meeting start=09:00 | 7 |
| Meeting type=Meeting | 5 |
| **Pass threshold** | **70/100** |

## Verification Strategy

- `export_result.sh` queries ticket by title LIKE, deal by name, event by subject LIKE
- `verifier.py`: C1 (35 pts) + C2 (35 pts) + C3 (30 pts)
- Partial credit per subtask — passing with 70 requires completing at least 2 of 3 fully
- Verifier function: `verify_hipaa_escalation_response`

## DB Tables Used

- `vtiger_troubletickets`: `ticket_title`, `ticketstatus`, `ticketseverities`, `ticketpriorities`
- `vtiger_potential`: `potentialname`, `sales_stage`, `probability`, `closingdate`
- `vtiger_activity`: `subject`, `activitytype`, `date_start`, `time_start`, `time_end`, `status`
- `vtiger_account`: linked to Pinnacle Healthcare Systems

## Edge Cases

- Agent may spell meeting subject slightly differently — verifier uses LIKE '%HIPAA%Pinnacle%' OR '%HIPAA%Emergency%'
- Ticket fields (priority/severity) use Vtiger's enum values: 'Urgent', 'Critical', 'In Progress'
- Deal stage must match exactly: 'Negotiation/Review'
