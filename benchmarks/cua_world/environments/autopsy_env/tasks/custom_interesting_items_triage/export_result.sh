#!/bin/bash
# Export script for custom_interesting_items_triage task

echo "=== Exporting results for custom_interesting_items_triage ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Kill Autopsy to release DB lock
echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "custom_interesting_items_triage",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "db_interesting_hits_count": 0,
    "db_config_logs_hits": 0,
    "db_hit_files": [],
    "tsv_file_exists": False,
    "tsv_mtime": 0,
    "tsv_content": "",
    "summary_file_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/triage_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Targeted_Triage_2024*/autopsy.db")
if not db_paths:
    db_paths = [p for p in glob.glob("/home/ga/Cases/*/autopsy.db") if "Targeted_Triage_2024" in p]

if not db_paths:
    result["error"] = "autopsy.db not found for case Targeted_Triage_2024"
    with open("/tmp/triage_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
print(f"Found DB: {db_path}")
result["case_db_found"] = True
result["case_name_matches"] = True

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Check data source
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_image_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            pass

    # Verify Interesting Items artifacts
    try:
        # Find the artifact_type_id for TSK_INTERESTING_FILE_HIT
        cur.execute("SELECT artifact_type_id FROM blackboard_artifact_types WHERE type_name='TSK_INTERESTING_FILE_HIT'")
        art_type_row = cur.fetchone()
        if art_type_row:
            art_type_id = art_type_row[0]
            
            # Count ALL interesting hits
            cur.execute(f"SELECT COUNT(*) FROM blackboard_artifacts WHERE artifact_type_id={art_type_id}")
            result["db_interesting_hits_count"] = cur.fetchone()[0]
            
            # Count specifically for "Config_And_Logs"
            query = f"""
                SELECT tf.name, attr.value_text 
                FROM blackboard_artifacts ba
                JOIN tsk_files tf ON ba.obj_id = tf.obj_id
                JOIN blackboard_attributes attr ON ba.artifact_id = attr.artifact_id
                JOIN blackboard_attribute_types atype ON attr.attribute_type_id = atype.attribute_type_id
                WHERE ba.artifact_type_id={art_type_id}
                  AND atype.type_name='TSK_SET_NAME'
                  AND attr.value_text='Config_And_Logs'
            """
            cur.execute(query)
            rows = cur.fetchall()
            result["db_config_logs_hits"] = len(rows)
            result["db_hit_files"] = [r["name"] for r in rows]
    except Exception as e:
        result["error"] += f" | DB artifact query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# TSV Report
tsv_path = "/home/ga/Reports/flagged_items.tsv"
if os.path.exists(tsv_path):
    result["tsv_file_exists"] = True
    result["tsv_mtime"] = int(os.path.getmtime(tsv_path))
    with open(tsv_path, "r", errors="replace") as f:
        result["tsv_content"] = f.read(16384)

# Summary Report
summary_path = "/home/ga/Reports/triage_summary.txt"
if os.path.exists(summary_path):
    result["summary_file_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(2048)

print(json.dumps(result, indent=2))
with open("/tmp/triage_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/triage_result.json")
PYEOF

echo "=== Export complete ==="