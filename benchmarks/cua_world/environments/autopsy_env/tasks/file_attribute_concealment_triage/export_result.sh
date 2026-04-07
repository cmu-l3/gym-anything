#!/bin/bash
# Export script for file_attribute_concealment_triage task

echo "=== Exporting results for file_attribute_concealment_triage ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot showing end state
take_screenshot /tmp/task_final.png ga

# Kill Autopsy to release DB locks safely
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, hashlib

result = {
    "task": "file_attribute_concealment_triage",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "exported_files": [],
    "csv_exists": False,
    "csv_mtime": 0,
    "csv_content": "",
    "summary_exists": False,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

# Pull task start timestamp
try:
    with open("/tmp/concealment_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Case Database Checks
db_paths = glob.glob("/home/ga/Cases/Concealed_Evidence_2024*/autopsy.db")
if db_paths:
    db_path = db_paths[0]
    result["case_db_found"] = True
    result["case_name_matches"] = True
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()
        
        # Check if the data source was added
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
        
        # Check if ingest ran (files were indexed)
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
        result["ingest_completed"] = cur.fetchone()[0] > 0
        
        conn.close()
    except Exception as e:
        result["error"] += f" | DB query error: {e}"
else:
    result["error"] += " | autopsy.db not found for case Concealed_Evidence_2024"

# Exported Files Check
export_dir = "/home/ga/Reports/hidden_exports"
if os.path.isdir(export_dir):
    for root, dirs, files in os.walk(export_dir):
        for name in files:
            path = os.path.join(root, name)
            try:
                with open(path, 'rb') as f:
                    data = f.read()
                    md5 = hashlib.md5(data).hexdigest()
                result["exported_files"].append({
                    "name": name,
                    "md5": md5,
                    "size": len(data)
                })
            except Exception:
                pass

# CSV Report Check
csv_path = "/home/ga/Reports/concealed_files.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_mtime"] = int(os.path.getmtime(csv_path))
    try:
        with open(csv_path, "r", errors="replace") as f:
            result["csv_content"] = f.read(8192)
    except Exception:
        pass

# Summary Report Check
summary_path = "/home/ga/Reports/concealment_summary.txt"
if os.path.exists(summary_path):
    result["summary_exists"] = True
    try:
        with open(summary_path, "r", errors="replace") as f:
            result["summary_content"] = f.read(2048)
    except Exception:
        pass

with open("/tmp/concealment_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("Result written to /tmp/concealment_result.json")
PYEOF

echo "=== Export complete ==="