#!/bin/bash
# Export script for exif_metadata_provenance task

echo "=== Exporting results for exif_metadata_provenance ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before closing
take_screenshot /tmp/task_final_state.png

kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "exif_metadata_provenance",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_image_count": 0,
    "db_exif_artifact_count": 0,
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
    with open("/tmp/exif_provenance_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Photo_Provenance_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Photo_Provenance_2024"
    with open("/tmp/exif_provenance_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
result["case_db_found"] = True
result["case_name_matches"] = True

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

    # Ingest / Image files check
    try:
        cur.execute("""
            SELECT COUNT(*) FROM tsk_files 
            WHERE meta_type=1 AND dir_flags=1 
              AND (mime_type LIKE 'image/%' OR lower(name) LIKE '%.jpg' OR lower(name) LIKE '%.jpeg')
        """)
        img_count = cur.fetchone()[0]
        result["db_image_count"] = img_count
        result["ingest_completed"] = img_count > 0
    except Exception:
        pass

    # EXIF artifacts check
    try:
        cur.execute("""
            SELECT COUNT(*) FROM blackboard_artifacts ba
            JOIN blackboard_artifact_types bat ON ba.artifact_type_id = bat.artifact_type_id
            WHERE bat.type_name = 'TSK_METADATA_EXIF'
        """)
        result["db_exif_artifact_count"] = cur.fetchone()[0]
    except Exception:
        pass

    conn.close()
except Exception as e:
    result["error"] += f" | DB error: {e}"

# Catalog file
catalog_path = "/home/ga/Reports/photo_provenance.txt"
if os.path.exists(catalog_path):
    result["catalog_file_exists"] = True
    result["catalog_mtime"] = int(os.path.getmtime(catalog_path))
    with open(catalog_path, "r", errors="replace") as f:
        result["catalog_content"] = f.read(16384)

# Summary file
summary_path = "/home/ga/Reports/exif_summary.txt"
if os.path.exists(summary_path):
    result["summary_file_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(4096)

with open("/tmp/exif_provenance_result.json", "w") as f:
    json.dump(result, f, indent=2)

echo "=== Export complete ==="
PYEOF