#!/bin/bash
# Setup script for PL/SQL Bulk ETL Package task
echo "=== Setting up PL/SQL Bulk ETL Package task ==="

source /workspace/scripts/task_utils.sh

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# --- Clean up previous run artifacts ---
echo "Cleaning up previous run artifacts..."

# Drop package if agent left it from a prior attempt
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP PACKAGE hr.review_etl_pkg';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "hr" 2>/dev/null || true

# Drop view
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP VIEW hr.vw_review_summary';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "hr" 2>/dev/null || true

# Drop tables from previous run
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE hr.etl_run_log CASCADE CONSTRAINTS PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "hr" 2>/dev/null || true

oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE hr.perf_reviews CASCADE CONSTRAINTS PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "hr" 2>/dev/null || true

# Remove stale output file
rm -f /home/ga/Documents/exports/review_summary.csv 2>/dev/null || true
sudo -u ga rm -f /home/ga/Documents/exports/review_summary.csv 2>/dev/null || true

# --- Create PERF_REVIEWS table ---
echo "Creating PERF_REVIEWS table..."
oracle_query "CREATE TABLE hr.perf_reviews (
  review_id          NUMBER PRIMARY KEY,
  employee_id        NUMBER REFERENCES hr.employees(employee_id),
  reviewer_id        NUMBER REFERENCES hr.employees(employee_id),
  department_id      NUMBER REFERENCES hr.departments(department_id),
  review_period      VARCHAR2(10) NOT NULL,
  review_date        DATE NOT NULL,
  raw_score          NUMBER(5,2) NOT NULL,
  max_possible_score NUMBER(5,2) NOT NULL DEFAULT 100,
  normalized_score   NUMBER(5,2),
  comments           VARCHAR2(500),
  status             VARCHAR2(20) DEFAULT 'NEW',
  processed_date     DATE,
  CONSTRAINT chk_pr_status CHECK (status IN ('NEW','PROCESSED','ERROR','SKIPPED'))
);
EXIT;" "hr"

echo "Seeding 12000 performance review rows (this takes ~30 seconds)..."

# Seed rows in 3 batches of 4000 using PL/SQL
oracle_query "DECLARE
  TYPE emp_id_tab IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  v_emp_ids emp_id_tab;
  v_mgr_ids emp_id_tab;
  v_dept_ids emp_id_tab;
  v_periods  SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST('2022-Q1','2022-Q2','2022-Q3','2022-Q4','2023-Q1','2023-Q2','2023-Q3','2023-Q4');
  v_idx      PLS_INTEGER := 1;
  v_emp_idx  PLS_INTEGER;
  v_dept_id  NUMBER;
  v_raw      NUMBER(5,2);
  v_mgr      NUMBER;
  v_period   VARCHAR2(10);
  v_date     DATE;
BEGIN
  SELECT employee_id BULK COLLECT INTO v_emp_ids FROM hr.employees WHERE job_id NOT LIKE 'AD%';
  SELECT NVL(manager_id, employee_id) BULK COLLECT INTO v_mgr_ids FROM hr.employees WHERE job_id NOT LIKE 'AD%';
  SELECT department_id BULK COLLECT INTO v_dept_ids FROM hr.employees WHERE job_id NOT LIKE 'AD%';
  FOR i IN 1..4000 LOOP
    v_emp_idx := MOD(i - 1, v_emp_ids.COUNT) + 1;
    v_raw     := ROUND(50 + DBMS_RANDOM.VALUE(0, 50), 2);
    v_period  := v_periods(MOD(i - 1, 8) + 1);
    v_date    := TO_DATE('2022-01-01','YYYY-MM-DD') + (i * 0.3);
    INSERT INTO hr.perf_reviews VALUES (
      i,
      v_emp_ids(v_emp_idx),
      v_mgr_ids(v_emp_idx),
      v_dept_ids(v_emp_idx),
      v_period,
      v_date,
      v_raw,
      100,
      NULL,
      'Auto-generated review ' || i,
      'NEW',
      NULL
    );
  END LOOP;
  COMMIT;
END;
/
EXIT;" "hr"

oracle_query "DECLARE
  TYPE emp_id_tab IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  v_emp_ids  emp_id_tab;
  v_mgr_ids  emp_id_tab;
  v_dept_ids emp_id_tab;
  v_periods  SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST('2022-Q1','2022-Q2','2022-Q3','2022-Q4','2023-Q1','2023-Q2','2023-Q3','2023-Q4');
  v_emp_idx  PLS_INTEGER;
  v_raw      NUMBER(5,2);
  v_period   VARCHAR2(10);
  v_date     DATE;
BEGIN
  SELECT employee_id BULK COLLECT INTO v_emp_ids FROM hr.employees WHERE job_id NOT LIKE 'AD%';
  SELECT NVL(manager_id, employee_id) BULK COLLECT INTO v_mgr_ids FROM hr.employees WHERE job_id NOT LIKE 'AD%';
  SELECT department_id BULK COLLECT INTO v_dept_ids FROM hr.employees WHERE job_id NOT LIKE 'AD%';
  FOR i IN 4001..8000 LOOP
    v_emp_idx := MOD(i - 1, v_emp_ids.COUNT) + 1;
    v_raw     := ROUND(55 + DBMS_RANDOM.VALUE(0, 45), 2);
    v_period  := v_periods(MOD(i - 1, 8) + 1);
    v_date    := TO_DATE('2022-01-01','YYYY-MM-DD') + (i * 0.3);
    INSERT INTO hr.perf_reviews VALUES (
      i,
      v_emp_ids(v_emp_idx),
      v_mgr_ids(v_emp_idx),
      v_dept_ids(v_emp_idx),
      v_period,
      v_date,
      v_raw,
      100,
      NULL,
      'Auto-generated review ' || i,
      'NEW',
      NULL
    );
  END LOOP;
  COMMIT;
