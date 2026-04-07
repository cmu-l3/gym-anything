#!/bin/bash
# Export script for extension_mismatch_detection task

echo "=== Exporting results for extension_mismatch_detection ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before closing
take_screenshot /tmp/task_final.png ga

# Kill Autopsy to release DB lock
echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "extension_mismatch_detection",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_has_mime_types": False,
    "db_mismatch_artifact_count": 0,
    "db_mismatched_files": [],
    "catalog_file_exists": False,
    "catalog_mtime": 0,
    "catalog_content": "",
    "summary_file_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/task_start_time.txt") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Extension_Mismatch_2024*/autopsy.db")
if not db_paths:
    # Broaden search if exact case name wasn't perfectly formatted
    db_paths = [p for p in glob.glob("/home/ga/Cases/*/autopsy.db") if "Extension" in p or "Mismatch" in p]

if not db_paths:
    result["error"] = "autopsy.db not found for case Extension_Mismatch_2024"
    with open("/tmp/extension_mismatch_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
print(f"Found DB: {db_path}")
result["case_db_found"] = True
result["case_name_matches"] = "Extension_Mismatch_2024" in db_path

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
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

    # Check ingest completed (files indexed and MIME populated)
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND mime_type IS NOT NULL AND mime_type != ''")
        mime_count = cur.fetchone()[0]
        result["db_has_mime_types"] = mime_count > 0
        result["ingest_completed"] = mime_count > 0
    except Exception:
        pass

    # Find Extension Mismatch artifacts
    try:
        cur.execute("""
            SELECT tf.name 
            FROM blackboard_artifacts ba
            JOIN blackboard_artifact_types bat ON ba.artifact_type_id = bat.artifact_type_id
            JOIN tsk_files tf ON ba.obj_id = tf.obj_id
            WHERE bat.type_name = 'TSK_EXT_MISMATCH_DETECTED'
        """)
        rows = cur.fetchall()
        result["db_mismatch_artifact_count"] = len(rows)
        result["db_mismatched_files"] = [r["name"] for r in rows]
    except Exception as e:
        result["error"] += f" | Mismatch artifact query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# Check Catalog file
catalog_path = "/home/ga/Reports/extension_mismatches.txt"
if os.path.exists(catalog_path):
    result["catalog_file_exists"] = True
    result["catalog_mtime"] = int(os.path.getmtime(catalog_path))
    with open(catalog_path, "r", errors="replace") as f:
        result["catalog_content"] = f.read(16384)
    print(f"Catalog file exists: {len(result['catalog_content'])} bytes")

# Check Summary file
summary_path = "/home/ga/Reports/mismatch_summary.txt"
if os.path.exists(summary_path):
    result["summary_file_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(8192)
    print(f"Summary file exists: {len(result['summary_content'])} bytes")

print(json.dumps(result, indent=2))
with open("/tmp/extension_mismatch_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/extension_mismatch_result.json")
PYEOF

echo "=== Export complete ==="