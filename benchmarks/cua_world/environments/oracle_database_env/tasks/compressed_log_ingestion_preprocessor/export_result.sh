#!/bin/bash
# Export results for Compressed Log Ingestion task

set -e

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
EXPORT_TIME=$(date -Iseconds)
take_screenshot /tmp/task_end.png

# Output JSON path
RESULT_JSON="/tmp/task_result.json"

# Python script to probe database and filesystem
python3 << PYEOF
import oracledb
import json
import os
import subprocess

result = {
    "table_exists": False,
    "table_config": {},
    "directory_exists": False,
    "directory_path": "",
    "preprocessor_used": False,
    "location_file": "",
    "query_success": False,
    "row_count": 0,
    "report_exists": False,
    "report_content": "",
    "db_error": "",
    "uncompressed_copy_found": False
}

try:
    # 1. Check Database Objects
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # Check External Table Definition
    cursor.execute("""
        SELECT table_name, type_name, default_directory_name, access_parameters
        FROM user_external_tables
        WHERE table_name = 'FIREWALL_LOGS_EXT'
    """)
    row = cursor.fetchone()
    if row:
        result["table_exists"] = True
        access_params = str(row[3]) if row[3] else ""
        result["table_config"] = {
            "type": row[1],
            "default_dir": row[2],
            "access_params": access_params
        }
        
        if "PREPROCESSOR" in access_params.upper():
            result["preprocessor_used"] = True

    # Check Location (File Name)
    cursor.execute("""
        SELECT location
        FROM user_external_locations
        WHERE table_name = 'FIREWALL_LOGS_EXT'
    """)
    loc_row = cursor.fetchone()
    if loc_row:
        result["location_file"] = loc_row[0]

    # Check Directory Object
    if result["table_config"].get("default_dir"):
        dir_name = result["table_config"]["default_dir"]
        cursor.execute("SELECT directory_path FROM all_directories WHERE directory_name = :1", [dir_name])
        dir_row = cursor.fetchone()
        if dir_row:
            result["directory_exists"] = True
            result["directory_path"] = dir_row[0]

    # 2. Test Query (The critical test for permissions and script functionality)
    # We query counts. If permissions are wrong, this raises ORA-29913
    try:
        cursor.execute("SELECT COUNT(*) FROM hr.firewall_logs_ext")
        count = cursor.fetchone()[0]
        result["query_success"] = True
        result["row_count"] = count
    except Exception as e:
        result["db_error"] = str(e)

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = f"Connection/Setup Error: {str(e)}"

# 3. Check Report File
report_path = "/home/ga/Desktop/blocked_report.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    try:
        with open(report_path, 'r') as f:
            result["report_content"] = f.read(500)
    except:
        pass

# 4. Check for uncompressed file (Anti-pattern check)
# If they unzipped the file to disk (e.g. firewall_trace.csv), they failed the storage requirement
if result["directory_path"] and os.path.exists(result["directory_path"]):
    for fname in os.listdir(result["directory_path"]):
        if fname.endswith(".csv") and not fname.endswith(".gz"):
            # Check if it's large (full dataset)
            if os.path.getsize(os.path.join(result["directory_path"], fname)) > 100000: # >100KB
                result["uncompressed_copy_found"] = True

# Save to JSON
with open("${RESULT_JSON}", "w") as f:
    json.dump(result, f, indent=2)

print("Export logic complete.")
PYEOF

# Adjust permissions
chmod 666 "$RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="