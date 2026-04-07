# Task: noc_monitoring_gap_remediation

**Difficulty:** very_hard
**Environment:** ManageEngine OpManager 12.4.154 (Ubuntu GNOME desktop)
**Max Steps:** 120 | **Timeout:** 1800s | **Reward:** dense

---

## Professional Context

The Network Operations Center (NOC) manager has produced a formal monitoring requirements specification (version 2.3) and placed it on the analyst's desktop. The document defines three mandatory device groups, two URL monitors for service health checking, and one notification profile for on-call alerting. The current OpManager configuration is partially contaminated with wrong-named groups and is missing all required monitors and notification profiles. A NOC analyst must audit the specification, identify every gap, and implement all required changes before the next shift handover.

---

## Starting State

- OpManager is running at `http://localhost:8060` (credentials: `admin` / `Admin@123`).
- Two incorrectly-named device groups exist: `Core-Network` and `Production-Servers`.
- No URL monitors exist.
- No notification profiles exist.
- The specification file is available at `~/Desktop/noc_monitoring_spec.txt`.

---

## Agent Workflow

1. Open `~/Desktop/noc_monitoring_spec.txt` and read all three sections carefully.
2. Log in to OpManager at `http://localhost:8060`.
3. **Section 1 — Device Groups:** Navigate to *Settings > Device Management > Groups* (or use the Groups menu). Delete or ignore the contamination groups. Create the three required groups with exact names and descriptions:
   - `Core-Network-Infrastructure`
   - `Production-Application-Servers`
   - `DMZ-Security-Perimeter`
4. **Section 2 — URL Monitors:** Navigate to *Monitors > URL Monitors* (or *Web Monitors*). Create:
   - `OpManager-Self-Monitor` targeting `http://localhost:8060`, interval 5 min, timeout 10 s.
   - `SNMP-Gateway-Check` targeting `http://localhost:8060/api/json/device/listDevices`, interval 10 min, timeout 30 s.
5. **Section 3 — Notification Profiles:** Navigate to *Settings > Notifications > Notification Profiles*. Create:
   - `NOC-24x7-Critical-Alert` with email `noc-oncall@company.internal`, triggers: Device Down and Critical Threshold Violation.
6. Verify each item appears correctly in the OpManager UI.

---

## Success Criteria

| # | Criterion | Points |
|---|-----------|--------|
| 1 | Device group `Core-Network-Infrastructure` exists | 20 |
| 2 | Device group `Production-Application-Servers` exists | 20 |
| 3 | Device group `DMZ-Security-Perimeter` exists | 20 |
| 4 | URL monitor `OpManager-Self-Monitor` exists (URL: `http://localhost:8060`) | 20 |
| 5 | Notification profile `NOC-24x7-Critical-Alert` with email `noc-oncall@company.internal` | 20 |

**Total: 100 points. Pass threshold: 60 points (3 of 5 criteria).**

---

## Key Files

| Path | Purpose |
|------|---------|
| `~/Desktop/noc_monitoring_spec.txt` | NOC monitoring requirements specification |
| `/tmp/noc_monitoring_result.json` | Exported state collected by `export_result.sh` |
| `setup_task.sh` | Pre-task hook: writes spec, creates contamination groups |
| `export_result.sh` | Post-task hook: collects groups, monitors, notification profiles |
| `verifier.py` | Scoring logic |

---

## Notes

- Group names must match the specification **exactly** (case-sensitive, hyphens preserved).
- The URL monitor display name must be `OpManager-Self-Monitor` (exact).
- The notification profile email must be `noc-oncall@company.internal`.
- The `export_result.sh` script tries multiple API endpoints for URL monitors; if the primary endpoint returns no data, it falls back to `/api/json/webmon/listWebMonitors` and `/api/json/webmonitor/listWebMonitors`.
- Notification profile verification uses both the PostgreSQL database and the OpManager API; either source is sufficient for a passing score.
