# Task: Brute Force Response — Identify Attack Target and Configure Defenses

## Domain Context

Security Operations Center (SOC) analysts and network defenders routinely use audit logs and SIEM tools to identify brute-force attacks against user accounts. ManageEngine ADAudit Plus surfaces failed logon events (Event ID 4625) and can be used to quickly identify which accounts are being targeted, with what frequency, and from where. A skilled analyst then combines this investigation with immediate defensive configuration: setting up alerts for future incidents and delegating monitoring responsibility to an incident handler.

## Task Goal

The agent must:
1. Navigate ADAudit Plus to find failed logon activity and identify the most-targeted account (without being told which one).
2. Create an incident handler technician account (`incident_handler`, Operator role).
3. Configure email notifications for SOC alerting.
4. Produce a written findings document naming the specific targeted account.

## Starting State (Unique to This Task)

`setup_task.ps1` generates **15 additional failed logon attempts specifically targeting `rwilliams`** (Robert Williams, Network Administrator). Combined with the base environment's generic failed logon events, this makes `rwilliams` clearly the most-targeted account by a large margin — the agent should be able to see this pattern in the ADAudit Plus failed logon reports.

**Key ground truth**: `rwilliams` is the primary brute-force target with 15 task-specific failed logins.

## Success Criteria

| Criterion | Points | Verification |
|-----------|--------|-------------|
| Technician `incident_handler` created (Operator) | 25 | DB query |
| Notification configured for security-alerts@corp.local | 25 | DB query |
| Analysis file exists, modified after task start | 20 | File system + timestamp |
| Analysis file mentions 'rwilliams' (correct answer) | 30 | Content match |

**Pass threshold**: 60/100

## Why This Is Hard

- The agent must discover the most-targeted account by investigating ADAudit Plus reports — NOT guessing
- The correct answer (`rwilliams`) must appear in the written file, verifying genuine investigation
- Three distinct ADAudit Plus features are required: Reports/Audit trail navigation, Admin > Delegation, Admin > Notifications
- No UI navigation steps are given

## Edge Cases

- ADAudit Plus may aggregate failed logins differently depending on the report view (by user vs. by event)
- The "Failed Logon Activity" report may be under "User Audit", "Logon/Logoff", or a search feature
- The agent should look for the account with the most events — there should be a clear winner (rwilliams with 15 extra attempts)
