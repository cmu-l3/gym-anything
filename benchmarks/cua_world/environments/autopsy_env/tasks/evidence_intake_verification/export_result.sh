#!/bin/bash
# Export script for evidence_intake_verification task

echo "=== Exporting results for evidence_intake_verification ==="

source /workspace/scripts/task_utils.sh

# Record final state screenshot
take_screenshot /tmp/task_final.png

# Kill Autopsy to ensure DB locks are released
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "evidence_intake_verification",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "report_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "inventory_exists": False,
    "inventory_mtime": 0,
    "inventory_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/task_start_time.txt") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate case DB
db_paths = glob.glob("/home/ga/Cases/Evidence_Intake_2024*/autopsy.db")
if db_paths:
    db_path = db_paths[0]
    result["case_db_found"] = True
    result["case_name_matches"] = True
    
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
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
        result["error"] += f" | DB error: {e}"

# Process intake report
report_path = "/home/ga/Reports/intake_report.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(4096)

# Process inventory CSV
inventory_path = "/home/ga/Reports/file_inventory.csv"
if os.path.exists(inventory_path):
    result["inventory_exists"] = True
    result["inventory_mtime"] = int(os.path.getmtime(inventory_path))
    with open(inventory_path, "r", errors="replace") as f:
        result["inventory_content"] = f.read(1024 * 1024) # Cap size to 1MB to prevent memory issues

with open("/tmp/evidence_intake_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export complete ==="