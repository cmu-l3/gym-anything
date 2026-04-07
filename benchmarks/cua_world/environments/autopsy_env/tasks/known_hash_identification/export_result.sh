#!/bin/bash
# Export script for known_hash_identification task

echo "=== Exporting results for known_hash_identification ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Kill Autopsy to ensure SQLite DB writes are flushed and lock is released
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "known_hash_identification",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_hash_hits": [],
    "report_file_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "summary_file_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/known_hash_start_time.txt") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Hash_Lookup_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Hash_Lookup_2024"
    with open("/tmp/known_hash_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
result["case_db_found"] = True
result["case_name_matches"] = True
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

    # Get hash set hits
    try:
        # TSK_HASHSET_HIT artifacts and TSK_SET_NAME attributes
        cur.execute("""
            SELECT tf.name AS filename, battr.value_text AS set_name
            FROM blackboard_artifacts ba
            JOIN blackboard_artifact_types bat ON ba.artifact_type_id = bat.artifact_type_id
            JOIN tsk_files tf ON ba.obj_id = tf.obj_id
            LEFT JOIN blackboard_attributes battr ON ba.artifact_id = battr.artifact_id
            LEFT JOIN blackboard_attribute_types baty ON battr.attribute_type_id = baty.attribute_type_id
            WHERE bat.type_name = 'TSK_HASHSET_HIT'
              AND (baty.type_name = 'TSK_SET_NAME' OR baty.type_name IS NULL)
        """)
        rows = cur.fetchall()
        for r in rows:
            result["db_hash_hits"].append({
                "filename": r["filename"],
                "set_name": r["set_name"] if "set_name" in r.keys() else None
            })
    except Exception as e:
        result["error"] += f" | Hash Hit query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB error: {e}"

# Hits report file
report_path = "/home/ga/Reports/hash_hits_report.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(16384)

# Summary file
summary_path = "/home/ga/Reports/hash_hits_summary.txt"
if os.path.exists(summary_path):
    result["summary_file_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(4096)

print(json.dumps(result, indent=2))
with open("/tmp/known_hash_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/known_hash_result.json")
PYEOF

echo "=== Export complete ==="