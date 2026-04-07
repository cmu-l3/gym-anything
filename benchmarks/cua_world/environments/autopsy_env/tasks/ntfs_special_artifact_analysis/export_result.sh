#!/bin/bash
# Export script for ntfs_special_artifact_analysis task

echo "=== Exporting results for ntfs_special_artifact_analysis ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# ── Kill Autopsy to release SQLite lock ───────────────────────────────────────
kill_autopsy
sleep 3

# ── Gather all results via Python ─────────────────────────────────────────────
python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "ntfs_special_artifact_analysis",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "inventory_file_exists": False,
    "inventory_mtime": 0,
    "inventory_content": "",
    "report_file_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/ntfs_artifact_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/NTFS_Artifact_Analysis_2024*/autopsy.db")
if not db_paths:
    db_paths = [p for p in glob.glob("/home/ga/Cases/*/autopsy.db") if "NTFS_Artifact" in p]
    
if not db_paths:
    result["error"] = "autopsy.db not found for case NTFS_Artifact_Analysis_2024"
    with open("/tmp/ntfs_artifact_result.json", "w") as f:
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

    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_image_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            pass

    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
        result["ingest_completed"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# Check inventory file
inventory_path = "/home/ga/Reports/ntfs_metafile_inventory.txt"
if os.path.exists(inventory_path):
    result["inventory_file_exists"] = True
    result["inventory_mtime"] = int(os.path.getmtime(inventory_path))
    with open(inventory_path, "r", errors="replace") as f:
        result["inventory_content"] = f.read(16384)

# Check report file
report_path = "/home/ga/Reports/ntfs_artifact_report.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(16384)

print(json.dumps(result, indent=2))
with open("/tmp/ntfs_artifact_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/ntfs_artifact_result.json")
PYEOF

echo "=== Export complete ==="