#!/bin/bash
# Export script for PL/SQL Bulk Processing Optimization
# Validates the solution by:
# 1. Inspecting the source code for BULK COLLECT/FORALL
# 2. Resetting data and RUNNING the agent's procedure to verify functionality

set -e
echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Read expected values
EXPECTED_TOTAL=$(cat /tmp/expected_total_amount.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "Running verification logic inside container..."
python3 << 'PYEOF'
import oracledb
import json
import os
import time

result = {
    "procedure_status": "MISSING",
    "source_code": "",
    "bulk_collect_found": False,
    "forall_found": False,
    "limit_found": False,
    "commit_in_loop": False,
    "functional_test_passed": False,
    "log_count": 0,
    "balance_total": 0.0,
    "execution_time_sec": 0.0,
    "error_message": ""
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Procedure Status and Source Code
    cursor.execute("""
        SELECT status 
        FROM user_objects 
        WHERE object_name = 'PROCESS_DAILY_SETTLEMENTS' 
        AND object_type = 'PROCEDURE'
    """)
    row = cursor.fetchone()
    if row:
        result["procedure_status"] = row[0]
        
        # Get Source
        cursor.execute("""
            SELECT text 
            FROM user_source 
            WHERE name = 'PROCESS_DAILY_SETTLEMENTS' 
            ORDER BY line
        """)
        source_lines = [r[0] for r in cursor.fetchall()]
        full_source = "".join(source_lines).upper()
        result["source_code"] = full_source
        
        # Static Analysis
        result["bulk_collect_found"] = "BULK COLLECT" in full_source
        result["forall_found"] = "FORALL" in full_source
        result["limit_found"] = "LIMIT" in full_source
        
        # Check for bad commit pattern (Commit inside a LOOP but NOT after END LOOP)
        # This is a heuristic; robust check is hard with regex, but we look for COMMIT appearing between LOOP and END LOOP
        # Simplification: Just check if keywords present
        pass
    
    # 2. Functional Test: RESET Data and RUN the procedure
    if result["procedure_status"] == "VALID":
        print("Resetting data for functional verification...")
        cursor.execute("TRUNCATE TABLE settlement_log")
        cursor.execute("UPDATE merchant_balances SET balance = 0")
        conn.commit()
        
        print("Executing agent procedure...")
        start_time = time.time()
        try:
            cursor.callproc("PROCESS_DAILY_SETTLEMENTS")
            result["execution_time_sec"] = time.time() - start_time
            
            # 3. Verify Results
            cursor.execute("SELECT COUNT(*) FROM settlement_log")
            result["log_count"] = cursor.fetchone()[0]
            
            cursor.execute("SELECT SUM(balance) FROM merchant_balances")
            row = cursor.fetchone()
            result["balance_total"] = float(row[0]) if row and row[0] is not None else 0.0
            
            expected_total = float(os.environ.get("EXPECTED_TOTAL", 0))
            
            # Allow small float tolerance
            if result["log_count"] == 50000 and abs(result["balance_total"] - expected_total) < 1.0:
                result["functional_test_passed"] = True
            
        except Exception as e:
            result["error_message"] = f"Execution failed: {str(e)}"
    
    cursor.close()
    conn.close()

except Exception as e:
    result["error_message"] = f"Verification script error: {str(e)}"

# Save result
with open("/tmp/bulk_opt_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Copy out
cp /tmp/bulk_opt_result.json /tmp/task_result.json 2>/dev/null || true
echo "Results saved to /tmp/task_result.json"
cat /tmp/task_result.json