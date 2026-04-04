# Task: investigate_brute_force_incident

## Domain Context

ManageEngine EventLog Analyzer is the primary SIEM dashboard for Information Security Analysts (onet_importance=93). A core daily workflow is investigating authentication anomalies identified through log monitoring — determining which accounts are targeted, correlating attack sources, and creating detection rules for recurrence.

## Task Overview

The environment contains real authentication failure log events seeded via the Linux syslog facility (real OS events, not synthetic data). The agent must act as an on-call SOC analyst who has been alerted to unusual authentication activity and must investigate, create detection coverage, and produce an incident report.

## Starting State

The setup script injects real syslog events:
- **Primary attack**: 28 failed authentication attempts for user `serviceacct` from IP `192.168.10.45`
- **Noise source 1**: 9 failed attempts for user `backup` from IP `10.0.0.15`
- **Noise source 2**: 4 failed attempts for user `admin` from IP `172.16.5.22`

Events are injected via `logger -p auth.warning` which writes to `/var/log/auth.log`, forwarded to ELA via rsyslog on port 514. The agent is NOT told which account is targeted — it must discover this through log analysis.

## What the Agent Must Do

1. **Investigate** (features: Log Search): Search log data to identify the user account with the most failed authentication attempts and the primary source IP. The agent must use ELA's log search functionality to find this.

2. **Create Alert Profile** (feature: Alert Profiles/Rules): Create a threshold-based alert in ELA named to reflect the discovered attack, severity Critical, triggered by 5+ failed auth events in 5 minutes from the identified account.

3. **Document Findings** (feature: File creation): Write a report to `~/Desktop/incident_report.txt` containing:
   - Targeted username: `serviceacct`
   - Attacker source IP: `192.168.10.45`
   - Total failed attempt count
   - Recommended remediation steps

## Verification Strategy

The verifier checks four independent criteria:

| Criterion | Points | Method |
|-----------|--------|--------|
| Report file exists and created after task start | 30 | File mtime check |
| Report contains correct targeted username `serviceacct` | 25 | grep report file |
| Report contains correct attacker IP `192.168.10.45` | 25 | grep report file |
| Alert profile created in ELA (new alert count > baseline) | 20 | DB table discovery + count comparison |

**Pass threshold**: 60 points (agent must at minimum correctly identify the attack and document it)

## Adversarial Robustness

- Baseline alert count recorded before agent starts; verifier requires NEW alerts (not pre-existing ones)
- Report file mtime is checked against `task_start_timestamp` (integer comparison per Lesson 15)
- Wrong-account/wrong-IP report = 0 on those criteria; task still partially completable via alert creation

## Key Application Features Exercised

- Log Search (advanced query by event type and source)
- Alert Profile creation (threshold-based rules)
- Event correlation and timeline reconstruction

## Evidence Notes

- Real log events injected at task start time
- Initial alert count baseline recorded in `/tmp/initial_alert_count`
- Task start timestamp: `/tmp/task_start_timestamp`
