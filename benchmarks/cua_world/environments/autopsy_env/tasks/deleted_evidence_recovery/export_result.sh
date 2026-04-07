#!/bin/bash
# Export script for deleted_evidence_recovery task
# Runs AFTER the agent session ends (post_task hook)

echo "=== Exporting results for deleted_evidence_recovery ==="

source /workspace/scripts/task_utils.sh

# ── Kill Autopsy to release SQLite lock ───────────────────────────────────────
echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

# ── Gather all results via Python ─────────────────────────────────────────────
python3 << 'PYEOF'
import json, os, sqlite3, glob, subprocess, re

result = {
    "task": "deleted_evidence_recovery",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_deleted_file_count": 0,
    "db_deleted_file_names": [],
    "report_file_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "export_dir_file_count": 0,
    "start_time": 0,
    "error": ""
}

# Read start time
try:
    with open("/tmp/deleted_evidence_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Deleted_Evidence_2024*/autopsy.db")
if not db_paths:
    # Try broader search
    db_paths = [p for p in glob.glob("/home/ga/Cases/*/autopsy.db")
                if "Deleted_Evidence_2024" in p]
if not db_paths:
    result["error"] = "autopsy.db not found for case Deleted_Evidence_2024"
    print(json.dumps(result, indent=2))
    with open("/tmp/deleted_evidence_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
print(f"Found DB: {db_path}")
result["case_db_found"] = True
result["case_name_matches"] = True

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

    # Get deleted files from DB
    try:
        cur.execute("""
            SELECT name, size, meta_addr
            FROM tsk_files
            WHERE dir_flags=2 AND meta_type=1
              AND name NOT IN ('.', '..', '$OrphanFiles')
              AND name NOT LIKE '$%'
        """)
        rows = cur.fetchall()
        result["db_deleted_file_count"] = len(rows)
        result["db_deleted_file_names"] = [r["name"] for r in rows]
    except Exception as e:
        result["error"] += f" | DB query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# Check agent's report file
report_path = "/home/ga/Reports/deleted_evidence_report.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        content = f.read(8192)
    result["report_content"] = content
    print(f"Report file: {len(content)} chars")
else:
    print("Report file not found")

# Check export directory
export_dir = "/home/ga/Reports/deleted_evidence"
if os.path.isdir(export_dir):
    files = [f for f in os.listdir(export_dir) if os.path.isfile(os.path.join(export_dir, f))]
    result["export_dir_file_count"] = len(files)
    print(f"Export dir: {len(files)} files")

print(json.dumps(result, indent=2))
with open("/tmp/deleted_evidence_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/deleted_evidence_result.json")
PYEOF

echo "=== Export complete ==="
