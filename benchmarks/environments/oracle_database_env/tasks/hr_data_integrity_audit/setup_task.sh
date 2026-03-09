#!/bin/bash
# Setup for hr_data_integrity_audit task
# Plants three categories of data quality issues into the HR schema for the agent to discover and fix.
# Issue categories (intentionally NOT documented here to avoid tipping off the agent):
#   Category A: 5 employees (IDs 300-304) with salary outside their job's MIN/MAX range
#   Category B: 4 employees (IDs 305-308) with hire_date in the future
#   Category C: 3 employees (IDs 309-311) with NULL department_id despite having a valid manager

set -e

echo "=== Setting up HR Data Integrity Audit Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight: Verify Oracle is running ---
echo "[1/6] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container ($ORACLE_CONTAINER) not running!"
    exit 1
fi

# --- Pre-flight: Verify HR schema connectivity ---
echo "[2/6] Verifying HR schema connectivity..."
CONN_OK=0
for attempt in 1 2 3; do
    CONN_TEST=$(oracle_query_raw "SELECT COUNT(*) FROM employees;" "hr" 2>/dev/null | tr -d ' ')
    if [[ "$CONN_TEST" =~ ^[0-9]+$ ]] && [ "$CONN_TEST" -ge 100 ]; then
        echo "  HR schema ready: $CONN_TEST employees"
        CONN_OK=1
        break
    fi
    echo "  Attempt $attempt failed, waiting 10s..."
    sleep 10
done
if [ "$CONN_OK" -eq 0 ]; then
    echo "ERROR: Cannot connect to HR schema after 3 attempts"
    exit 1
fi

# --- Record baseline state BEFORE planting issues ---
echo "[3/6] Recording baseline state..."
INITIAL_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM employees;" "hr" | tr -d ' ')
INITIAL_COUNT=${INITIAL_COUNT:-107}
echo "$INITIAL_COUNT" > /tmp/initial_employee_count_audit
chmod 600 /tmp/initial_employee_count_audit

# --- Clean up any previously planted test data ---
echo "[4/6] Cleaning up any prior planted test data..."
oracle_query "
BEGIN
  EXECUTE IMMEDIATE 'DELETE FROM employees WHERE employee_id BETWEEN 300 AND 311';
  COMMIT;
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "hr" > /dev/null 2>&1 || true
sleep 1

# --- Plant Issue Category A: Salary outside job MIN/MAX range ---
# IT_PROG: min=4000, max=10000
# SA_REP:  min=6000, max=12008
# FI_ACCOUNT: min=4200, max=9000
# PU_CLERK: min=2500, max=5500
echo "  Planting salary violation records..."
oracle_query "
INSERT INTO employees VALUES (300, 'Marcus',   'Webb',      'MWEBB300A',   '650.555.0300', TO_DATE('12-03-2022','DD-MM-YYYY'), 'IT_PROG',    1200,  NULL, 103, 60);
INSERT INTO employees VALUES (301, 'Elena',    'Vasquez',   'EVASQUEZ1B',  '650.555.0301', TO_DATE('08-06-2021','DD-MM-YYYY'), 'IT_PROG',   18500,  NULL, 103, 60);
INSERT INTO employees VALUES (302, 'Reginald', 'Okafor',    'ROKAFOR2C',   '650.555.0302', TO_DATE('15-09-2020','DD-MM-YYYY'), 'SA_REP',      900,  NULL, 145, 80);
INSERT INTO employees VALUES (303, 'Priya',    'Sharma',    'PSHARMA3D',   '650.555.0303', TO_DATE('22-11-2019','DD-MM-YYYY'), 'FI_ACCOUNT', 25000, NULL, 108, 100);
INSERT INTO employees VALUES (304, 'Antoine',  'Leblanc',   'ALEBLANC4E',  '650.555.0304', TO_DATE('01-04-2021','DD-MM-YYYY'), 'PU_CLERK',    120,  NULL, 114, 30);
COMMIT;
" "hr" > /dev/null 2>&1 || { echo "WARNING: Some salary violation inserts may have failed"; }

