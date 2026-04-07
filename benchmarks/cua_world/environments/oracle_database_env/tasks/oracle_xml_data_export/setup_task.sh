#!/bin/bash
# Setup for oracle_xml_data_export task
# Ensures clean state: removes output files and drops target function if exists

set -e

echo "=== Setting up Oracle XML Data Export Task ==="

source /workspace/scripts/task_utils.sh

# --- Verify Oracle is running ---
echo "[1/5] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Verify HR schema ---
echo "[2/5] Verifying HR schema connectivity..."
# Wait loop in case DB is warming up
for i in {1..5}; do
    EMP_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM employees;" "hr" 2>/dev/null | tr -d ' ')
    if [[ "$EMP_COUNT" =~ ^[0-9]+$ ]] && [ "$EMP_COUNT" -ge 100 ]; then
        echo "  HR schema ready: $EMP_COUNT employees"
        break
    fi
    echo "  Attempt $i failed or schema not ready. Retrying in 5s..."
    sleep 5
done

if [[ ! "$EMP_COUNT" =~ ^[0-9]+$ ]]; then
    echo "CRITICAL: HR schema check failed. Output: $EMP_COUNT"
    exit 1
fi

# --- Clean up prior artifacts ---
echo "[3/5] Cleaning up previous artifacts..."
rm -f /home/ga/Desktop/org_structure.xml
rm -f /home/ga/Desktop/compensation_feed.xml

# Drop the function if it exists from a previous run
oracle_query "
BEGIN
  EXECUTE IMMEDIATE 'DROP FUNCTION generate_dept_xml';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "hr" > /dev/null 2>&1 || true

# --- Record Task Start Time ---
echo "[4/5] Recording start time..."
date +%s > /tmp/task_start_timestamp

# --- Ensure Tools are Ready ---
echo "[5/5] Checking environment..."
# Ensure directory exists
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Files to be created:"
echo "  - /home/ga/Desktop/org_structure.xml"
echo "  - /home/ga/Desktop/compensation_feed.xml"
echo "Function to be created:"
echo "  - GENERATE_DEPT_XML"