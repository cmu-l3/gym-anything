#!/bin/bash
# Setup for EBR Zero-Downtime Deployment task
# Ensures a clean state by resetting default edition and removing artifacts

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up EBR Task ==="

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for database to be ready
wait_for_oracle_ready() {
    for i in {1..30}; do
        if sudo docker exec oracle-xe bash -c "sqlplus -s system/OraclePassword123@localhost:1521/XEPDB1 <<<'exit;'" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

if ! wait_for_oracle_ready; then
    echo "ERROR: Oracle database not reachable."
    exit 1
fi

echo "Cleaning up previous state..."

# SQL script to reset state
# 1. Reset default edition to ORA$BASE (if changed)
# 2. Drop the RELEASE_V2 edition (if exists)
# 3. Drop the package from HR schema
# 4. Revoke edition permissions to start fresh (optional, but ensures clean slate)

sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@localhost:1521/XEPDB1 << 'EOF'
SET SERVEROUTPUT ON
BEGIN
    -- 1. Reset Default Edition to ORA$BASE
    BEGIN
        EXECUTE IMMEDIATE 'ALTER DATABASE DEFAULT EDITION = ORA$BASE';
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Notice: Could not set default edition to ORA$BASE: ' || SQLERRM);
    END;

    -- 2. Drop RELEASE_V2 if it exists
    -- Note: Cannot drop an edition if it has active sessions or is the default
    BEGIN
        EXECUTE IMMEDIATE 'DROP EDITION RELEASE_V2 CASCADE';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -38802 THEN -- ORA-38802: edition does not exist
                DBMS_OUTPUT.PUT_LINE('Notice: Could not drop RELEASE_V2: ' || SQLERRM);
            END IF;
    END;

    -- 3. Cleanup HR objects
    BEGIN
        EXECUTE IMMEDIATE 'DROP PACKAGE hr.payroll_calc';
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;
END;
/
EXIT;
EOF

# Verify cleanup
echo "Verifying cleanup..."
CURRENT_EDITION=$(oracle_query_raw "SELECT property_value FROM database_properties WHERE property_name = 'DEFAULT_EDITION';" "system")
echo "Current Default Edition: $CURRENT_EDITION"

# Ensure HR account is unlocked
oracle_query "ALTER USER hr ACCOUNT UNLOCK;" "system" >/dev/null

# Clean up desktop files
rm -f /home/ga/Desktop/patch_validation.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="