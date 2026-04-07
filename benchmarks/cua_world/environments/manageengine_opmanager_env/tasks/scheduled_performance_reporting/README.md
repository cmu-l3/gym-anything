# Task: scheduled_performance_reporting

**Difficulty:** hard
**Environment:** ManageEngine OpManager 12.4.154 (Ubuntu GNOME desktop)
**Max Steps:** 100 | **Timeout:** 1200s | **Reward:** dense

---

## Overview

This task requires configuring two automated scheduled reports in ManageEngine OpManager so that IT operations and executive stakeholders receive regular infrastructure health data by email. The agent must navigate the OpManager Reports module, create and schedule both reports with precise names, scopes, schedules, and recipient email addresses.

---

## Domain Context

Enterprise IT teams rely on scheduled performance and availability reports to track infrastructure health without manual intervention. OpManager's reporting module supports configurable report schedules that deliver HTML or PDF summaries to designated recipients on a weekly or monthly cadence. Misconfigured report schedules — wrong email recipients, wrong report types, or wrong schedule frequencies — result in stakeholders receiving no data or incorrect data, undermining SLA review and capacity planning processes.

---

## Goal

The agent must create and schedule the following two reports in OpManager:

1. **Infrastructure-Availability-Report**
   - Report type: Availability
   - Scope: All devices
   - Schedule: Weekly, every Monday at 08:00 AM
   - Delivery email: `it-ops@company.internal`

2. **Executive-Performance-Summary**
   - Report type: Performance
   - Scope: All devices
   - Schedule: Monthly, on the 1st of each month at 07:00 AM
   - Delivery email: `it-executive@company.internal`

---

## Starting State

- OpManager is running at `http://localhost:8060` (credentials: `admin` / `Admin@123`).
- No scheduled reports exist.
- Firefox is open and showing the OpManager dashboard.

---

## Agent Workflow

1. Log in to OpManager at `http://localhost:8060` with `admin` / `Admin@123` if not already logged in.
2. Navigate to the **Reports** section (top navigation bar or left sidebar).
3. Locate the **Schedule Reports** or **Add Report** option.
4. Create the first report:
   - Name: `Infrastructure-Availability-Report`
   - Type: Availability
   - Devices: All
   - Schedule: Weekly, Monday, 08:00 AM
   - Email recipient: `it-ops@company.internal`
   - Save / Schedule the report.
5. Create the second report:
   - Name: `Executive-Performance-Summary`
   - Type: Performance
   - Devices: All
   - Schedule: Monthly, Day 1, 07:00 AM
   - Email recipient: `it-executive@company.internal`
   - Save / Schedule the report.
6. Confirm both scheduled reports appear in the reports list.

---

## Success Criteria (100 points total, pass at 60)

| Criterion | Points | Description |
|-----------|--------|-------------|
| Infrastructure-Availability-Report name | 30 | Report with exact name `Infrastructure-Availability-Report` exists |
| Infrastructure-Availability-Report email | 20 | Delivery email is `it-ops@company.internal` |
| Executive-Performance-Summary name | 30 | Report with exact name `Executive-Performance-Summary` exists |
| Executive-Performance-Summary email | 20 | Delivery email is `it-executive@company.internal` |

To pass (60 pts), the agent must complete at least one report fully (50 pts) plus find the name of the second (30 pts), or complete both report names without any emails.

---

## Verification Approach

The `export_result.sh` script collects report data from two sources:

1. **OpManager REST API** — tries `/api/json/report/listReports` and `/api/json/reports/getScheduledReports` (plus fallback variants) to retrieve report metadata as JSON.
2. **PostgreSQL database** — discovers all tables matching `%report%` or `%schedule%`, then queries them directly; also scans tables with email-related columns.

The `verifier.py` script searches all collected data (case-insensitively) for the required report names and associated email addresses. A proximity window search links each report name to its email so that unrelated email addresses do not inflate the score. Either data source (API or DB) is sufficient for a passing score.

---

## Anti-Gaming

- Report names are checked case-insensitively but must be exact matches (hyphens required, no abbreviations).
- Email addresses must be the exact addresses specified (`it-ops@company.internal`, `it-executive@company.internal`); partial matches or wrong domains score zero for the email criterion.
- The email credit for each report is only awarded when the name is also found, preventing a fabricated email entry from scoring points without a corresponding report.
