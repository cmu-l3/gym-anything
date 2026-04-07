#!/bin/bash
# Export script for mac_timestamp_anomaly_detection task

echo "=== Exporting results for mac_timestamp_anomaly_detection ==="

source /workspace/scripts/task_utils.sh

kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "mac_timestamp_anomaly_detection",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "csv_file_exists": False,
    "csv_mtime": 0,
    "csv_content": "",
    "csv_line_count": 0,
    "report_file_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/mac_anomaly_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Timestamp_Anomaly_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Timestamp_Anomaly_2024"
    with open("/tmp/mac_anomaly_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
result["case_db_found"] = True
result["case_name_matches"] = True
print(f"Found DB: {db_path}")

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Data source check
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    # Ingest check
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
        result["ingest_completed"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    conn.close()
except Exception as e:
    result["error"] += f" | DB error: {e}"

# Check CSV File
csv_path = "/home/ga/Reports/mac_timestamps.csv"
if os.path.exists(csv_path):
    result["csv_file_exists"] = True
    result["csv_mtime"] = int(os.path.getmtime(csv_path))
    with open(csv_path, "r", errors="replace") as f:
        content = f.read(32768)  # Read up to 32KB
    result["csv_content"] = content
    result["csv_line_count"] = len([l for l in content.splitlines() if l.strip()])
    print(f"CSV file: {result['csv_line_count']} lines")

# Check Report File
report_path = "/home/ga/Reports/timestamp_anomalies.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(8192)
    print(f"Report file: {len(result['report_content'])} chars")

print(json.dumps(result, indent=2))
with open("/tmp/mac_anomaly_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/mac_anomaly_result.json")
PYEOF

echo "=== Export complete ==="