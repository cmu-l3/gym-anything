#!/bin/bash
# Setup script for Automated Compensation Processing task
# Grants necessary privileges and cleans up any previous artifacts

set -e

echo "=== Setting up Scheduler Compensation Automation Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight: Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Pre-flight: Verify Database Connection ---
echo "[2/4] Verifying HR schema connection..."
for attempt in 1 2 3; do
    if oracle_query "SELECT 1 FROM dual;" "hr" > /dev/null 2>&1; then
        echo "  Connection successful"
        break
    fi
    echo "  Waiting for database..."
    sleep 5
done

# --- Setup: Clean up and Grant Privileges ---
echo "[3/4] Preparing database state..."

# 1. Grant CREATE JOB to HR (required for DBMS_SCHEDULER)
echo "  Granting CREATE JOB to HR user..."
oracle_query "GRANT CREATE JOB TO hr;" "system"

# 2. Clean up any previous task artifacts to ensure a fresh start
echo "  Dropping existing objects if they exist..."
oracle_query "
BEGIN
    -- Drop jobs first
    BEGIN DBMS_SCHEDULER.DROP_JOB('MONTHLY_COMP_SNAPSHOT', TRUE); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DBMS_SCHEDULER.DROP_JOB('DAILY_ANOMALY_CHECK', TRUE); EXCEPTION WHEN OTHERS THEN NULL; END;
    
    -- Drop procedures
    BEGIN EXECUTE IMMEDIATE 'DROP PROCEDURE CAPTURE_COMP_SNAPSHOT'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP PROCEDURE DETECT_SALARY_ANOMALIES'; EXCEPTION WHEN OTHERS THEN NULL; END;
    
    -- Drop tables
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE COMPENSATION_SNAPSHOTS PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE SALARY_ANOMALIES PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    
    -- Drop sequences if used (best effort)
    BEGIN EXECUTE IMMEDIATE 'DROP SEQUENCE COMP_SNAPSHOT_SEQ'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP SEQUENCE SALARY_ANOMALY_SEQ'; EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/" "hr"

# 3. Clean up Desktop files
rm -f /home/ga/Desktop/compensation_snapshots.csv
rm -f /home/ga/Desktop/salary_anomalies.csv

# --- Final Steps ---
echo "[4/4] Finalizing setup..."
date +%s > /tmp/task_start_time.txt
chmod 644 /tmp/task_start_time.txt

# Ensure DBeaver is running for the agent
if ! pgrep -f dbeaver > /dev/null; then
    echo "  Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper &" 2>/dev/null || su - ga -c "DISPLAY=:1 dbeaver &" 2>/dev/null &
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="