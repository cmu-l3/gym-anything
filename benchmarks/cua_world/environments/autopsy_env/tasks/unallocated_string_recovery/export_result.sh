#!/bin/bash
# Export script for unallocated_string_recovery task

echo "=== Exporting results for unallocated_string_recovery ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Release SQLite lock by stopping Autopsy
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "unallocated_string_recovery",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "raw_strings_exists": False,
    "raw_strings_mtime": 0,
    "raw_strings_content": "",
    "raw_strings_line_count": 0,
    "classification_exists": False,
    "classification_mtime": 0,
    "classification_content": "",
    "summary_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/string_recovery_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Check autopsy.db
db_paths = glob.glob("/home/ga/Cases/String_Recovery_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for String_Recovery_2024"
else:
    db_path = db_paths[0]
    result["case_db_found"] = True
    result["case_name_matches"] = True

    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()

        # Check if data source was successfully added
        try:
            cur.execute("SELECT COUNT(*) FROM data_source_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            try:
                cur.execute("SELECT COUNT(*) FROM tsk_image_info")
                result["data_source_added"] = cur.fetchone()[0] > 0
            except Exception:
                pass

        # Check if Ingest completed and populated DB
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
            result["ingest_completed"] = cur.fetchone()[0] > 0
        except Exception:
            pass

        conn.close()
    except Exception as e:
        result["error"] += f" | DB error: {e}"

# Process Raw Strings File
raw_path = "/home/ga/Reports/raw_unallocated_strings.txt"
if os.path.exists(raw_path):
    result["raw_strings_exists"] = True
    result["raw_strings_mtime"] = int(os.path.getmtime(raw_path))
    # Read the line count efficiently without blowing up memory
    with open(raw_path, 'rb') as f:
        result["raw_strings_line_count"] = sum(1 for _ in f)
    # Extract sample bytes to verify content
    with open(raw_path, "r", errors="replace") as f:
        result["raw_strings_content"] = f.read(100000)

# Process Classification Report
class_path = "/home/ga/Reports/string_classification.txt"
if os.path.exists(class_path):
    result["classification_exists"] = True
    result["classification_mtime"] = int(os.path.getmtime(class_path))
    with open(class_path, "r", errors="replace") as f:
        result["classification_content"] = f.read(50000)

# Process Summary Report
summary_path = "/home/ga/Reports/string_recovery_summary.txt"
if os.path.exists(summary_path):
    result["summary_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(10000)

with open("/tmp/string_recovery_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export complete ==="