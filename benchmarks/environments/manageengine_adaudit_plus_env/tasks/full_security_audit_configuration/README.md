# Task: Full Security Audit Configuration & Threat Assessment

## Overview

A fresh ADAudit Plus deployment requires complete enterprise configuration AND active incident response. The agent must simultaneously investigate an ongoing attack (multiple failed logon sources, file access activity) while configuring the tool for long-term use. This task requires the agent to synthesize information from multiple ADAudit Plus report categories and take coordinated action.

## Domain Context

This task reflects the work of **Security Operations Center (SOC) Analysts** and **IT Auditors** performing an initial deployment hardening exercise. Industry surveys (SANS 2023 SOC Survey) show that 71% of SOC teams encounter active incidents during tool deployment, requiring concurrent investigation and configuration work.

## Goal

By the end of this task, the following must all be true:

1. **Technician account `security_ops`** exists with Operator role.

2. **An email notification** configured with threshold-based alerting (for failed logon events).

3. **A scheduled daily report** named 'Security Summary' (or similar containing "security" and "summary"/"daily").

4. **A threat assessment file** at `C:\Users\Docker\Desktop\threat_assessment.txt` that:
   - Names `bruteforce1` as the primary threat account (most failed logons)
   - Contains analysis of suspicious activity
   - Is at least 300 characters (substantive report)

## Starting State

The setup script generates a realistic incident scenario:
- `bruteforce1` generates 25 failed logon attempts (clear primary threat)
- `testattacker` generates 8 failed logon attempts (secondary threat)
- `wrongadmin` generates 5 failed logon attempts (noise/secondary)
- `jsmith` accesses files in `C:\AuditTestFolder\Confidential\` (file access events)
- `mjohnson` successfully logs in multiple times (normal activity for contrast)

The agent must navigate multiple ADAudit Plus report sections to build a complete picture before writing the assessment.

## Scoring (100 points total)

| Criterion | Points |
|-----------|--------|
| Technician `security_ops` created with Operator role | 20 pts |
| Email notification configured | 15 pts |
| Scheduled 'Security Summary' daily report exists | 20 pts |
| Threat assessment file exists and modified after task start | 10 pts |
| Assessment file mentions `bruteforce1` (primary threat) | 20 pts |
| Assessment file is substantial (≥300 chars) | 15 pts |

**Pass threshold: 60 points**

## Verification Strategy

1. **Technician**: DB query for `security_ops` username and role.
2. **Notification**: DB query for notification profiles / email alert configuration.
3. **Scheduled report**: DB query for report schedules containing 'security' and 'summary'/'daily'.
4. **Assessment file**: File existence, modification timestamp, content analysis for target accounts.

## Data Reference

- Windows Event ID 4625: Failed logon
- Windows Event ID 4634: File access (combined with object access auditing)
- ADAudit Plus captures via Windows Security event log subscription
- Relevant sections: Reports > Logon Activity > Failed Logons, Reports > File Audit

## Edge Cases

- The notification check uses broad matching (any non-empty notification email with threshold-like setting)
- 'Security Summary' matching is flexible — "security" AND ("summary" OR "daily") in report name
- Primary threat identification: `bruteforce1` must appear in the assessment file (case-insensitive)
- File size check uses both content length and file size for robustness
