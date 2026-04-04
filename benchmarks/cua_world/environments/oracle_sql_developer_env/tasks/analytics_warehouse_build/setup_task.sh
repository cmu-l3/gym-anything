#!/bin/bash
# Setup script for Analytics Data Warehouse Build task
echo "=== Setting up Analytics Data Warehouse Build ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle container
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# --- Drop and recreate the ANALYTICS user cleanly ---
echo "Setting up ANALYTICS schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER analytics CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER analytics IDENTIFIED BY Analytics2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA 100M ON users;
GRANT CREATE SESSION TO analytics;
GRANT CREATE TABLE TO analytics;
GRANT CREATE VIEW TO analytics;
GRANT CREATE SEQUENCE TO analytics;
GRANT CREATE PROCEDURE TO analytics;
EXIT;" "system"

# Grant SELECT on all HR tables so analytics can access source data
oracle_query "GRANT SELECT ON hr.employees TO analytics;
GRANT SELECT ON hr.departments TO analytics;
GRANT SELECT ON hr.jobs TO analytics;
GRANT SELECT ON hr.job_history TO analytics;
GRANT SELECT ON hr.locations TO analytics;
GRANT SELECT ON hr.countries TO analytics;
GRANT SELECT ON hr.regions TO analytics;
EXIT;" "system"

# --- Create staging tables (these are provided to the agent as source data) ---
echo "Creating staging tables in ANALYTICS schema..."

oracle_query "CREATE TABLE analytics.stg_employees AS
  SELECT
    employee_id,
    first_name,
    last_name,
    email,
    hire_date,
    job_id,
    salary,
    commission_pct,
    manager_id,
    department_id
  FROM hr.employees;
EXIT;" "system"

oracle_query "CREATE TABLE analytics.stg_departments AS
  SELECT
    department_id,
    department_name,
    manager_id,
    location_id
  FROM hr.departments;
EXIT;" "system"

oracle_query "CREATE TABLE analytics.stg_jobs AS
  SELECT
    job_id,
    job_title,
    min_salary,
    max_salary
  FROM hr.jobs;
EXIT;" "system"

oracle_query "CREATE TABLE analytics.stg_job_history AS
  SELECT
    employee_id,
    start_date,
    end_date,
    job_id,
    department_id
  FROM hr.job_history;
EXIT;" "system"

# Verify staging tables are loaded
STG_EMP_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM analytics.stg_employees;" "system" | tr -d '[:space:]')
STG_DEPT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM analytics.stg_departments;" "system" | tr -d '[:space:]')
STG_JOB_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM analytics.stg_jobs;" "system" | tr -d '[:space:]')
echo "Staging tables loaded: employees=$STG_EMP_COUNT, departments=$STG_DEPT_COUNT, jobs=$STG_JOB_COUNT"

# --- Record baseline (no FACT_* or DIM_* tables exist yet) ---
INITIAL_FACT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'ANALYTICS' AND table_name LIKE 'FACT%';" "system" | tr -d '[:space:]')
INITIAL_DIM_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'ANALYTICS' AND table_name LIKE 'DIM%';" "system" | tr -d '[:space:]')
printf '%s' "${INITIAL_FACT_COUNT:-0}" > /tmp/initial_fact_table_count
printf '%s' "${INITIAL_DIM_COUNT:-0}" > /tmp/initial_dim_table_count
echo "Baseline: $INITIAL_FACT_COUNT FACT tables, $INITIAL_DIM_COUNT DIM tables"

# Ensure export directory exists
sudo -u ga mkdir -p /home/ga/Documents/exports 2>/dev/null || mkdir -p /home/ga/Documents/exports 2>/dev/null || true

# Pre-configure connection for the analytics schema and HR
# Configure HR connection (main entry point)
ensure_hr_connection "HR Database" "hr" "$HR_PWD"

# Also pre-configure the Analytics connection
SQLDEVELOPER_SYSTEM_DIR=$(find /home/ga/.sqldeveloper -maxdepth 1 -name "system*" -type d 2>/dev/null | head -1)
if [ -n "$SQLDEVELOPER_SYSTEM_DIR" ]; then
    CONN_DIR=$(find "$SQLDEVELOPER_SYSTEM_DIR" -name "o.jdeveloper.db.connection*" -type d 2>/dev/null | head -1)
    if [ -z "$CONN_DIR" ]; then
        CONN_DIR="$SQLDEVELOPER_SYSTEM_DIR/o.jdeveloper.db.connection.24.2.0.284.2209"
        mkdir -p "$CONN_DIR"
    fi
    CONN_FILE="$CONN_DIR/connections.json"
    cat > "$CONN_FILE" << CONNEOF
{
  "connections": [
    {
      "name": "HR Database",
      "type": "jdbc",
      "info": {
        "role": "",
        "SavePassword": "true",
        "OracleConnectionType": "BASIC",
        "RaptorConnectionType": "Oracle",
        "customUrl": "jdbc:oracle:thin:@localhost:1521/XEPDB1",
        "hostname": "localhost",
        "driver": "oracle.jdbc.OracleDriver",
        "port": "1521",
        "subtype": "oraJDBC",
        "ConnName": "HR Database",
        "serviceName": "XEPDB1",
        "user": "hr",
        "password": "hr123"
      }
    },
    {
      "name": "Analytics Schema",
      "type": "jdbc",
      "info": {
        "role": "",
        "SavePassword": "true",
        "OracleConnectionType": "BASIC",
        "RaptorConnectionType": "Oracle",
        "customUrl": "jdbc:oracle:thin:@localhost:1521/XEPDB1",
        "hostname": "localhost",
        "driver": "oracle.jdbc.OracleDriver",
        "port": "1521",
        "subtype": "oraJDBC",
        "ConnName": "Analytics Schema",
        "serviceName": "XEPDB1",
        "user": "analytics",
        "password": "Analytics2024"
      }
    }
  ]
}
CONNEOF
    chown ga:ga "$CONN_FILE"
fi

sleep 2
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

echo "=== Analytics Warehouse setup complete ==="
echo "ANALYTICS schema created with 4 staging tables (stg_employees=$STG_EMP_COUNT rows)"
echo "Agent must design and build: FACT_EMPLOYEE_SNAPSHOT, DIM_DEPARTMENT, DIM_JOB, RPT_DEPT_SALARY_SUMMARY view"
