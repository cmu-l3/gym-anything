# project_timesheet_portfolio

## Domain Context

**Occupation**: Social and Community Service Managers — operations managers at nonprofit organizations managing program portfolios, client billing, and staff time tracking across multiple community programs (253M GDP, top OrangeHRM user segment).

**Scenario**: HopeWell Community Services begins Q2 2025 with two new client contracts. The Operations Manager must configure the project portfolio in OrangeHRM: create the client accounts, projects, and activities — then record staff timesheets for the first work week (April 7-11, 2025) to enable client billing.

---

## Goal

Read the project portfolio brief on the Desktop. Complete all 4 steps in OrangeHRM:
1. Create 2 clients (customers) in Admin > Projects > Customers
2. Create 2 projects under their respective clients
3. Create project activities for each project
4. Submit timesheets for 2 employees for the week of April 7-11, 2025

**End state**: `ohrm_customer` has Riverside Community Foundation and Metro School District. `ohrm_project` has both projects. `ohrm_project_activity` has all 4 activities. `ohrm_timesheet` and `ohrm_timesheet_item` have entries for Michael Thompson and Kevin Hernandez for April 7-11, 2025.

---

## Why This is Very Hard

- 4 distinct UI workflows: Customers, Projects, Activities (all in Admin > Projects), then Timesheets (in Time module)
- Creating timesheets for specific employees from an admin perspective requires navigating Time > Timesheets > All Timesheets or creating them as the user
- Activities must be created AFTER projects (dependency chain)
- Timesheets must reference projects/activities that exist (further dependency)
- Description gives only goal; agent discovers all 4 workflows independently
- Timesheet entry requires selecting specific dates, projects, activities, and hour values

---

## Project Portfolio Specification

### Clients to Create
| Client Name |
|-------------|
| Riverside Community Foundation |
| Metro School District |

### Projects to Create
| Project Name | Client |
|--------------|--------|
| After-School Program Expansion | Riverside Community Foundation |
| Digital Literacy Initiative | Metro School District |

### Activities to Create
| Activity | Project |
|----------|---------|
| Program Planning | After-School Program Expansion |
| Community Outreach | After-School Program Expansion |
| Curriculum Development | Digital Literacy Initiative |
| Instructor Training | Digital Literacy Initiative |

### Timesheet Hours (Week of April 7-11, 2025)

**Michael Thompson (EMP005)**:
| Date | Hours | Project | Activity |
|------|-------|---------|----------|
| Mon Apr 7 | 4h | After-School Program Expansion | Program Planning |
| Tue Apr 8 | 4h | After-School Program Expansion | Community Outreach |
| Wed Apr 9 | 8h | After-School Program Expansion | Program Planning |

**Kevin Hernandez (EMP015)**:
| Date | Hours | Project | Activity |
|------|-------|---------|----------|
| Mon Apr 7 | 8h | Digital Literacy Initiative | Curriculum Development |
| Tue Apr 8 | 4h | Digital Literacy Initiative | Instructor Training |
| Thu Apr 10 | 4h | Digital Literacy Initiative | Curriculum Development |

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Riverside Community Foundation client exists | 10 |
| Metro School District client exists | 10 |
| After-School Program Expansion project exists | 10 |
| Digital Literacy Initiative project exists | 10 |
| Program Planning activity exists | 5 |
| Community Outreach activity exists | 5 |
| Curriculum Development activity exists | 5 |
| Instructor Training activity exists | 5 |
| Michael Thompson has timesheet for Apr 7-11 | 10 |
| Michael Thompson logged ≥ 8 hours | 10 |
| Kevin Hernandez has timesheet for Apr 7-11 | 10 |
| Kevin Hernandez logged ≥ 8 hours | 10 |
| **Total** | **100** |

**Pass threshold**: 65

---

## Anti-Pattern 4 Check

All infrastructure (clients + projects + activities) without any timesheets = 60 pts < 65 threshold. Agent must submit at least one employee's timesheet to pass.

---

## Verification Strategy

**export_result.sh** queries:
- `ohrm_customer` for client names
- `ohrm_project` for project names
- `ohrm_project_activity` for activity names (scoped to correct project IDs)
- `ohrm_timesheet` + `ohrm_timesheet_item` summing `duration` for dates in range April 7-11, 2025

**verifier.py** normalizes hours: if `duration > 100`, assumes seconds and divides by 3600; otherwise treats as hours. Accepts ≥ 8 total hours for the week.

---

## Setup State

`setup_task.sh`:
1. Soft-deletes any prior Riverside/Metro customers and cascades to projects/activities/timesheet_items
2. Clears timesheets for EMP005, EMP015 covering April 7-11, 2025
3. Ensures ESS user accounts for both employees exist
4. Creates `/home/ga/Desktop/q2_project_portfolio_brief.txt`

---

## Schema Reference

```sql
ohrm_customer:
  customer_id  INT  (PK)
  name         VARCHAR
  is_deleted   TINYINT

ohrm_project:
  project_id   INT  (PK)
  customer_id  INT  (FK → ohrm_customer)
  name         VARCHAR
  is_deleted   TINYINT

ohrm_project_activity:
  activity_id  INT  (PK)
  project_id   INT  (FK → ohrm_project)
  name         VARCHAR
  is_deleted   TINYINT

ohrm_timesheet:
  timesheet_id INT  (PK)
  employee_id  INT  (FK → hs_hr_employee.emp_number)
  state        VARCHAR  ('SUBMITTED', 'APPROVED', etc.)
  start_date   DATE
  end_date     DATE

ohrm_timesheet_item:
  timesheet_id INT  (FK → ohrm_timesheet)
  date         DATE
  duration     INT  (seconds, or 0-24 depending on OrangeHRM version)
  project_id   INT  (FK → ohrm_project)
  activity_id  INT  (FK → ohrm_project_activity)
```

---

## Edge Cases

- OrangeHRM may store timesheet duration as seconds (3600 = 1 hour) or as integer hours — verifier normalizes with threshold at 100
- Timesheets may need to be created from the employee's perspective or from Admin > Time, depending on OrangeHRM configuration
- The verifier accepts any total ≥ 8 hours for the week, not a specific per-day breakdown
