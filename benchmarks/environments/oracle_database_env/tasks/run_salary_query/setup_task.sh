#!/bin/bash
# Setup script for Run Salary Query task
# Ensures database is ready with GUI visible and cleans up any previous results

# Exit on any unhandled error
set -e

# Trap to ensure we log exit status
trap 'EXIT_CODE=$?; if [ $EXIT_CODE -ne 0 ]; then echo "TASK SETUP FAILED with exit code $EXIT_CODE"; fi' EXIT

echo "=== Setting up Run Salary Query task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ============================================================
# CRITICAL: Pre-flight database connectivity checks
# ============================================================

echo ""
echo "=== Running Pre-flight Database Checks ==="

# Verify Oracle container is running
echo "Checking Oracle container..."
if ! sudo docker ps | grep -q oracle-xe; then
    echo "ERROR: Oracle container not running!"
    echo "TASK SETUP FAILED: Cannot proceed without database"
    exit 1
fi
echo "  Oracle container: RUNNING"

# Test database connection with retry
echo "Testing database connection..."
DB_CONNECTED=false
for attempt in {1..5}; do
    echo "  Connection attempt $attempt..."

    # Try to connect and run a simple query
    TEST_OUTPUT=$(sudo docker exec oracle-xe bash -c "sqlplus -s hr/hr123@localhost:1521/XEPDB1 <<'SQLEOF'
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT 'CONNECTION_OK' FROM DUAL;
EXIT;
SQLEOF" 2>&1)

    # Check for ORA- errors
    if echo "$TEST_OUTPUT" | grep -q "ORA-"; then
        ORA_ERROR=$(echo "$TEST_OUTPUT" | grep "ORA-" | head -1)
        echo "    Connection failed: $ORA_ERROR"
        sleep 5
        continue
    fi

    # Check for success marker
    if echo "$TEST_OUTPUT" | grep -q "CONNECTION_OK"; then
        DB_CONNECTED=true
        echo "  Database connection: OK"
        break
    fi

    sleep 5
done

if [ "$DB_CONNECTED" != "true" ]; then
    echo "ERROR: Database connection failed after 5 attempts!"
    echo "TASK SETUP FAILED: Cannot proceed without database connection"
    echo "Last output: $TEST_OUTPUT"
    exit 1
fi

# Verify HR schema exists and has data
echo "Verifying HR schema..."
SCHEMA_OUTPUT=$(sudo docker exec oracle-xe bash -c "sqlplus -s hr/hr123@localhost:1521/XEPDB1 <<'SQLEOF'
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM employees;
EXIT;
SQLEOF" 2>&1)

# Extract employee count
EMP_COUNT=$(echo "$SCHEMA_OUTPUT" | grep -E '^\s*[0-9]+\s*$' | tr -d '[:space:]')

if [ -z "$EMP_COUNT" ] || [ "$EMP_COUNT" -lt 100 ] 2>/dev/null; then
    echo "ERROR: HR schema not properly loaded (expected 100+ employees, found: ${EMP_COUNT:-0})"
    echo "TASK SETUP FAILED: HR schema required for this task"
    exit 1
fi
echo "  HR schema: OK ($EMP_COUNT employees)"

# Verify IT department employees exist (task requirement)
IT_EMP_OUTPUT=$(sudo docker exec oracle-xe bash -c "sqlplus -s hr/hr123@localhost:1521/XEPDB1 <<'SQLEOF'
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM employees WHERE department_id = 60 AND salary > 5000;
EXIT;
SQLEOF" 2>&1)

IT_EMP_COUNT=$(echo "$IT_EMP_OUTPUT" | grep -E '^\s*[0-9]+\s*$' | tr -d '[:space:]')

if [ -z "$IT_EMP_COUNT" ] || [ "$IT_EMP_COUNT" -lt 1 ] 2>/dev/null; then
    echo "ERROR: No IT employees with salary > 5000 found (expected at least 2)"
    echo "TASK SETUP FAILED: Required data missing"
    exit 1
fi
echo "  IT dept employees (salary > 5000): $IT_EMP_COUNT"

echo "=== Pre-flight checks PASSED ==="
echo ""

# Store expected count for verification (not shown to agent)
echo "$IT_EMP_COUNT" > /tmp/expected_query_count
chmod 600 /tmp/expected_query_count  # Restrict access

# Clean up any previous result file
rm -f /tmp/query_results.txt 2>/dev/null || true

# ============================================================
# Verify DBeaver is installed (but don't launch it - agent should open it)
# ============================================================

echo ""
echo "=== Verifying DBeaver Installation ==="

# Kill any existing DBeaver processes to ensure clean state
echo "Cleaning up any existing DBeaver processes..."
pkill -f dbeaver 2>/dev/null || true
sleep 2

# Install DBeaver if not present
if ! which dbeaver-ce > /dev/null 2>&1; then
    echo "Installing DBeaver..."
    sudo snap install dbeaver-ce --classic 2>/dev/null || true
    sleep 10
fi

# Verify DBeaver is installed
if ! which dbeaver-ce > /dev/null 2>&1; then
    echo "ERROR: DBeaver is not installed and could not be installed!"
    exit 1
fi
echo "DBeaver installation: OK"

# Take screenshot of clean desktop state BEFORE task starts
echo ""
echo "Taking task start screenshot (clean desktop)..."
sleep 2
DISPLAY=:1 import -window root /tmp/task_start_screenshot.png 2>/dev/null || true
echo "Task start screenshot saved to /tmp/task_start_screenshot.png"

echo ""
echo "=== Run Salary Query Task Ready ==="
echo ""
echo "The agent should open DBeaver from the applications menu and connect to the database."
echo "Save results to: /tmp/query_results.txt"
echo ""
echo "Connection details available to agent:"
echo "  Host: localhost"
echo "  Port: 1521"
echo "  Database/Service: XEPDB1"
echo "  Username: hr"
echo "  Password: hr123"
echo ""
