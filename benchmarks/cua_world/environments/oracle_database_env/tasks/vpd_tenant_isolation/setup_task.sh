#!/bin/bash
# Setup script for VPD Tenant Isolation task
# Creates the SAAS_CORE schema, populates data, and sets up the challenge environment

set -e

echo "=== Setting up VPD Tenant Isolation Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight: Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container ($ORACLE_CONTAINER) not running!"
    exit 1
fi

# Wait for DB to be ready
wait_for_oracle 300

# --- Create Schema and Data ---
echo "[2/4] Creating SAAS_CORE schema and populating data..."

# Create SQL setup script
cat > /tmp/setup_saas_env.sql << 'SQLEOF'
-- Clean up previous run
BEGIN
    EXECUTE IMMEDIATE 'DROP USER saas_core CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP USER clinic_north_app CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP USER clinic_south_app CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP USER saas_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- Create Schema Owner
CREATE USER saas_core IDENTIFIED BY Admin123;
GRANT CONNECT, RESOURCE, CREATE PROCEDURE, CREATE ANY CONTEXT TO saas_core;
GRANT CREATE ANY TRIGGER TO saas_core;
GRANT EXECUTE ON DBMS_RLS TO saas_core;
ALTER USER saas_core QUOTA UNLIMITED ON USERS;

-- Create App Users
CREATE USER clinic_north_app IDENTIFIED BY user123;
GRANT CREATE SESSION TO clinic_north_app;

CREATE USER clinic_south_app IDENTIFIED BY user123;
GRANT CREATE SESSION TO clinic_south_app;

CREATE USER saas_admin IDENTIFIED BY Admin123;
GRANT CREATE SESSION TO saas_admin;

-- Connect as SAAS_CORE to build objects
CONNECT saas_core/Admin123@localhost:1521/XEPDB1;

-- 1. Create Mapping Table
CREATE TABLE clinic_user_map (
    db_username VARCHAR2(30),
    clinic_id   NUMBER
);

INSERT INTO clinic_user_map VALUES ('CLINIC_NORTH_APP', 100);
INSERT INTO clinic_user_map VALUES ('CLINIC_SOUTH_APP', 200);
-- SAAS_ADMIN is intentionally NOT in the map (logic should handle NULL/missing)
COMMIT;

-- 2. Create Data Table
CREATE TABLE patient_encounters (
    encounter_id   NUMBER PRIMARY KEY,
    clinic_id      NUMBER,
    patient_name   VARCHAR2(50),
    diagnosis_code VARCHAR2(10),
    visit_date     DATE,
    notes          VARCHAR2(100)
);

-- 3. Populate Data (100 rows total)
BEGIN
    -- Clinic 100 (North): 35 rows
    FOR i IN 1..35 LOOP
        INSERT INTO patient_encounters VALUES (
            i, 100, 
            'Patient_N_' || i, 
            'J01.' || MOD(i, 9), 
            SYSDATE - MOD(i, 365), 
            'Routine checkup at Northside'
        );
    END LOOP;

    -- Clinic 200 (South): 42 rows
    FOR i IN 36..77 LOOP
        INSERT INTO patient_encounters VALUES (
            i, 200, 
            'Patient_S_' || i, 
            'E11.' || MOD(i, 9), 
            SYSDATE - MOD(i, 365), 
            'Follow-up at Southside'
        );
    END LOOP;

    -- Clinic 300 (Orphaned/Other): 23 rows (IDs 78-100)
    -- These should NOT be visible to North or South
    FOR i IN 78..100 LOOP
        INSERT INTO patient_encounters VALUES (
            i, 300, 
            'Patient_O_' || i, 
            'Z00.' || MOD(i, 9), 
            SYSDATE - MOD(i, 365), 
            'External clinic record'
        );
    END LOOP;
    COMMIT;
END;
/

-- 4. Grant Access
GRANT SELECT ON patient_encounters TO clinic_north_app;
GRANT SELECT ON patient_encounters TO clinic_south_app;
GRANT SELECT ON patient_encounters TO saas_admin;
-- Grant execute on map for debugging/policy (though policy runs as owner usually)
GRANT SELECT ON clinic_user_map TO clinic_north_app; 

EXIT;
SQLEOF

# Execute setup script as SYSTEM
echo "Running SQL setup..."
sudo docker exec -i "$ORACLE_CONTAINER" sqlplus -s system/${SYSTEM_PWD}@localhost:1521/XEPDB1 < /tmp/setup_saas_env.sql > /tmp/setup_log.txt 2>&1

if grep -q "ORA-" /tmp/setup_log.txt; then
    echo "WARNING: ORA- errors detected in setup:"
    grep "ORA-" /tmp/setup_log.txt
    # Continue only if errors are benign (like drop user failed)
fi

# --- Create Helper Script for Agent ---
echo "[3/4] Creating verification script for agent..."
cat > /home/ga/Desktop/verify_isolation.sql << 'EOF'
-- Agent Verification Script
-- Run this to check if your policy is working correctly.

SET LINESIZE 200
SET PAGESIZE 100
SET FEEDBACK OFF

PROMPT =================================================
PROMPT VERIFYING TENANT ISOLATION
PROMPT =================================================

PROMPT
PROMPT Connecting as CLINIC_NORTH_APP (Clinic 100)...
CONNECT clinic_north_app/user123@localhost:1521/XEPDB1
SELECT USER as CURRENT_USER, COUNT(*) as VISIBLE_ROWS FROM saas_core.patient_encounters;
PROMPT Expected: 35 rows

PROMPT
PROMPT Connecting as CLINIC_SOUTH_APP (Clinic 200)...
CONNECT clinic_south_app/user123@localhost:1521/XEPDB1
SELECT USER as CURRENT_USER, COUNT(*) as VISIBLE_ROWS FROM saas_core.patient_encounters;
PROMPT Expected: 42 rows

PROMPT
PROMPT Connecting as SAAS_ADMIN...
CONNECT saas_admin/Admin123@localhost:1521/XEPDB1
SELECT USER as CURRENT_USER, COUNT(*) as VISIBLE_ROWS FROM saas_core.patient_encounters;
PROMPT Expected: 100 rows

PROMPT
PROMPT =================================================
PROMPT verification complete
PROMPT
EXIT
EOF
chmod 644 /home/ga/Desktop/verify_isolation.sql

# --- Ensure DBeaver is installed (standard for Oracle env) ---
echo "[4/4] Ensuring DBeaver is ready..."
if ! which dbeaver-ce > /dev/null 2>&1; then
    sudo snap install dbeaver-ce --classic 2>/dev/null || true
fi

# Record start time
date +%s > /tmp/task_start_time

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "SAAS_CORE environment ready."