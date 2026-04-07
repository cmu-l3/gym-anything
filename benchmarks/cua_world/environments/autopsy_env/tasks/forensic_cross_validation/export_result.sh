#!/bin/bash
# Export script for forensic_cross_validation task

echo "=== Exporting results for forensic_cross_validation ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before closing
take_screenshot /tmp/task_final_state.png ga

# ── Kill Autopsy to release SQLite lock ───────────────────────────────────────
echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

# ── Gather all results via Python ─────────────────────────────────────────────
python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "forensic_cross_validation",
    "case_db_found": False,
    "data_source_added": False,
    "ingest_completed": False,
    "tsk_raw_exists": False,
    "tsk_raw_mtime": 0,
    "tsk_raw_content": "",
    "tsk_inv_exists": False,
    "tsk_inv_mtime": 0,
    "tsk_inv_content": "",
    "aut_inv_exists": False,
    "aut_inv_mtime": 0,
    "aut_inv_content": "",
    "report_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

# Read start time
try:
    with open("/tmp/crossval_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/QA_Crossval_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for case QA_Crossval_2024"
else:
    db_path = db_paths[0]
    print(f"Found DB: {db_path}")
    result["case_db_found"] = True
    
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
                
        # Check ingest completed
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
            result["ingest_completed"] = cur.fetchone()[0] > 0
        except Exception:
            pass
            
        conn.close()
    except Exception as e:
        result["error"] += f" | DB error: {e}"

def read_file(path, key_prefix):
    if os.path.exists(path):
        result[key_prefix + "_exists"] = True
        result[key_prefix + "_mtime"] = int(os.path.getmtime(path))
        with open(path, "r", errors="replace") as f:
            result[key_prefix + "_content"] = f.read(32768)
    else:
        print(f"File not found: {path}")

read_file("/home/ga/Reports/tsk_raw_output.txt", "tsk_raw")
read_file("/home/ga/Reports/crossval_tsk_inventory.txt", "tsk_inv")
read_file("/home/ga/Reports/crossval_autopsy_inventory.txt", "aut_inv")
read_file("/home/ga/Reports/crossval_report.txt", "report")

print(json.dumps(result, indent=2))
with open("/tmp/crossval_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/crossval_result.json")
PYEOF

echo "=== Export complete ==="