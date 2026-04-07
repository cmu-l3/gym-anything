#!/bin/bash
# Export script for metadata_filesystem_timestamp_divergence task

echo "=== Exporting results for Temporal Divergence Analysis ==="

source /workspace/scripts/task_utils.sh

# Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Kill Autopsy to release SQLite locks
echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "metadata_filesystem_timestamp_divergence",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_exif_artifacts_found": False,
    "csv_file_exists": False,
    "csv_mtime": 0,
    "csv_content": "",
    "summary_file_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/temporal_divergence_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# 1. Check Autopsy Database
db_paths = glob.glob("/home/ga/Cases/Temporal_Divergence_2026*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for case Temporal_Divergence_2026"
else:
    db_path = db_paths[0]
    result["case_db_found"] = True
    result["case_name_matches"] = True
    print(f"Found DB: {db_path}")

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

        # Check ingest completed (files indexed)
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
            result["ingest_completed"] = cur.fetchone()[0] > 0
        except Exception:
            pass

        # Check for EXIF artifacts
        try:
            cur.execute("""
                SELECT COUNT(*) FROM blackboard_artifacts ba
                JOIN blackboard_artifact_types bat ON ba.artifact_type_id = bat.artifact_type_id
                WHERE bat.type_name LIKE '%EXIF%' OR bat.type_name LIKE '%METADATA%'
            """)
            result["db_exif_artifacts_found"] = cur.fetchone()[0] > 0
        except Exception:
            pass

        conn.close()
    except Exception as e:
        result["error"] += f" | DB error: {e}"

# 2. Check CSV Report
csv_path = "/home/ga/Reports/timestamp_divergence.csv"
if os.path.exists(csv_path):
    result["csv_file_exists"] = True
    result["csv_mtime"] = int(os.path.getmtime(csv_path))
    with open(csv_path, "r", errors="replace") as f:
        content = f.read(16384)
    result["csv_content"] = content
    print(f"CSV file: {len(content)} chars")

# 3. Check Summary Report
summary_path = "/home/ga/Reports/temporal_summary.txt"
if os.path.exists(summary_path):
    result["summary_file_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        content = f.read(4096)
    result["summary_content"] = content
    print(f"Summary file: {len(content)} chars")

print(json.dumps(result, indent=2))
with open("/tmp/temporal_divergence_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/temporal_divergence_result.json")

PYEOF

echo "=== Export complete ==="