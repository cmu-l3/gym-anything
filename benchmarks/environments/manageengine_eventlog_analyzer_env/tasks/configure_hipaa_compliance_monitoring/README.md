# Task: configure_hipaa_compliance_monitoring

## Domain Context

Security Management Specialists (onet_importance=83) and compliance officers at healthcare organizations use ManageEngine EventLog Analyzer to meet HIPAA audit requirements. HIPAA mandates specific log retention periods (minimum 7 years for certain records) and requires audit controls with alerting on unauthorized PHI access. This is a realistic professional workflow that goes beyond a single UI action — it requires navigating multiple sections of the application.

## Task Overview

Three healthcare servers have been added as syslog sources. The agent must configure the SIEM to meet HIPAA compliance requirements: proper log retention settings, a PHI access alert, and a compliance report export.

## Starting State

The setup script adds 3 Linux syslog devices via the ELA REST API:
- `ehr-server-01` at IP `10.10.1.10`
- `pharmacy-db` at IP `10.10.1.11`
- `billing-system` at IP `10.10.1.12`

Additionally, real PHI access simulation events are injected via `logger` to populate the logs.

## What the Agent Must Do

1. **View HIPAA compliance report** (feature: Compliance module): Navigate to the Compliance section, select HIPAA standard, and view the current status.

2. **Set log retention** (feature: Settings/Log Management): Update the log retention period to 2555 days (HIPAA-required 7 years). This requires navigating to the appropriate settings section.

3. **Create alert** (feature: Alert Profiles): Create an alert profile named 'PHI Unauthorized Access' with Critical severity, triggered by 1+ authentication failures.

4. **Export report** (feature: Report export): Export the HIPAA compliance report to `~/Desktop/hipaa_compliance_report.html`.

## Verification Strategy

| Criterion | Points | Method |
|-----------|--------|--------|
| HIPAA report file exported and modified after task start | 25 | File mtime + HIPAA vocabulary check |
| Alert 'PHI Unauthorized Access' (or similar) created with Critical severity | 30 | DB query on alert tables |
| Report file has HIPAA-specific content | 20 | Grep for HIPAA vocabulary |
| Log retention ≥ 2555 days set (or evidence of navigation to settings) | 25 | DB query on config tables |

**Pass threshold**: 60 points

## Multi-Feature Complexity

This task requires navigating at least 4 distinct areas of the application:
1. Dashboard → Compliance section → HIPAA report
2. Settings → Log Management/Retention settings
3. Alerts → Create new alert profile
4. Reports → Export function

## Evidence Notes

- Initial alert count recorded in `/tmp/initial_alert_count_hipaa`
- Device addition confirmed via API during setup
- Task start timestamp: `/tmp/task_start_timestamp`
