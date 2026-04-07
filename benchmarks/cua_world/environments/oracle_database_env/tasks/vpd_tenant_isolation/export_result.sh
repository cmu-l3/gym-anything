#!/bin/bash
# Export script for VPD Tenant Isolation task
# Verifies the solution by running a dynamic test suite inside the container

set -e
echo "=== Exporting VPD Isolation Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Create Python verification script to run inside the VM
# We use Python/oracledb because it handles multiple connections cleanly
cat > /tmp/verify_vpd.py << 'PYEOF'
import oracledb
import json
import sys

result = {
    "policy_exists": False,
    "policy_details": {},
    "north_count": -1,
    "south_count": -1,
    "admin_count": -1,
    "dynamic_test_passed": False,
    "dynamic_test_details": "",
    "errors": []
}

dsn = "localhost:1521/XEPDB1"

try:
    # 1. Check Policy Existence (as SYSTEM)
    conn_sys = oracledb.connect(user="system", password="OraclePassword123", dsn=dsn)
    cur_sys = conn_sys.cursor()
    
    cur_sys.execute("""
        SELECT policy_name, function, policy_group, enable
        FROM dba_policies 
        WHERE object_owner = 'SAAS_CORE' 
          AND object_name = 'PATIENT_ENCOUNTERS'
    """)
    policies = cur_sys.fetchall()
    if policies:
        result["policy_exists"] = True
        result["policy_details"] = {
            "name": policies[0][0],
            "function": policies[0][1],
            "enabled": policies[0][3]
        }
    
    cur_sys.close()
    conn_sys.close()

    # 2. Check Row Counts for Standard Users
    def get_count(user, pwd):
        try:
            conn = oracledb.connect(user=user, password=pwd, dsn=dsn)
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM saas_core.patient_encounters")
            count = cur.fetchone()[0]
            cur.close()
            conn.close()
            return count
        except Exception as e:
            result["errors"].append(f"Error connecting as {user}: {str(e)}")
            return -1

    result["north_count"] = get_count("clinic_north_app", "user123")
    result["south_count"] = get_count("clinic_south_app", "user123")
    result["admin_count"] = get_count("saas_admin", "Admin123")

    # 3. Dynamic Anti-Gaming Test
    # Create a brand new user and clinic mapping that the agent couldn't have hardcoded
    # If the policy correctly looks up the user in the table, this will work.
    try:
        conn_sys = oracledb.connect(user="system", password="OraclePassword123", dsn=dsn)
        cur_sys = conn_sys.cursor()
        
        # Setup Dynamic Test Data
        # User: DYNAMIC_TEST_99, Clinic: 999
        cur_sys.execute("CREATE USER dynamic_test_99 IDENTIFIED BY test1234")
        cur_sys.execute("GRANT CREATE SESSION TO dynamic_test_99")
        cur_sys.execute("GRANT SELECT ON saas_core.patient_encounters TO dynamic_test_99")
        
        # Insert mapping
        cur_sys.execute("INSERT INTO saas_core.clinic_user_map VALUES ('DYNAMIC_TEST_99', 999)")
        
        # Insert 1 row for this clinic
        cur_sys.execute("""
            INSERT INTO saas_core.patient_encounters (encounter_id, clinic_id, patient_name) 
            VALUES (9999, 999, 'Dynamic Patient')
        """)
        conn_sys.commit()
        
        # Connect as new user and check visibility
        conn_dyn = oracledb.connect(user="dynamic_test_99", password="test1234", dsn=dsn)
        cur_dyn = conn_dyn.cursor()
        cur_dyn.execute("SELECT COUNT(*) FROM saas_core.patient_encounters")
        dyn_count = cur_dyn.fetchone()[0]
        
        cur_dyn.close()
        conn_dyn.close()
        
        # Verify: Should see exactly 1 row
        if dyn_count == 1:
            result["dynamic_test_passed"] = True
            result["dynamic_test_details"] = "User saw exactly 1 row (correct)"
        else:
            result["dynamic_test_passed"] = False
            result["dynamic_test_details"] = f"User saw {dyn_count} rows (expected 1). Hardcoding suspected."
            
        # Cleanup
        cur_sys.execute("DROP USER dynamic_test_99 CASCADE")
        cur_sys.execute("DELETE FROM saas_core.clinic_user_map WHERE clinic_id = 999")
        cur_sys.execute("DELETE FROM saas_core.patient_encounters WHERE clinic_id = 999")
        conn_sys.commit()
        cur_sys.close()
        conn_sys.close()
        
    except Exception as e:
        result["errors"].append(f"Dynamic test failed: {str(e)}")

except Exception as e:
    result["errors"].append(f"Fatal verification error: {str(e)}")

with open("/tmp/vpd_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Run the python verification script
python3 /tmp/verify_vpd.py

# Check if audit file exists (bonus)
if [ -f "/home/ga/Desktop/isolation_audit.txt" ]; then
    echo "Audit file found."
fi

# Permissions fix
chmod 666 /tmp/vpd_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/vpd_result.json"
cat /tmp/vpd_result.json