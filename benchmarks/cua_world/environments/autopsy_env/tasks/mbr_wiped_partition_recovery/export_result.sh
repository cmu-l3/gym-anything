#!/bin/bash
echo "=== Exporting results for mbr_wiped_partition_recovery ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Kill Autopsy to release DB locks
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, hashlib

result = {
    "task": "mbr_wiped_partition_recovery",
    "recovered_volume_exists": False,
    "recovered_volume_hash_match": False,
    "case_db_found": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_files_populated": False,
    "report_exists": False,
    "report_content": "",
    "inventory_exists": False,
    "inventory_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/mbr_recovery_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

try:
    with open("/tmp/ground_truth_hash.txt") as f:
        gt_hash = f.read().strip()
except Exception:
    gt_hash = ""

# Check recovered volume
recovered_path = "/home/ga/evidence/recovered_volume.dd"
if os.path.exists(recovered_path):
    result["recovered_volume_exists"] = True
    try:
        with open(recovered_path, "rb") as f:
            file_hash = hashlib.md5(f.read()).hexdigest()
        result["recovered_volume_hash_match"] = (file_hash == gt_hash)
    except Exception as e:
        result["error"] += f" Hash error: {e}"

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/MBR_Recovery_2026*/autopsy.db")
if db_paths:
    db_path = db_paths[0]
    result["case_db_found"] = True
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()
        
        try:
            cur.execute("SELECT name FROM data_source_info")
            names = [r[0] for r in cur.fetchall()]
            result["data_source_added"] = any("recovered_volume" in n for n in names)
        except Exception:
            try:
                cur.execute("SELECT name FROM tsk_image_info")
                names = [r[0] for r in cur.fetchall()]
                result["data_source_added"] = any("recovered_volume" in n for n in names)
            except Exception:
                pass
                
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
            count = cur.fetchone()[0]
            result["db_files_populated"] = count > 0
            result["ingest_completed"] = count > 0
        except Exception:
            pass
            
        conn.close()
    except Exception as e:
        result["error"] += f" DB error: {e}"

# Check reports
report_path = "/home/ga/Reports/partition_recovery_report.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(4096)

inv_path = "/home/ga/Reports/root_inventory.csv"
if os.path.exists(inv_path):
    result["inventory_exists"] = True
    with open(inv_path, "r", errors="replace") as f:
        result["inventory_content"] = f.read(16384)

print(json.dumps(result, indent=2))
with open("/tmp/mbr_recovery_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result written to /tmp/mbr_recovery_result.json"
echo "=== Export complete ==="