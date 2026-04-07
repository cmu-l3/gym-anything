#!/bin/bash
# Setup script for RBAC HR Security Implementation task
echo "=== Setting up RBAC HR Security Implementation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /home/ga/.task_start_time

# -------------------------------------------------------
# Verify Oracle container is running
# -------------------------------------------------------
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running."

# Verify HR schema exists
HR_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM hr.employees;" "system" | tr -d '[:space:]')
if [ -z "$HR_CHECK" ] || [ "$HR_CHECK" = "ERROR" ] || [ "$HR_CHECK" -lt 1 ] 2>/dev/null; then
    echo "ERROR: HR schema not loaded or inaccessible"
    exit 1
fi
echo "HR schema verified ($HR_CHECK employees)"

# -------------------------------------------------------
# Clean up previous run artifacts (Idempotency)
# -------------------------------------------------------
echo "Cleaning up any existing artifacts from previous runs..."

sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
SET SERVEROUTPUT ON
BEGIN
  -- Drop users
  FOR u IN (SELECT username FROM dba_users WHERE username IN ('TEST_HR_MANAGER', 'TEST_HR_ANALYST', 'TEST_DEPT_MGR', 'TEST_READONLY')) LOOP
    EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
  END LOOP;
  
  -- Drop roles
  FOR r IN (SELECT role FROM dba_roles WHERE role IN ('HR_FULL_ACCESS', 'HR_ANALYST', 'DEPT_VIEWER', 'HR_READONLY')) LOOP
    EXECUTE IMMEDIATE 'DROP ROLE ' || r.role;
  END LOOP;
  
  -- Drop audit policies
  FOR p IN (SELECT policy_name FROM audit_unified_policies WHERE policy_name = 'SALARY_ACCESS_AUDIT') LOOP
    EXECUTE IMMEDIATE 'NOAUDIT POLICY SALARY_ACCESS_AUDIT';
    EXECUTE IMMEDIATE 'DROP AUDIT POLICY SALARY_ACCESS_AUDIT';
  END LOOP;
END;
/

-- Drop views in HR schema
BEGIN
  EXECUTE IMMEDIATE 'DROP VIEW hr.employees_public_vw';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP VIEW hr.compensation_audit_vw';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;
EOSQL

echo "Cleanup complete."

# -------------------------------------------------------
# Pre-configure connections in SQL Developer
# -------------------------------------------------------
echo "Pre-configuring SQL Developer connections..."
ensure_hr_connection "HR Schema" "hr" "hr123"
ensure_hr_connection "SYSTEM Admin" "system" "OraclePassword123"

# -------------------------------------------------------
# Launch SQL Developer
# -------------------------------------------------------
echo "Checking SQL Developer status..."
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    echo "Starting SQL Developer..."
    su - ga -c "DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 JAVA_TOOL_OPTIONS='--add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.desktop/sun.awt=ALL-UNNAMED --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED -Dsun.java2d.xrender=false' /opt/sqldeveloper/sqldeveloper.sh > /tmp/sqldeveloper_launch.log 2>&1 &"
    
    # Wait for window to appear
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
            echo "SQL Developer window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize and Focus SQL Developer
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2

# Take initial screenshot
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="