#!/bin/bash
# Setup for star_schema_warehouse task
# Ensures Oracle is ready and cleans up any previous warehouse tables

set -e

echo "=== Setting up Star Schema Warehouse Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# --- Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    # Try to start it (using the env's startup script if available, or manual start)
    /workspace/scripts/setup_oracle.sh || exit 1
fi

# --- Verify HR schema connectivity ---
echo "[2/4] Verifying HR schema..."
for attempt in 1 2 3; do
    EMP_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM employees;" "hr" 2>/dev/null | tr -d ' ')
    if [[ "$EMP_COUNT" =~ ^[0-9]+$ ]] && [ "$EMP_COUNT" -ge 100 ]; then
        echo "  HR schema ready: $EMP_COUNT employees"
        break
    fi
    echo "  Attempt $attempt failed, waiting 10s..."
    sleep 10
    if [ $attempt -eq 3 ]; then
        echo "ERROR: Cannot connect to HR schema"
        exit 1
    fi
done

# --- Clean up prior artifacts (Drop warehouse tables if they exist) ---
echo "[3/4] Cleaning up previous warehouse tables..."
oracle_query "
BEGIN
    FOR t IN (SELECT table_name FROM user_tables WHERE table_name IN ('FACT_WORKFORCE', 'DIM_EMPLOYEE', 'DIM_DEPARTMENT', 'DIM_JOB', 'DIM_TIME')) LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS';
    END LOOP;
    
    FOR s IN (SELECT sequence_name FROM user_sequences WHERE sequence_name LIKE '%_SEQ' OR sequence_name LIKE '%_KEY') LOOP
        EXECUTE IMMEDIATE 'DROP SEQUENCE ' || s.sequence_name;
    END LOOP;
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "hr" > /dev/null 2>&1 || true

# Remove file artifacts
rm -f /home/ga/Desktop/warehouse_analysis.txt
rm -f /home/ga/Desktop/warehouse_counts.txt

# --- Ensure DBeaver is running/ready ---
echo "[4/4] Preparing Desktop environment..."
# Launch DBeaver in background so it's ready for the agent
if ! pgrep -f dbeaver > /dev/null; then
    su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper &" > /dev/null 2>&1 || \
    su - ga -c "DISPLAY=:1 dbeaver-ce &" > /dev/null 2>&1 || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="