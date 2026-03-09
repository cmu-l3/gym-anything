# Task: Multi-Role Access Governance Investigation

## Overview

A Windows security incident has occurred: unauthorized privilege escalations were detected. Multiple local user accounts were added to sensitive Windows security groups without following the change management process. Your governance team must investigate using ADAudit Plus, establish governance infrastructure, and document the findings.

## Domain Context

This task reflects the real workflow of **IT Auditors** and **Compliance Officers** who use ADAudit Plus to investigate unauthorized group membership changes — one of the most common insider threat indicators. The Ponemon Institute reports that 63% of insider threat incidents involve privilege escalation via group membership manipulation.

## Goal

By the end of this task, the following must be true:

1. **Three governance technician accounts** must exist in ADAudit Plus:
   - `gov_lead` with Auditor role
   - `risk_analyst` with Operator role
   - `change_manager` with Operator role

2. **A scheduled weekly report** named 'Group Membership Changes Weekly' must be configured.

3. **A governance audit text file** at `C:\Users\Docker\Desktop\governance_audit.txt` must:
   - List the specific user accounts that were added to privileged groups
   - Identify which groups they were added to
   - Include remediation recommendations

## Starting State

The setup script generates unauthorized group membership changes:
- `jsmith` is added to the `Administrators` group
- `abrown` is added to the `Security_Team` group
- These events are captured in the Windows Security event log

The agent must navigate to the appropriate ADAudit Plus report section to discover these changes before documenting them.

## Scoring (100 points total)

| Criterion | Points |
|-----------|--------|
| Technician `gov_lead` created with Auditor role | 15 pts |
| Technician `risk_analyst` created with Operator role | 10 pts |
| Technician `change_manager` created with Operator role | 10 pts |
| Scheduled report 'Group Membership Changes Weekly' exists | 20 pts |
| Governance audit file exists and was modified after task start | 15 pts |
| Audit file mentions `jsmith` (correct target) | 15 pts |
| Audit file mentions `abrown` (correct target) | 15 pts |

**Pass threshold: 60 points**

## Verification Strategy

1. **Technician existence**: PowerShell export script queries the ADAudit Plus PostgreSQL database for each technician username and role.
2. **Scheduled report**: Queries DB for report name containing 'Group Membership' or 'Weekly'.
3. **Audit file content**: Reads `C:\Users\Docker\Desktop\governance_audit.txt`, checks for target usernames (`jsmith`, `abrown`) and modification timestamp after task start.

## Data Reference

- Windows Security Event ID 4732: A member was added to a security-enabled local group
- ADAudit Plus captures these via its Windows event collection agent
- Relevant ADAudit Plus report path: Reports > Local Logon Activity > Local Groups

## Edge Cases

- The file content check uses case-insensitive substring search for usernames
- Partial credit is awarded for getting some but not all technicians
- The report name matching is flexible (substring match on 'group membership' or 'weekly')
