# Task: Investigate Account Activity — Security Threat Investigation

## Domain Context

IT Security Analysts and SOC (Security Operations Center) personnel use ManageEngine ADAudit Plus as a central audit trail for investigating Windows account management events, failed logins, and privilege changes. A key daily workflow is triage of automated alerts: an alert fires, and the analyst must navigate ADAudit Plus to discover which specific accounts were involved, correlate events, and document findings for the incident record — without being told in advance which accounts to look at.

## Task Goal

The agent receives a high-level alert: suspicious account activity occurred in the last 24 hours. It must:

1. Use ADAudit Plus's reports and audit search features to independently discover which local accounts had management events (creations, modifications, password resets) and which were targeted by failed logons.
2. Create a new technician account (`soc_analyst1`, Operator role) to handle ongoing monitoring.
3. Produce a written investigation report at `C:\Users\Docker\Desktop\account_threat_report.txt` that contains the discovered usernames and event summaries.

## Starting State (Unique to This Task)

The `setup_task.ps1` adds the following events on top of the base environment:
- 10 additional failed logon attempts targeting user `dlee` (making dlee clearly the most-targeted account alongside the base failed-logon accounts)
- A description modification on user `mjohnson` (generates Event ID 4738 — User Account Changed)

**Actual usernames involved in account management events**: jsmith, mjohnson, rwilliams, abrown, dlee (created by post_start), plus dlee has extra failed logon events from this setup.

**Actual failed logon usernames** (both base + task-specific): baduser1, baduser2, wrongadmin, testattacker, bruteforce1 (from post_start) and additional attempts against dlee.

## Success Criteria

| Criterion | Points | Verification |
|-----------|--------|-------------|
| Technician `soc_analyst1` created with Operator role | 30 | DB query or API |
| Report file exists at Desktop path | 15 | File system |
| Report file modified after task start (proves agent wrote it) | 15 | Timestamp comparison |
| File mentions ≥2 actual usernames from audit trail | 25 | Content keyword match |
| File is substantial (≥200 chars, shows real investigation effort) | 15 | File size |

**Pass threshold**: 60/100

## Verification Strategy

`export_result.ps1`:
1. Queries the ADAudit Plus PostgreSQL database for technician with username `soc_analyst1`
2. Checks for the report file at `C:\Users\Docker\Desktop\account_threat_report.txt`
3. Reads file content and checks for known usernames from the event data
4. Records task start timestamp vs file modification time
5. Writes all results to `C:\Users\Docker\investigate_account_activity_result.json`

`verifier.py`:
1. Copies result JSON from VM
2. Awards points per criterion with independent try/except blocks
3. Returns partial credit for incomplete work

## Why This Is Hard

- The agent is NOT told which accounts were involved — it must navigate ADAudit Plus reports to discover them
- The agent must combine investigation (reports navigation) with configuration (creating a technician) and documentation (writing a file)
- No UI steps are given; the agent must discover the right report sections independently
- Multiple distinct features required: Reports module, Admin > Delegation, file output

## Edge Cases

- ADAudit Plus may take time to ingest newly generated Windows events; the report may show events from the last hour or last day
- The technician creation form requires setting Authentication Mode to "Product Authentication" before filling fields
- The report file must be substantive — a file with just "dlee" does not earn full content points
