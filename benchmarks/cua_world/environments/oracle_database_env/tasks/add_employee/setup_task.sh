#!/bin/bash
# Setup script for Add Employee task
# Records initial state and ensures Oracle database is ready with GUI visible and connected

# Exit on any unhandled error
set -e

# Trap to ensure we log exit status
trap 'EXIT_CODE=$?; if [ $EXIT_CODE -ne 0 ]; then echo "TASK SETUP FAILED with exit code $EXIT_CODE"; fi' EXIT

echo "=== Setting up Add Employee task ==="

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

echo "=== Pre-flight checks PASSED ==="
echo ""

# Get initial employee count (use verified count from pre-flight)
INITIAL_EMP_COUNT="$EMP_COUNT"

# CRITICAL: Validate that the value is numeric
if ! [[ "$INITIAL_EMP_COUNT" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Initial employee count is not numeric: '$INITIAL_EMP_COUNT'"
    echo "TASK SETUP FAILED: Cannot capture valid initial state"
    exit 1
fi

echo "$INITIAL_EMP_COUNT" > /tmp/initial_employee_count
echo "Initial employee count: $INITIAL_EMP_COUNT"

# Get max employee ID with proper validation
MAX_EMP_ID_OUTPUT=$(sudo docker exec oracle-xe bash -c "sqlplus -s hr/hr123@localhost:1521/XEPDB1 <<'SQLEOF'
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT NVL(MAX(employee_id), 0) FROM employees;
EXIT;
SQLEOF" 2>&1)

MAX_EMP_ID=$(echo "$MAX_EMP_ID_OUTPUT" | grep -E '^\s*[0-9]+\s*$' | tr -d '[:space:]')

# CRITICAL: Validate that the value is numeric
if ! [[ "$MAX_EMP_ID" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Max employee ID is not numeric: '$MAX_EMP_ID'"
    echo "Raw output: $MAX_EMP_ID_OUTPUT"
    echo "TASK SETUP FAILED: Cannot capture valid initial state"
    exit 1
fi

echo "$MAX_EMP_ID" > /tmp/initial_max_employee_id
echo "Current max employee ID: $MAX_EMP_ID"

# Protect the initial state files from being read by agent
chmod 600 /tmp/initial_employee_count 2>/dev/null || true
chmod 600 /tmp/initial_max_employee_id 2>/dev/null || true

# Check if target employee already exists (should not)
if employee_exists_by_name "Sarah" "Johnson"; then
    echo "WARNING: Employee 'Sarah Johnson' already exists - cleaning up..."
    oracle_query "DELETE FROM employees WHERE LOWER(first_name)='sarah' AND LOWER(last_name)='johnson';" "hr"

    # Re-capture counts after cleanup with validation
    INITIAL_EMP_COUNT=$(echo "$EMP_COUNT" | grep -E '^[0-9]+$' | head -1)
    if [[ "$INITIAL_EMP_COUNT" =~ ^[0-9]+$ ]]; then
        echo "$INITIAL_EMP_COUNT" > /tmp/initial_employee_count
    fi

    MAX_EMP_ID_OUTPUT=$(sudo docker exec oracle-xe bash -c "sqlplus -s hr/hr123@localhost:1521/XEPDB1 <<'SQLEOF'
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT NVL(MAX(employee_id), 0) FROM employees;
EXIT;
SQLEOF" 2>&1)
    MAX_EMP_ID=$(echo "$MAX_EMP_ID_OUTPUT" | grep -E '^\s*[0-9]+\s*$' | tr -d '[:space:]')
    if [[ "$MAX_EMP_ID" =~ ^[0-9]+$ ]]; then
        echo "$MAX_EMP_ID" > /tmp/initial_max_employee_id
    fi

    echo "Updated initial employee count: $INITIAL_EMP_COUNT, max ID: $MAX_EMP_ID"
fi

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
echo "=== Add Employee Task Ready ==="
echo ""
echo "The agent should open DBeaver from the applications menu and connect to the database."
echo ""
echo "Connection details available to agent:"
echo "  Host: localhost"
echo "  Port: 1521"
echo "  Database/Service: XEPDB1"
echo "  Username: hr"
echo "  Password: hr123"
echo ""
