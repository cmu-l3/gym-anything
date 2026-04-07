#!/bin/bash
# Export script for sleuthkit_backend_database_extraction task

echo "=== Exporting results for sleuthkit_backend_database_extraction ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Kill Autopsy to ensure all SQLite locks on autopsy.db are released
echo "Killing Autopsy to release SQLite locks..."
kill_autopsy
sleep 3

# Run Python script to evaluate DB and CSV state and dump to JSON
python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "sleuthkit_backend_database_extraction",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_md5_count": 0,
    "db_md5_list": [],
    "csv_exists": False,
    "csv_mtime": 0,
    "csv_content": "",
    "start_time": 0,
    "error": ""
}

# 1. Load start time
try:
    with open("/tmp/sleuthkit_backend_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# 2. Find Autopsy Case Database
db_paths = glob.glob("/home/ga/Cases/Backend_DB_Extraction_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for case Backend_DB_Extraction_2024"
    with open("/tmp/sleuthkit_backend_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
print(f"Found DB: {db_path}")
result["case_db_found"] = True
result["case_name_matches"] = True

# 3. Query the Database
try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Check data source addition
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_image_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            pass

    # Extract MD5s populated by Hash Lookup ingest
    try:
        cur.execute("SELECT md5 FROM tsk_files WHERE md5 IS NOT NULL AND md5 != ''")
        rows = cur.fetchall()
        result["db_md5_count"] = len(rows)
        result["db_md5_list"] = [r["md5"].lower() for r in rows if r["md5"]]
        result["ingest_completed"] = result["db_md5_count"] > 0
    except Exception as e:
        result["error"] += f" | DB query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# 4. Check Agent's CSV Export
csv_path = "/home/ga/Reports/custom_hash_export.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_mtime"] = int(os.path.getmtime(csv_path))
    try:
        with open(csv_path, "r", errors="replace") as f:
            # Read up to 1MB of the CSV to prevent massive memory usage
            result["csv_content"] = f.read(1024 * 1024)
        print(f"Agent's CSV loaded: {len(result['csv_content'])} characters")
    except Exception as e:
        result["error"] += f" | CSV read error: {e}"
else:
    print(f"Agent's CSV not found at {csv_path}")

# Dump to result JSON
print(json.dumps(result, indent=2))
with open("/tmp/sleuthkit_backend_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result successfully written to /tmp/sleuthkit_backend_result.json")
PYEOF

chmod 666 /tmp/sleuthkit_backend_result.json 2>/dev/null || true
echo "=== Export complete ==="