SAL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM employees WHERE employee_id BETWEEN 300 AND 304;" "hr" | tr -d ' ')
echo "  Salary violation records planted: ${SAL_CHECK:-0}/5"

# --- Plant Issue Category B: Future hire dates ---
echo "  Planting future hire date records..."
oracle_query "
INSERT INTO employees VALUES (305, 'Yuki',   'Tanaka',    'YTANAKA5F',   '650.555.0305', TO_DATE('15-01-2028','DD-MM-YYYY'), 'IT_PROG',    7000, NULL, 103, 60);
INSERT INTO employees VALUES (306, 'Fatima', 'Al-Hassan', 'FALHASSAN6G', '650.555.0306', TO_DATE('30-06-2027','DD-MM-YYYY'), 'SA_REP',     8000, NULL, 145, 80);
INSERT INTO employees VALUES (307, 'Carlos', 'Gutierrez', 'CGUTIERR7H',  '650.555.0307', TO_DATE('20-03-2027','DD-MM-YYYY'), 'FI_ACCOUNT', 6500, NULL, 108, 100);
INSERT INTO employees VALUES (308, 'Amara',  'Diallo',    'ADIALLO8I',   '650.555.0308', TO_DATE('10-09-2029','DD-MM-YYYY'), 'HR_REP',     5500, NULL, 101, 40);
COMMIT;
" "hr" > /dev/null 2>&1 || { echo "WARNING: Some future date inserts may have failed"; }

DATE_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM employees WHERE employee_id BETWEEN 305 AND 308;" "hr" | tr -d ' ')
echo "  Future hire date records planted: ${DATE_CHECK:-0}/4"

# --- Plant Issue Category C: NULL department_id with valid manager ---
echo "  Planting NULL department records..."
oracle_query "
INSERT INTO employees VALUES (309, 'Victor',  'Petrov', 'VPETROV9J',  '650.555.0309', TO_DATE('14-05-2022','DD-MM-YYYY'), 'ST_CLERK', 2800, NULL, 120, NULL);
INSERT INTO employees VALUES (310, 'Mei',     'Zhang',  'MZHANG10K',  '650.555.0310', TO_DATE('28-08-2021','DD-MM-YYYY'), 'SH_CLERK', 3200, NULL, 121, NULL);
INSERT INTO employees VALUES (311, 'Ibrahim', 'Nkosi',  'INKOSI11L',  '650.555.0311', TO_DATE('03-11-2020','DD-MM-YYYY'), 'ST_CLERK', 2500, NULL, 122, NULL);
COMMIT;
" "hr" > /dev/null 2>&1 || { echo "WARNING: Some null dept inserts may have failed"; }

DEPT_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM employees WHERE employee_id BETWEEN 309 AND 311;" "hr" | tr -d ' ')
echo "  NULL department records planted: ${DEPT_CHECK:-0}/3"

# --- Final verification of planted issues ---
TOTAL_PLANTED=$(oracle_query_raw "SELECT COUNT(*) FROM employees WHERE employee_id BETWEEN 300 AND 311;" "hr" | tr -d ' ')
echo "  Total problematic employees in DB: ${TOTAL_PLANTED:-0}/12"

# --- Record task start timestamp ---
echo "[5/6] Recording task start..."
date +%s > /tmp/task_start_timestamp
chmod 600 /tmp/task_start_timestamp

# --- Clean up any prior audit report ---
rm -f /home/ga/Desktop/hr_audit_report.txt

# --- Ensure DBeaver is running ---
echo "[6/6] Ensuring DBeaver is available..."
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "dbeaver"; then
    su - ga -c "DISPLAY=:1 /snap/bin/dbeaver-ce &" > /dev/null 2>&1 || true
    sleep 6
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== HR Data Integrity Audit Setup Complete ==="
