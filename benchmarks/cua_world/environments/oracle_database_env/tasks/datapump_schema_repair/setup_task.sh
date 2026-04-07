#!/bin/bash
# Setup for Data Pump Schema Repair task
# Ensures clean state: HR schema exists, HR_APP schema does NOT exist, Data Pump dir is clear.

set -e

echo "=== Setting up Data Pump Schema Repair Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight: Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container ($ORACLE_CONTAINER) not running!"
    exit 1
fi

# --- Pre-flight: Verify HR schema connectivity ---
echo "[2/4] Verifying HR schema connectivity..."
for attempt in 1 2 3; do
    CONN_TEST=$(oracle_query_raw "SELECT COUNT(*) FROM employees;" "hr" 2>/dev/null | tr -d ' ')
    if [[ "$CONN_TEST" =~ ^[0-9]+$ ]] && [ "$CONN_TEST" -ge 100 ]; then
        echo "  HR schema ready: $CONN_TEST employees"
        break
    fi
    echo "  Attempt $attempt failed, waiting 10s..."
    sleep 10
    if [ $attempt -eq 3 ]; then
        echo "ERROR: Cannot connect to HR schema"
        exit 1
    fi
done

# --- Clean up prior artifacts (HR_APP schema and dump files) ---
echo "[3/4] Cleaning up prior artifacts..."
oracle_query "
BEGIN
  -- Drop HR_APP user if exists
  BEGIN
    EXECUTE IMMEDIATE 'DROP USER hr_app CASCADE';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
/" "system" > /dev/null 2>&1 || true

# Clean up Data Pump directory in the container
# Default location for XE 21c is usually /opt/oracle/admin/XE/dpdump/
sudo docker exec "$ORACLE_CONTAINER" bash -c "rm -f /opt/oracle/admin/XE/dpdump/*.dmp /opt/oracle/admin/XE/dpdump/*.log" 2>/dev/null || true

# --- Record Baseline ---
echo "[4/4] Recording baseline state..."
date +%s > /tmp/task_start_timestamp
chmod 600 /tmp/task_start_timestamp

# Verify DATA_PUMP_DIR path (for debugging/verification later)
DP_DIR=$(oracle_query_raw "SELECT directory_path FROM dba_directories WHERE directory_name='DATA_PUMP_DIR';" "system" | tr -d ' ')
echo "  DATA_PUMP_DIR path: $DP_DIR"
echo "$DP_DIR" > /tmp/dp_dir_path.txt

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "  Target: Create HR_APP from HR (excluding REGIONS)"
echo "  Target: Fix EMP_DETAILS_VIEW in HR_APP"