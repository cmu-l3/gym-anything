#!/bin/bash
# Export script for file_system_timeline task

echo "=== Exporting results for file_system_timeline ==="

source /workspace/scripts/task_utils.sh

kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "file_system_timeline",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_timeline_event_count": 0,
    "db_file_names": [],
    "timeline_csv_exists": False,
    "timeline_csv_mtime": 0,
    "timeline_csv_content": "",
    "timeline_csv_line_count": 0,
    "report_file_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/file_system_timeline_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Timeline_Analysis_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Timeline_Analysis_2024"
    with open("/tmp/file_system_timeline_result.json", "w") as f:
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
        count = cur.fetchone()[0]
        result["ingest_completed"] = count > 0
    except Exception:
        pass

    # Get timeline events from tsk_files (mtime/atime/ctime)
    try:
        cur.execute("""
            SELECT name, meta_addr, size, mtime, atime, ctime, crtime
            FROM tsk_files
            WHERE meta_type=1
              AND name NOT IN ('.', '..', '$OrphanFiles')
              AND name NOT LIKE '$%'
            ORDER BY mtime DESC
        """)
        rows = cur.fetchall()
        result["db_timeline_event_count"] = len(rows) * 4  # 4 timestamps per file
        result["db_file_names"] = [r["name"] for r in rows[:50]]
    except Exception as e:
        result["error"] += f" | Timeline query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB error: {e}"

# Timeline CSV
csv_path = "/home/ga/Reports/fs_timeline.csv"
if os.path.exists(csv_path):
    result["timeline_csv_exists"] = True
    result["timeline_csv_mtime"] = int(os.path.getmtime(csv_path))
    with open(csv_path, "r", errors="replace") as f:
        content = f.read(32768)
    result["timeline_csv_content"] = content
    result["timeline_csv_line_count"] = len([l for l in content.splitlines() if l.strip()])
    print(f"Timeline CSV: {result['timeline_csv_line_count']} lines")

# Narrative report
report_path = "/home/ga/Reports/timeline_report.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(8192)
    print(f"Report file: {len(result['report_content'])} chars")

print(json.dumps(result, indent=2))
with open("/tmp/file_system_timeline_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/file_system_timeline_result.json")
PYEOF

echo "=== Export complete ==="
