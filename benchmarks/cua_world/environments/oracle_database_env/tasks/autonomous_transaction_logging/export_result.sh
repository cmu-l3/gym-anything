#!/bin/bash
# Export script for Autonomous Transaction Logging task

set -e
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Database Export Script using Python for robust JSON creation
python3 << 'PYEOF'
import oracledb
import json
import os
import re

result = {
    "logs_found": False,
    "log_entries": [],
    "balance_correct": False,
    "sender_balance": -1,
    "pragma_found": False,
    "logging_proc_exists": False,
    "evidence_file_exists": False,
    "evidence_file_content": ""
}

try:
    # Connect to DB
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()
    
    # 1. Check Logs
    # We look for entries created after the task started
    cursor.execute("""
        SELECT severity, message 
        FROM system_logs 
        WHERE message LIKE '%Insufficient funds%' 
        ORDER BY log_id DESC
    """)
    logs = cursor.fetchall()
    if logs:
        result["logs_found"] = True
        result["log_entries"] = [{"severity": r[0], "message": r[1]} for r in logs]
        
    # 2. Check Balances
    cursor.execute("SELECT balance FROM bank_accounts WHERE account_id = 1001")
    row = cursor.fetchone()
    if row:
        result["sender_balance"] = row[0]
        # Balance should be 1000 (initial) because the 5000 transfer failed
        if row[0] == 1000:
            result["balance_correct"] = True
            
    # 3. Check for PRAGMA AUTONOMOUS_TRANSACTION in source code
    cursor.execute("""
        SELECT name, text 
        FROM user_source 
        WHERE UPPER(text) LIKE '%PRAGMA%AUTONOMOUS_TRANSACTION%'
    """)
    source_rows = cursor.fetchall()
    if source_rows:
        result["pragma_found"] = True
        
    # 4. Check for distinct logging procedure (Modularization)
    # We check if there's a procedure other than PROCESS_TRANSFER that uses the pragma
    cursor.execute("""
        SELECT DISTINCT name 
        FROM user_source 
        WHERE UPPER(text) LIKE '%PRAGMA%AUTONOMOUS_TRANSACTION%'
        AND UPPER(name) != 'PROCESS_TRANSFER'
    """)
    mod_rows = cursor.fetchall()
    if mod_rows:
        result["logging_proc_exists"] = True

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# 5. Check Evidence File
evidence_path = "/home/ga/Desktop/audit_evidence.txt"
if os.path.exists(evidence_path):
    result["evidence_file_exists"] = True
    try:
        with open(evidence_path, 'r') as f:
            result["evidence_file_content"] = f.read(1000) # Read first 1000 chars
    except:
        pass

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

chmod 644 /tmp/task_result.json
echo "Results exported to /tmp/task_result.json"