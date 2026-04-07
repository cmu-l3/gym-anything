# Task: url_monitor_service_remediation

## Overview
This task evaluates an agent's ability to read a structured service catalog document and perform both corrective and additive configuration changes in ManageEngine OpManager's URL monitoring subsystem. Two monitors have been deliberately misconfigured prior to the task, and three additional service endpoints are absent entirely. The agent must identify all five action items from the catalog and implement every change correctly.

## Domain Context
Network operations teams routinely maintain a URL monitoring catalog that defines the authoritative set of HTTP service endpoints to monitor, their polling frequency, and acceptable response timeouts. When endpoint ownership changes or catalog revisions are issued, NOC engineers must reconcile OpManager's live configuration against the catalog — fixing broken monitors and onboarding new ones. Failure to act leaves monitoring gaps or misleading alert data.

## Goal
The agent must read `~/Desktop/url_service_catalog.txt`, identify all five required changes (two fixes, three additions), and implement them in OpManager at http://localhost:8060 (admin/Admin@123). All changes must be persisted so they are visible via the API or database after the session ends.

## Starting State
Two URL monitors are pre-created with deliberate errors:
- **Internal-Auth-Service**: exists but points to `http://localhost:9090/auth` instead of the correct URL (`http://localhost:8060/apiclient/ember/Login.jsp`).
- **OpManager-API-Health**: exists with the correct URL but a poll interval of 30 minutes instead of the required 3 minutes.

Three monitors required by the catalog are entirely absent:
- Primary-Web-Portal
- SNMP-Polling-Endpoint
- NOC-Dashboard-Availability

## Agent Workflow
1. Open and read `~/Desktop/url_service_catalog.txt` from the Ubuntu desktop.
2. Log in to OpManager at http://localhost:8060 with credentials admin/Admin@123.
3. Navigate to the URL Monitors section (Settings > Monitors > URL Monitors or equivalent).
4. Locate **Internal-Auth-Service** and update its URL to `http://localhost:8060/apiclient/ember/Login.jsp`.
5. Locate **OpManager-API-Health** and change its poll interval from 30 minutes to 3 minutes.
6. Create new URL monitor **Primary-Web-Portal** with URL `http://localhost:8060/client`, poll interval 5 min, timeout 10 s.
7. Create new URL monitor **SNMP-Polling-Endpoint** with URL `http://localhost:8060`, poll interval 15 min, timeout 30 s.
8. Create new URL monitor **NOC-Dashboard-Availability** with URL `http://localhost:8060/apiclient/ember`, poll interval 10 min, timeout 15 s.
9. Save all changes and confirm they appear in the monitor list.

## Success Criteria (100 points total, pass at 60)

| Criterion | Points | Description |
|-----------|--------|-------------|
| Internal-Auth-Service URL corrected | 20 | Monitor exists and its URL contains `Login.jsp` |
| OpManager-API-Health poll interval corrected | 20 | Monitor exists with a poll interval of exactly 3 minutes |
| Primary-Web-Portal created | 20 | Monitor with this display name exists in OpManager |
| SNMP-Polling-Endpoint created | 20 | Monitor with this display name exists in OpManager |
| NOC-Dashboard-Availability created | 20 | Monitor with this display name exists in OpManager |

## Verification Approach
The `export_result.sh` script queries both the OpManager REST API (trying multiple URL monitor endpoints) and the PostgreSQL database directly. The `verifier.py` script cross-references both sources: for the URL and interval criteria it checks the structured API response first, then falls back to pattern-matching the raw database dump. Existence checks for the three new monitors use both sources as well, so a monitor is credited even if the API endpoint is unresponsive as long as it is present in the database.

## Anti-Gaming
- The verifier requires the corrected URL for Internal-Auth-Service to specifically contain `Login.jsp` — simply renaming the monitor or changing the host:port without the correct path will not pass.
- The poll interval for OpManager-API-Health must be exactly 3 minutes; the setup deliberately sets it to 30 minutes, so the agent cannot reuse the creation step as a fix.
- All three new monitor names are exact-match checked (case-insensitive) — partial names or alternative names do not earn points.
- The result file is populated at export time from live system state, so pre-writing a fake result file has no effect.
