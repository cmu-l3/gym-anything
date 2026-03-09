# OrangeHRM Environment — Evidence Documentation

This directory contains screenshots and logs from interactive testing of all 5 tasks in the OrangeHRM 5.8 environment (2026-02-20).

## Environment Summary

- **Application**: OrangeHRM 5.8 (Community Edition)
- **Base**: ubuntu-gnome-systemd_highres (QEMU+Apptainer)
- **Deployment**: Docker-in-QEMU — `orangehrm/orangehrm:5.8` + `mariadb:10.11`, port 8000
- **Admin credentials**: `admin` / `Admin@OHrm2024!`
- **Seed data**: 20 employees, 8 job titles, 5 leave types, 6 departments

## Tasks Tested

### Task 1: add_employee
- **Pre-task**: Navigates to Admin > PIM > Add Employee form
- **Screenshot**: `task1_add_employee_start.png` — blank Add Employee form (First Name, Last Name, Employee ID fields)
- **Log**: `task1_pretask_log.txt`
- **Test result**: Filled Marcus Rivera / MR-022, clicked Save → "Successfully Saved" + redirected to Personal Details (empNumber=22)

### Task 2: create_job_title
- **Pre-task**: Navigates to Admin > Job > Job Titles list (8 titles pre-loaded, no Cloud Architect)
- **Screenshot**: `task2_create_job_title_start.png` — Job Titles list showing "(8) Records Found" with 8 unique titles, green "+ Add" button visible
- **Log**: `task2_pretask_log.txt`
- **Test result**: Clicked + Add → filled "Cloud Architect" → Saved → 9 records, Cloud Architect visible

### Task 3: add_leave_type
- **Pre-task**: Navigates to Leave > Configuration > Leave Types list (5 types pre-loaded)
- **Screenshot**: `task3_add_leave_type_start.png` — Leave Types list with Add button
- **Log**: `task3_pretask_log.txt`
- **Test result**: Clicked + Add → filled "Bereavement Leave" → Saved → 6 records, Bereavement Leave visible

### Task 4: update_employee_contact
- **Pre-task**: Navigates to James Anderson's (EMP001) Contact Details page; resets work phone to 212-555-0101
- **Screenshot**: `task4_update_employee_contact_start.png` — Contact Details form with work phone "212-555-0101"
- **Log**: `task4_pretask_log.txt`
- **Test result**: Updated Work Phone to "646-555-9900" → clicked Save → page shows new value

### Task 5: apply_leave
- **Pre-task**: Ensures Sarah Mitchell (EMP002) has Annual Leave entitlement (15 days), configures leave period, navigates to Leave > Assign Leave form
- **Screenshot**: `task5_apply_leave_start.png` — blank Assign Leave form
- **Form filled screenshot**: `task5_apply_leave_form_filled.png` — form showing Sarah Mitchell, Annual Leave, 15.00 Day(s) balance, 2026-02-23 to 2026-02-23, "Personal errand" comment
- **Success screenshot**: `task5_apply_leave_success.png` — form reset to blank (OrangeHRM behavior post-assignment)
- **DB verification**: `ohrm_leave_request` table shows id=2, emp_number=3, leave_type_id=1, date_applied=2026-02-23
- **Log**: `task5_pretask_log.txt`
- **Test result**: Leave successfully assigned; form cleared after submission

## Key Technical Details Verified

- OrangeHRM 5.8 Docker container launches reliably via docker-compose
- Admin login works with `Admin@OHrm2024!` (bcrypt hash set via PHP PDO in post_start)
- All 5 pre-task scripts navigate to the correct start state in < 30s
- Leave assignment requires `leave_period_defined=Yes` in `hs_hr_config` + a record in `ohrm_leave_period_history`
- Leave can only be assigned on working days (Mon-Fri); `setup_task.sh` computes next workday
- Assign Leave button is at VG (1195, ~500) → actual (1793, ~753) in unscrolled 1920x1080 view
- OrangeHRM 5.8 ships with pre-existing default job titles; seed SQL soft-deletes all defaults before inserting the 8 seeded titles to prevent duplicates
- `add_employee/setup_task.sh` cleans up any non-seeded employees (not EMP001-EMP020) from prior test runs to keep employee count at 21 (20 seeded + 1 admin)
