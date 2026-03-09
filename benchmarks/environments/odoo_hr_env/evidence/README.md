# Odoo HR Environment — Evidence

Collected 2026-02-23 on rebuilt environment (SSH port 2351, VNC port 5905).
Updated 2026-02-23: fixed leave types (Paid Time Off / Unpaid), dynamic employee ID lookups, XML ID URL routing, create_employee end-to-end demo redone with correct Job Position (M2O) field.

---

## Data Source: Odoo Official Demo Data

This environment uses **Odoo's built-in official demo data** (`hr/data/hr_demo.xml`,
`hr_holidays/data/hr_holidays_demo.xml`). No synthetic employees were created.

**setup_data.py output** (run during post_start hook):
```
=== Setting up supplementary HR data ===
(Base data provided by Odoo official demo: 20 employees, 7 departments, etc.)
Created Paid Time Off allocation for 'Rachel Perry' (id=18, days=10, state=validate)
Created leave for 'Rachel Perry' (id=18, state=confirm): Annual vacation — Paid Time Off
Created leave for 'Doris Cole' (id=16, state=confirm): Personal time off — Unpaid
=== Supplementary data setup complete ===
```

**Database verification** (xmlrpc query after post_start):
```
Total employees: 20
  - Abigail Peterson | Management / Professional Services | Consultant
  - Anita Oliver     | Management / Research & Development / R&D USA | Experienced Developer
  - Audrey Peterson  | Management / Professional Services | Consultant
  - Beth Evans       | Management / Research & Development | Experienced Developer
  - Doris Cole       | Management / Professional Services | Consultant
  - Eli Lambert      | Management / Sales | Marketing and Community Manager
  - Ernest Reed      | Management / Professional Services | Consultant
  - Jeffrey Kelly    | Management / Sales | Marketing and Community Manager
  - Jennie Fletcher  | Management / Research & Development | Experienced Developer
  - Keith Byrd       | Management / Research & Development | Experienced Developer
  - Marc Demo        | Management / Research & Development | Experienced Developer
  - Mitchell Admin   | Management | Chief Executive Officer
  - Paul Williams    | Management / R&D / R&D USA / Long Term Projects | Experienced Developer
  - Rachel Perry     | Management / Sales | Marketing and Community Manager
  - Randall Lewis    | Management / Research & Development | Experienced Developer
  - Ronnie Hart      | Management / Research & Development | Chief Technical Officer
  - Sharlene Rhodes  | Management | Experienced Developer
  - Tina Williamson  | Management / Administration | Human Resources Manager
  - Toni Jimenez     | Management / Professional Services | Consultant
  - Walter Horton    | Management / Research & Development | Experienced Developer
Total departments: 7
Leave types: ['Paid Time Off', 'Sick Time Off', 'Unpaid', 'Compensatory Days', 'Parental Leaves', 'Training Time Off']
  Pending leave: Rachel Perry - Annual vacation (Paid Time Off)
  Pending leave: Doris Cole - Personal time off (Unpaid)
```

**Odoo server log** (from `docker logs odoo-web` during post_start):
```
2026-02-23 04:05:15,066  INFO  Odoo version 17.0-20260217
2026-02-23 04:05:19,567  INFO  odoo.modules.loading: loading 58 modules...
2026-02-23 04:05:20,109  INFO  odoo.modules.loading: 58 modules loaded in 0.54s
2026-02-23 04:05:20,219  INFO  odoo.modules.loading: Modules loaded.
2026-02-23 04:05:20,225  INFO  odoo.modules.registry: Registry loaded in 0.720s
2026-02-23 04:05:35,199  INFO  Login successful for db:odoo_hr login:admin
2026-02-23 04:05:35,817  WARNING  Time off request must be in Draft state ...
  (expected: admin-created leaves in Odoo 17 go directly to confirm state)
2026-02-23 04:05:35,874  INFO  POST /xmlrpc/2/object — leave created OK (state=confirm)
```

---

## Task Start States (all 10 verified)

All screenshots captured after `setup_task.sh` ran cleanly (exit code 0).

