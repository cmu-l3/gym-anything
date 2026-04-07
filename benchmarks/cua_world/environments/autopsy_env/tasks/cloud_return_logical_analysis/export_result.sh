#!/bin/bash
# Export script for cloud_return_logical_analysis task

echo "=== Exporting results for cloud_return_logical_analysis ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png ga

# Kill Autopsy to release SQLite locks
echo "Stopping Autopsy..."
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "cloud_return_logical_analysis",
    "case_db_found": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_total_files": 0,
    "db_jpeg_count": 0,
    "db_text_count": 0,
    "db_has_hashes": False,
    "catalog_file_exists": False,
    "catalog_mtime": 0,
    "catalog_content": "",
    "summary_file_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

# Read start time
try:
    with open("/tmp/cloud_return_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Cloud_Return_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Cloud_Return_2024"
    with open("/tmp/cloud_return_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
result["case_db_found"] = True
print(f"Found DB: {db_path}")

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Data source check
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    # DB file and MIME counts
    # We filter out directories (dir_flags=1 usually means allocated files in Autopsy TSK schema, dir_type=5 means regular file)
    try:
        # Total files
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1 AND name NOT IN ('.', '..')")
        result["db_total_files"] = cur.fetchone()[0]
        
        if result["db_total_files"] > 0:
            result["ingest_completed"] = True
            
        # JPEG count
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND mime_type = 'image/jpeg'")
        result["db_jpeg_count"] = cur.fetchone()[0]
        
        # Text count
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND mime_type = 'text/plain'")
        result["db_text_count"] = cur.fetchone()[0]
    except Exception as e:
        result["error"] += f" | Count query error: {e}"

    # Check for Hash artifacts or md5 hashes populated directly in tsk_files
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE md5 IS NOT NULL AND md5 != ''")
        if cur.fetchone()[0] > 0:
            result["db_has_hashes"] = True
    except Exception:
        pass

    conn.close()
except Exception as e:
    result["error"] += f" | DB error: {e}"

# Catalog file
catalog_path = "/home/ga/Reports/logical_catalog.tsv"
if os.path.exists(catalog_path):
    result["catalog_file_exists"] = True
    result["catalog_mtime"] = int(os.path.getmtime(catalog_path))
    with open(catalog_path, "r", errors="replace") as f:
        result["catalog_content"] = f.read(16384)  # Read up to 16KB for validation

# Summary file
summary_path = "/home/ga/Reports/cloud_summary.txt"
if os.path.exists(summary_path):
    result["summary_file_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(2048)

print(json.dumps(result, indent=2))
with open("/tmp/cloud_return_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/cloud_return_result.json")
PYEOF

echo "=== Export complete ==="