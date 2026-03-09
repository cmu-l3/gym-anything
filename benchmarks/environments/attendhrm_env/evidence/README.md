# AttendHRM Environment Evidence

Environment: `attendhrm_env@0.1`
Verified: 2026-02-24

## Task Start State Screenshots

| Screenshot | Task | Description |
|---|---|---|
| `ts_add_department.png` | `add_department` | Department list screen (Modules > Employer > Department) showing Department Wise Head Count chart and department table (ACC, ADM, IT, etc.) with green '+' add button |
| `ts_employee_list.png` | `add_employee`, `edit_employee_designation` | Employee list showing 50 active employees with columns: Employee Id, Full Name, Location, Department, Designation, Employee Type, Is Active |
| `ts_attendance_reports.png` | `generate_attendance_report` | Attendance Reports list (Modules > Reports > Attendance Reports) showing 26+ report types including Attendance Register - Monthly, Daily, Weekly, etc. |
| `ts_employee_import.png` | `import_employees` | Employee Import Wizard showing format selection step (New Import Format / Existing Import Format) |

## Attendance Data Verification

The Demo database (Firebird `DEMO.FDB`) contains substantial pre-populated attendance data:

- `ATT_REG` (Attendance Register): **242,689 rows** — timestamps, durations, employee assignments
- `ATT_IMP` (Attendance Import): **173,186 rows**
- `EMP_EMP` (Employees): **50 employees** with locations, departments, designations
- Data spans 2019-2020 with realistic ~8-hour shift durations
- Verified via Firebird `isql` queries against `C:\Program Files (x86)\Attend HRM\Data\DEMO.FDB`

This ensures the "Attendance Register - Monthly" report will produce non-empty results.

## Full Pipeline Verification

- AttendHRM installs to `C:\Program Files (x86)\Attend HRM\Bin\Attend.exe`
- Install uses `curl.exe` for reliable 287MB download
- Login credentials: admin/admin (Demo database)
- First-run: Firebird service auto-starts; Employer Details dialog handled in post_start
- Task setup: kill AttendHRM → double-click desktop icon → login → navigate to task screen
- Each task start state confirmed via VNC screenshots + visual_grounding analysis
