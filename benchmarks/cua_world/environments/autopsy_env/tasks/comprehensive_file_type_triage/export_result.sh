#!/bin/bash
# Export script for comprehensive_file_type_triage task

echo "=== Exporting results for comprehensive_file_type_triage ==="

source /workspace/scripts/task_utils.sh

# ── Kill Autopsy to release SQLite lock ───────────────────────────────────────
kill_autopsy
sleep 3

# ── Take final screenshot ─────────────────────────────────────────────────────
take_screenshot /tmp/task_final_state.png ga

# ── Gather results via Python ─────────────────────────────────────────────────
python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "comprehensive_file_type_triage",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_total_files": 0,
    "db_files_with_mime": 0,
    "inventory_file_exists": False,
    "inventory_mtime": 0,
    "inventory_content": "",
    "summary_file_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/file_type_triage_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Check case DB
db_paths = glob.glob("/home/ga/Cases/USB_Triage_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for case USB_Triage_2024"
    with open("/tmp/file_type_triage_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
result["case_db_found"] = True
result["case_name_matches"] = True

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Check data source
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_image_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            pass

    # Check files & mime types
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
        result["db_total_files"] = cur.fetchone()[0]
        
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND mime_type IS NOT NULL AND mime_type != ''")
        result["db_files_with_mime"] = cur.fetchone()[0]
        
        if result["db_files_with_mime"] > 0:
            result["ingest_completed"] = True
    except Exception as e:
        result["error"] += f" | DB query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# Read Inventory File
inv_path = "/home/ga/Reports/file_type_inventory.txt"
if os.path.exists(inv_path):
    result["inventory_file_exists"] = True
    result["inventory_mtime"] = int(os.path.getmtime(inv_path))
    with open(inv_path, "r", errors="replace") as f:
        result["inventory_content"] = f.read(20000)

# Read Summary File
sum_path = "/home/ga/Reports/triage_summary.txt"
if os.path.exists(sum_path):
    result["summary_file_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(sum_path))
    with open(sum_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(4096)

with open("/tmp/file_type_triage_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export complete ==="