#!/bin/bash
# Export script for unallocated_carving_analysis task

echo "=== Exporting results for unallocated_carving_analysis ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png ga

# Kill Autopsy to safely access the SQLite DB
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "unallocated_carving_analysis",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_carved_count": 0,
    "db_allocated_count": 0,
    "db_has_hashes": False,
    "carved_catalog_exists": False,
    "carved_catalog_mtime": 0,
    "carved_catalog_content": "",
    "allocated_catalog_exists": False,
    "allocated_catalog_mtime": 0,
    "allocated_catalog_content": "",
    "analysis_report_exists": False,
    "analysis_report_mtime": 0,
    "analysis_report_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/carving_analysis_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Carving_Analysis_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Carving_Analysis_2024"
    with open("/tmp/carving_analysis_result.json", "w") as f:
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
        pass

    # Carved Files Count (PhotoRec creates files under a $CarvedFiles virtual dir)
    try:
        cur.execute("""
            SELECT COUNT(*) FROM tsk_files 
            WHERE parent_path LIKE '%$CarvedFiles%' OR name LIKE 'f%.%' OR dir_type=7
        """)
        result["db_carved_count"] = cur.fetchone()[0]
        if result["db_carved_count"] > 0:
            result["ingest_completed"] = True
    except Exception as e:
        result["error"] += f" | Carved DB query error: {e}"

    # Allocated Files Count
    try:
        cur.execute("""
            SELECT COUNT(*) FROM tsk_files 
            WHERE meta_type=1 AND dir_flags=1 
              AND name NOT IN ('.', '..') AND name NOT LIKE '$%'
        """)
        result["db_allocated_count"] = cur.fetchone()[0]
        if result["db_allocated_count"] > 0:
            result["ingest_completed"] = True
    except Exception as e:
        pass

    # Hash check
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE md5 IS NOT NULL AND md5 != ''")
        result["db_has_hashes"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    conn.close()
except Exception as e:
    result["error"] += f" | DB error: {e}"

# Read Report Files
def read_report(filepath):
    if os.path.exists(filepath):
        mtime = int(os.path.getmtime(filepath))
        with open(filepath, "r", errors="replace") as f:
            return True, mtime, f.read(16384)
    return False, 0, ""

ex, mt, ct = read_report("/home/ga/Reports/carved_files_catalog.txt")
result["carved_catalog_exists"], result["carved_catalog_mtime"], result["carved_catalog_content"] = ex, mt, ct

ex, mt, ct = read_report("/home/ga/Reports/allocated_files_catalog.txt")
result["allocated_catalog_exists"], result["allocated_catalog_mtime"], result["allocated_catalog_content"] = ex, mt, ct

ex, mt, ct = read_report("/home/ga/Reports/carving_analysis_report.txt")
result["analysis_report_exists"], result["analysis_report_mtime"], result["analysis_report_content"] = ex, mt, ct

# Save results
with open("/tmp/carving_analysis_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/carving_analysis_result.json")
PYEOF

echo "=== Export complete ==="