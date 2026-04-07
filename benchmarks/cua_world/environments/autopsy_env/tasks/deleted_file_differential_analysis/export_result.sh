#!/bin/bash
# Export script for deleted_file_differential_analysis task

echo "=== Exporting results for deleted_file_differential_analysis ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before killing the app
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ── Kill Autopsy to release SQLite lock ───────────────────────────────────────
echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

# ── Gather all results via Python ─────────────────────────────────────────────
python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "deleted_file_differential_analysis",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "report_file_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "summary_file_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

# Read start time
try:
    with open("/tmp/task_start_time.txt") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Deletion_Differential_2024*/autopsy.db")
if not db_paths:
    db_paths = [p for p in glob.glob("/home/ga/Cases/*/autopsy.db")
                if "Deletion_Differential_2024" in p]
if not db_paths:
    result["error"] = "autopsy.db not found for case Deletion_Differential_2024"
    with open("/tmp/deletion_differential_result.json", "w") as f:
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
        pass

    # Check ingest completed (files indexed)
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
        result["ingest_completed"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    conn.close()
except Exception as e:
    result["error"] += f" | DB error: {e}"

# Check agent's report file
report_path = "/home/ga/Reports/deletion_differential.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(16384)

# Check agent's summary file
summary_path = "/home/ga/Reports/deletion_summary.txt"
if os.path.exists(summary_path):
    result["summary_file_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(4096)

print(json.dumps(result, indent=2))
with open("/tmp/deletion_differential_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/deletion_differential_result.json")
PYEOF

echo "=== Export complete ==="