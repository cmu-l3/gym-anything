#!/bin/bash
echo "=== Exporting results for encryption_entropy_screening ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot before killing the app
take_screenshot /tmp/task_final_state.png

kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "encryption_entropy_screening",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "csv_file_exists": False,
    "csv_mtime": 0,
    "csv_content": "",
    "report_file_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/encryption_screening_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Encryption_Screening_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Encryption_Screening_2024"
    with open("/tmp/encryption_screening_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
result["case_db_found"] = True
result["case_name_matches"] = True

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Data source check
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_image_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            pass

    # Ingest check
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
        result["ingest_completed"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    conn.close()
except Exception as e:
    result["error"] += f" | DB error: {e}"

# CSV file check
csv_path = "/home/ga/Reports/entropy_analysis.csv"
if os.path.exists(csv_path):
    result["csv_file_exists"] = True
    result["csv_mtime"] = int(os.path.getmtime(csv_path))
    with open(csv_path, "r", errors="replace") as f:
        result["csv_content"] = f.read(1024 * 512) # Up to 512KB

# Report file check
report_path = "/home/ga/Reports/encryption_screening_report.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(1024 * 64) # Up to 64KB

with open("/tmp/encryption_screening_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result successfully written to /tmp/encryption_screening_result.json")
PYEOF

echo "=== Export complete ==="