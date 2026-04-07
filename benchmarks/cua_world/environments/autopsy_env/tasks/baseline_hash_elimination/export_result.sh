#!/bin/bash
echo "=== Exporting results for baseline_hash_elimination ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_final.png ga

# Kill Autopsy to ensure SQLite databases are flushed and unlocked
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "baseline_hash_elimination",
    "start_time": 0,
    "case_db_found": False,
    "suspect_added": False,
    "db_known_files_count": 0,
    "db_unknown_files_count": 0,
    "baseline_hashes_exists": False,
    "baseline_hashes_mtime": 0,
    "baseline_hashes_content": "",
    "csv_exists": False,
    "csv_mtime": 0,
    "csv_content": "",
    "summary_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "error": ""
}

try:
    with open("/tmp/baseline_start_time") as f:
        result["start_time"] = int(f.read().strip())
except:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Exfiltration_Analysis_2026*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Exfiltration_Analysis_2026"
else:
    db_path = db_paths[0]
    result["case_db_found"] = True
    print(f"Found DB: {db_path}")

    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()

        # Check if suspect was added
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_image_info")
            result["suspect_added"] = cur.fetchone()[0] > 0
        except:
            pass
            
        # Check Known/Eliminated files
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE known = 1 AND meta_type = 1")
            result["db_known_files_count"] = cur.fetchone()[0]
            
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE known = 0 AND meta_type = 1 AND dir_flags = 1 AND size > 0 AND name NOT IN ('.', '..')")
            result["db_unknown_files_count"] = cur.fetchone()[0]
        except Exception as e:
            result["error"] += f" | Known files query error: {e}"

        conn.close()
    except Exception as e:
        result["error"] += f" | DB open error: {e}"

# Read Hash text file
hash_path = "/home/ga/evidence/baseline_hashes.txt"
if os.path.exists(hash_path):
    result["baseline_hashes_exists"] = True
    result["baseline_hashes_mtime"] = int(os.path.getmtime(hash_path))
    with open(hash_path, "r", errors="replace") as f:
        result["baseline_hashes_content"] = f.read(10000)

# Read CSV report
csv_path = "/home/ga/Reports/anomalous_files.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_mtime"] = int(os.path.getmtime(csv_path))
    with open(csv_path, "r", errors="replace") as f:
        result["csv_content"] = f.read(16384)

# Read Summary text file
summary_path = "/home/ga/Reports/elimination_summary.txt"
if os.path.exists(summary_path):
    result["summary_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(2048)

print(json.dumps(result, indent=2))
with open("/tmp/baseline_task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export complete ==="