| Screenshot | Task | Start State |
|---|---|---|
| `create_employee_start.png` | create_employee | Employees kanban — 20 official demo employees visible |
| `update_employee_job_title_start.png` | update_employee_job_title | **Marc Demo's employee form** — Job Title field is empty (cleared by setup), Job Position = "Experienced Developer" |
| `create_department_start.png` | create_department | Departments list — 7 departments, "Product Management" absent |
| `set_employee_manager_start.png` | set_employee_manager | **Walter Horton's employee form** — Manager field = "Paul Williams" (reset by setup), visible on main form |
| `create_job_position_start.png` | create_job_position | Job Positions list — 7 positions (CEO, CTO, Consultant, Experienced Developer, HR Manager, Marketing Mgr, Trainee), "Data Scientist" absent |
| `create_leave_allocation_start.png` | create_leave_allocation | All Allocations list — existing demo allocations, no Randall Lewis entries |
| `approve_leave_request_start.png` | approve_leave_request | All Time Off manager list — Rachel Perry pending "Annual vacation" (Paid Time Off, To Approve) |
| `refuse_leave_request_start.png` | refuse_leave_request | **Doris Cole's leave request form** — "Personal time off", type=Unpaid, state=To Approve, Approve/Refuse buttons visible |
| `create_expense_report_start.png` | create_expense_report | **New Expense form** — blank form (description placeholder, Total = $0.00, Employee = Mitchell Admin), agent must fill in Ernest Reed |
| `add_employee_tag_start.png` | add_employee_tag | **Jennie Fletcher's employee form** — Tags field shows "Employee" only, "Trainer" tag absent (cleared by setup via XML-RPC) |

---

## Interactive Testing: create_employee (end-to-end)

**Task**: Create employee Sarah Mitchell, Job Position: Experienced Developer (M2O dropdown),
Department: Research & Development.

**IMPORTANT**: This demo correctly sets the `job_id` Many2one field (Job Position dropdown in
the right column), NOT the free-text `job_title` field under the employee name. These are
distinct fields in Odoo 17.

**Step-by-step screenshots with grounding coordinates**:

| Step | Screenshot | Action | Visual Grounding Result |
|---|---|---|---|
| 1 | `create_employee_start.png` | Task setup — 20 demo employees in kanban | Confirmed 20 employees, "New" button at (74,147) [1280×720] |
| 2 | `create_employee_02_new_form.png` | Clicked New → blank employee form | Employee Name field at (353,230); Job Position M2O at ~(630,341); Department at ~(640,315) |
| 3 | `create_employee_03_name_typed.png` | Typed "Sarah Mitchell" in Name field | "Sarah Mitchell" confirmed at top of form |
| 4 | `create_employee_04_job_position_dropdown.png` | Clicked Job Position M2O field (right column) → dropdown open | Dropdown shows all 7 job positions; "Experienced Developer" at (587,420) [1280×720] |
| 5 | `create_employee_05_dept_dropdown.png` | Selected "Experienced Developer"; clicked Department, typed "Research" | Department dropdown filtered — "Management / Research & Development" at (622,377) [1280×720] |
| 6 | `create_employee_06_fields_set.png` | Selected "Research & Development" | Job Position="Experienced Developer", Department="Management / Research & Development" |
| 7 | `create_employee_07_saved_kanban.png` | Clicked cloud save icon (200,152) → saved, returned to kanban | Sarah Mitchell card visible in kanban with "Experienced Developer" |
| 8 | `create_employee_08_saved_form.png` | Clicked Sarah Mitchell card → saved form view | Breadcrumb: "Employees / Sarah Mitchell"; URL: `/web#id=22`; Job Position: "Experienced Developer"; "Employee created" activity |

**Verification** (post-save xmlrpc query confirmed 21 total employees, new ID=22):
```
Total employees: 21
  - Sarah Mitchell | Management / Research & Development | job_id=[4, 'Experienced Developer'] | job_title='Experienced Developer'
```

The `job_id` Many2one field is set to `[4, 'Experienced Developer']` — confirming the M2O
dropdown was used (not just the free-text `job_title` field).

**Conclusion**: The `create_employee` task is completable end-to-end by an agent using
screenshot grounding + xdotool interactions. The Job Position M2O dropdown must be clicked in
the right column of the form (label at ~(486,341) in 1280×720), not the `job_title` free-text
field below the employee name.

---

## Key Technical Notes

- Odoo 17 CE uses `#action=<xml_id>` URL routing (not `/odoo/` prefix — returns 404)
- Admin-created leave requests go directly to `confirm` state in Odoo 17 (no separate action_confirm call needed)
- Task start screenshots were taken with `su - ga -c "DISPLAY=:1 XAUTHORITY=... scrot ..."` (root cannot run scrot directly)
- All 10 task setups pass with exit code 0
- Employee IDs are looked up dynamically via XML-RPC in all setup_task.sh scripts (not hardcoded)
- Odoo 17 save: use cloud save icon at ~(200,152) in 1280×720 (NOT Ctrl+S which opens browser save dialog)
- `job_id` = Job Position M2O dropdown (right column); `job_title` = free-text subtitle under name — these are distinct fields
- Rachel Perry's "Annual vacation" uses "Paid Time Off" leave type (requires allocation — one is created by setup_data.py)
- Doris Cole's "Personal time off" uses "Unpaid" leave type (no allocation required)
- refuse_leave_request URL uses stable XML ID `hr_holidays.hr_leave_action_action_approve_department` (not numeric action ID)
