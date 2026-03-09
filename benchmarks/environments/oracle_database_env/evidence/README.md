# Oracle Database Environment - Documentation

This document describes the Oracle Database environment setup, known issues, and testing status.

## Environment Details

- **Base Image**: ubuntu-gnome-systemd_highres
- **Oracle Version**: Oracle XE 21c (via gvenzl/oracle-xe:21-slim Docker image)
- **GUI Client**: DBeaver Community Edition
- **Database**: XEPDB1 (Pluggable Database)
- **Schema**: HR Sample Schema (Oracle's official)

## Tasks

### Task 1: add_employee@1
- **Difficulty**: Medium
- **Objective**: Add a new IT Programmer employee to the HR database
- **Employee Details**: Sarah Johnson, IT_PROG, Salary $5500, Department 60
- **Verification**: 9 criteria checked (name, email, job, salary, department, newly_added, phone, manager, hire_date)

### Task 2: run_salary_query@1
- **Difficulty**: Easy
- **Objective**: Query IT department employees earning over $5000
- **Output**: Export results to /tmp/query_results.txt
- **Expected Result**: 2 employees (Alexander Hunold $9000, Bruce Ernst $6000)

## HR Schema Data

The HR sample schema contains:
- 107 employees (IDs 100-206)
- 27 departments
- 19 job types
- IT Department (60): 5 employees total
- IT employees with salary > $5000: 2 employees

## Connection Details

```
Host: localhost
Port: 1521
Database/Service: XEPDB1
Username: hr
Password: hr123

System Username: system
System Password: OraclePassword123
```

## Setup Script Behavior

### post_start (setup_oracle.sh)
- Waits minimum 90 seconds for Oracle XE to initialize
- Uses `set -e` to exit on any error
- Creates HR user with retry logic (3 attempts)
- Loads HR schema with retry logic (3 attempts)
- Verifies 100+ employees exist before declaring success
- **FAILS with exit code 1 if any step fails**

### pre_task (setup_task.sh)
- Uses `set -e` to exit on any error
- Verifies Oracle container is running
- Tests database connectivity with 5 retry attempts
- Validates HR schema has 100+ employees
- Validates initial state values are numeric (not ERROR text)
- Launches DBeaver with 3 retry attempts (90s timeout each)
- Dismisses startup dialogs automatically
- Verifies DBeaver window is visible before proceeding
- **FAILS with exit code 1 if any check fails**

### post_task (export_result.sh)
- Verifies database connectivity before querying
- Creates error JSON if database unavailable
- Queries database for task results

## Verification Logic

### add_employee verifier
- 9 criteria: name, email, job_id, salary, department_id, newly_added, phone, manager_id, hire_date
- Pass threshold: 70% (requires ~6.3/9 criteria)
- Anti-cheat: Verifies employee_id > initial_max_id (new employee)
- Strict hire date: Must be exactly January 15, 2024 (no partial credit)

### run_salary_query verifier
- Ground truth validation via independent database query
- Same-line validation: employee_id AND name must appear on same line (anti-cheat)
- Pass threshold: 70% AND 90%+ expected employees matched

## Known Issues and Fixes Applied

### Issue 1: Oracle TNS Listener Not Ready
- **Problem**: Schema creation ran before Oracle listener was ready
- **Fix**: Minimum 90 second wait, proper ORA- error detection, retry logic
- **Status**: FIXED

### Issue 2: Setup Scripts Completing Despite Failures
- **Problem**: Scripts reported success even when database failed
- **Fix**: Added `set -e`, explicit exit codes, numeric validation for state files
- **Status**: FIXED

### Issue 3: DBeaver Not Visible at Task Start
- **Problem**: Task start showed bare desktop
- **Fix**: 3 retry attempts, 90s wait, visibility verification, fail on error
- **Status**: FIXED

### Issue 4: Initial State Files Corrupted
- **Problem**: Files contained "ERROR" text instead of numbers
- **Fix**: Numeric validation with regex, exit if non-numeric
- **Status**: FIXED

### Issue 5: oracle_query_raw Not Reporting Errors
- **Problem**: Function returned error text as if it were data
- **Fix**: Check for ORA- errors, return "ERROR" and exit code 1
- **Status**: FIXED

## Screenshots (Historical - May Show Failed States)

The screenshots in this directory are from historical testing iterations and may show failed states:
- 01_dbeaver_oracle_connected.png - DBeaver with connection panel
- 02_dbeaver_sql_query.png - Shows ORA-00923 error (failed test)
- 03_ubuntu_desktop.png - Bare Ubuntu desktop

These do NOT represent the expected task start state. After fixes, the task should start with DBeaver visible and running.

## Testing Commands

```bash
# SSH into the VM
ssh -p <ssh_port> ga@localhost
# Password: password123

# Check Oracle container
sudo docker ps | grep oracle-xe

# Test database connection
sudo docker exec oracle-xe sqlplus hr/hr123@localhost:1521/XEPDB1

# Check employee count
sudo docker exec oracle-xe bash -c "echo 'SELECT COUNT(*) FROM employees;' | sqlplus -s hr/hr123@localhost:1521/XEPDB1"

# Check DBeaver window
DISPLAY=:1 wmctrl -l | grep -i dbeaver
```

## Last Updated

2026-02-03 - Added `set -e`, fixed error propagation, improved validation
