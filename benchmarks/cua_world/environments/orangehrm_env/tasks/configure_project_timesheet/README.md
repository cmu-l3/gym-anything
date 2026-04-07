# configure_project_timesheet

**Environment:** OrangeHRM 5.8
**Difficulty:** Medium
**Domain:** Energy / Field Services — Project Time Tracking

## Description

You are the Project Coordinator at **Midwest Energy Cooperative**, a regional utility company that manages renewable energy infrastructure across the Midwest. The operations team needs to begin time-tracking for field staff working on the **Annual Turbine Maintenance 2024** project.

A work order on your Desktop lists the activities to configure and the timesheet hours to enter for field technician Ethan Davis.

## Steps Required

1. **Add a Customer**: Go to *Time > Project Info > Customers* and add `Midwest Energy Cooperative`.
2. **Create a Project**: Go to *Time > Project Info > Projects* and add `Annual Turbine Maintenance 2024` under that customer. Add `Admin User` as the Project Admin.
3. **Add Activities** to the project:
   - `Turbine Inspection`
   - `Parts Replacement`
   - `Safety Testing`
4. **Open Ethan Davis's timesheet** for the current week: *Time > Timesheets > Employee Timesheets*, select Ethan Davis.
5. **Enter the following hours**:
   | Day | Activity | Hours |
   |-----|----------|-------|
   | Mon | Turbine Inspection | 8.00 |
   | Tue | Turbine Inspection | 6.00 |
   | Tue | Parts Replacement | 2.00 |
   | Wed | Parts Replacement | 8.00 |
   | Thu | Parts Replacement | 4.00 |
   | Thu | Safety Testing | 4.00 |
   | Fri | Safety Testing | 8.00 |
6. **Submit** the timesheet.

## Scoring (100 pts total, pass threshold 60)

| Component | Points |
|-----------|--------|
| Customer `Midwest Energy Cooperative` created | 10 |
| Project `Annual Turbine Maintenance 2024` under correct customer | 12 |
| Each of 3 activities created (5 pts × 3) | 15 |
| Timesheet exists for current week | 10 |
| Timesheet status = SUBMITTED | 8 |
| Each of 7 correct daily entries (4 pts × 7) | 28 |
| Total hours = 40.0 | 7 |
| Workflow evident (bonus if score > 20) | 10 |

**Do-nothing score:** 0 (no records exist until agent creates them)

## Anti-Pattern 4 Check

- All infra (customer + project + activities) but no timesheet: 37 + 10 bonus = 47 < 60 ✓
- Infra + timesheet (not submitted, no entries): 47 + 10 bonus = 57 < 60 ✓
- Full correct completion: ≥ 100 pts → pass ✓

## Spec File

`/workspace/tasks/configure_project_timesheet/work_order.txt` (placed on Desktop during setup)

## Result File

`/tmp/task_result.json` — written by `export_result.sh`
