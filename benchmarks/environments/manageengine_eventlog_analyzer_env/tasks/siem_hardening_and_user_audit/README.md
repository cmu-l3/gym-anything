# Task: siem_hardening_and_user_audit

## Domain Context

Security Management Specialists (onet_importance=83) are responsible for ensuring that the SIEM itself is properly hardened. Over-privileged accounts and misconfigured alert severities are common findings in SIEM audits. Remediating these issues — access control review, role right-sizing, and alert severity correction — is a standard part of SOC governance and security posture management.

## Task Overview

The setup script creates two contractor accounts with excessive Admin privileges and seeds two alert profiles with incorrect Warning severity. The agent must identify and fix these misconfigurations, create a new analyst account, and document all changes.

## Starting State

The setup script creates the following via the ELA REST API:
- **Technician `contractor01`** with Administrator role (should be Operator)
- **Technician `it-support`** with Administrator role (should be Operator)
- **Alert `SSH Brute Force - Warning`** with Warning severity (should be Critical)
- **Alert `Failed Auth Monitor`** with Warning severity (should be Critical)

## What the Agent Must Do

1. **User Audit & Remediation** (feature: Settings > Technicians & Roles): Find and downgrade both `contractor01` and `it-support` from Admin to Operator role.

2. **New User Creation** (feature: Technicians creation): Create `soc-analyst-02` as an Operator.

3. **Alert Severity Fix** (feature: Alert Profiles editing): Find the 2 Warning-severity alerts that should be Critical and update them.

4. **Documentation** (feature: File creation): Write `~/Desktop/hardening_report.txt` listing all changes made.

## Verification Strategy

| Criterion | Points | Method |
|-----------|--------|--------|
| Hardening report file created after task start | 15 | File mtime |
| contractor01 and/or it-support role changed to Operator | 30 | DB query on technician tables |
| New user soc-analyst-02 created | 25 | DB query on technician tables |
| Report mentions contractor01 and soc-analyst-02 | 30 | grep report content |

**Pass threshold**: 60 points

**Note**: Alert severity changes are difficult to verify programmatically without knowing the exact DB schema; the report content check partially covers this.

## Why This Is Hard

- Agent must navigate to a specific settings area (Technicians & Roles) not obvious from the dashboard
- Agent must identify which accounts need changing (told explicitly, but must navigate to find them)
- Agent must also navigate to the Alert Profiles section to fix severities
- Agent must create a new account AND document everything
- Four distinct UI operations across Settings and Alerts sections

## Evidence Notes

- Initial technician state captured in `/tmp/initial_tech_count`
- contractor01 and it-support created during setup
- Misconfigured alerts created during setup
- Task start timestamp: `/tmp/task_start_timestamp`
