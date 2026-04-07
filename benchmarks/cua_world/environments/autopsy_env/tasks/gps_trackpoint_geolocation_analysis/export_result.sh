#!/bin/bash
# Export script for gps_trackpoint_geolocation_analysis task

echo "=== Exporting results for gps_trackpoint_geolocation_analysis ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot before killing process
take_screenshot /tmp/task_final.png ga

echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "gps_trackpoint_geolocation_analysis",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "db_gps_artifacts": 0,
    "csv_export_exists": False,
    "csv_export_mtime": 0,
    "csv_export_content": "",
    "report_file_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/gps_trackpoint_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate the newly created case database
db_paths = glob.glob("/home/ga/Cases/SAR_GPS_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for SAR_GPS_2024"
    with open("/tmp/gps_trackpoint_result.json", "w") as f:
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

    # Verify that the image was successfully added as a data source
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_image_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            pass

    # Verify that GPX data was processed and trackpoints were populated
    try:
        cur.execute("""
            SELECT COUNT(*) FROM blackboard_artifacts
            WHERE artifact_type_id IN (
                SELECT artifact_type_id FROM blackboard_artifact_types
                WHERE type_name IN ('TSK_GPS_TRACKPOINT', 'TSK_GPS_ROUTE')
            )
        """)
        result["db_gps_artifacts"] = cur.fetchone()[0]
    except Exception as e:
        result["error"] += f" | GPS query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# Harvest the user's exported CSV data
csv_path = "/home/ga/Reports/trackpoints_export.csv"
if os.path.exists(csv_path):
    result["csv_export_exists"] = True
    result["csv_export_mtime"] = int(os.path.getmtime(csv_path))
    with open(csv_path, "r", errors="replace") as f:
        result["csv_export_content"] = f.read(16384)

# Harvest the final analytic report
report_path = "/home/ga/Reports/SAR_Report.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(2048)

print(json.dumps(result, indent=2))
with open("/tmp/gps_trackpoint_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/gps_trackpoint_result.json")
PYEOF

echo "=== Export complete ==="