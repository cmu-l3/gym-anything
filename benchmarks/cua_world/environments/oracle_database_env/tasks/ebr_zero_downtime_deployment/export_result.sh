#!/bin/bash
# Export script for EBR Zero-Downtime Deployment
# Verifies the logic in both editions and checks the default edition status

set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting EBR Task Results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check for the user report file
REPORT_PATH="/home/ga/Desktop/patch_validation.txt"
REPORT_EXISTS=false
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=true
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1000) # Limit size
fi

# 3. Execute Verification Logic INSIDE the container using Python
# This avoids connectivity issues and uses the environment's installed drivers.
# We verify:
#   A. Default Edition setting
#   B. Logic in ORA$BASE (should be 1000)
#   C. Logic in RELEASE_V2 (should be 2400 for Emp 100)
#   D. Edition existence

echo "Running internal verification script..."

# Create the python script to run inside the container
cat > /tmp/verify_ebr.py << 'PYEOF'
import oracledb
import json
import sys

# Configuration
USER = "hr"
PWD = "hr123"
DSN = "localhost:1521/XEPDB1"
EMP_ID = 100
EXPECTED_BASE = 1000
EXPECTED_V2 = 2400 # 10% of 24000

result = {
    "default_edition": None,
    "editions_list": [],
    "hr_editions_enabled": False,
    "base_logic_result": None,
    "base_logic_error": None,
    "v2_logic_result": None,
    "v2_logic_error": None,
    "default_conn_result": None,
    "isolation_success": False,
    "cutover_success": False
}

try:
    # 1. Check System State (Default Edition & List)
    # Need SYSTEM privileges to see DBA_EDITIONS usually, or check DATABASE_PROPERTIES
    sys_conn = oracledb.connect(user="system", password="OraclePassword123", dsn=DSN)
    sys_cur = sys_conn.cursor()
    
    # Get Default Edition
    sys_cur.execute("SELECT property_value FROM database_properties WHERE property_name = 'DEFAULT_EDITION'")
    row = sys_cur.fetchone()
    if row:
        result["default_edition"] = row[0]
        
    # Get List of Editions
    sys_cur.execute("SELECT edition_name FROM dba_editions ORDER BY edition_name")
    result["editions_list"] = [r[0] for r in sys_cur.fetchall()]
    
    # Check if HR is editions enabled
    sys_cur.execute("SELECT editions_enabled FROM dba_users WHERE username = 'HR'")
    row = sys_cur.fetchone()
    if row:
        result["hr_editions_enabled"] = (row[0] == 'Y')
        
    sys_conn.close()

    # 2. Verify ORA$BASE Logic
    try:
        # Note: 'edition' param in connect requires config, or we use SQL execution to set it
        # Simple way: Connect, alter session
        conn_base = oracledb.connect(user=USER, password=PWD, dsn=DSN)
        cur_base = conn_base.cursor()
        cur_base.execute("ALTER SESSION SET EDITION = ORA$BASE")
        
        func_val = cur_base.callfunc("PAYROLL_CALC.GET_BONUS", oracledb.NUMBER, [EMP_ID])
        result["base_logic_result"] = func_val
        conn_base.close()
    except Exception as e:
        result["base_logic_error"] = str(e)

    # 3. Verify RELEASE_V2 Logic
    try:
        conn_v2 = oracledb.connect(user=USER, password=PWD, dsn=DSN)
        cur_v2 = conn_v2.cursor()
        cur_v2.execute("ALTER SESSION SET EDITION = RELEASE_V2")
        
        func_val = cur_v2.callfunc("PAYROLL_CALC.GET_BONUS", oracledb.NUMBER, [EMP_ID])
        result["v2_logic_result"] = func_val
        conn_v2.close()
    except Exception as e:
        result["v2_logic_error"] = str(e)

    # 4. Verify Default Connection Logic (Cutover Check)
    try:
        conn_def = oracledb.connect(user=USER, password=PWD, dsn=DSN)
        cur_def = conn_def.cursor()
        # Do NOT set edition, verify what we get by default
        func_val = cur_def.callfunc("PAYROLL_CALC.GET_BONUS", oracledb.NUMBER, [EMP_ID])
        result["default_conn_result"] = func_val
        conn_def.close()
    except Exception as e:
        result["default_conn_result"] = f"Error: {str(e)}"

    # Evaluation
    # Isolation: Base gives 1000, V2 gives 2400
    if result["base_logic_result"] == EXPECTED_BASE and result["v2_logic_result"] == EXPECTED_V2:
        result["isolation_success"] = True
        
    # Cutover: Default connection gives 2400 AND System says default is RELEASE_V2
    if result["default_conn_result"] == EXPECTED_V2 and result["default_edition"] == 'RELEASE_V2':
        result["cutover_success"] = True

except Exception as e:
    result["global_error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Copy script to container and run
sudo docker cp /tmp/verify_ebr.py oracle-xe:/tmp/verify_ebr.py
sudo docker exec oracle-xe python3 /tmp/verify_ebr.py > /tmp/verification_output.json

# Merge Report File status into JSON
# Using jq if available, otherwise simple python merge
python3 << PYMERGE
import json

try:
    with open('/tmp/verification_output.json', 'r') as f:
        data = json.load(f)
except:
    data = {"global_error": "Failed to load verification output"}

data["report_file_exists"] = "${REPORT_EXISTS}"
data["report_content"] = """${REPORT_CONTENT}"""

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
PYMERGE

echo "Result JSON generated:"
cat /tmp/task_result.json