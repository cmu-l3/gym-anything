# Task: forensic_export_and_scheduled_reporting

## Domain Context

Information Security Analysts and Incident Responders regularly perform forensic log collection for legal proceedings and set up ongoing automated reporting for SOC management. This task combines two distinct professional workflows: evidence preservation (export + archival) and operational monitoring (scheduled reports + alerting). Both are standard responsibilities documented in the SIEM use case library.

## Task Overview

Root user activity events have been seeded in the logs. The agent must export this evidence as CSV, configure a legal hold archival policy, set up a recurring scheduled report, and create a monitoring alert — four distinct features of EventLog Analyzer exercised in a single professional workflow.

## Starting State

The setup script seeds real root user activity events via `logger`:
- Root authentication events
- Root privilege-level command events
- Sudo escalation records

## What the Agent Must Do

1. **Log Export** (feature: Log Search + Export): Search for `root` user events in the last 24 hours and export results to `~/Desktop/root_activity_export.csv`. This requires finding the export button within the log search results view.

2. **Log Archival** (feature: Settings/Archive): Navigate to Settings and configure an archive policy named `Legal Evidence Hold` with 730+ day retention. This feature is in a different section of the UI from reporting.

3. **Scheduled Report** (feature: Reports/Scheduling): Create a scheduled report named `Daily SOC Security Summary` set to run daily. This requires navigating to Reports and using the scheduling functionality.

4. **Alert Profile** (feature: Alerts): Create `Root Access Monitor` alert with Critical severity, threshold of 1 root event.

## Verification Strategy

| Criterion | Points | Method |
|-----------|--------|--------|
| CSV export file created after task start and non-empty | 25 | File mtime + size check |
| Scheduled report created with daily frequency | 25 | DB table discovery + frequency check |
| Log archival with >= 730 day retention configured | 25 | DB table discovery |
| Root access alert profile created | 25 | DB table discovery |

**Pass threshold**: 60 points (must complete at least 2.5 of 4 subtasks)

## Feature Coverage (distinct from other tasks)

This is the only task using:
- Log Search **export** functionality (not just search)
- Scheduled reports module
- Log archival/retention configuration
- Alert profile creation (different target event type from Tasks 1-3)

## Evidence Notes

- Root activity events injected via `logger`
- Task start timestamp: `/tmp/task_start_timestamp`
- Initial scheduled report count in `/tmp/initial_report_count`
