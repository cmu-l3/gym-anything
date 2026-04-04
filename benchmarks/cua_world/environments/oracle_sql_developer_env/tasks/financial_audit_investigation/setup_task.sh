#!/bin/bash
# Setup script for Financial Compliance Audit Investigation task
echo "=== Setting up Financial Compliance Audit Investigation ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# --- Clean up previous run artifacts ---
echo "Cleaning up previous run artifacts..."

oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE hr.expense_reports CASCADE CONSTRAINTS PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "hr" 2>/dev/null || true

oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE hr.salary_change_log CASCADE CONSTRAINTS PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "hr" 2>/dev/null || true

# Drop any triggers agent may have left from previous attempts
oracle_query "BEGIN
  FOR t IN (SELECT trigger_name FROM user_triggers WHERE table_name = 'EMPLOYEES') LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP TRIGGER hr.' || t.trigger_name;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END;
/
EXIT;" "hr" 2>/dev/null || true

# Restore original salaries in case of re-run (Oracle HR schema defaults)
# These are the canonical HR schema salary values
oracle_query "UPDATE hr.employees SET salary = 17000 WHERE employee_id = 101;
UPDATE hr.employees SET salary = 4400 WHERE employee_id = 200;
UPDATE hr.employees SET salary = 11000 WHERE employee_id = 114;
UPDATE hr.employees SET salary = 2700 WHERE employee_id = 139;
COMMIT;
EXIT;" "hr" 2>/dev/null || true

# --- Create EXPENSE_REPORTS table ---
echo "Creating EXPENSE_REPORTS table..."
oracle_query "CREATE TABLE hr.expense_reports (
  report_id       NUMBER PRIMARY KEY,
  employee_id     NUMBER REFERENCES hr.employees(employee_id),
  submission_date DATE NOT NULL,
  expense_type    VARCHAR2(50) NOT NULL,
  amount          NUMBER(10,2) NOT NULL,
  description     VARCHAR2(200),
  status          VARCHAR2(20) DEFAULT 'PENDING',
  CONSTRAINT chk_exp_status CHECK (status IN ('PENDING','APPROVED','REJECTED'))
);
EXIT;" "hr"

echo "Inserting expense report records..."
# Batch 1: Normal records + first duplicate pair (emp 100: reports 2 and 3 identical)
oracle_query "INSERT INTO hr.expense_reports VALUES (1,  100, DATE '2024-01-08', 'MEALS',           145.00, 'Client lunch Q1 kickoff', 'APPROVED');
INSERT INTO hr.expense_reports VALUES (2,  100, DATE '2024-01-15', 'TRAVEL',          1250.00, 'Flight NYC strategy meeting', 'PENDING');
INSERT INTO hr.expense_reports VALUES (3,  100, DATE '2024-01-15', 'TRAVEL',          1250.00, 'Flight NYC strategy meeting', 'PENDING');
INSERT INTO hr.expense_reports VALUES (4,  101, DATE '2024-01-20', 'EQUIPMENT',       8500.00, 'Executive laptop upgrade urgent', 'PENDING');
INSERT INTO hr.expense_reports VALUES (5,  102, DATE '2024-01-22', 'MEALS',            320.00, 'Department team lunch', 'APPROVED');
INSERT INTO hr.expense_reports VALUES (6,  103, DATE '2024-02-05', 'TRAVEL',           890.00, 'Flight Chicago client visit', 'APPROVED');
INSERT INTO hr.expense_reports VALUES (7,  103, DATE '2024-02-10', 'HOTEL',            420.00, 'Hotel Chicago conference', 'PENDING');
INSERT INTO hr.expense_reports VALUES (8,  103, DATE '2024-02-10', 'HOTEL',            420.00, 'Hotel Chicago conference', 'PENDING');
INSERT INTO hr.expense_reports VALUES (9,  104, DATE '2024-02-15', 'EQUIPMENT',       6300.00, 'Development workstation', 'PENDING');
INSERT INTO hr.expense_reports VALUES (10, 105, DATE '2024-02-18', 'OFFICE_SUPPLIES',   85.00, 'Printer cartridges', 'APPROVED');
COMMIT;
EXIT;" "hr"

# Batch 2: Remaining normal records
oracle_query "INSERT INTO hr.expense_reports VALUES (11, 106, DATE '2024-02-20', 'TRAVEL',          650.00, 'Train San Francisco summit', 'APPROVED');
INSERT INTO hr.expense_reports VALUES (12, 107, DATE '2024-02-25', 'MEALS',           210.00, 'Project kickoff dinner', 'APPROVED');
INSERT INTO hr.expense_reports VALUES (13, 108, DATE '2024-03-01', 'EQUIPMENT',      1200.00, 'Monitors for home office', 'PENDING');
INSERT INTO hr.expense_reports VALUES (14, 109, DATE '2024-03-05', 'TRAVEL',          450.00, 'Flight LA vendor meeting', 'APPROVED');
INSERT INTO hr.expense_reports VALUES (15, 110, DATE '2024-03-08', 'OFFICE_SUPPLIES',  45.00, 'Whiteboard markers', 'APPROVED');
INSERT INTO hr.expense_reports VALUES (16, 111, DATE '2024-03-10', 'TRAVEL',          780.00, 'Flight Seattle partner review', 'APPROVED');
INSERT INTO hr.expense_reports VALUES (17, 112, DATE '2024-03-12', 'MEALS',            95.00, 'Working lunch with auditors', 'APPROVED');
INSERT INTO hr.expense_reports VALUES (18, 113, DATE '2024-03-15', 'EQUIPMENT',       380.00, 'Ergonomic keyboard mouse', 'APPROVED');
INSERT INTO hr.expense_reports VALUES (19, 114, DATE '2024-03-18', 'TRAVEL',         1100.00, 'Flight Boston supply chain conf', 'PENDING');
INSERT INTO hr.expense_reports VALUES (20, 115, DATE '2024-03-20', 'MEALS',           175.00, 'Supplier negotiation lunch', 'APPROVED');
COMMIT;
EXIT;" "hr"