END;
/
EXIT;" "hr"

oracle_query "DECLARE
  TYPE emp_id_tab IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  v_emp_ids  emp_id_tab;
  v_mgr_ids  emp_id_tab;
  v_dept_ids emp_id_tab;
  v_periods  SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST('2022-Q1','2022-Q2','2022-Q3','2022-Q4','2023-Q1','2023-Q2','2023-Q3','2023-Q4');
  v_emp_idx  PLS_INTEGER;
  v_raw      NUMBER(5,2);
  v_period   VARCHAR2(10);
  v_date     DATE;
BEGIN
  SELECT employee_id BULK COLLECT INTO v_emp_ids FROM hr.employees WHERE job_id NOT LIKE 'AD%';
  SELECT NVL(manager_id, employee_id) BULK COLLECT INTO v_mgr_ids FROM hr.employees WHERE job_id NOT LIKE 'AD%';
  SELECT department_id BULK COLLECT INTO v_dept_ids FROM hr.employees WHERE job_id NOT LIKE 'AD%';
  FOR i IN 8001..12000 LOOP
    v_emp_idx := MOD(i - 1, v_emp_ids.COUNT) + 1;
    v_raw     := ROUND(60 + DBMS_RANDOM.VALUE(0, 40), 2);
    v_period  := v_periods(MOD(i - 1, 8) + 1);
    v_date    := TO_DATE('2022-01-01','YYYY-MM-DD') + (i * 0.3);
    INSERT INTO hr.perf_reviews VALUES (
      i,
      v_emp_ids(v_emp_idx),
      v_mgr_ids(v_emp_idx),
      v_dept_ids(v_emp_idx),
      v_period,
      v_date,
      v_raw,
      100,
      NULL,
      'Auto-generated review ' || i,
      'NEW',
      NULL
    );
  END LOOP;
  COMMIT;
END;
/
EXIT;" "hr"

echo "12000 PERF_REVIEWS rows seeded"

# --- Create ETL_RUN_LOG table ---
echo "Creating ETL_RUN_LOG table..."
oracle_query "CREATE TABLE hr.etl_run_log (
  run_id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run_start_ts   TIMESTAMP NOT NULL,
  run_end_ts     TIMESTAMP,
  rows_processed NUMBER DEFAULT 0,
  rows_errored   NUMBER DEFAULT 0,
  run_status     VARCHAR2(20) DEFAULT 'RUNNING',
  run_by         VARCHAR2(50) DEFAULT USER,
  comments       VARCHAR2(500),
  CONSTRAINT chk_run_status CHECK (run_status IN ('RUNNING','COMPLETED','FAILED'))
);
EXIT;" "hr"

# --- Record baseline state for adversarial robustness ---
echo "Recording baseline state..."

INITIAL_PROCESSED=$(oracle_query_raw "SELECT COUNT(*) FROM hr.perf_reviews WHERE status = 'PROCESSED';" "hr" | tr -d '[:space:]')
printf '%s' "${INITIAL_PROCESSED:-0}" > /tmp/plsql_bulk_etl_initial_processed
echo "Baseline: ${INITIAL_PROCESSED:-0} rows already PROCESSED (should be 0)"

INITIAL_PKG_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner = 'HR' AND object_name = 'REVIEW_ETL_PKG' AND object_type IN ('PACKAGE','PACKAGE BODY');" "system" | tr -d '[:space:]')
printf '%s' "${INITIAL_PKG_COUNT:-0}" > /tmp/plsql_bulk_etl_initial_pkg_count
echo "Baseline: ${INITIAL_PKG_COUNT:-0} package objects exist (should be 0)"

INITIAL_LOG_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM hr.etl_run_log;" "hr" | tr -d '[:space:]')
printf '%s' "${INITIAL_LOG_ROWS:-0}" > /tmp/plsql_bulk_etl_initial_log_rows
echo "Baseline: ${INITIAL_LOG_ROWS:-0} ETL log rows exist (should be 0)"

date +%s > /tmp/plsql_bulk_etl_start_ts

# Ensure export directory exists
sudo -u ga mkdir -p /home/ga/Documents/exports 2>/dev/null || mkdir -p /home/ga/Documents/exports 2>/dev/null || true

# Pre-configure HR connection and focus SQL Developer
ensure_hr_connection "HR Database" "hr" "${HR_PWD:-hr123}"
sleep 2

if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
    open_hr_connection_in_sqldeveloper
fi

echo "=== PL/SQL Bulk ETL Package setup complete ==="
echo "Ready: 12000 PERF_REVIEWS rows with STATUS='NEW', empty ETL_RUN_LOG, no REVIEW_ETL_PKG package"
