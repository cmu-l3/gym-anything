#!/bin/bash
# Export script for intra_device_duplicate_analysis task

echo "=== Exporting results for intra_device_duplicate_analysis ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

# ── Gather results and DB state via Python ────────────────────────────────────
python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "intra_device_duplicate_analysis",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_has_hashes": False,
    "groups_file_exists": False,
    "groups_file_mtime": 0,
    "groups_content": "",
    "summary_file_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

# Read start time
try:
    with open("/tmp/duplicate_analysis_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Duplicate_Analysis_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for case Duplicate_Analysis_2024"
    with open("/tmp/duplicate_analysis_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
print(f"Found DB: {db_path}")
result["case_db_found"] = True
result["case_name_matches"] = True

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Check data source was added
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    # Check ingest completed
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
        result["ingest_completed"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    # Check if MD5 hashes were populated in the DB (anti-gaming to ensure Autopsy was used)
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE md5 IS NOT NULL AND md5 != ''")
        hash_count = cur.fetchone()[0]
        result["db_has_hashes"] = hash_count > 0
    except Exception as e:
        result["error"] += f" | DB hash query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# Check agent's groups report file
groups_path = "/home/ga/Reports/duplicate_groups.txt"
if os.path.exists(groups_path):
    result["groups_file_exists"] = True
    result["groups_file_mtime"] = int(os.path.getmtime(groups_path))
    with open(groups_path, "r", errors="replace") as f:
        result["groups_content"] = f.read(16384)

# Check summary file
summary_path = "/home/ga/Reports/duplicate_summary.txt"
if os.path.exists(summary_path):
    result["summary_file_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(2048)

print(json.dumps(result, indent=2))
with open("/tmp/duplicate_analysis_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/duplicate_analysis_result.json")
PYEOF

echo "=== Export complete ==="