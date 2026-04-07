#!/bin/bash
# Export script for ntfs_mft_data_run_mapping task

echo "=== Exporting results for ntfs_mft_data_run_mapping ==="

source /workspace/scripts/task_utils.sh

# Record final state visually
take_screenshot /tmp/task_final_state.png

# ── Kill Autopsy to release SQLite lock ───────────────────────────────────────
echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

# ── Gather results ────────────────────────────────────────────────────────────
python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "ntfs_mft_data_run_mapping",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "tsv_exists": False,
    "tsv_mtime": 0,
    "tsv_content": "",
    "summary_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/mft_data_run_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/MFT_Data_Run_Analysis*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for case MFT_Data_Run_Analysis"
else:
    db_path = db_paths[0]
    result["case_db_found"] = True
    result["case_name_matches"] = True
    
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()
        
        # Check data source was added
        try:
            cur.execute("SELECT COUNT(*) FROM data_source_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            try:
                cur.execute("SELECT COUNT(*) FROM tsk_image_info")
                result["data_source_added"] = cur.fetchone()[0] > 0
            except Exception:
                pass
        conn.close()
    except Exception as e:
        result["error"] += f" | DB open error: {e}"

# Read TSV report
tsv_path = "/home/ga/Reports/data_run_map.tsv"
if os.path.exists(tsv_path):
    result["tsv_exists"] = True
    result["tsv_mtime"] = int(os.path.getmtime(tsv_path))
    with open(tsv_path, "r", errors="replace") as f:
        result["tsv_content"] = f.read(32000)

# Read Summary report
summary_path = "/home/ga/Reports/mft_summary.txt"
if os.path.exists(summary_path):
    result["summary_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(8192)

print(json.dumps(result, indent=2))
with open("/tmp/mft_data_run_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export complete ==="