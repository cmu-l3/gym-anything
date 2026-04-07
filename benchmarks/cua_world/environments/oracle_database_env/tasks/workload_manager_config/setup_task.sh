#!/bin/bash
# Setup script for Workload Manager Configuration task
# Ensures clean state: no active plan, users exist, old plan deleted

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Workload Manager Task ==="

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for Oracle to be ready
echo "Checking Oracle status..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# Create setup SQL script
cat > /tmp/setup_workload.sql << 'EOF'
-- Connect as SYSTEM
CONNECT system/OraclePassword123@localhost:1521/XEPDB1

-- 1. Ensure Users Exist
DECLARE
  v_count NUMBER;
BEGIN
  SELECT count(*) INTO v_count FROM dba_users WHERE username = 'APP_USER';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER APP_USER IDENTIFIED BY AppUser123';
    EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE TO APP_USER';
  END IF;

  SELECT count(*) INTO v_count FROM dba_users WHERE username = 'RPT_USER';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER RPT_USER IDENTIFIED BY RptUser123';
    EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE TO RPT_USER';
  END IF;
END;
/

-- 2. Clean up previous state
-- Disable any active plan first to allow deletion
ALTER SYSTEM SET RESOURCE_MANAGER_PLAN = '';

-- Delete plan and groups if they exist (using pending area to be safe, or direct procedure)
BEGIN
    -- Delete plan cascade (removes directives)
    DBMS_RESOURCE_MANAGER.DELETE_PLAN_CASCADE(plan => 'STABILITY_PLAN');
EXCEPTION
    WHEN OTHERS THEN NULL; -- Ignore if doesn't exist
END;
/

BEGIN
    -- Delete consumer groups
    DBMS_RESOURCE_MANAGER.DELETE_CONSUMER_GROUP(consumer_group => 'CRITICAL_APP_CG');
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

BEGIN
    DBMS_RESOURCE_MANAGER.DELETE_CONSUMER_GROUP(consumer_group => 'BATCH_REPORT_CG');
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

-- Clear pending area if it exists from a crashed session
BEGIN
    DBMS_RESOURCE_MANAGER.CLEAR_PENDING_AREA();
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

-- Verify clean state
SELECT 'SETUP_COMPLETE' FROM dual;

EXIT;
EOF

echo "Executing setup SQL..."
sql_output=$(sudo docker exec -i "$ORACLE_CONTAINER" sqlplus /nolog << 'RUNSQL'
@/tmp/setup_workload.sql
RUNSQL
)

echo "$sql_output"

if echo "$sql_output" | grep -q "SETUP_COMPLETE"; then
    echo "Setup SQL executed successfully."
else
    echo "WARNING: Setup SQL might have had issues. Output:"
    echo "$sql_output"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="