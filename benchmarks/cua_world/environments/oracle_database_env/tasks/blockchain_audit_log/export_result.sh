#!/bin/bash
# Export results for Blockchain Audit Log task
# Queries DB for table metadata, row counts, and verifies evidence files

set -e

echo "=== Exporting Blockchain Audit Log Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python for reliable DB querying and JSON construction
python3 << 'PYEOF'
import oracledb
import json
import os
import sys

result = {
    "table_exists": False,
    "is_blockchain": False,
    "no_drop_days": 0,
    "no_delete_days": 0,
    "hash_algorithm": "UNKNOWN",
    "row_count": 0,
    "data_integrity_sample": None,
    "tamper_evidence_exists": False,
    "tamper_evidence_content": "",
    "signature_file_exists": False,
    "signature_file_content": "",
    "db_error": None
}

try:
    # Connect to DB
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Table Metadata (is it a blockchain table?)
    cursor.execute("""
        SELECT table_name, no_drop_days, no_delete_days, hash_algorithm
        FROM user_blockchain_tables
        WHERE table_name = 'SALARY_CHANGE_LEDGER'
    """)
    row = cursor.fetchone()
    if row:
        result["table_exists"] = True
        result["is_blockchain"] = True
        result["no_drop_days"] = row[1] if row[1] is not None else 0
        result["no_delete_days"] = row[2] if row[2] is not None else 0
        result["hash_algorithm"] = row[3]
    else:
        # Check if it exists as a normal table (failure case)
        cursor.execute("SELECT table_name FROM user_tables WHERE table_name = 'SALARY_CHANGE_LEDGER'")
        if cursor.fetchone():
            result["table_exists"] = True
            result["is_blockchain"] = False

    # 2. Check Row Count and Data
    if result["table_exists"]:
        cursor.execute("SELECT COUNT(*) FROM SALARY_CHANGE_LEDGER")
        result["row_count"] = cursor.fetchone()[0]

        # Verify specific data point (e.g., ID 1 matches expectation)
        try:
            cursor.execute("SELECT new_salary FROM SALARY_CHANGE_LEDGER WHERE log_id = 1")
            data = cursor.fetchone()
            if data:
                result["data_integrity_sample"] = data[0]
        except Exception:
            pass

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# 3. Check Evidence Files
evidence_path = "/home/ga/Desktop/tamper_evidence.txt"
if os.path.exists(evidence_path):
    result["tamper_evidence_exists"] = True
    # Check if created during task
    if os.path.getmtime(evidence_path) > float(sys.argv[1]):
        try:
            with open(evidence_path, 'r', errors='ignore') as f:
                result["tamper_evidence_content"] = f.read(1000).strip()
        except:
            pass

sig_path = "/home/ga/Desktop/latest_signature.txt"
if os.path.exists(sig_path):
    result["signature_file_exists"] = True
    if os.path.getmtime(sig_path) > float(sys.argv[1]):
        try:
            with open(sig_path, 'r', errors='ignore') as f:
                result["signature_file_content"] = f.read(1000).strip()
        except:
            pass

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF "$TASK_START"

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json