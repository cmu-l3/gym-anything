#!/bin/bash
# Setup script for Schema Migration Preparation task
# Ensures clean state: removes previous backup tables and output files

set -e

echo "=== Setting up Schema Migration Prep Task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# --- Pre-flight: Verify Oracle is running ---
echo "Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Verify HR schema connectivity ---
echo "Verifying HR schema connectivity..."
for attempt in {1..5}; do
    if oracle_query_raw "SELECT 1 FROM DUAL;" "hr" > /dev/null 2>&1; then
        echo "  Connection OK"
        break
    fi
    echo "  Waiting for database..."
    sleep 5
done

# --- Clean up previous run artifacts (DB) ---
echo "Cleaning up backup tables..."
oracle_query "
BEGIN
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE bkp_employees PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE bkp_departments PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE bkp_jobs PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/" "hr" > /dev/null 2>&1 || true

# --- Clean up previous run artifacts (Files) ---
echo "Cleaning up output files..."
rm -f /home/ga/Desktop/hr_schema_ddl.sql
rm -f /home/ga/Desktop/migration_manifest.txt
rm -f /home/ga/Desktop/dependency_report.txt

# --- Record Initial Table Counts (for verification comparison) ---
echo "Recording initial row counts..."
EMP_COUNT=$(get_table_count "employees" "hr")
DEPT_COUNT=$(get_table_count "departments" "hr")
JOB_COUNT=$(get_table_count "jobs" "hr")

cat > /tmp/initial_counts.json << EOF
{
    "employees": ${EMP_COUNT:-0},
    "departments": ${DEPT_COUNT:-0},
    "jobs": ${JOB_COUNT:-0}
}
EOF

# Ensure DBeaver is installed (agent might need it)
if ! which dbeaver-ce > /dev/null 2>&1; then
    echo "Installing DBeaver..."
    sudo snap install dbeaver-ce --classic 2>/dev/null || true
fi

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="