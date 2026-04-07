#!/bin/bash
# Export script for file_size_anomaly_detection task

echo "=== Exporting results for file_size_anomaly_detection ==="

source /workspace/scripts/task_utils.sh

# 1. Take final state screenshot
take_screenshot /tmp/task_final_state.png

# 2. Kill Autopsy to release DB lock
kill_autopsy
sleep 3

# 3. Aggregate all results using Python
python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "file_size_anomaly_detection",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "inventory_exists": False,
    "inventory_mtime": 0,
    "inventory_content": "",
    "inventory_line_count": 0,
    "report_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

# Start time
try:
    with open("/tmp/size_anomaly_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate case DB
db_paths = glob.glob("/home/ga/Cases/Size_Anomaly_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for case Size_Anomaly_2024"
else:
    db_path = db_paths[0]
    result["case_db_found"] = True
    result["case_name_matches"] = True
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
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

# Inventory CSV
csv_path = "/home/ga/Reports/file_size_inventory.csv"
if os.path.exists(csv_path):
    result["inventory_exists"] = True
    result["inventory_mtime"] = int(os.path.getmtime(csv_path))
    with open(csv_path, "r", errors="replace") as f:
        content = f.read(100000) # Read up to 100KB to prevent OOM on massive files
    result["inventory_content"] = content
    result["inventory_line_count"] = len([l for l in content.splitlines() if l.strip()])

# Analytical Report
report_path = "/home/ga/Reports/size_anomaly_report.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(10000)

print(json.dumps(result, indent=2))
with open("/tmp/size_anomaly_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export complete ==="