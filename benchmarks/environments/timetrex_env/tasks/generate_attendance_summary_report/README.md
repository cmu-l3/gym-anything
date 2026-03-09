# Generate Attendance Summary Report

## Overview

At month-end, the Payroll Clerk must produce an attendance summary for the previous month to reconcile timesheets before running payroll. TimeTrex has a built-in report engine with CSV export capability. The task requires navigating to the correct report type, setting the correct date range, and exporting the result to a specific file path on the Desktop.

## Goal

Generate a TimeSheet Summary (or equivalent attendance/timesheet) report in TimeTrex for the date range **February 1, 2026 to February 28, 2026**, covering all employees. Export it as a CSV file to:

```
/home/ga/Desktop/attendance_feb2026.csv
```

The file must contain actual data rows (not an empty or header-only file) and must be created after the task starts.

## Success Criteria

1. **(30 pts)** File exists at `/home/ga/Desktop/attendance_feb2026.csv` and was created/modified after task setup completed.
2. **(40 pts)** File contains more than 1 line (has data rows, not just a header).
3. **(30 pts)** File is non-trivially sized (>100 bytes), indicating a real export rather than an empty placeholder.

Partial credit: if the file is saved to Downloads instead of Desktop, 25 pts total are awarded.

## Verification Strategy

`export_result.sh` checks:
- `stat -c %s` for file size
- `wc -l` for line count
- `stat -c %Y` mtime vs task start timestamp

The verifier also attempts to copy the CSV directly from the VM and show a preview of the first 3 lines for debugging.

## Edge Cases

- The agent may need to set the "Pay Period" type to "Custom Date Range" to enter Feb 1 – Feb 28 explicitly.
- TimeTrex may default to saving downloads in the browser's Downloads folder rather than the Desktop — the agent must either configure the download location or move the file.
- If demo punch data for February 2026 does not exist, `setup_task.sh` injects minimal punch records for two employees on 2026-02-03.
- The report type name may vary (e.g., "TimeSheet Detail", "TimeSheet Summary", "Attendance Summary") — the agent must find the appropriate report.

## Starting State

- Any pre-existing `attendance_feb2026.csv` on the Desktop or in Downloads is deleted before the task starts.
- Task start timestamp is recorded for mtime comparison.
- Demo data includes punch records for February 2026 (injected if missing).
