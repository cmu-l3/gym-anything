#!/bin/bash
# Export script for jpeg_evidence_cataloging task

echo "=== Exporting results for jpeg_evidence_cataloging ==="

source /workspace/scripts/task_utils.sh

kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "jpeg_evidence_cataloging",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_jpeg_count": 0,
    "db_jpeg_names": [],
    "db_has_mime_types": False,
    "db_has_hashes": False,
    "catalog_file_exists": False,
    "catalog_mtime": 0,
    "catalog_content": "",
    "summary_file_exists": False,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/jpeg_evidence_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/JPEG_Catalog_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for JPEG_Catalog_2024"
    with open("/tmp/jpeg_evidence_result.json", "w") as f:
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

    # Ingest check (MIME types)
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND mime_type IS NOT NULL AND mime_type != ''")
        mime_count = cur.fetchone()[0]
        result["db_has_mime_types"] = mime_count > 0
        result["ingest_completed"] = mime_count > 0
    except Exception:
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
            result["ingest_completed"] = cur.fetchone()[0] > 0
        except Exception:
            pass

    # Count JPEGs by MIME type or extension
    try:
        cur.execute("""
            SELECT name, size, meta_addr, mime_type
            FROM tsk_files
            WHERE meta_type=1
              AND (mime_type='image/jpeg' OR lower(name) LIKE '%.jpg' OR lower(name) LIKE '%.jpeg')
              AND name NOT IN ('.', '..')
        """)
        jpeg_rows = cur.fetchall()
        result["db_jpeg_count"] = len(jpeg_rows)
        result["db_jpeg_names"] = [r["name"] for r in jpeg_rows]
    except Exception as e:
        result["error"] += f" | JPEG query error: {e}"

    # Check for hash artifacts
    try:
        cur.execute("""
            SELECT COUNT(*) FROM blackboard_artifacts
            WHERE artifact_type_id IN (
                SELECT artifact_type_id FROM blackboard_artifact_types
                WHERE type_name LIKE '%HASH%' OR type_name LIKE '%HASHSET%'
            )
        """)
        result["db_has_hashes"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    conn.close()
except Exception as e:
    result["error"] += f" | DB error: {e}"

# Catalog file
catalog_path = "/home/ga/Reports/jpeg_catalog.tsv"
if os.path.exists(catalog_path):
    result["catalog_file_exists"] = True
    result["catalog_mtime"] = int(os.path.getmtime(catalog_path))
    with open(catalog_path, "r", errors="replace") as f:
        result["catalog_content"] = f.read(16384)

# Summary file
summary_path = "/home/ga/Reports/jpeg_catalog_summary.txt"
if os.path.exists(summary_path):
    result["summary_file_exists"] = True
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(2048)

print(json.dumps(result, indent=2))
with open("/tmp/jpeg_evidence_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/jpeg_evidence_result.json")
PYEOF

echo "=== Export complete ==="
