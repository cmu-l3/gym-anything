#!/bin/bash
# Export script for keyword_contraband_search task

echo "=== Exporting results for keyword_contraband_search ==="

source /workspace/scripts/task_utils.sh

kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "keyword_contraband_search",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_keyword_hit_count": 0,
    "db_keyword_hit_files": [],
    "db_keywords_found": [],
    "hits_file_exists": False,
    "hits_file_mtime": 0,
    "hits_file_content": "",
    "summary_file_exists": False,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/keyword_contraband_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Keyword_Search_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Keyword_Search_2024"
    with open("/tmp/keyword_contraband_result.json", "w") as f:
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

    # Query keyword hit artifacts (artifact_type_id for TSK_KEYWORD_HIT varies)
    # Try by type name first
    try:
        cur.execute("""
            SELECT bat.type_name, bat.artifact_type_id
            FROM blackboard_artifact_types bat
            WHERE bat.type_name LIKE '%KEYWORD%'
        """)
        kw_types = cur.fetchall()
        print(f"Keyword artifact types: {[(r['type_name'], r['artifact_type_id']) for r in kw_types]}")

        if kw_types:
            type_ids = [str(r["artifact_type_id"]) for r in kw_types]
            type_ids_str = ",".join(type_ids)
            cur.execute(f"""
                SELECT DISTINCT tf.name AS filename,
                       ba.artifact_type_id,
                       battr.value_text AS keyword_value
                FROM blackboard_artifacts ba
                JOIN tsk_files tf ON ba.obj_id = tf.obj_id
                LEFT JOIN blackboard_attributes battr ON ba.artifact_id = battr.artifact_id
                LEFT JOIN blackboard_attribute_types baty ON battr.attribute_type_id = baty.attribute_type_id
                WHERE ba.artifact_type_id IN ({type_ids_str})
                  AND (baty.type_name = 'TSK_KEYWORD' OR baty.type_name IS NULL)
            """)
            rows = cur.fetchall()
            result["db_keyword_hit_count"] = len(rows)
            result["db_keyword_hit_files"] = list(set(r["filename"] for r in rows))
            result["db_keywords_found"] = list(set(
                r["keyword_value"] for r in rows if r["keyword_value"]
            ))
        else:
            # No keyword artifact types found — ingest may not have included keyword search
            print("No keyword artifact types found in DB")
    except Exception as e:
        result["error"] += f" | Keyword query error: {e}"
        # Fallback: count all artifacts
        try:
            cur.execute("SELECT COUNT(*) FROM blackboard_artifacts")
            total_arts = cur.fetchone()[0]
            result["error"] += f" | Total artifacts: {total_arts}"
        except Exception:
            pass

    conn.close()
except Exception as e:
    result["error"] += f" | DB error: {e}"

# Hits report file
hits_path = "/home/ga/Reports/keyword_hits.txt"
if os.path.exists(hits_path):
    result["hits_file_exists"] = True
    result["hits_file_mtime"] = int(os.path.getmtime(hits_path))
    with open(hits_path, "r", errors="replace") as f:
        result["hits_file_content"] = f.read(8192)
    print(f"Hits file: {len(result['hits_file_content'])} chars")

# Summary file
summary_path = "/home/ga/Reports/keyword_summary.txt"
if os.path.exists(summary_path):
    result["summary_file_exists"] = True
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(2048)

print(json.dumps(result, indent=2))
with open("/tmp/keyword_contraband_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/keyword_contraband_result.json")
PYEOF

echo "=== Export complete ==="
