#!/bin/bash
# Export results for Storage Emergency Response task

set -e

echo "=== Exporting Storage Emergency Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# --- Run Verification Logic via Python ---
# We use Python to handle the complex checks (multiple queries, logic)
python3 << 'PYEOF'
import oracledb
import json
import os
import datetime

result = {
    "ts_archive_exists": False,
    "historical_table_moved": False,
    "historical_table_tablespace": "UNKNOWN",
    "ts_emr_logs_free_mb": 0.0,
    "indexes_valid": False,
    "invalid_index_count": -1,
    "operational_check_passed": False,
    "report_file_exists": False,
    "report_file_content": "",
    "timestamp": datetime.datetime.now().isoformat()
}

try:
    conn = oracledb.connect(user="system", password="OraclePassword123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check if TS_ARCHIVE exists
    cursor.execute("SELECT COUNT(*) FROM dba_tablespaces WHERE tablespace_name = 'TS_ARCHIVE'")
    if cursor.fetchone()[0] > 0:
        result["ts_archive_exists"] = True

    # 2. Check location of EMR_HISTORICAL_LOGS
    cursor.execute("SELECT tablespace_name FROM dba_segments WHERE segment_name = 'EMR_HISTORICAL_LOGS' AND owner = 'SYSTEM'")
    row = cursor.fetchone()
    if row:
        result["historical_table_tablespace"] = row[0]
        if row[0] == 'TS_ARCHIVE':
            result["historical_table_moved"] = True

    # 3. Check free space in TS_EMR_LOGS
    # Calculation: Sum of free bytes in dba_free_space
    cursor.execute("SELECT SUM(bytes)/1024/1024 FROM dba_free_space WHERE tablespace_name = 'TS_EMR_LOGS'")
    row = cursor.fetchone()
    if row and row[0]:
        result["ts_emr_logs_free_mb"] = float(row[0])

    # 4. Check Index Validity on EMR_HISTORICAL_LOGS
    # Moving a table marks indexes UNUSABLE unless rebuilt or UPDATE INDEXES used
    cursor.execute("""
        SELECT COUNT(*) 
        FROM dba_indexes 
        WHERE table_name = 'EMR_HISTORICAL_LOGS' 
          AND owner = 'SYSTEM' 
          AND status != 'VALID'
    """)
    invalid_count = cursor.fetchone()[0]
    result["invalid_index_count"] = invalid_count
    if invalid_count == 0:
        result["indexes_valid"] = True

    # 5. Operational Check: Try to insert into EMR_ADMISSION_LOGS
    try:
        cursor.execute("INSERT INTO system.emr_admission_logs (patient_id, admission_date, notes) VALUES (9999, SYSDATE, 'VERIFICATION_PROBE')")
        conn.commit()
        result["operational_check_passed"] = True
        # Clean up probe
        cursor.execute("DELETE FROM system.emr_admission_logs WHERE notes = 'VERIFICATION_PROBE'")
        conn.commit()
    except Exception as e:
        result["operational_check_error"] = str(e)

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# 6. Check Report File
report_path = "/home/ga/Desktop/storage_report.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    try:
        with open(report_path, "r") as f:
            result["report_file_content"] = f.read(500)
    except:
        pass

# Save to JSON
with open("/tmp/storage_emergency_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

echo "=== Export Done ==="
cat /tmp/storage_emergency_result.json