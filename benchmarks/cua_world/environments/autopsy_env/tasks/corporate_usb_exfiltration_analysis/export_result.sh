#!/bin/bash
# Export script for corporate_usb_exfiltration_analysis task

echo "=== Exporting results for corporate_usb_exfiltration_analysis ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png ga

kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, hashlib

result = {
    "task": "corporate_usb_exfiltration_analysis",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_count": 0,
    "ingest_completed": False,
    "hashset_imported": False,
    "hashset_name": "",
    "hashset_hit_count": 0,
    "hashset_hit_files": [],
    "report_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

# 1. Get task start time
try:
    with open("/tmp/exfiltration_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# 2. Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/IP_Theft_2024*/autopsy.db")
if not db_paths:
    db_paths = [p for p in glob.glob("/home/ga/Cases/*/autopsy.db") if "IP_Theft" in p]

if db_paths:
    db_path = db_paths[0]
    result["case_db_found"] = True
    result["case_name_matches"] = "IP_Theft_2024" in db_path
    print(f"Found DB: {db_path}")

    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()

        # Count data sources
        try:
            cur.execute("SELECT COUNT(*) FROM data_source_info")
            result["data_source_count"] = cur.fetchone()[0]
        except Exception:
            try:
                cur.execute("SELECT COUNT(*) FROM tsk_image_info")
                result["data_source_count"] = cur.fetchone()[0]
            except Exception:
                pass

        # Check ingest completion
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
            result["ingest_completed"] = cur.fetchone()[0] > 0
        except Exception:
            pass

        # Check for hashset hits (Corporate_IP)
        try:
            cur.execute("""
                SELECT bat.artifact_type_id
                FROM blackboard_artifact_types bat
                WHERE bat.type_name = 'TSK_HASHSET_HIT'
            """)
            hit_type = cur.fetchone()
            if hit_type:
                hit_type_id = hit_type[0]

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
                result["hashset_hit_count"] = len(rows)
                result["hashset_hit_files"] = [r["filename"] for r in rows]
                hashset_names = list(set([r["hashset_name"] for r in rows]))
                if hashset_names:
                    result["hashset_name"] = hashset_names[0]
                    result["hashset_imported"] = True
        except Exception as e:
            result["error"] += f" | Hashset query error: {e}"

        conn.close()
    except Exception as e:
        result["error"] += f" | DB error: {e}"
else:
    result["error"] = "autopsy.db not found"

# 3. Check report file
report_path = "/home/ga/Reports/exfiltration_report.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    try:
        with open(report_path, "r", encoding="utf-8", errors="replace") as f:
            result["report_content"] = f.read(16384)
    except Exception as e:
        result["error"] += f" | Report read error: {e}"

print(json.dumps(result, indent=2))
with open("/tmp/exfiltration_result.json", "w") as f:
    json.dump(result, f, indent=2)
chmod_cmd = "chmod 666 /tmp/exfiltration_result.json"
os.system(chmod_cmd)
PYEOF

echo "=== Export complete ==="
