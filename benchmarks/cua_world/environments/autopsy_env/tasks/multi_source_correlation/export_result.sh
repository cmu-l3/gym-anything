#!/bin/bash
# Export script for multi_source_correlation task

echo "=== Exporting results for multi_source_correlation ==="

source /workspace/scripts/task_utils.sh

kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "multi_source_correlation",
    "case_db_found": False,
    "case_name_matches": False,
    "source1_added": False,
    "source2_added": False,
    "both_sources_added": False,
    "ingest_completed": False,
    "db_source1_file_count": 0,
    "db_source2_file_count": 0,
    "db_total_files": 0,
    "db_hash_artifact_count": 0,
    "correlation_report_exists": False,
    "correlation_report_mtime": 0,
    "correlation_report_content": "",
    "summary_file_exists": False,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/multi_source_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Cross_Device_Analysis_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Cross_Device_Analysis_2024"
    with open("/tmp/multi_source_result.json", "w") as f:
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

    # Check data sources
    try:
        cur.execute("""
            SELECT device_id, added_date, obj_id
            FROM data_source_info
            ORDER BY obj_id
        """)
        ds_rows = cur.fetchall()
        result["both_sources_added"] = len(ds_rows) >= 2
        result["source1_added"] = len(ds_rows) >= 1
        result["source2_added"] = len(ds_rows) >= 2
        print(f"Data sources in DB: {len(ds_rows)}")
    except Exception:
        # Fallback to tsk_image_info
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_image_info")
            count = cur.fetchone()[0]
            result["source1_added"] = count >= 1
            result["source2_added"] = count >= 2
            result["both_sources_added"] = count >= 2
        except Exception:
            pass

    # Get file counts per data source
    try:
        cur.execute("""
            SELECT tsk_objects.par_obj_id, COUNT(*) as cnt
            FROM tsk_files
            JOIN tsk_objects ON tsk_files.obj_id = tsk_objects.obj_id
            WHERE tsk_files.meta_type=1 AND tsk_files.dir_flags=1
            GROUP BY tsk_objects.par_obj_id
        """)
        per_ds_counts = cur.fetchall()
        counts = [r["cnt"] for r in per_ds_counts]
        result["db_total_files"] = sum(counts)
        if len(counts) >= 1:
            result["db_source1_file_count"] = counts[0]
        if len(counts) >= 2:
            result["db_source2_file_count"] = counts[1]
        result["ingest_completed"] = result["db_total_files"] > 0
    except Exception:
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
            result["db_total_files"] = cur.fetchone()[0]
            result["ingest_completed"] = result["db_total_files"] > 0
        except Exception:
            pass

    # Hash artifact count
    try:
        cur.execute("""
            SELECT COUNT(*) FROM blackboard_artifacts ba
            JOIN blackboard_artifact_types bat ON ba.artifact_type_id = bat.artifact_type_id
            WHERE bat.type_name LIKE '%HASH%' OR bat.type_name LIKE '%MD5%'
        """)
        result["db_hash_artifact_count"] = cur.fetchone()[0]
    except Exception:
        pass

    conn.close()
except Exception as e:
    result["error"] += f" | DB error: {e}"

# Correlation report
corr_path = "/home/ga/Reports/correlation_report.txt"
if os.path.exists(corr_path):
    result["correlation_report_exists"] = True
    result["correlation_report_mtime"] = int(os.path.getmtime(corr_path))
    with open(corr_path, "r", errors="replace") as f:
        result["correlation_report_content"] = f.read(8192)
    print(f"Correlation report: {len(result['correlation_report_content'])} chars")

# Summary file
summary_path = "/home/ga/Reports/correlation_summary.txt"
if os.path.exists(summary_path):
    result["summary_file_exists"] = True
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(2048)

print(json.dumps(result, indent=2))
with open("/tmp/multi_source_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/multi_source_result.json")
PYEOF

echo "=== Export complete ==="
