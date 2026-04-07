#!/bin/bash
echo "=== Exporting results for secure_wipe_pattern_detection ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Kill Autopsy to release DB locks
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "secure_wipe_pattern_detection",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "csv_exists": False,
    "csv_mtime": 0,
    "csv_content": "",
    "summary_exists": False,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/secure_wipe_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Check Autopsy DB
db_paths = glob.glob("/home/ga/Cases/Spoliation_Investigation_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Spoliation_Investigation_2024"
else:
    db_path = db_paths[0]
    result["case_db_found"] = True
    result["case_name_matches"] = True
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        if cur.fetchone()[0] > 0:
            result["data_source_added"] = True
        conn.close()
    except Exception as e:
        result["error"] += f" | DB error: {e}"

# Read CSV report
csv_path = "/home/ga/Reports/wiping_analysis.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_mtime"] = int(os.path.getmtime(csv_path))
    with open(csv_path, "r", errors="replace") as f:
        result["csv_content"] = f.read(16384)

# Read summary report
summary_path = "/home/ga/Reports/spoliation_summary.txt"
if os.path.exists(summary_path):
    result["summary_exists"] = True
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(4096)

# Output JSON
with open("/tmp/secure_wipe_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/secure_wipe_result.json")
PYEOF

echo "=== Export complete ==="