oracle_query "INSERT INTO hr.expense_reports VALUES (21, 116, DATE '2024-03-22', 'OFFICE_SUPPLIES',  220.00, 'Filing cabinets and folders', 'APPROVED');
INSERT INTO hr.expense_reports VALUES (22, 117, DATE '2024-03-25', 'TRAVEL',           520.00, 'Flight DC regulatory briefing', 'PENDING');
INSERT INTO hr.expense_reports VALUES (23, 118, DATE '2024-03-28', 'EQUIPMENT',        890.00, 'Headset webcam remote work', 'PENDING');
INSERT INTO hr.expense_reports VALUES (24, 119, DATE '2024-04-01', 'MEALS',            135.00, 'Quarter-end team celebration', 'APPROVED');
INSERT INTO hr.expense_reports VALUES (25, 120, DATE '2024-04-03', 'TRAVEL',           330.00, 'Train regional operations meeting', 'PENDING');
COMMIT;
EXIT;" "hr"

echo "25 expense reports inserted (2 duplicate pairs: emp 100 reports 2&3, emp 103 reports 7&8)"

# --- Create SALARY_CHANGE_LOG table ---
echo "Creating SALARY_CHANGE_LOG table..."
oracle_query "CREATE TABLE hr.salary_change_log (
  log_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  employee_id  NUMBER NOT NULL,
  old_salary   NUMBER(8,2),
  new_salary   NUMBER(8,2),
  changed_by   VARCHAR2(50) DEFAULT USER,
  change_date  TIMESTAMP DEFAULT SYSTIMESTAMP
);
EXIT;" "hr"

# --- Seed salary violations (4 employees outside their job range) ---
# Job ranges from HR schema:
#   AD_VP:    min=15000, max=30000  -> emp 101 set to 32000 (over max by 2000)
#   AD_ASST:  min=3000,  max=6000   -> emp 200 set to 7500  (over max by 1500)
#   PU_MAN:   min=8000,  max=15000  -> emp 114 set to 16800 (over max by 1800)
#   ST_CLERK: min=2000,  max=5000   -> emp 139 set to 5600  (over max by 600)
echo "Seeding 4 salary policy violations..."
oracle_query "UPDATE hr.employees SET salary = 32000 WHERE employee_id = 101;
UPDATE hr.employees SET salary = 7500  WHERE employee_id = 200;
UPDATE hr.employees SET salary = 16800 WHERE employee_id = 114;
UPDATE hr.employees SET salary = 5600  WHERE employee_id = 139;
COMMIT;
EXIT;" "hr"

# --- Record baseline counts for adversarial verification ---
echo "Recording baseline state..."

INITIAL_TRIGGER_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_triggers WHERE owner = 'HR' AND table_name = 'EMPLOYEES' AND status = 'ENABLED';" "system" | tr -d '[:space:]')
INITIAL_TRIGGER_COUNT=${INITIAL_TRIGGER_COUNT:-0}
printf '%s' "$INITIAL_TRIGGER_COUNT" > /tmp/initial_hr_trigger_count

VIOLATIONS_SEEDED=$(oracle_query_raw "SELECT COUNT(*) FROM hr.employees e JOIN hr.jobs j ON e.job_id = j.job_id WHERE e.salary < j.min_salary OR e.salary > j.max_salary;" "hr" | tr -d '[:space:]')
printf '%s' "${VIOLATIONS_SEEDED:-4}" > /tmp/known_salary_violations

EXP_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM hr.expense_reports;" "hr" | tr -d '[:space:]')
printf '%s' "${EXP_COUNT:-25}" > /tmp/initial_expense_count

echo "Baseline: $INITIAL_TRIGGER_COUNT existing triggers, $VIOLATIONS_SEEDED salary violations seeded"

# Ensure export directory exists
sudo -u ga mkdir -p /home/ga/Documents/exports 2>/dev/null || mkdir -p /home/ga/Documents/exports 2>/dev/null || true

# Pre-configure HR connection and focus SQL Developer
ensure_hr_connection "HR Database" "hr" "$HR_PWD"
sleep 2

if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
    open_hr_connection_in_sqldeveloper
fi

echo "=== Financial Audit setup complete ==="
echo "Seeded: 25 expense records (2 duplicate pairs), 4 salary violations, empty SALARY_CHANGE_LOG"
