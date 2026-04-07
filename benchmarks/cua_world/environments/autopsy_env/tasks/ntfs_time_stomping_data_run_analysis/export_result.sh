#!/bin/bash
echo "=== Exporting results for ntfs_time_stomping_data_run_analysis ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_final_state.png ga

# Kill Autopsy to release SQLite locks
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "ntfs_time_stomping_data_run_analysis",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "tag_created": False,
    "tagged_files": [],
    "csv_exists": False,
    "csv_mtime": 0,
    "csv_content": "",
    "summary_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/mft_task_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# 1. Locate and parse autopsy.db
db_paths = glob.glob("/home/ga/Cases/MFT_Analysis_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for MFT_Analysis_2024"
    with open("/tmp/mft_analysis_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
result["case_db_found"] = True
result["case_name_matches"] = True

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Check Data Source
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_image_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            pass

    # Check Tagging
    try:
        cur.execute("""
            SELECT t.display_name, f.name, f.meta_addr 
            FROM content_tags ct 
            JOIN tag_names t ON ct.tag_name_id = t.tag_name_id 
            JOIN tsk_files f ON ct.obj_id = f.obj_id 
            WHERE t.display_name = 'Time Stomp Check'
        """)
        rows = cur.fetchall()
        if rows:
            result["tag_created"] = True
            result["tagged_files"] = [{"name": r[1], "inode": str(r[2])} for r in rows]
    except Exception as e:
        result["error"] += f" | Tag query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB error: {e}"

# 2. Extract Agent's Output CSV
csv_path = "/home/ga/Reports/mft_metadata_report.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_mtime"] = int(os.path.getmtime(csv_path))
    with open(csv_path, "r", errors="replace") as f:
        result["csv_content"] = f.read(16384)

# 3. Extract Summary Text
summary_path = "/home/ga/Reports/mft_summary.txt"
if os.path.exists(summary_path):
    result["summary_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(4096)

with open("/tmp/mft_analysis_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/mft_analysis_result.json")
PYEOF

echo "=== Export complete ==="