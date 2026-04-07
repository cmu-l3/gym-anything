#!/bin/bash
# Export script for custom_hashset_triage task

echo "=== Exporting results for custom_hashset_triage ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png ga

kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, hashlib

result = {
    "task": "custom_hashset_triage",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_hashset_hits": 0,
    "db_hashset_names": [],
    "db_hit_files": [],
    "export_dir_exists": False,
    "exported_files": [],
    "exported_md5s": [],
    "report_exists": False,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/custom_hashset_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Target_Hunting_2024*/autopsy.db")
if not db_paths:
    db_paths = [p for p in glob.glob("/home/ga/Cases/*/autopsy.db") if "Target_Hunting" in p]

if not db_paths:
    result["error"] = "autopsy.db not found"
    with open("/tmp/custom_hashset_result.json", "w") as f:
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

    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_image_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception: pass

    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
        result["ingest_completed"] = cur.fetchone()[0] > 0
    except Exception: pass

    try:
        # Check for TSK_HASHSET_HIT
        cur.execute("""
            SELECT baty.type_name, bat.artifact_type_id
            FROM blackboard_artifact_types bat
            WHERE bat.type_name = 'TSK_HASHSET_HIT'
        """)
        hit_type = cur.fetchone()
        if hit_type:
            hit_type_id = hit_type["artifact_type_id"]
            
            # Find hits
            cur.execute(f"""
                SELECT tf.name AS filename, battr.value_text AS hashset_name
                FROM blackboard_artifacts ba
                JOIN tsk_files tf ON ba.obj_id = tf.obj_id
                JOIN blackboard_attributes battr ON ba.artifact_id = battr.artifact_id
                JOIN blackboard_attribute_types baty ON battr.attribute_type_id = baty.attribute_type_id
                WHERE ba.artifact_type_id = {hit_type_id}
                  AND baty.type_name = 'TSK_SET_NAME'
            """)
            rows = cur.fetchall()
            result["db_hashset_hits"] = len(rows)
            result["db_hit_files"] = [r["filename"] for r in rows]
            result["db_hashset_names"] = list(set([r["hashset_name"] for r in rows]))
    except Exception as e:
        result["error"] += f" | Hashset hits query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# Check exported files
export_dir = "/home/ga/Reports/Hit_Exports"
if os.path.isdir(export_dir):
    result["export_dir_exists"] = True
    for fname in os.listdir(export_dir):
        fpath = os.path.join(export_dir, fname)
        if os.path.isfile(fpath):
            result["exported_files"].append(fname)
            try:
                with open(fpath, 'rb') as f:
                    md5 = hashlib.md5(f.read()).hexdigest()
                result["exported_md5s"].append(md5)
            except Exception: pass

# Check report
report_path = "/home/ga/Reports/target_hit_report.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    try:
        with open(report_path, "r", errors="replace") as f:
            result["report_content"] = f.read(4096)
    except Exception: pass

print(json.dumps(result, indent=2))
with open("/tmp/custom_hashset_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export complete ==="